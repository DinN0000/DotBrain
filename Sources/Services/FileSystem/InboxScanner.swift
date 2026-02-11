import Foundation

/// Scans _Inbox/ folder for files to process
struct InboxScanner {
    let pkmRoot: String

    /// Large file warning threshold (100MB)
    static let largeFileThreshold = 100 * 1024 * 1024

    /// System files to ignore
    private static let ignoredFiles: Set<String> = [
        ".DS_Store", ".gitkeep", ".obsidian", "Thumbs.db",
        "desktop.ini", "Icon\r", ".localized", ".Spotlight-V100",
        ".Trashes", ".fseventsd", ".TemporaryItems",
    ]

    private static let ignoredPrefixes = [".", "_"]

    /// Ignored extensions (system/temp files)
    private static let ignoredExtensions: Set<String> = [
        "tmp", "swp", "lock", "part",
    ]

    /// Scan inbox and return top-level items (both files and folders)
    func scan() -> [String] {
        let inboxPath = PKMPathManager(root: pkmRoot).inboxPath
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: inboxPath) else {
            return []
        }

        return entries.compactMap { name -> String? in
            guard shouldInclude(name) else { return nil }

            let fullPath = (inboxPath as NSString).appendingPathComponent(name)

            // Skip symbolic links that point outside pkmRoot
            if isSymbolicLink(fullPath, fileManager: fm) {
                guard let resolved = try? fm.destinationOfSymbolicLink(atPath: fullPath),
                      resolved.hasPrefix(pkmRoot) else {
                    return nil
                }
            }

            guard fm.fileExists(atPath: fullPath) else { return nil }

            // Log large file warnings
            if let attrs = try? fm.attributesOfItem(atPath: fullPath),
               let size = attrs[.size] as? Int,
               size > Self.largeFileThreshold {
                print("[InboxScanner] 대용량 파일 경고: \(name) (\(size / 1024 / 1024)MB)")
            }

            return fullPath
        }.sorted()
    }

    /// List all readable text files inside a directory (for content extraction)
    func filesInDirectory(at dirPath: String) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return [] }

        return entries.compactMap { name -> String? in
            guard shouldInclude(name) else { return nil }

            let fullPath = (dirPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else { return nil }
            return fullPath
        }.sorted()
    }

    // MARK: - Private

    private func shouldInclude(_ name: String) -> Bool {
        guard !Self.ignoredFiles.contains(name) else { return false }
        guard !Self.ignoredPrefixes.contains(where: { name.hasPrefix($0) }) else { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        guard !Self.ignoredExtensions.contains(ext) else { return false }

        return true
    }

    private func isSymbolicLink(_ path: String, fileManager fm: FileManager) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else { return false }
        return type == .typeSymbolicLink
    }
}
