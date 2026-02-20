import Foundation

/// Manages PARA folder paths for the PKM vault
struct PKMPathManager {
    let root: String

    var inboxPath: String { (root as NSString).appendingPathComponent("_Inbox") }
    var centralAssetsPath: String { (root as NSString).appendingPathComponent("_Assets") }
    var documentsAssetsPath: String { (centralAssetsPath as NSString).appendingPathComponent("documents") }
    var imagesAssetsPath: String { (centralAssetsPath as NSString).appendingPathComponent("images") }
    var projectsPath: String { (root as NSString).appendingPathComponent("1_Project") }
    var areaPath: String { (root as NSString).appendingPathComponent("2_Area") }
    var resourcePath: String { (root as NSString).appendingPathComponent("3_Resource") }
    var archivePath: String { (root as NSString).appendingPathComponent("4_Archive") }
    var metaPath: String { (root as NSString).appendingPathComponent("_meta") }
    var noteIndexPath: String { (metaPath as NSString).appendingPathComponent("note-index.json") }

    /// Get the base path for a PARA category
    func paraPath(for category: PARACategory) -> String {
        switch category {
        case .project: return projectsPath
        case .area: return areaPath
        case .resource: return resourcePath
        case .archive: return archivePath
        }
    }

    /// Sanitize a folder name to prevent path traversal attacks
    private func sanitizeFolderName(_ name: String) -> String {
        let components = name.components(separatedBy: "/")
        let safe = components.filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        let limited = Array(safe.prefix(3))
        return limited.map { component in
            let cleaned = component.replacingOccurrences(of: "\0", with: "")
            return String(cleaned.prefix(255))
        }.joined(separator: "/")
    }

    /// Get the target directory for a classification result
    func targetDirectory(for result: ClassifyResult) -> String {
        if result.para == .project, let project = result.project {
            let safeProject = sanitizeFolderName(project)
            let targetPath = (projectsPath as NSString).appendingPathComponent(safeProject)
            guard isPathInsideRoot(targetPath, base: projectsPath) else { return projectsPath }
            return targetPath
        }

        let base = paraPath(for: result.para)
        let sanitized = sanitizeTargetFolder(result.targetFolder, para: result.para)
        if sanitized.isEmpty {
            return base
        }
        let safeFolder = sanitizeFolderName(sanitized)
        let targetPath = (base as NSString).appendingPathComponent(safeFolder)
        guard isPathInsideRoot(targetPath, base: base) else { return base }
        return targetPath
    }

    /// Strip PARA category names from the beginning of target folder to prevent nesting (e.g., "Area/DevOps" → "DevOps")
    private func sanitizeTargetFolder(_ folder: String, para: PARACategory) -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let dangerousNames: Set<String> = [
            para.folderName.lowercased(),   // "2_area"
            para.displayName.lowercased(),  // "area"
            para.rawValue.lowercased()      // "area"
        ]
        let inboxNames: Set<String> = ["inbox", "_inbox"]

        let components = trimmed.components(separatedBy: "/").filter { !$0.isEmpty }
        guard let first = components.first else { return "" }

        let normalizedFirst = first.lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
            .replacingOccurrences(of: #"^[1-4][\s_\-]?"#, with: "", options: .regularExpression)

        if dangerousNames.contains(normalizedFirst) || inboxNames.contains(normalizedFirst) {
            let remaining = Array(components.dropFirst())
            return remaining.joined(separator: "/")
        }
        return trimmed
    }

    /// Get the centralized assets subdirectory for a file based on its extension
    func assetsDirectory(for filePath: String) -> String {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        if BinaryExtractor.imageExtensions.contains(ext) {
            return imagesAssetsPath
        }
        return documentsAssetsPath
    }

    /// Validate that a path is safely within the PKM root (prevents symlink traversal)
    /// Call this before any file read/write to untrusted paths
    func isPathSafe(_ path: String) -> Bool {
        let resolvedRoot = URL(fileURLWithPath: root).standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return isPathInsideResolvedRoot(resolvedPath, resolvedRoot: resolvedRoot)
    }

    private func isPathInsideRoot(_ path: String, base: String) -> Bool {
        let resolvedBase = URL(fileURLWithPath: base).standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        return isPathInsideResolvedRoot(resolvedPath, resolvedRoot: resolvedBase)
    }

    private func isPathInsideResolvedRoot(_ path: String, resolvedRoot: String) -> Bool {
        if path == resolvedRoot { return true }
        let normalizedRoot = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return path.hasPrefix(normalizedRoot)
    }

    /// Check if PKM folder structure exists
    func isInitialized() -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: root)
            && fm.fileExists(atPath: inboxPath)
            && fm.fileExists(atPath: projectsPath)
    }

    /// Create the full PARA folder structure
    func initializeStructure() throws {
        let fm = FileManager.default
        let folders = [inboxPath, projectsPath, areaPath, resourcePath, archivePath,
                       documentsAssetsPath, imagesAssetsPath, metaPath]
        for folder in folders {
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
        
        // Generate AI companion files (CLAUDE.md, AGENTS.md, .cursorrules, agents, skills)
        try AICompanionService.generateAll(pkmRoot: root)

        // Create .Templates/ folder with default templates
        try TemplateService.initializeTemplates(pkmRoot: root)
    }

    /// Get existing subfolders for Area/Resource/Archive
    func existingSubfolders() -> [String: [String]] {
        var result: [String: [String]] = [
            "area": [],
            "resource": [],
            "archive": [],
        ]

        let fm = FileManager.default
        let mappings: [(String, String)] = [
            ("area", areaPath),
            ("resource", resourcePath),
            ("archive", archivePath),
        ]

        for (key, dirPath) in mappings {
            guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { continue }
            var isDir: ObjCBool = false
            result[key] = entries.filter { name in
                !name.hasPrefix(".") && !name.hasPrefix("_")
                    && fm.fileExists(atPath: (dirPath as NSString).appendingPathComponent(name), isDirectory: &isDir)
                    && isDir.boolValue
            }
        }

        return result
    }
}
