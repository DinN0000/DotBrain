# Smart Hybrid Asset Management — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Centralize all binary files into a single `_Assets/` at vault root with type-based subdirectories, and only generate companion .md for document files (not images).

**Architecture:** Replace scattered per-folder `_Assets/` directories with a single `_Assets/{documents,images}/` at the vault root. FileMover routes binaries by extension. Images skip companion .md generation entirely. A one-time migration moves existing scattered assets to the new centralized location.

**Tech Stack:** Swift 5.9, Foundation, CryptoKit (existing)

---

### Task 1: PKMPathManager — Centralized Asset Paths

**Files:**
- Modify: `Sources/Services/FileSystem/PKMPathManager.swift`

**Step 1: Add centralized asset path properties**

Replace the existing `assetsPath` and `assetsDirectory(for:)` with centralized paths. In `PKMPathManager.swift`:

```swift
// Replace line 8:
//   var assetsPath: String { (root as NSString).appendingPathComponent("_Assets") }
// With:
var centralAssetsPath: String { (root as NSString).appendingPathComponent("_Assets") }
var documentsAssetsPath: String { (centralAssetsPath as NSString).appendingPathComponent("documents") }
var imagesAssetsPath: String { (centralAssetsPath as NSString).appendingPathComponent("images") }
```

Replace `assetsDirectory(for:)` (lines 81-84):

```swift
// OLD:
func assetsDirectory(for targetDir: String) -> String {
    return (targetDir as NSString).appendingPathComponent("_Assets")
}

// NEW:
/// Get the centralized assets subdirectory for a file based on its extension
func assetsDirectory(for filePath: String) -> String {
    let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
    if BinaryExtractor.imageExtensions.contains(ext) {
        return imagesAssetsPath
    }
    return documentsAssetsPath
}
```

**Step 2: Add `_Assets/documents/` and `_Assets/images/` to vault initialization**

In `initializeStructure()` (line 115-127), add asset subdirectories:

```swift
func initializeStructure() throws {
    let fm = FileManager.default
    let folders = [inboxPath, projectsPath, areaPath, resourcePath, archivePath,
                   documentsAssetsPath, imagesAssetsPath]
    for folder in folders {
        try fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
    }
    // ... rest unchanged
}
```

**Step 3: Build and verify**

Run: `swift build`
Expected: Clean build, no errors.

**Step 4: Commit**

```
feat: centralize _Assets/ path management in PKMPathManager
```

---

### Task 2: FileMover — Route Binaries to Central _Assets/, Skip Image Companions

**Files:**
- Modify: `Sources/Services/FileSystem/FileMover.swift`

**Step 1: Update `moveBinaryFile()` to use centralized _Assets/**

In `moveBinaryFile()` (line 207), replace per-folder `_Assets/` with centralized routing:

```swift
// OLD (lines 215-216):
let assetsDir = pathManager.assetsDirectory(for: targetDir)
try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

// NEW:
let assetsDir = pathManager.assetsDirectory(for: filePath)
try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)
```

**Step 2: Update duplicate detection to search centralized `_Assets/`**

The `findDuplicateByHash` and `findDuplicateByMetadata` calls already search `assetsDir` — since we changed `assetsDir` to point to the centralized location, this works automatically. No change needed.

**Step 3: Skip companion .md for image files**

After the file is moved (after line 248), add an image check before companion generation:

```swift
// After: try fm.moveItem(atPath: filePath, toPath: resolvedAssetPath)
// (line 248)

// Skip companion .md for image files — EXIF-only data is not useful as standalone notes
let isImage = BinaryExtractor.imageExtensions.contains(
    URL(fileURLWithPath: fileName).pathExtension.lowercased()
)

if isImage {
    return ProcessedFileResult(
        fileName: fileName,
        para: classification.para,
        targetPath: resolvedAssetPath,
        tags: classification.tags
    )
}

// ... rest of companion .md generation continues for documents only
```

**Step 4: Build and verify**

Run: `swift build`
Expected: Clean build.

**Step 5: Commit**

```
feat: route binaries to central _Assets/, skip image companions
```

---

### Task 3: FrontmatterWriter — Update Companion .md Link Paths

**Files:**
- Modify: `Sources/Services/FileSystem/FrontmatterWriter.swift`

**Step 1: Update `createCompanionMarkdown()` to use centralized path**

In `createCompanionMarkdown()` (line 94-96), the wikilink currently uses a relative `_Assets/` path. Update to use the centralized path:

```swift
// OLD (line 96):
result += "![[_Assets/\(fileName)]]\n"

// NEW:
let ext = extractResult.file?.format ?? ""
let subdir = BinaryExtractor.imageExtensions.contains(ext) ? "images" : "documents"
result += "![[_Assets/\(subdir)/\(fileName)]]\n"
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Clean build.

**Step 3: Commit**

```
fix: update companion .md wikilinks to centralized _Assets/ paths
```

---

### Task 4: FolderReorganizer — Handle Centralized Assets During Reorganization

**Files:**
- Modify: `Sources/Pipeline/FolderReorganizer.swift`

**Step 1: Skip binary files in `scanFolder()`**

Binary files now live in centralized `_Assets/`, not in PARA subfolders. But companion `.pdf.md` files still need to be scanned. The current `scanFolder()` (line 398) already skips `_`-prefixed entries, which covers `_Assets/`. No change needed here.

**Step 2: Handle companion .md files during reorganization**

When `FolderReorganizer` relocates a companion `.pdf.md` file via `FileMover.moveFile()`, the FileMover detects it as a text file (it ends in `.md`) and processes it normally. The wikilink `![[_Assets/documents/file.pdf]]` inside the companion uses a vault-root-relative path, so it stays valid regardless of which PARA folder the companion moves to. No change needed.

**Step 3: Verify flattenFolder handles new structure**

In `flattenFolder()` (line 285), nested `_Assets/` folders will be encountered. The current logic already skips `_`-prefixed files (line 308, 323). However, it also moves nested non-hidden files to top level — we need to make sure it doesn't try to move files from `_Assets/` subdirectories.

The `flattenFolder` method is only called on PARA subfolders (e.g., `2_Area/Finance/`). Since binary files are now in centralized `_Assets/` (not per-folder `_Assets/`), there should be no `_Assets/` inside PARA subfolders for new files. For migration purposes, this is handled in Task 6. No change needed here.

**Step 4: Build and verify**

Run: `swift build`
Expected: Clean build (no code changes in this task — verification only).

**Step 5: Commit**

No commit needed — this task is verification only. Proceed to Task 5.

---

### Task 5: InboxScanner — Exclude Vault-Root _Assets/ from Scanning

**Files:**
- Modify: `Sources/Services/FileSystem/InboxScanner.swift`

**Step 1: Verify `_Assets/` exclusion**

The InboxScanner only scans `_Inbox/`, not the vault root or PARA folders. The centralized `_Assets/` at vault root is never scanned because `scan()` (line 60) only reads from `inboxPath`. No change needed.

However, `filesInDirectory()` (line 105) is used by `InboxProcessor.extractFolderContent()` to scan arbitrary directories. If someone drops a folder containing `_Assets/` into inbox, the `_` prefix filter on line 124 (`!name.hasPrefix("_")`) already excludes it. No change needed.

**Step 2: Verify**

Run: `swift build`
Expected: Clean build.

No commit needed — verification only.

---

### Task 6: AssetMigrator — Migrate Existing Scattered _Assets/ to Central

**Files:**
- Create: `Sources/Services/FileSystem/AssetMigrator.swift`

**Step 1: Create the migration service**

```swift
import Foundation

/// Migrates scattered per-folder _Assets/ directories to centralized _Assets/{documents,images}/
/// One-time operation triggered from vault health check or settings.
enum AssetMigrator {
    struct MigrationResult {
        var movedDocuments: Int = 0
        var movedImages: Int = 0
        var deletedImageCompanions: Int = 0
        var updatedCompanions: Int = 0
        var cleanedDirectories: Int = 0
        var errors: [String] = []
    }

    /// Check if migration is needed (any per-folder _Assets/ exist)
    static func needsMigration(pkmRoot: String) -> Bool {
        let pm = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default
        let paraFolders = [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath]

        for paraFolder in paraFolders {
            guard let entries = try? fm.contentsOfDirectory(atPath: paraFolder) else { continue }
            for entry in entries {
                let subPath = (paraFolder as NSString).appendingPathComponent(entry)
                let assetsPath = (subPath as NSString).appendingPathComponent("_Assets")
                if fm.fileExists(atPath: assetsPath) {
                    return true
                }
            }
        }

        // Also check root-level _Assets/ that lacks documents/ or images/ subdirs
        let centralAssets = pm.centralAssetsPath
        if fm.fileExists(atPath: centralAssets) {
            let hasDocs = fm.fileExists(atPath: pm.documentsAssetsPath)
            let hasImages = fm.fileExists(atPath: pm.imagesAssetsPath)
            if !hasDocs || !hasImages {
                return true
            }
            // Check if root _Assets/ has files directly (not in subdirs)
            if let rootEntries = try? fm.contentsOfDirectory(atPath: centralAssets) {
                let nonSubdirs = rootEntries.filter { $0 != "documents" && $0 != "images" && !$0.hasPrefix(".") }
                if !nonSubdirs.isEmpty { return true }
            }
        }

        return false
    }

    /// Perform the full migration
    static func migrate(pkmRoot: String) -> MigrationResult {
        let pm = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default
        var result = MigrationResult()

        // Ensure centralized directories exist
        try? fm.createDirectory(atPath: pm.documentsAssetsPath, withIntermediateDirectories: true)
        try? fm.createDirectory(atPath: pm.imagesAssetsPath, withIntermediateDirectories: true)

        // Step 1: Move files from root _Assets/ (flat) to subdirectories
        migrateRootAssets(pm: pm, fm: fm, result: &result)

        // Step 2: Collect and move from scattered per-folder _Assets/
        let paraFolders = [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath]
        for paraFolder in paraFolders {
            guard let entries = try? fm.contentsOfDirectory(atPath: paraFolder) else { continue }
            for entry in entries {
                let subPath = (paraFolder as NSString).appendingPathComponent(entry)
                let assetsPath = (subPath as NSString).appendingPathComponent("_Assets")
                guard fm.fileExists(atPath: assetsPath) else { continue }

                migrateScatteredAssets(from: assetsPath, pm: pm, fm: fm, result: &result)

                // Clean up empty _Assets/ directory
                let remaining = (try? fm.contentsOfDirectory(atPath: assetsPath))?.filter { !$0.hasPrefix(".") } ?? []
                if remaining.isEmpty {
                    try? fm.removeItem(atPath: assetsPath)
                    result.cleanedDirectories += 1
                }
            }
        }

        // Step 3: Delete orphaned image companion files
        deleteImageCompanions(pkmRoot: pkmRoot, pm: pm, fm: fm, result: &result)

        // Step 4: Update document companion wikilinks
        updateCompanionLinks(pkmRoot: pkmRoot, fm: fm, result: &result)

        NSLog("[AssetMigrator] 마이그레이션 완료: 문서 %d, 이미지 %d 이동, 이미지 컴패니언 %d 삭제, 컴패니언 %d 업데이트, 폴더 %d 정리, 오류 %d",
              result.movedDocuments, result.movedImages, result.deletedImageCompanions,
              result.updatedCompanions, result.cleanedDirectories, result.errors.count)

        return result
    }

    // MARK: - Private

    private static func migrateRootAssets(pm: PKMPathManager, fm: FileManager, result: inout MigrationResult) {
        guard let entries = try? fm.contentsOfDirectory(atPath: pm.centralAssetsPath) else { return }

        for entry in entries {
            guard entry != "documents" && entry != "images" && !entry.hasPrefix(".") else { continue }
            let sourcePath = (pm.centralAssetsPath as NSString).appendingPathComponent(entry)

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourcePath, isDirectory: &isDir), !isDir.boolValue else { continue }

            let ext = URL(fileURLWithPath: entry).pathExtension.lowercased()
            let isImage = BinaryExtractor.imageExtensions.contains(ext)
            let targetDir = isImage ? pm.imagesAssetsPath : pm.documentsAssetsPath
            let targetPath = (targetDir as NSString).appendingPathComponent(entry)

            do {
                let resolved = resolveConflict(targetPath, fm: fm)
                try fm.moveItem(atPath: sourcePath, toPath: resolved)
                if isImage { result.movedImages += 1 } else { result.movedDocuments += 1 }
            } catch {
                result.errors.append("이동 실패 \(entry): \(error.localizedDescription)")
            }
        }
    }

    private static func migrateScatteredAssets(from assetsPath: String, pm: PKMPathManager, fm: FileManager, result: inout MigrationResult) {
        guard let files = try? fm.contentsOfDirectory(atPath: assetsPath) else { return }

        for fileName in files {
            guard !fileName.hasPrefix(".") else { continue }
            let sourcePath = (assetsPath as NSString).appendingPathComponent(fileName)

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: sourcePath, isDirectory: &isDir), !isDir.boolValue else { continue }

            let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
            let isImage = BinaryExtractor.imageExtensions.contains(ext)
            let targetDir = isImage ? pm.imagesAssetsPath : pm.documentsAssetsPath
            let targetPath = (targetDir as NSString).appendingPathComponent(fileName)

            do {
                let resolved = resolveConflict(targetPath, fm: fm)
                try fm.moveItem(atPath: sourcePath, toPath: resolved)
                if isImage { result.movedImages += 1 } else { result.movedDocuments += 1 }
            } catch {
                result.errors.append("이동 실패 \(fileName): \(error.localizedDescription)")
            }
        }
    }

    /// Delete image companion .md files (e.g., photo.png.md, image.jpg.md)
    private static func deleteImageCompanions(pkmRoot: String, pm: PKMPathManager, fm: FileManager, result: inout MigrationResult) {
        let paraFolders = [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath]

        for paraFolder in paraFolders {
            guard let enumerator = fm.enumerator(atPath: paraFolder) else { continue }
            while let relativePath = enumerator.nextObject() as? String {
                let fullPath = (paraFolder as NSString).appendingPathComponent(relativePath)

                // Match pattern: *.{image_ext}.md
                guard fullPath.hasSuffix(".md") else { continue }
                let withoutMd = String(fullPath.dropLast(3)) // remove .md
                let innerExt = URL(fileURLWithPath: withoutMd).pathExtension.lowercased()
                guard BinaryExtractor.imageExtensions.contains(innerExt) else { continue }

                do {
                    try fm.trashItem(at: URL(fileURLWithPath: fullPath), resultingItemURL: nil)
                    result.deletedImageCompanions += 1
                } catch {
                    result.errors.append("이미지 컴패니언 삭제 실패: \(relativePath)")
                }
            }
        }
    }

    /// Update wikilinks in document companion files from old to new path format
    private static func updateCompanionLinks(pkmRoot: String, fm: FileManager, result: inout MigrationResult) {
        let pm = PKMPathManager(root: pkmRoot)
        let paraFolders = [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath]
        let docExtensions: Set<String> = ["pdf", "docx", "pptx", "xlsx"]

        for paraFolder in paraFolders {
            guard let enumerator = fm.enumerator(atPath: paraFolder) else { continue }
            while let relativePath = enumerator.nextObject() as? String {
                let fullPath = (paraFolder as NSString).appendingPathComponent(relativePath)

                // Match pattern: *.{doc_ext}.md
                guard fullPath.hasSuffix(".md") else { continue }
                let withoutMd = String(fullPath.dropLast(3))
                let innerExt = URL(fileURLWithPath: withoutMd).pathExtension.lowercased()
                guard docExtensions.contains(innerExt) else { continue }

                guard var content = try? String(contentsOfFile: fullPath, encoding: .utf8) else { continue }

                // Replace old-style ![[_Assets/filename]] with ![[_Assets/documents/filename]]
                let originalContent = content
                // Pattern: ![[_Assets/filename.ext]] where filename doesn't contain /documents/ or /images/
                // This regex matches ![[_Assets/X]] where X doesn't start with documents/ or images/
                let fileName = (withoutMd as NSString).lastPathComponent
                let oldLink = "![[_Assets/\(fileName)]]"
                let newLink = "![[_Assets/documents/\(fileName)]]"

                if content.contains(oldLink) {
                    content = content.replacingOccurrences(of: oldLink, with: newLink)
                }

                if content != originalContent {
                    try? content.write(toFile: fullPath, atomically: true, encoding: .utf8)
                    result.updatedCompanions += 1
                }
            }
        }
    }

    private static func resolveConflict(_ path: String, fm: FileManager) -> String {
        guard fm.fileExists(atPath: path) else { return path }

        let dir = (path as NSString).deletingLastPathComponent
        let ext = (path as NSString).pathExtension
        let baseName = ((path as NSString).lastPathComponent as NSString).deletingPathExtension

        var counter = 2
        while counter < 1000 {
            let newName = ext.isEmpty ? "\(baseName)_\(counter)" : "\(baseName)_\(counter).\(ext)"
            let newPath = (dir as NSString).appendingPathComponent(newName)
            if !fm.fileExists(atPath: newPath) { return newPath }
            counter += 1
        }
        let uuid = UUID().uuidString.prefix(8)
        let fallbackName = ext.isEmpty ? "\(baseName)_\(uuid)" : "\(baseName)_\(uuid).\(ext)"
        return (dir as NSString).appendingPathComponent(fallbackName)
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Clean build.

**Step 3: Commit**

```
feat: add AssetMigrator for scattered _Assets/ consolidation
```

---

### Task 7: Wire Migration into App Lifecycle

**Files:**
- Modify: `Sources/Models/AppState.swift` (or wherever vault initialization runs)

**Step 1: Find where vault setup runs**

Search for `initializeStructure()` calls and `isInitialized()` checks. The migration should run once after vault initialization is confirmed.

**Step 2: Add migration trigger**

After confirming `PKMPathManager.isInitialized()` returns true, check and run migration:

```swift
if AssetMigrator.needsMigration(pkmRoot: pkmRoot) {
    let migrationResult = AssetMigrator.migrate(pkmRoot: pkmRoot)
    NSLog("[AppState] 에셋 마이그레이션: 문서 %d, 이미지 %d 이동", migrationResult.movedDocuments, migrationResult.movedImages)
}
```

This runs once — after migration completes, `needsMigration()` returns false on subsequent launches.

**Step 3: Build and verify**

Run: `swift build`
Expected: Clean build.

**Step 4: Commit**

```
feat: auto-migrate scattered _Assets/ on app launch
```

---

### Task 8: Integration Build and Manual Test

**Step 1: Full build**

Run: `swift build -c release`
Expected: Clean build with zero warnings.

**Step 2: Manual test checklist**

1. Launch app → migration should run if scattered `_Assets/` exist
2. Drop a PDF into `_Inbox/` → should go to `_Assets/documents/`, companion .md created in PARA folder
3. Drop an image into `_Inbox/` → should go to `_Assets/images/`, NO companion .md created
4. Check companion .md has `![[_Assets/documents/filename.pdf]]` wikilink
5. Verify old scattered `_Assets/` directories are cleaned up
6. Verify image `.png.md` companions are deleted

**Step 3: Final commit**

```
chore: verify smart asset management integration
```
