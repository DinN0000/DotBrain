import Foundation

struct ProjectManager {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Create

    /// Create a new project with folder and index note
    func createProject(name: String, summary: String = "") throws -> String {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)

        guard pathManager.isPathSafe(projectDir) else {
            throw ProjectError.notFound(safeName) // path traversal — invalid path
        }
        guard !fm.fileExists(atPath: projectDir) else {
            throw ProjectError.alreadyExists(safeName)
        }

        // Create project directory (assets go to centralized _Assets/)
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)

        // Create index note
        let indexContent = FrontmatterWriter.createIndexNote(
            folderName: safeName,
            para: .project,
            description: summary
        )

        // Add project-specific sections
        let fullContent = indexContent + "\n## 목적\n\n\(summary)\n\n## 현재 상태\n\n진행 중\n\n## Related Notes\n\n"

        let indexPath = (projectDir as NSString).appendingPathComponent("\(safeName).md")
        try fullContent.write(toFile: indexPath, atomically: true, encoding: .utf8)

        return projectDir
    }

    // MARK: - Complete (Archive)

    /// Archive a completed project: move to 4_Archive/, update status, mark references
    func completeProject(name: String) throws -> Int {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)

        guard pathManager.isPathSafe(projectDir) else {
            throw ProjectError.notFound(safeName)
        }
        guard fm.fileExists(atPath: projectDir) else {
            throw ProjectError.notFound(safeName)
        }

        // Update all .md files in project: status -> completed, para -> archive
        let updatedCount = try updateAllNotes(in: projectDir, status: .completed, para: .archive)

        // Move folder to 4_Archive/
        let archiveDir = (pathManager.archivePath as NSString).appendingPathComponent(safeName)
        if fm.fileExists(atPath: archiveDir) {
            let timestamp = Int(Date().timeIntervalSince1970)
            let newName = "\(safeName)_\(timestamp)"
            let newDir = (pathManager.archivePath as NSString).appendingPathComponent(newName)
            try fm.moveItem(atPath: projectDir, toPath: newDir)
        } else {
            try fm.moveItem(atPath: projectDir, toPath: archiveDir)
        }

        // Mark references in other notes with "(완료됨)"
        markReferencesCompleted(projectName: safeName)

        return updatedCount
    }

    // MARK: - Reactivate

    /// Restore a project from archive back to 1_Project/
    func reactivateProject(name: String) throws -> Int {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let archiveDir = (pathManager.archivePath as NSString).appendingPathComponent(safeName)

        guard pathManager.isPathSafe(archiveDir) else {
            throw ProjectError.notFound(safeName)
        }
        guard fm.fileExists(atPath: archiveDir) else {
            throw ProjectError.notFound(safeName)
        }

        // Check for conflict BEFORE modifying frontmatter
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)
        guard !fm.fileExists(atPath: projectDir) else {
            throw ProjectError.alreadyExists(safeName)
        }

        let updatedCount = try updateAllNotes(in: archiveDir, status: .active, para: .project)
        try fm.moveItem(atPath: archiveDir, toPath: projectDir)

        unmarkReferencesCompleted(projectName: safeName)

        return updatedCount
    }

    // MARK: - Private Helpers

    private func sanitizeName(_ name: String) -> String {
        let components = name.components(separatedBy: "/")
        let safe = components.filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        return safe.prefix(3).map { component in
            let cleaned = component
                .replacingOccurrences(of: "\0", with: "")
                .replacingOccurrences(of: "\\", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return String(cleaned.prefix(255))
        }.joined(separator: "/")
    }

    /// Recursively update all .md files under a directory via FileManager.enumerator (single OS call)
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

    private func markReferencesCompleted(projectName: String) {
        // Two-pass: strip existing marks first to prevent double-marking
        markInVault(
            pattern: "[[\(projectName)]] (완료됨)",
            replacement: "[[\(projectName)]]"
        )
        markInVault(
            pattern: "[[\(projectName)]]",
            replacement: "[[\(projectName)]] (완료됨)"
        )
    }

    private func unmarkReferencesCompleted(projectName: String) {
        markInVault(
            pattern: "[[\(projectName)]] (완료됨)",
            replacement: "[[\(projectName)]]"
        )
    }

    private func updateWikiLinks(from oldName: String, to newName: String) -> Int {
        renameInVault(
            pattern: "[[\(oldName)]]",
            replacement: "[[\(newName)]]"
        )
    }

    /// Collect all .md files across PARA categories recursively (single enumerator per category)
    private func collectVaultMarkdownFiles() -> [String] {
        let fm = FileManager.default
        let categories = [pathManager.projectsPath, pathManager.areaPath, pathManager.resourcePath, pathManager.archivePath]
        var files: [String] = []

        for basePath in categories {
            guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
            while let relativePath = enumerator.nextObject() as? String {
                guard relativePath.hasSuffix(".md") else { continue }
                let fileName = (relativePath as NSString).lastPathComponent
                guard !fileName.hasPrefix("."), !fileName.hasPrefix("_") else { continue }
                // Skip hidden/system directories
                let components = relativePath.components(separatedBy: "/")
                guard !components.contains(where: { $0.hasPrefix(".") || $0.hasPrefix("_") }) else { continue }
                files.append((basePath as NSString).appendingPathComponent(relativePath))
            }
        }

        return files
    }

    /// Simple find-and-replace across vault markdown files
    @discardableResult
    private func markInVault(pattern: String, replacement: String) -> Int {
        let files = collectVaultMarkdownFiles()
        var count = 0

        for filePath in files {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            guard content.contains(pattern) else { continue }
            let updated = content.replacingOccurrences(of: pattern, with: replacement)
            if updated != content {
                do {
                    try updated.write(toFile: filePath, atomically: true, encoding: .utf8)
                    count += 1
                } catch {
                    NSLog("[ProjectManager] WikiLink 업데이트 실패: %@ — %@", filePath, error.localizedDescription)
                }
            }
        }

        return count
    }

    /// Simple replace — for wiki link renames where normalization would be destructive
    @discardableResult
    private func renameInVault(pattern: String, replacement: String) -> Int {
        let files = collectVaultMarkdownFiles()
        var count = 0

        for filePath in files {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
            let updated = content.replacingOccurrences(of: pattern, with: replacement)
            if updated != content {
                do {
                    try updated.write(toFile: filePath, atomically: true, encoding: .utf8)
                    count += 1
                } catch {
                    NSLog("[ProjectManager] WikiLink 이름변경 실패: %@ — %@", filePath, error.localizedDescription)
                }
            }
        }

        return count
    }
}

enum ProjectError: LocalizedError {
    case alreadyExists(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name): return "프로젝트 '\(name)'이 이미 존재합니다"
        case .notFound(let name): return "프로젝트 '\(name)'을 찾을 수 없습니다"
        }
    }
}
