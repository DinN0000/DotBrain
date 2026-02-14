import Foundation

struct PARAMover {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Move

    /// Move a folder from one PARA category to another.
    /// Updates all internal .md frontmatter (para + status), moves the folder,
    /// and updates WikiLink references if moving to/from archive.
    /// Returns the number of notes updated.
    func moveFolder(name: String, from source: PARACategory, to target: PARACategory) throws -> Int {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let sourcePath = pathManager.paraPath(for: source)
        let targetPath = pathManager.paraPath(for: target)
        let sourceDir = (sourcePath as NSString).appendingPathComponent(safeName)

        guard fm.fileExists(atPath: sourceDir) else {
            throw PARAMoveError.notFound(safeName, source)
        }

        // Determine status: .completed for archive, .active otherwise
        let newStatus: NoteStatus = target == .archive ? .completed : .active

        // Update all .md frontmatter in the source folder before moving
        let updatedCount = try updateAllNotes(in: sourceDir, status: newStatus, para: target)

        // Move folder to target category, resolving conflicts with timestamp suffix
        var destinationDir = (targetPath as NSString).appendingPathComponent(safeName)
        if fm.fileExists(atPath: destinationDir) {
            let timestamp = Int(Date().timeIntervalSince1970)
            destinationDir = (targetPath as NSString).appendingPathComponent("\(safeName)_\(timestamp)")
        }
        try fm.moveItem(atPath: sourceDir, toPath: destinationDir)

        // Update WikiLink references across the vault
        if target == .archive {
            markReferencesCompleted(folderName: safeName)
        } else if source == .archive {
            unmarkReferencesCompleted(folderName: safeName)
        }

        return updatedCount
    }

    // MARK: - List

    /// List all folders in a given PARA category with file count and summary.
    func listFolders(in category: PARACategory) -> [(name: String, fileCount: Int, summary: String)] {
        let fm = FileManager.default
        let basePath = pathManager.paraPath(for: category)

        guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else {
            return []
        }

        var results: [(name: String, fileCount: Int, summary: String)] = []

        for entry in entries.sorted() {
            guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }

            let dirPath = (basePath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // Count non-hidden, non-underscore files
            let fileCount: Int
            if let files = try? fm.contentsOfDirectory(atPath: dirPath) {
                fileCount = files.filter { !$0.hasPrefix(".") && !$0.hasPrefix("_") }.count
            } else {
                fileCount = 0
            }

            // Read index note frontmatter for summary
            let indexPath = (dirPath as NSString).appendingPathComponent("\(entry).md")
            let summary: String
            if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                let (frontmatter, _) = Frontmatter.parse(markdown: content)
                summary = frontmatter.summary ?? ""
            } else {
                summary = ""
            }

            results.append((name: entry, fileCount: fileCount, summary: summary))
        }

        return results
    }

    // MARK: - Private Helpers

    private func sanitizeName(_ name: String) -> String {
        let components = name.components(separatedBy: "/")
        let safe = components.filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        return safe.prefix(3).map { component in
            let cleaned = component
                .replacingOccurrences(of: "\0", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(cleaned.prefix(255))
        }.joined(separator: "/")
    }

    /// Recursively update all .md files under a directory via FileManager.enumerator
    private func updateAllNotes(in directory: String, status: NoteStatus, para: PARACategory) throws -> Int {
        let fm = FileManager.default
        var count = 0

        guard let enumerator = fm.enumerator(atPath: directory) else { return 0 }
        while let relativePath = enumerator.nextObject() as? String {
            guard relativePath.hasSuffix(".md") else { continue }
            let fileName = (relativePath as NSString).lastPathComponent
            guard !fileName.hasPrefix("."), !fileName.hasPrefix("_") else { continue }

            let filePath = (directory as NSString).appendingPathComponent(relativePath)
            guard var content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (existing, body) = Frontmatter.parse(markdown: content)
            var updated = existing
            updated.status = status
            updated.para = para
            content = updated.stringify() + "\n" + body
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            count += 1
        }

        return count
    }

    private func markReferencesCompleted(folderName: String) {
        markInVault(
            pattern: "[[\(folderName)]]",
            replacement: "[[\(folderName)]] (완료됨)"
        )
    }

    private func unmarkReferencesCompleted(folderName: String) {
        markInVault(
            pattern: "[[\(folderName)]] (완료됨)",
            replacement: "[[\(folderName)]]"
        )
    }

    /// Collect all .md files across PARA categories recursively
    private func collectVaultMarkdownFiles() -> [String] {
        let fm = FileManager.default
        let categories = [
            pathManager.projectsPath, pathManager.areaPath,
            pathManager.resourcePath, pathManager.archivePath,
        ]
        var files: [String] = []

        for basePath in categories {
            guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
            while let relativePath = enumerator.nextObject() as? String {
                guard relativePath.hasSuffix(".md") else { continue }
                let fileName = (relativePath as NSString).lastPathComponent
                guard !fileName.hasPrefix("."), !fileName.hasPrefix("_") else { continue }
                let components = relativePath.components(separatedBy: "/")
                guard !components.contains(where: { $0.hasPrefix(".") || $0.hasPrefix("_") }) else { continue }
                files.append((basePath as NSString).appendingPathComponent(relativePath))
            }
        }

        return files
    }

    /// Replace with normalization to prevent double-marking
    @discardableResult
    private func markInVault(pattern: String, replacement: String) -> Int {
        let files = collectVaultMarkdownFiles()
        var count = 0

        for filePath in files {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let normalized = content.replacingOccurrences(of: replacement, with: pattern)
            let updated = normalized.replacingOccurrences(of: pattern, with: replacement)
            if updated != content {
                try? updated.write(toFile: filePath, atomically: true, encoding: .utf8)
                count += 1
            }
        }

        return count
    }
}

// MARK: - Error

enum PARAMoveError: LocalizedError {
    case notFound(String, PARACategory)
    case alreadyExists(String, PARACategory)

    var errorDescription: String? {
        switch self {
        case .notFound(let name, let cat):
            return "'\(name)' 폴더를 \(cat.displayName)에서 찾을 수 없습니다"
        case .alreadyExists(let name, let cat):
            return "'\(name)' 폴더가 이미 \(cat.displayName)에 존재합니다"
        }
    }
}
