import Foundation

struct ProjectManager {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Create

    /// Create a new project with folder, index note, and _Assets/
    func createProject(name: String, summary: String = "") throws -> String {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)

        guard !fm.fileExists(atPath: projectDir) else {
            throw ProjectError.alreadyExists(safeName)
        }

        // Create project directory and _Assets/
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let assetsDir = (projectDir as NSString).appendingPathComponent("_Assets")
        try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

        // Create index note
        let indexContent = FrontmatterWriter.createIndexNote(
            folderName: safeName,
            para: .project,
            description: summary
        )

        // Add project-specific sections
        let fullContent = indexContent + "\n## 목적\n\n\(summary)\n\n## 현재 상태\n\n진행 중\n\n## 관련 노트\n\n"

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

        guard fm.fileExists(atPath: archiveDir) else {
            throw ProjectError.notFound(safeName)
        }

        let updatedCount = try updateAllNotes(in: archiveDir, status: .active, para: .project)

        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)
        guard !fm.fileExists(atPath: projectDir) else {
            throw ProjectError.alreadyExists(safeName)
        }
        try fm.moveItem(atPath: archiveDir, toPath: projectDir)

        unmarkReferencesCompleted(projectName: safeName)

        return updatedCount
    }

    // MARK: - Rename

    /// Rename a project: folder, index note, and all WikiLink references
    func renameProject(from oldName: String, to newName: String) throws -> Int {
        let fm = FileManager.default
        let safeOld = sanitizeName(oldName)
        let safeNew = sanitizeName(newName)
        let oldDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeOld)

        guard fm.fileExists(atPath: oldDir) else {
            throw ProjectError.notFound(safeOld)
        }

        let newDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeNew)
        guard !fm.fileExists(atPath: newDir) else {
            throw ProjectError.alreadyExists(safeNew)
        }

        let oldIndex = (oldDir as NSString).appendingPathComponent("\(safeOld).md")
        let newIndex = (oldDir as NSString).appendingPathComponent("\(safeNew).md")
        if fm.fileExists(atPath: oldIndex) {
            try fm.moveItem(atPath: oldIndex, toPath: newIndex)
        }

        try fm.moveItem(atPath: oldDir, toPath: newDir)

        let updatedCount = updateWikiLinks(from: safeOld, to: safeNew)

        return updatedCount
    }

    // MARK: - List

    /// List all projects with their status
    func listProjects() -> [(name: String, status: NoteStatus, summary: String)] {
        let fm = FileManager.default
        var projects: [(name: String, status: NoteStatus, summary: String)] = []

        if let entries = try? fm.contentsOfDirectory(atPath: pathManager.projectsPath) {
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let indexPath = (pathManager.projectsPath as NSString)
                    .appendingPathComponent(entry)
                    .appending("/\(entry).md")
                if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                    let (frontmatter, _) = Frontmatter.parse(markdown: content)
                    projects.append((
                        name: entry,
                        status: frontmatter.status ?? .active,
                        summary: frontmatter.summary ?? ""
                    ))
                } else {
                    projects.append((name: entry, status: .active, summary: ""))
                }
            }
        }

        if let entries = try? fm.contentsOfDirectory(atPath: pathManager.archivePath) {
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let dir = (pathManager.archivePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
                projects.append((name: entry, status: .completed, summary: "(아카이브)"))
            }
        }

        return projects
    }

    // MARK: - Private Helpers

    private func sanitizeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateAllNotes(in directory: String, status: NoteStatus, para: PARACategory) throws -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return 0 }
        var count = 0

        for file in files where file.hasSuffix(".md") {
            let filePath = (directory as NSString).appendingPathComponent(file)
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
        replaceInVault(
            pattern: "[[\(projectName)]]",
            replacement: "[[\(projectName)]] (완료됨)"
        )
    }

    private func unmarkReferencesCompleted(projectName: String) {
        replaceInVault(
            pattern: "[[\(projectName)]] (완료됨)",
            replacement: "[[\(projectName)]]"
        )
    }

    private func updateWikiLinks(from oldName: String, to newName: String) -> Int {
        replaceInVault(
            pattern: "[[\(oldName)]]",
            replacement: "[[\(newName)]]"
        )
    }

    @discardableResult
    private func replaceInVault(pattern: String, replacement: String) -> Int {
        let fm = FileManager.default
        let categories = [pathManager.projectsPath, pathManager.areaPath, pathManager.resourcePath, pathManager.archivePath]
        var count = 0

        for basePath in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }

                for file in files where file.hasSuffix(".md") {
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    // Remove any existing replacement to prevent double-marking
                    let normalized = content.replacingOccurrences(of: replacement, with: pattern)
                    let updated = normalized.replacingOccurrences(of: pattern, with: replacement)
                    if updated != content {
                        try? updated.write(toFile: filePath, atomically: true, encoding: .utf8)
                        count += 1
                    }
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
