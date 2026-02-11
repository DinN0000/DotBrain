import Foundation

/// Manages PARA folder paths for the PKM vault
struct PKMPathManager {
    let root: String

    var inboxPath: String { (root as NSString).appendingPathComponent("_Inbox") }
    var assetsPath: String { (root as NSString).appendingPathComponent("_Assets") }
    var projectsPath: String { (root as NSString).appendingPathComponent("1_Project") }
    var areaPath: String { (root as NSString).appendingPathComponent("2_Area") }
    var resourcePath: String { (root as NSString).appendingPathComponent("3_Resource") }
    var archivePath: String { (root as NSString).appendingPathComponent("4_Archive") }

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
        // Remove path traversal components and absolute path prefixes
        let components = name.components(separatedBy: "/")
        let safe = components.filter { $0 != ".." && $0 != "." && !$0.isEmpty }
        return safe.joined(separator: "/")
    }

    /// Get the target directory for a classification result
    func targetDirectory(for result: ClassifyResult) -> String {
        if result.para == .project, let project = result.project {
            let safeProject = sanitizeFolderName(project)
            let targetPath = (projectsPath as NSString).appendingPathComponent(safeProject)
            // Verify the resolved path is within projectsPath
            guard targetPath.hasPrefix(projectsPath) else { return projectsPath }
            return targetPath
        }

        let base = paraPath(for: result.para)
        if result.targetFolder.isEmpty {
            return base
        }
        let safeFolder = sanitizeFolderName(result.targetFolder)
        let targetPath = (base as NSString).appendingPathComponent(safeFolder)
        // Verify the resolved path is within the PARA base directory
        guard targetPath.hasPrefix(base) else { return base }
        return targetPath
    }

    /// Get the assets directory for a target directory
    func assetsDirectory(for targetDir: String) -> String {
        return (targetDir as NSString).appendingPathComponent("_Assets")
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
        let folders = [inboxPath, projectsPath, areaPath, resourcePath, archivePath]
        for folder in folders {
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
        }
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
