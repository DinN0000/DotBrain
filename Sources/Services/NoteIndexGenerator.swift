import Foundation

// MARK: - Models

/// Single note entry in the vault index
struct NoteIndexEntry: Codable, Sendable {
    let path: String
    let folder: String
    let para: String
    let tags: [String]
    let summary: String
    let project: String?
    let status: String?
}

/// Folder-level summary entry in the vault index
struct FolderIndexEntry: Codable, Sendable {
    let path: String
    let para: String
    let summary: String
    let tags: [String]
}

/// Root structure for _meta/note-index.json
struct NoteIndex: Codable, Sendable {
    let version: Int
    let updated: String
    var folders: [String: FolderIndexEntry]
    var notes: [String: NoteIndexEntry]
}

// MARK: - Generator

/// Generates and maintains _meta/note-index.json for AI vault navigation.
/// Replaces MOCGenerator with a single JSON index that AI tools can read efficiently.
struct NoteIndexGenerator: Sendable {
    let pkmRoot: String

    private static let currentVersion = 1

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Public API

    /// Incremental update: re-scan only the specified folders, merge into existing index
    func updateForFolders(_ folderPaths: Set<String>) async {
        var index = loadExisting() ?? emptyIndex()

        for folderPath in folderPaths {
            let folderName = (folderPath as NSString).lastPathComponent
            let para = PARACategory.fromPath(folderPath) ?? .archive
            let relFolder = relativePath(folderPath)

            // Remove old notes belonging to this folder
            let keysToRemove = index.notes.keys.filter { index.notes[$0]?.folder == relFolder }
            for key in keysToRemove {
                index.notes.removeValue(forKey: key)
            }

            // Scan and add fresh entries
            let (folderEntry, noteEntries) = scanFolder(
                folderPath: folderPath,
                folderName: folderName,
                para: para
            )

            if let folderEntry {
                index.folders[relFolder] = folderEntry
            } else {
                // Folder is empty or gone, remove it
                index.folders.removeValue(forKey: relFolder)
            }

            for (notePath, entry) in noteEntries {
                index.notes[notePath] = entry
            }
        }

        index = NoteIndex(
            version: NoteIndexGenerator.currentVersion,
            updated: Self.timestamp(),
            folders: index.folders,
            notes: index.notes
        )

        save(index)
    }

    /// Full regeneration: scan all PARA categories from scratch
    func regenerateAll() async {
        let fm = FileManager.default
        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        var allFolders: [String: FolderIndexEntry] = [:]
        var allNotes: [String: NoteIndexEntry] = [:]

        for (para, basePath) in categories {
            guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let (folderEntry, noteEntries) = scanFolder(
                    folderPath: folderPath,
                    folderName: entry,
                    para: para
                )

                let relFolder = relativePath(folderPath)
                if let folderEntry {
                    allFolders[relFolder] = folderEntry
                }
                for (notePath, noteEntry) in noteEntries {
                    allNotes[notePath] = noteEntry
                }
            }
        }

        let index = NoteIndex(
            version: NoteIndexGenerator.currentVersion,
            updated: Self.timestamp(),
            folders: allFolders,
            notes: allNotes
        )

        save(index)
    }

    // MARK: - Private Helpers

    /// Scan a single folder, returning its folder entry and all note entries
    private func scanFolder(
        folderPath: String,
        folderName: String,
        para: PARACategory
    ) -> (FolderIndexEntry?, [(String, NoteIndexEntry)]) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: folderPath) else {
            return (nil, [])
        }

        let relFolder = relativePath(folderPath)
        var noteEntries: [(String, NoteIndexEntry)] = []
        var tagCounts: [String: Int] = [:]
        var summaries: [String] = []

        for entry in entries.sorted() {
            // Skip non-markdown, hidden, underscore-prefixed, and MOC files
            guard entry.hasSuffix(".md"),
                  !entry.hasPrefix("."),
                  !entry.hasPrefix("_"),
                  entry != "\(folderName).md" else { continue }

            let filePath = (folderPath as NSString).appendingPathComponent(entry)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            let relNotePath = relativePath(filePath)

            let noteEntry = NoteIndexEntry(
                path: relNotePath,
                folder: relFolder,
                para: para.rawValue,
                tags: frontmatter.tags,
                summary: frontmatter.summary ?? "",
                project: frontmatter.project,
                status: frontmatter.status?.rawValue
            )

            noteEntries.append((relNotePath, noteEntry))

            // Aggregate tags for folder-level summary
            for tag in frontmatter.tags {
                tagCounts[tag, default: 0] += 1
            }
            if let summary = frontmatter.summary, !summary.isEmpty {
                summaries.append(summary)
            }
        }

        guard !noteEntries.isEmpty else { return (nil, []) }

        // Top 10 tags by frequency
        let topTags = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }

        // Folder summary: combine first few note summaries or use count
        let folderSummary: String
        if summaries.isEmpty {
            folderSummary = "\(noteEntries.count) notes"
        } else {
            folderSummary = summaries.prefix(3).joined(separator: "; ")
        }

        let folderEntry = FolderIndexEntry(
            path: relFolder,
            para: para.rawValue,
            summary: folderSummary,
            tags: topTags
        )

        return (folderEntry, noteEntries)
    }

    /// Convert an absolute path to a path relative to pkmRoot
    private func relativePath(_ absolutePath: String) -> String {
        let root = pkmRoot.hasSuffix("/") ? pkmRoot : pkmRoot + "/"
        if absolutePath.hasPrefix(root) {
            return String(absolutePath.dropFirst(root.count))
        }
        return absolutePath
    }

    /// Load existing note-index.json if present
    private func loadExisting() -> NoteIndex? {
        let indexPath = metaIndexPath()
        guard let data = FileManager.default.contents(atPath: indexPath) else { return nil }
        do {
            return try JSONDecoder().decode(NoteIndex.self, from: data)
        } catch {
            NSLog("[NoteIndexGenerator] Failed to decode existing index: %@", error.localizedDescription)
            return nil
        }
    }

    /// Save index to _meta/note-index.json with prettyPrinted + sortedKeys
    private func save(_ index: NoteIndex) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent("_meta")
        let indexPath = metaIndexPath()

        // Create _meta/ directory if needed
        if !fm.fileExists(atPath: metaDir) {
            do {
                try fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
            } catch {
                NSLog("[NoteIndexGenerator] Failed to create _meta directory: %@", error.localizedDescription)
                return
            }
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let data = try encoder.encode(index)
            try data.write(to: URL(fileURLWithPath: indexPath), options: .atomic)
        } catch {
            NSLog("[NoteIndexGenerator] Failed to save index: %@", error.localizedDescription)
        }
    }

    /// Path to _meta/note-index.json
    private func metaIndexPath() -> String {
        (pkmRoot as NSString)
            .appendingPathComponent("_meta")
            .appending("/note-index.json")
    }

    /// Create an empty index structure
    private func emptyIndex() -> NoteIndex {
        NoteIndex(
            version: NoteIndexGenerator.currentVersion,
            updated: Self.timestamp(),
            folders: [:],
            notes: [:]
        )
    }

    /// ISO 8601 date string for the updated field
    private static func timestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: Date())
    }
}
