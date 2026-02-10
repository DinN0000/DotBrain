import Foundation

/// Scans _Inbox/ folder for files to process
struct InboxScanner {
    let pkmRoot: String

    /// System files to ignore
    private static let ignoredFiles: Set<String> = [
        ".DS_Store", ".gitkeep", ".obsidian", "Thumbs.db",
    ]

    private static let ignoredPrefixes = [".", "_"]

    /// Scan inbox and return file paths
    func scan() -> [String] {
        let inboxPath = PKMPathManager(root: pkmRoot).inboxPath
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(atPath: inboxPath) else {
            return []
        }

        return entries.compactMap { name -> String? in
            // Skip system files
            guard !Self.ignoredFiles.contains(name) else { return nil }
            guard !Self.ignoredPrefixes.contains(where: { name.hasPrefix($0) }) else { return nil }

            let fullPath = (inboxPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue else {
                return nil
            }

            return fullPath
        }.sorted()
    }
}
