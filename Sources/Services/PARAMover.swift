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

        guard pathManager.isPathSafe(sourceDir) else {
            throw PARAMoveError.notFound(safeName, source)
        }
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

        // Clean up Area projects field when moving a project out of 1_Project
        if source == .project {
            FrontmatterWriter.removeProjectFromArea(projectName: safeName, pkmRoot: pkmRoot)
        }

        return updatedCount
    }

    // MARK: - Delete

    /// Move a folder to macOS Trash (recoverable via Finder).
    func deleteFolder(name: String, category: PARACategory) throws {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let basePath = pathManager.paraPath(for: category)
        let folderPath = (basePath as NSString).appendingPathComponent(safeName)

        guard pathManager.isPathSafe(folderPath) else {
            throw PARAMoveError.notFound(safeName, category)
        }
        guard fm.fileExists(atPath: folderPath) else {
            throw PARAMoveError.notFound(safeName, category)
        }

        // Clean up Area projects field before deleting
        if category == .project {
            FrontmatterWriter.removeProjectFromArea(projectName: safeName, pkmRoot: pkmRoot)
        }

        let folderURL = URL(fileURLWithPath: folderPath)
        try fm.trashItem(at: folderURL, resultingItemURL: nil)
    }

    // MARK: - Merge

    /// Merge source folder into target folder within the same category.
    /// Moves all files from source to target, appending timestamp on conflict.
    /// Updates frontmatter project fields, then deletes source folder.
    /// Returns the number of files moved.
    func mergeFolder(source: String, into target: String, category: PARACategory) throws -> Int {
        let fm = FileManager.default
        let safeSource = sanitizeName(source)
        let safeTarget = sanitizeName(target)
        let basePath = pathManager.paraPath(for: category)
        let sourceDir = (basePath as NSString).appendingPathComponent(safeSource)
        let targetDir = (basePath as NSString).appendingPathComponent(safeTarget)

        guard pathManager.isPathSafe(sourceDir), pathManager.isPathSafe(targetDir) else {
            throw PARAMoveError.notFound(safeSource, category)
        }
        guard fm.fileExists(atPath: sourceDir) else {
            throw PARAMoveError.notFound(safeSource, category)
        }
        guard fm.fileExists(atPath: targetDir) else {
            throw PARAMoveError.notFound(safeTarget, category)
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: sourceDir) else { return 0 }
        var movedCount = 0

        for entry in entries {
            guard !entry.hasPrefix(".") else { continue }

            // Skip source's own index note
            if entry == "\(safeSource).md" { continue }
            // Skip _Assets — move files to centralized _Assets/{documents,images}/
            if entry == "_Assets" {
                let sourceAssets = (sourceDir as NSString).appendingPathComponent("_Assets")
                var assetMoveFailed = false
                if let assetFiles = try? fm.contentsOfDirectory(atPath: sourceAssets) {
                    for assetFile in assetFiles where !assetFile.hasPrefix(".") {
                        let src = (sourceAssets as NSString).appendingPathComponent(assetFile)
                        let centralDir = pathManager.assetsDirectory(for: assetFile)
                        try? fm.createDirectory(atPath: centralDir, withIntermediateDirectories: true)
                        var dst = (centralDir as NSString).appendingPathComponent(assetFile)
                        if fm.fileExists(atPath: dst) {
                            let ext = (assetFile as NSString).pathExtension
                            let base = (assetFile as NSString).deletingPathExtension
                            let ts = Int(Date().timeIntervalSince1970)
                            dst = (centralDir as NSString).appendingPathComponent(
                                ext.isEmpty ? "\(base)_\(ts)" : "\(base)_\(ts).\(ext)"
                            )
                        }
                        do {
                            try fm.moveItem(atPath: src, toPath: dst)
                        } catch {
                            assetMoveFailed = true
                            NSLog("[PARAMover] 에셋 이동 실패 %@: %@", src, error.localizedDescription)
                        }
                    }
                }
                // Remove the now-empty local _Assets/ directory only if all moves succeeded
                if !assetMoveFailed {
                    let remaining = (try? fm.contentsOfDirectory(atPath: sourceAssets))?.filter { !$0.hasPrefix(".") } ?? []
                    if remaining.isEmpty {
                        try? fm.removeItem(atPath: sourceAssets)
                    }
                }
                continue
            }

            let srcPath = (sourceDir as NSString).appendingPathComponent(entry)
            var dstPath = (targetDir as NSString).appendingPathComponent(entry)

            // Resolve name conflicts with timestamp
            if fm.fileExists(atPath: dstPath) {
                let ext = (entry as NSString).pathExtension
                let base = (entry as NSString).deletingPathExtension
                let ts = Int(Date().timeIntervalSince1970)
                let newName = ext.isEmpty ? "\(base)_\(ts)" : "\(base)_\(ts).\(ext)"
                dstPath = (targetDir as NSString).appendingPathComponent(newName)
            }

            try fm.moveItem(atPath: srcPath, toPath: dstPath)
            movedCount += 1

            // Update project field in frontmatter for .md files
            if entry.hasSuffix(".md") {
                if var content = try? String(contentsOfFile: dstPath, encoding: .utf8) {
                    let (existing, body) = Frontmatter.parse(markdown: content)
                    if existing.project == safeSource {
                        var updated = existing
                        updated.project = safeTarget
                        content = updated.stringify() + "\n" + body
                        do {
                            try content.write(toFile: dstPath, atomically: true, encoding: .utf8)
                        } catch {
                            NSLog("[PARAMover] 프론트매터 업데이트 실패: %@ — %@", dstPath, error.localizedDescription)
                        }
                    }
                }
            }
        }

        // Delete source index note that was skipped during merge
        let sourceIndex = (sourceDir as NSString).appendingPathComponent("\(safeSource).md")
        try? fm.removeItem(atPath: sourceIndex)

        // Remove now-empty source folder
        try? fm.removeItem(atPath: sourceDir)

        // Clean up Area projects field for merged-away project
        if category == .project {
            FrontmatterWriter.removeProjectFromArea(projectName: safeSource, pkmRoot: pkmRoot)
        }

        return movedCount
    }

    // MARK: - Rename

    /// Rename a folder within the same PARA category.
    /// Updates frontmatter project fields, renames index note, and updates WikiLink references.
    /// Returns the number of notes updated.
    func renameFolder(oldName: String, newName: String, category: PARACategory) throws -> Int {
        let fm = FileManager.default
        let safeOld = sanitizeName(oldName)
        let safeNew = sanitizeName(newName)
        guard !safeNew.isEmpty else { throw PARAMoveError.notFound(safeNew, category) }

        let basePath = pathManager.paraPath(for: category)
        let oldDir = (basePath as NSString).appendingPathComponent(safeOld)
        let newDir = (basePath as NSString).appendingPathComponent(safeNew)

        guard pathManager.isPathSafe(oldDir) else {
            throw PARAMoveError.notFound(safeOld, category)
        }
        guard fm.fileExists(atPath: oldDir) else {
            throw PARAMoveError.notFound(safeOld, category)
        }
        guard !fm.fileExists(atPath: newDir) else {
            throw PARAMoveError.alreadyExists(safeNew, category)
        }

        // Update frontmatter project fields in all .md files (while oldName.md still exists)
        var count = 0
        if let enumerator = fm.enumerator(atPath: oldDir) {
            while let relativePath = enumerator.nextObject() as? String {
                guard relativePath.hasSuffix(".md") else { continue }
                let filePath = (oldDir as NSString).appendingPathComponent(relativePath)
                guard var content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                let (existing, body) = Frontmatter.parse(markdown: content)
                if existing.project == safeOld {
                    var updated = existing
                    updated.project = safeNew
                    content = updated.stringify() + "\n" + body
                    try content.write(toFile: filePath, atomically: true, encoding: .utf8)
                    count += 1
                }
            }
        }

        // Rename index note after enumerator is done (avoids stale path in live enumeration)
        let oldIndex = (oldDir as NSString).appendingPathComponent("\(safeOld).md")
        let newIndex = (oldDir as NSString).appendingPathComponent("\(safeNew).md")
        if fm.fileExists(atPath: oldIndex) {
            try fm.moveItem(atPath: oldIndex, toPath: newIndex)
        }

        // Move (rename) the folder
        try fm.moveItem(atPath: oldDir, toPath: newDir)

        // Update WikiLink references across the vault
        markInVault(pattern: "[[\(safeOld)]]", replacement: "[[\(safeNew)]]")

        // Update Area projects field for renamed project
        if category == .project {
            FrontmatterWriter.renameProjectInArea(oldName: safeOld, newName: safeNew, pkmRoot: pkmRoot)
        }

        return count
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
        // Two-pass: strip existing marks first to prevent double-marking
        markInVault(
            pattern: "[[\(folderName)]] (완료됨)",
            replacement: "[[\(folderName)]]"
        )
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
                    NSLog("[PARAMover] WikiLink 업데이트 실패: %@ — %@", filePath, error.localizedDescription)
                }
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
