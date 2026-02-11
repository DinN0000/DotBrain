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

    /// Ignored extensions (system/temp files + code files)
    private static let ignoredExtensions: Set<String> = [
        // System/temp
        "tmp", "swp", "lock", "part",
        // Source code
        "swift", "py", "js", "ts", "jsx", "tsx", "go", "rs", "java",
        "c", "cpp", "h", "hpp", "cs", "rb", "php", "kt", "scala",
        "m", "mm", "r", "lua", "pl", "sh", "bash", "zsh", "fish",
        "vue", "svelte", "astro",
        // Config/build
        "json", "toml", "yml", "yaml", "xml", "ini", "cfg", "conf",
        "gradle", "cmake", "makefile",
        // Compiled/binary dev artifacts
        "o", "a", "so", "dylib", "class", "pyc", "pyo",
        "wasm", "dll", "exe", "bin",
        // Package/lock files
        "resolved",
    ]

    /// Dev project marker files — if a folder contains any of these, it's a code project
    private static let codeProjectMarkers: Set<String> = [
        ".git", ".gitignore", "Package.swift", "package.json",
        "Cargo.toml", "go.mod", "pom.xml", "build.gradle",
        "Makefile", "CMakeLists.txt", "Gemfile", "requirements.txt",
        "pyproject.toml", "setup.py", "tsconfig.json", ".xcodeproj",
        ".xcworkspace", "Podfile", "pubspec.yaml", ".sln", ".csproj",
    ]

    /// Dev file names to always skip (even without extension check)
    private static let ignoredFileNames: Set<String> = [
        "package.json", "package-lock.json", "yarn.lock", "pnpm-lock.yaml",
        "Cargo.lock", "Gemfile.lock", "Podfile.lock", "go.sum",
        "Makefile", "Dockerfile", "docker-compose.yml",
        ".gitignore", ".gitmodules", ".editorconfig", ".prettierrc",
        ".eslintrc", ".eslintrc.js", ".eslintrc.json",
        "tsconfig.json", "webpack.config.js", "vite.config.ts",
        "LICENSE", "LICENSE.md", "CONTRIBUTING.md", "CHANGELOG.md",
    ]

    /// Scan inbox and return top-level items (both files and folders).
    /// Skips code files and code project folders automatically.
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

            // Skip code project folders
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
                if Self.isCodeProject(at: fullPath, fm: fm) {
                    print("[InboxScanner] 코드 프로젝트 건너뜀: \(name)")
                    return nil
                }
            }

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
        guard !Self.ignoredFileNames.contains(name) else { return false }
        guard !Self.ignoredPrefixes.contains(where: { name.hasPrefix($0) }) else { return false }

        let ext = (name as NSString).pathExtension.lowercased()
        guard !Self.ignoredExtensions.contains(ext) else { return false }

        return true
    }

    /// Detect if a folder is a code/dev project by checking for marker files
    static func isCodeProject(at dirPath: String, fm: FileManager) -> Bool {
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return false }
        let entrySet = Set(entries)
        return !codeProjectMarkers.isDisjoint(with: entrySet)
    }

    private func isSymbolicLink(_ path: String, fileManager fm: FileManager) -> Bool {
        guard let attrs = try? fm.attributesOfItem(atPath: path),
              let type = attrs[.type] as? FileAttributeType else { return false }
        return type == .typeSymbolicLink
    }
}
