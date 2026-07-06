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
    let area: String?
}

/// Folder-level summary entry in the vault index
struct FolderIndexEntry: Codable, Sendable {
    let path: String
    let para: String
    let summary: String
    let tags: [String]
}

/// Root structure for .meta/note-index.json
struct NoteIndex: Codable, Sendable {
    let version: Int
    let updated: String
    var folders: [String: FolderIndexEntry]
    var notes: [String: NoteIndexEntry]
}

// MARK: - Generator

/// Serializes every note-index.json writer. The index has multiple async
/// writers (pipelines, UI refresh, startup bootstrap) whose load-modify-write
/// cycles would otherwise interleave and silently drop entries. The closures
/// are synchronous, so actor reentrancy cannot split a cycle.
private actor NoteIndexWriteQueue {
    static let shared = NoteIndexWriteQueue()
    func perform(_ work: @Sendable () -> Void) { work() }
}

/// Generates and maintains .meta/note-index.json for AI vault navigation.
/// Replaces MOCGenerator with a single JSON index that AI tools can read efficiently.
struct NoteIndexGenerator: Sendable {
    let pkmRoot: String
    private let canonicalRoot: String

    private static let currentVersion = 1

    init(pkmRoot: String) {
        self.pkmRoot = pkmRoot
        let resolved = URL(fileURLWithPath: pkmRoot).resolvingSymlinksInPath().path
        self.canonicalRoot = resolved.hasSuffix("/") ? resolved : resolved + "/"
    }

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Public API

    /// Incremental update: re-scan only the specified folders, merge into existing index
    func updateForFolders(_ folderPaths: Set<String>) async {
        await NoteIndexWriteQueue.shared.perform {
            var index = loadExisting() ?? emptyIndex()

            // Reverse indexes make stale-entry removal O(1) per note instead
            // of a full key scan per note (quadratic on bootstrap-sized runs)
            var keysByFolder: [String: Set<String>] = [:]
            var keysByFileName: [String: Set<String>] = [:]
            for (key, entry) in index.notes {
                keysByFolder[entry.folder, default: []].insert(key)
                keysByFileName[(key as NSString).lastPathComponent, default: []].insert(key)
            }

            func removeNote(_ key: String) {
                guard let entry = index.notes.removeValue(forKey: key) else { return }
                keysByFolder[entry.folder]?.remove(key)
                keysByFileName[(key as NSString).lastPathComponent]?.remove(key)
            }
            func insertNote(_ key: String, _ entry: NoteIndexEntry) {
                index.notes[key] = entry
                keysByFolder[entry.folder, default: []].insert(key)
                keysByFileName[(key as NSString).lastPathComponent, default: []].insert(key)
            }

            for folderPath in folderPaths {
                let folderName = (folderPath as NSString).lastPathComponent
                let para = PARACategory.fromPath(folderPath) ?? .archive
                let relFolder = relativePath(folderPath)
                let includeFolderEntry = folderPath != pathManager.paraPath(for: para)

                // Remove old notes belonging to this folder
                for key in Array(keysByFolder[relFolder] ?? []) {
                    removeNote(key)
                }

                // Scan and add fresh entries
                let (folderEntry, noteEntries) = scanFolder(
                    folderPath: folderPath,
                    folderName: folderName,
                    para: para,
                    includeFolderEntry: includeFolderEntry
                )

                if let folderEntry {
                    index.folders[relFolder] = folderEntry
                } else {
                    index.folders.removeValue(forKey: relFolder)
                }

                for (notePath, entry) in noteEntries {
                    // Remove stale entries for the same filename in other folders
                    let fileName = (notePath as NSString).lastPathComponent
                    for key in Array(keysByFileName[fileName] ?? []) where key != notePath {
                        removeNote(key)
                    }
                    insertNote(notePath, entry)
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
    }

    /// Full regeneration: scan all PARA categories from scratch
    func regenerateAll() async {
        await NoteIndexWriteQueue.shared.perform {
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
                let (_, rootNoteEntries) = scanFolder(
                    folderPath: basePath,
                    folderName: (basePath as NSString).lastPathComponent,
                    para: para,
                    includeFolderEntry: false
                )
                for (notePath, noteEntry) in rootNoteEntries {
                    allNotes[notePath] = noteEntry
                }

                // Recurse into nested subfolders (vault allows up to depth 3);
                // scanFolder itself stays non-recursive so each folder keeps
                // its own entry
                guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
                var subfolderPaths: [String] = []
                while let element = enumerator.nextObject() as? String {
                    let name = (element as NSString).lastPathComponent
                    let folderPath = (basePath as NSString).appendingPathComponent(element)
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                    if name.hasPrefix(".") || name.hasPrefix("_") {
                        enumerator.skipDescendants()
                        continue
                    }
                    guard pathManager.isPathSafe(folderPath) else { continue }
                    subfolderPaths.append(folderPath)
                }

                for folderPath in subfolderPaths.sorted() {
                    let (folderEntry, noteEntries) = scanFolder(
                        folderPath: folderPath,
                        folderName: (folderPath as NSString).lastPathComponent,
                        para: para,
                        includeFolderEntry: true
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
    }

    /// Remove index entries for folders that no longer exist on disk.
    /// Incremental `updateForFolders` only re-scans dirty folders, so deleted
    /// folders leave stale folder/note entries behind and pollute index-first
    /// context. Call this during vault checks to keep the index consistent.
    /// Mirrors `FolderRelationStore.pruneStale`.
    func pruneStale(existingFolders: Set<String>) async {
        await NoteIndexWriteQueue.shared.perform {
            pruneStaleSync(existingFolders: existingFolders)
        }
    }

    private func pruneStaleSync(existingFolders: Set<String>) {
        guard var index = loadExisting() else { return }

        // Notes directly under a PARA category root (not in a subfolder) are
        // keyed by the category relpath, which is never in existingFolders.
        let categoryRoots: Set<String> = Set([
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ].map { relativePath($0) })

        let normalized = Set(existingFolders.map { $0.precomposedStringWithCanonicalMapping })
        func isLive(_ folder: String) -> Bool {
            let key = folder.precomposedStringWithCanonicalMapping
            return categoryRoots.contains(key) || normalized.contains(key)
        }

        let folderCountBefore = index.folders.count
        let noteCountBefore = index.notes.count

        index.folders = index.folders.filter { isLive($0.key) }
        index.notes = index.notes.filter { isLive($0.value.folder) }

        let prunedFolders = folderCountBefore - index.folders.count
        let prunedNotes = noteCountBefore - index.notes.count
        guard prunedFolders + prunedNotes > 0 else { return }

        save(NoteIndex(
            version: NoteIndexGenerator.currentVersion,
            updated: Self.timestamp(),
            folders: index.folders,
            notes: index.notes
        ))
        NSLog("[NoteIndexGenerator] Pruned %d stale folders, %d stale notes", prunedFolders, prunedNotes)
    }

    // MARK: - Private Helpers

    /// Scan a single folder, returning its folder entry and all note entries
    private func scanFolder(
        folderPath: String,
        folderName: String,
        para: PARACategory,
        includeFolderEntry: Bool
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
            // Skip non-markdown, hidden, underscore-prefixed files
            guard entry.hasSuffix(".md"),
                  !entry.hasPrefix("."),
                  !entry.hasPrefix("_") else { continue }

            let filePath = (folderPath as NSString).appendingPathComponent(entry)
            guard let handle = FileHandle(forReadingAtPath: filePath) else { continue }
            let data = handle.readData(ofLength: 4096)
            handle.closeFile()
            // readData may cut in the middle of a multi-byte UTF-8 character;
            // try trimming up to 3 trailing bytes to recover a valid string
            var content: String?
            for trim in 0...min(3, data.count) {
                if let s = String(data: data.dropLast(trim), encoding: .utf8) {
                    content = s
                    break
                }
            }
            guard let content else { continue }

            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            let relNotePath = relativePath(filePath)

            let noteEntry = NoteIndexEntry(
                path: relNotePath,
                folder: relFolder,
                para: para.rawValue,
                tags: frontmatter.tags,
                summary: frontmatter.summary ?? "",
                project: frontmatter.project,
                status: frontmatter.status?.rawValue,
                area: frontmatter.area
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

        guard includeFolderEntry else {
            return (nil, noteEntries)
        }

        // Top 10 tags by frequency
        let topTags = tagCounts
            .sorted { $0.value > $1.value }
            .prefix(10)
            .map { $0.key }

        // Folder summary: combine first few note summaries or use count
        let folderSummary: String
        if noteEntries.isEmpty {
            folderSummary = "\(folderName) (\(para.rawValue))"
        } else if summaries.isEmpty {
            folderSummary = "\(noteEntries.count) notes"
        } else {
            folderSummary = summaries.prefix(3).joined(separator: "; ")
        }

        // Use folder name as tag when no notes provide tags
        let finalTags = topTags.isEmpty ? [folderName] : topTags

        let folderEntry = FolderIndexEntry(
            path: relFolder,
            para: para.rawValue,
            summary: folderSummary,
            tags: finalTags
        )

        return (folderEntry, noteEntries)
    }

    /// Convert an absolute path to a path relative to pkmRoot (canonicalized for symlink safety, NFC-normalized)
    private func relativePath(_ absolutePath: String) -> String {
        let canonicalPath = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath().path
        guard canonicalPath.hasPrefix(canonicalRoot) else {
            return absolutePath.precomposedStringWithCanonicalMapping
        }
        return String(canonicalPath.dropFirst(canonicalRoot.count))
            .precomposedStringWithCanonicalMapping
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

    /// Save index to .meta/note-index.json with prettyPrinted + sortedKeys
    private func save(_ index: NoteIndex) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        let indexPath = metaIndexPath()

        // Create .meta/ directory if needed
        if !fm.fileExists(atPath: metaDir) {
            do {
                try fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
            } catch {
                NSLog("[NoteIndexGenerator] Failed to create .meta directory: %@", error.localizedDescription)
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

    /// Path to .meta/note-index.json
    private func metaIndexPath() -> String {
        (pkmRoot as NSString)
            .appendingPathComponent(".meta")
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
        ISO8601DateFormatter().string(from: Date())
    }
}
