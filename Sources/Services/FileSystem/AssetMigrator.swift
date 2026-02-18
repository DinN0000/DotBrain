import Foundation

/// Migrates scattered per-folder _Assets/ directories to the centralized _Assets/{documents,images}/ structure
enum AssetMigrator {

    // MARK: - Result

    struct MigrationResult {
        var movedDocuments: Int = 0
        var movedImages: Int = 0
        var deletedImageCompanions: Int = 0
        var updatedCompanions: Int = 0
        var cleanedDirectories: Int = 0
        var errors: [String] = []
    }

    // MARK: - Detection

    /// Returns true if the vault has scattered _Assets/ directories or a misconfigured root _Assets/
    static func needsMigration(pkmRoot: String) -> Bool {
        let fm = FileManager.default
        let pathManager = PKMPathManager(root: pkmRoot)

        // Check 1: root _Assets/ exists but missing documents/ or images/ subdirs
        let centralAssets = pathManager.centralAssetsPath
        if fm.fileExists(atPath: centralAssets) {
            let docsExists = fm.fileExists(atPath: pathManager.documentsAssetsPath)
            let imagesExists = fm.fileExists(atPath: pathManager.imagesAssetsPath)
            if !docsExists || !imagesExists {
                return true
            }
        }

        // Check 2: root _Assets/ has files directly in it (not in subdirs)
        if hasLooseFiles(in: centralAssets) {
            return true
        }

        // Check 3: any PARA subfolder has a local _Assets/ directory
        let paraFolders = [
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ]
        for paraFolder in paraFolders {
            if hasScatteredAssets(in: paraFolder) {
                return true
            }
        }

        return false
    }

    // MARK: - Migration

    /// Migrate all scattered _Assets/ directories to centralized _Assets/{documents,images}/
    static func migrate(pkmRoot: String) -> MigrationResult {
        let fm = FileManager.default
        let pathManager = PKMPathManager(root: pkmRoot)
        var result = MigrationResult()

        NSLog("[AssetMigrator] 에셋 마이그레이션 시작: %@", pkmRoot)

        // Step 1: Ensure centralized directories exist
        do {
            try fm.createDirectory(atPath: pathManager.documentsAssetsPath, withIntermediateDirectories: true)
            try fm.createDirectory(atPath: pathManager.imagesAssetsPath, withIntermediateDirectories: true)
        } catch {
            result.errors.append("중앙 에셋 폴더 생성 실패: \(error.localizedDescription)")
            NSLog("[AssetMigrator] 중앙 폴더 생성 실패: %@", error.localizedDescription)
            return result
        }

        // Step 2: Move loose files from root _Assets/ to appropriate subdirs
        migrateLooseFiles(
            in: pathManager.centralAssetsPath,
            pathManager: pathManager,
            result: &result
        )

        // Step 3: Move files from scattered PARA subfolder _Assets/ to central
        let paraFolders = [
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ]
        for paraFolder in paraFolders {
            migrateScatteredAssets(
                paraFolder: paraFolder,
                pathManager: pathManager,
                result: &result
            )
        }

        // Step 4: Delete orphaned image companion files across all PARA folders
        deleteOrphanedImageCompanions(pkmRoot: pkmRoot, pathManager: pathManager, result: &result)

        // Step 5: Update wikilinks in document companion files
        updateCompanionWikilinks(pkmRoot: pkmRoot, pathManager: pathManager, result: &result)

        NSLog(
            "[AssetMigrator] 마이그레이션 완료 — 문서: %d, 이미지: %d, 삭제된 이미지 동반파일: %d, 업데이트된 동반파일: %d, 정리된 폴더: %d, 오류: %d",
            result.movedDocuments, result.movedImages, result.deletedImageCompanions,
            result.updatedCompanions, result.cleanedDirectories, result.errors.count
        )

        return result
    }

    // MARK: - Private Helpers

    /// Check if a directory has files directly in it (not counting subdirectories)
    private static func hasLooseFiles(in dirPath: String) -> Bool {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return false }

        for entry in entries {
            let fullPath = (dirPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                // Skip .DS_Store and other hidden files
                if !entry.hasPrefix(".") {
                    return true
                }
            }
        }
        return false
    }

    /// Check if any subfolder (one level deep) in a PARA folder has a local _Assets/ directory
    private static func hasScatteredAssets(in paraFolder: String) -> Bool {
        let fm = FileManager.default
        guard let subfolders = try? fm.contentsOfDirectory(atPath: paraFolder) else { return false }

        for subfolder in subfolders {
            let subfolderPath = (paraFolder as NSString).appendingPathComponent(subfolder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: subfolderPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let assetsPath = (subfolderPath as NSString).appendingPathComponent("_Assets")
            if fm.fileExists(atPath: assetsPath) {
                return true
            }
        }
        return false
    }

    /// Move loose files from root _Assets/ directly into the correct subdirectory
    private static func migrateLooseFiles(
        in centralAssetsPath: String,
        pathManager: PKMPathManager,
        result: inout MigrationResult
    ) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: centralAssetsPath) else { return }

        for entry in entries {
            let fullPath = (centralAssetsPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            // Skip subdirectories (documents/, images/) and hidden files
            if isDir.boolValue || entry.hasPrefix(".") { continue }

            let ext = URL(fileURLWithPath: entry).pathExtension.lowercased()
            let isImage = BinaryExtractor.imageExtensions.contains(ext)
            let targetDir = isImage ? pathManager.imagesAssetsPath : pathManager.documentsAssetsPath
            let targetPath = (targetDir as NSString).appendingPathComponent(entry)
            let resolvedPath = resolveConflict(targetPath)

            do {
                try fm.moveItem(atPath: fullPath, toPath: resolvedPath)
                if isImage {
                    result.movedImages += 1
                } else {
                    result.movedDocuments += 1
                }
                NSLog("[AssetMigrator] 루트 파일 이동: %@ -> %@", entry, isImage ? "images/" : "documents/")
            } catch {
                result.errors.append("루트 파일 이동 실패 (\(entry)): \(error.localizedDescription)")
            }
        }
    }

    /// Scan one level of subfolders in a PARA folder and migrate any scattered _Assets/
    private static func migrateScatteredAssets(
        paraFolder: String,
        pathManager: PKMPathManager,
        result: inout MigrationResult
    ) {
        let fm = FileManager.default
        guard let subfolders = try? fm.contentsOfDirectory(atPath: paraFolder) else { return }

        for subfolder in subfolders {
            let subfolderPath = (paraFolder as NSString).appendingPathComponent(subfolder)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: subfolderPath, isDirectory: &isDir), isDir.boolValue else {
                continue
            }

            let localAssetsPath = (subfolderPath as NSString).appendingPathComponent("_Assets")
            guard fm.fileExists(atPath: localAssetsPath) else { continue }

            NSLog("[AssetMigrator] 산재된 에셋 폴더 발견: %@", localAssetsPath)

            // Move all files from this scattered _Assets/ to centralized location
            guard let assetEntries = try? fm.contentsOfDirectory(atPath: localAssetsPath) else {
                continue
            }

            for assetEntry in assetEntries {
                let sourcePath = (localAssetsPath as NSString).appendingPathComponent(assetEntry)
                var entryIsDir: ObjCBool = false
                guard fm.fileExists(atPath: sourcePath, isDirectory: &entryIsDir) else { continue }
                // Skip hidden files and subdirectories
                if assetEntry.hasPrefix(".") { continue }
                if entryIsDir.boolValue { continue }

                let ext = URL(fileURLWithPath: assetEntry).pathExtension.lowercased()
                let isImage = BinaryExtractor.imageExtensions.contains(ext)
                let targetDir = isImage ? pathManager.imagesAssetsPath : pathManager.documentsAssetsPath
                let targetPath = (targetDir as NSString).appendingPathComponent(assetEntry)
                let resolvedPath = resolveConflict(targetPath)

                do {
                    try fm.moveItem(atPath: sourcePath, toPath: resolvedPath)
                    if isImage {
                        result.movedImages += 1
                    } else {
                        result.movedDocuments += 1
                    }
                } catch {
                    result.errors.append("에셋 이동 실패 (\(assetEntry)): \(error.localizedDescription)")
                }
            }

            // Remove the now-empty scattered _Assets/ directory
            removeDirectoryIfEmpty(localAssetsPath, result: &result)
        }
    }

    /// Delete orphaned image companion files (*.png.md, *.jpg.md, etc.) across PARA folders
    private static func deleteOrphanedImageCompanions(
        pkmRoot: String,
        pathManager: PKMPathManager,
        result: inout MigrationResult
    ) {
        let paraFolders = [
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ]

        for paraFolder in paraFolders {
            deleteImageCompanions(in: paraFolder, result: &result)
        }
    }

    /// Recursively find and trash image companion .md files in a directory tree
    private static func deleteImageCompanions(in dirPath: String, result: inout MigrationResult) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return }

        for entry in entries {
            let fullPath = (dirPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                // Recurse into subdirectories but skip _Assets/ itself
                if entry != "_Assets" {
                    deleteImageCompanions(in: fullPath, result: &result)
                }
                continue
            }

            // Check if this is an image companion file (e.g., photo.png.md)
            guard entry.hasSuffix(".md") else { continue }
            let withoutMd = String(entry.dropLast(3)) // remove ".md"
            let imageExt = URL(fileURLWithPath: withoutMd).pathExtension.lowercased()
            guard BinaryExtractor.imageExtensions.contains(imageExt) else { continue }

            // Only trash if DotBrain-generated (has our frontmatter marker)
            guard let content = try? String(contentsOfFile: fullPath, encoding: .utf8),
                  content.contains("para:") else { continue }

            // This is a DotBrain-generated image companion — trash it
            do {
                try fm.trashItem(at: URL(fileURLWithPath: fullPath), resultingItemURL: nil)
                result.deletedImageCompanions += 1
                NSLog("[AssetMigrator] 이미지 동반파일 삭제: %@", entry)
            } catch {
                result.errors.append("이미지 동반파일 삭제 실패 (\(entry)): \(error.localizedDescription)")
            }
        }
    }

    /// Update wikilinks in document companion files: ![[_Assets/file]] -> ![[_Assets/documents/file]]
    private static func updateCompanionWikilinks(
        pkmRoot: String,
        pathManager: PKMPathManager,
        result: inout MigrationResult
    ) {
        let paraFolders = [
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ]

        for paraFolder in paraFolders {
            updateWikilinksInDirectory(paraFolder, result: &result)
        }
    }

    /// Recursively update companion .md files that have old-style _Assets/ wikilinks
    private static func updateWikilinksInDirectory(_ dirPath: String, result: inout MigrationResult) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return }

        for entry in entries {
            let fullPath = (dirPath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue {
                if entry != "_Assets" {
                    updateWikilinksInDirectory(fullPath, result: &result)
                }
                continue
            }

            // Only process document companion .md files (e.g., report.pdf.md, slides.pptx.md)
            guard entry.hasSuffix(".md") else { continue }
            let withoutMd = String(entry.dropLast(3))
            let docExt = URL(fileURLWithPath: withoutMd).pathExtension.lowercased()
            let documentExtensions = BinaryExtractor.binaryExtensions.subtracting(BinaryExtractor.imageExtensions)
            guard documentExtensions.contains(docExt) else { continue }

            // Read content and check for old-style wikilinks
            guard var content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

            // Pattern: ![[_Assets/filename]] where filename is NOT already in documents/ or images/
            let oldPattern = "![[_Assets/"
            guard content.contains(oldPattern) else { continue }

            var updated = false
            // Replace ![[_Assets/X]] with ![[_Assets/documents/X]] (skip if already has subdir)
            let lines = content.components(separatedBy: "\n")
            var newLines: [String] = []

            for line in lines {
                var newLine = line
                // Match ![[_Assets/filename]] but not ![[_Assets/documents/...]] or ![[_Assets/images/...]]
                if line.contains("![[_Assets/"),
                   !line.contains("![[_Assets/documents/"),
                   !line.contains("![[_Assets/images/") {
                    newLine = line.replacingOccurrences(of: "![[_Assets/", with: "![[_Assets/documents/")
                    updated = true
                }
                newLines.append(newLine)
            }

            if updated {
                content = newLines.joined(separator: "\n")
                do {
                    try content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                    result.updatedCompanions += 1
                    NSLog("[AssetMigrator] 위키링크 업데이트: %@", entry)
                } catch {
                    result.errors.append("위키링크 업데이트 실패 (\(entry)): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Remove a directory if it is empty (ignoring .DS_Store), increment cleanedDirectories counter
    private static func removeDirectoryIfEmpty(_ dirPath: String, result: inout MigrationResult) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: dirPath) else { return }

        let meaningful = entries.filter { !$0.hasPrefix(".") }
        guard meaningful.isEmpty else { return }

        do {
            try fm.removeItem(atPath: dirPath)
            result.cleanedDirectories += 1
            NSLog("[AssetMigrator] 빈 폴더 삭제: %@", dirPath)
        } catch {
            result.errors.append("빈 폴더 삭제 실패: \(error.localizedDescription)")
        }
    }

    /// Resolve filename conflicts by appending _2, _3, etc. Falls back to UUID suffix.
    private static func resolveConflict(_ path: String) -> String {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return path }

        let dir = (path as NSString).deletingLastPathComponent
        let ext = (path as NSString).pathExtension
        let baseName: String
        if ext.isEmpty {
            baseName = (path as NSString).lastPathComponent
        } else {
            baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        }

        var counter = 2
        let maxAttempts = 1000
        while counter < maxAttempts {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let newPath = (dir as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: newPath) {
                return newPath
            }
            counter += 1
        }

        let uuid = UUID().uuidString.prefix(8)
        let fallbackName = ext.isEmpty ? "\(baseName)_\(uuid)" : "\(baseName)_\(uuid).\(ext)"
        return (dir as NSString).appendingPathComponent(fallbackName)
    }
}
