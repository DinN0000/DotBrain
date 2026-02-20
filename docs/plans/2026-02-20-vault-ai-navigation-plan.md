# Vault AI Navigation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** MOC 기반 구조적 링크를 JSON 인덱스로 대체하고, 시맨틱 링크 품질을 개선하여 AI/사람 모두의 볼트 탐색 효율을 높인다.

**Architecture:** NoteIndexGenerator가 볼트 메타데이터를 `_meta/note-index.json`으로 출력. ContextMapBuilder가 인덱스에서 읽도록 변경. LinkCandidateGenerator/LinkAIFilter의 기준을 강화하여 의미있는 연결만 생성. MOCGenerator 제거.

**Tech Stack:** Swift 5.9, macOS 13+, Foundation (JSON Serialization)

**Design Doc:** `docs/plans/2026-02-20-vault-ai-navigation-design.md`

---

### Task 1: Create NoteIndexGenerator

NoteIndexGenerator를 만들어 `_meta/note-index.json`을 생성하는 핵심 컴포넌트.

**Files:**
- Create: `Sources/Services/NoteIndexGenerator.swift`
- Reference: `Sources/Services/MOCGenerator.swift` (동일한 볼트 스캔 패턴)
- Reference: `Sources/Services/FileSystem/PKMPathManager.swift` (경로 관리)
- Reference: `Sources/Models/Frontmatter.swift` (프론트매터 파싱)

**Step 1: Create NoteIndexGenerator with index model**

```swift
import Foundation

/// Note index entry for a single note
struct NoteIndexEntry: Codable, Sendable {
    let path: String
    let folder: String
    let para: String
    let tags: [String]
    let summary: String
    let project: String?
    let status: String?
}

/// Folder index entry
struct FolderIndexEntry: Codable, Sendable {
    let path: String
    let para: String
    var summary: String
    var tags: [String]
}

/// Top-level index structure
struct NoteIndex: Codable, Sendable {
    let version: Int
    let updated: String
    var folders: [String: FolderIndexEntry]
    var notes: [String: NoteIndexEntry]
}

/// Generates and updates _meta/note-index.json for AI vault navigation
struct NoteIndexGenerator: Sendable {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    private var metaPath: String {
        (pkmRoot as NSString).appendingPathComponent("_meta")
    }

    private var indexPath: String {
        (metaPath as NSString).appendingPathComponent("note-index.json")
    }

    // MARK: - Public API

    /// Regenerate index for specific folders (incremental update)
    func updateForFolders(_ folderPaths: Set<String>) async {
        var index = loadExisting() ?? NoteIndex(
            version: 1,
            updated: "",
            folders: [:],
            notes: [:]
        )

        for folderPath in folderPaths {
            let folderName = (folderPath as NSString).lastPathComponent
            let para = PARACategory.fromPath(folderPath) ?? .archive

            // Update folder entry
            let (folderEntry, noteEntries) = scanFolder(
                folderPath: folderPath,
                folderName: folderName,
                para: para
            )
            index.folders[folderName] = folderEntry

            // Remove old notes from this folder, add new ones
            index.notes = index.notes.filter { $0.value.folder != folderName }
            for (name, entry) in noteEntries {
                index.notes[name] = entry
            }
        }

        index = NoteIndex(
            version: index.version,
            updated: ISO8601DateFormatter().string(from: Date()),
            folders: index.folders,
            notes: index.notes
        )

        save(index)
    }

    /// Regenerate entire index (full scan)
    func regenerateAll() async {
        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        let fm = FileManager.default
        var allFolders: [String: FolderIndexEntry] = [:]
        var allNotes: [String: NoteIndexEntry] = [:]

        for (para, basePath) in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                let (folderEntry, noteEntries) = scanFolder(
                    folderPath: folderPath,
                    folderName: folder,
                    para: para
                )
                allFolders[folder] = folderEntry
                for (name, entry) in noteEntries {
                    allNotes[name] = entry
                }
            }
        }

        let index = NoteIndex(
            version: 1,
            updated: ISO8601DateFormatter().string(from: Date()),
            folders: allFolders,
            notes: allNotes
        )

        save(index)
    }

    // MARK: - Private

    private func scanFolder(
        folderPath: String,
        folderName: String,
        para: PARACategory
    ) -> (FolderIndexEntry, [(String, NoteIndexEntry)]) {
        let fm = FileManager.default
        let relativeFolderPath = relativePath(folderPath)

        var folderTags: [String: Int] = [:]
        var noteEntries: [(String, NoteIndexEntry)] = []

        guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else {
            let folderEntry = FolderIndexEntry(
                path: relativeFolderPath,
                para: para.rawValue,
                summary: "",
                tags: []
            )
            return (folderEntry, [])
        }

        for file in files.sorted() {
            guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
            // Skip MOC files (legacy)
            guard file != "\(folderName).md" else { continue }

            let filePath = (folderPath as NSString).appendingPathComponent(file)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            let baseName = (file as NSString).deletingPathExtension

            for tag in frontmatter.tags {
                folderTags[tag, default: 0] += 1
            }

            noteEntries.append((baseName, NoteIndexEntry(
                path: relativePath(filePath),
                folder: folderName,
                para: para.rawValue,
                tags: frontmatter.tags,
                summary: frontmatter.summary ?? "",
                project: frontmatter.project,
                status: frontmatter.status?.rawValue
            )))
        }

        let topTags = folderTags.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
        let folderEntry = FolderIndexEntry(
            path: relativeFolderPath,
            para: para.rawValue,
            summary: "",
            tags: topTags
        )

        return (folderEntry, noteEntries)
    }

    private func relativePath(_ absolutePath: String) -> String {
        if absolutePath.hasPrefix(pkmRoot) {
            var relative = String(absolutePath.dropFirst(pkmRoot.count))
            if relative.hasPrefix("/") { relative = String(relative.dropFirst()) }
            return relative
        }
        return absolutePath
    }

    private func loadExisting() -> NoteIndex? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)) else { return nil }
        return try? JSONDecoder().decode(NoteIndex.self, from: data)
    }

    private func save(_ index: NoteIndex) {
        let fm = FileManager.default
        if !fm.fileExists(atPath: metaPath) {
            try? fm.createDirectory(atPath: metaPath, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(index) else { return }
        try? data.write(to: URL(fileURLWithPath: indexPath))
    }
}
```

**Step 2: Build and verify no compile errors**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded (new file compiles standalone)

**Step 3: Commit**

```bash
git add Sources/Services/NoteIndexGenerator.swift
git commit -m "feat: add NoteIndexGenerator for vault AI navigation index"
```

---

### Task 2: Update ContextMapBuilder to read from index

ContextMapBuilder가 MOC 파일 대신 note-index.json에서 VaultContextMap을 빌드하도록 변경.

**Files:**
- Modify: `Sources/Services/ContextMapBuilder.swift`
- Reference: `Sources/Services/ContextMap.swift` (ContextMapEntry 구조 확인)

**Step 1: Rewrite ContextMapBuilder to read from index**

Replace the entire content of `ContextMapBuilder.swift`:

```swift
import Foundation

/// Builds a VaultContextMap from note-index.json (pure file I/O, no AI calls)
struct ContextMapBuilder: Sendable {
    let pkmRoot: String

    private var indexPath: String {
        ((pkmRoot as NSString).appendingPathComponent("_meta") as NSString)
            .appendingPathComponent("note-index.json")
    }

    /// Build context map from note index
    func build() async -> VaultContextMap {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
              let index = try? JSONDecoder().decode(NoteIndex.self, from: data) else {
            // Fallback: return empty map if index doesn't exist yet
            return VaultContextMap(entries: [], folderCount: 0, buildDate: Date())
        }

        var entries: [ContextMapEntry] = []

        for (noteName, note) in index.notes {
            let para = PARACategory(rawValue: note.para) ?? .archive
            let folder = index.folders[note.folder]

            entries.append(ContextMapEntry(
                noteName: noteName,
                summary: note.summary,
                folderName: note.folder,
                para: para,
                folderSummary: folder?.summary ?? "",
                tags: folder?.tags ?? []
            ))
        }

        return VaultContextMap(
            entries: entries,
            folderCount: index.folders.count,
            buildDate: Date()
        )
    }
}
```

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/ContextMapBuilder.swift
git commit -m "refactor: ContextMapBuilder reads from note-index.json instead of MOC files"
```

---

### Task 3: Replace MOCGenerator call sites

5개의 MOCGenerator 호출 지점을 NoteIndexGenerator로 교체.

**Files:**
- Modify: `Sources/App/AppState.swift:347-348`
- Modify: `Sources/Pipeline/InboxProcessor.swift:228-229`
- Modify: `Sources/Pipeline/VaultReorganizer.swift:278-279`
- Modify: `Sources/Pipeline/FolderReorganizer.swift:214-227`
- Modify: `Sources/UI/PARAManageView.swift:582-601`

**Step 1: Replace AppState.swift**

At line 340, change the phase label and replace MOCGenerator:

```swift
// Before (lines 340, 347-348):
AppState.shared.backgroundTaskPhase = "폴더 요약 갱신 중..."
...
let generator = MOCGenerator(pkmRoot: root)
await generator.regenerateAll(dirtyFolders: dirtyFolders)

// After:
AppState.shared.backgroundTaskPhase = "노트 인덱스 갱신 중..."
...
let indexGenerator = NoteIndexGenerator(pkmRoot: root)
await indexGenerator.updateForFolders(dirtyFolders)
```

**Step 2: Replace InboxProcessor.swift**

At lines 228-229:

```swift
// Before:
let mocGenerator = MOCGenerator(pkmRoot: pkmRoot)
await mocGenerator.updateMOCsForFolders(affectedFolders)

// After:
let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
await indexGenerator.updateForFolders(affectedFolders)
```

**Step 3: Replace VaultReorganizer.swift**

At lines 277-279:

```swift
// Before:
onProgress?(0.93, "MOC 갱신 중...")
let mocGenerator = MOCGenerator(pkmRoot: pkmRoot)
await mocGenerator.updateMOCsForFolders(affectedFolders)

// After:
onProgress?(0.93, "노트 인덱스 갱신 중...")
let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
await indexGenerator.updateForFolders(affectedFolders)
```

**Step 4: Replace FolderReorganizer.swift**

At lines 214-227, replace MOC generation with index update:

```swift
// Before:
let mocGenerator = MOCGenerator(pkmRoot: pkmRoot)
do {
    try await mocGenerator.generateMOC(folderPath: folderPath, folderName: subfolder, para: category)
} catch {
    NSLog("[FolderReorganizer] MOC 생성 실패: %@ — %@", subfolder, error.localizedDescription)
}
let affectedFolders = Set(processed.filter(\.isSuccess).compactMap { ... })
if !affectedFolders.isEmpty {
    await mocGenerator.updateMOCsForFolders(affectedFolders)
}

// After:
var foldersToUpdate: Set<String> = [folderPath]
let additionalFolders = Set(processed.filter(\.isSuccess).compactMap { result -> String? in
    let dir = (result.targetPath as NSString).deletingLastPathComponent
    return dir.isEmpty || dir == folderPath ? nil : dir
})
foldersToUpdate.formUnion(additionalFolders)
let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
await indexGenerator.updateForFolders(foldersToUpdate)
```

**Step 5: Replace PARAManageView.swift**

Replace both `refreshMOC` and `refreshCategoryMOC` methods (lines 582-601):

```swift
private func refreshIndex(folderName: String, category: PARACategory) {
    let root = appState.pkmRootPath
    Task.detached(priority: .utility) {
        let pathManager = PKMPathManager(root: root)
        let basePath = pathManager.paraPath(for: category)
        let folderPath = (basePath as NSString).appendingPathComponent(folderName)
        let indexGenerator = NoteIndexGenerator(pkmRoot: root)
        await indexGenerator.updateForFolders([folderPath])
    }
}

private func refreshCategoryIndex(_ category: PARACategory) {
    let root = appState.pkmRootPath
    Task.detached(priority: .utility) {
        let pathManager = PKMPathManager(root: root)
        let basePath = pathManager.paraPath(for: category)
        let fm = FileManager.default
        guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { return }
        var folderPaths: Set<String> = []
        for folder in folders {
            guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
            let folderPath = (basePath as NSString).appendingPathComponent(folder)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue {
                folderPaths.insert(folderPath)
            }
        }
        let indexGenerator = NoteIndexGenerator(pkmRoot: root)
        await indexGenerator.updateForFolders(folderPaths)
    }
}
```

Also update all call sites in PARAManageView that call `refreshMOC` to call `refreshIndex`, and `refreshCategoryMOC` to `refreshCategoryIndex`.

**Step 6: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 7: Commit**

```bash
git add Sources/App/AppState.swift Sources/Pipeline/InboxProcessor.swift \
  Sources/Pipeline/VaultReorganizer.swift Sources/Pipeline/FolderReorganizer.swift \
  Sources/UI/PARAManageView.swift
git commit -m "refactor: replace MOCGenerator with NoteIndexGenerator at all call sites"
```

---

### Task 4: Remove MOCGenerator

MOCGenerator.swift 삭제 및 관련 참조 정리.

**Files:**
- Delete: `Sources/Services/MOCGenerator.swift`
- Modify: `Sources/Services/AICompanionService.swift` (주석 내 MOC 언급 수정)

**Step 1: Delete MOCGenerator.swift**

```bash
git rm Sources/Services/MOCGenerator.swift
```

**Step 2: Update AICompanionService.swift comments**

AICompanionService.swift에서 "MOC"를 언급하는 주석/프롬프트를 "note-index.json" 기반으로 수정. 4개 위치 (lines 218, 432, 567, 677/773).

Search for all MOC references and update to reflect the new index-based approach.

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded (no remaining references to MOCGenerator)

**Step 4: Commit**

```bash
git add -A
git commit -m "refactor: remove MOCGenerator, update AICompanionService references"
```

---

### Task 5: Improve LinkCandidateGenerator scoring

태그 1개 겹침 제거, 후보 진입 기준 강화.

**Files:**
- Modify: `Sources/Services/SemanticLinker/LinkCandidateGenerator.swift:46-54,68,78`

**Step 1: Update scoring logic**

In `generateCandidates()`:

```swift
// Before (lines 48-54):
let otherTags = Set(other.tags.map { $0.lowercased() })
let tagOverlap = noteTags.intersection(otherTags).count
if tagOverlap >= 2 {
    score += Double(tagOverlap) * 1.5
} else if tagOverlap == 1 {
    score += 0.5
}

// After:
let otherTags = Set(other.tags.map { $0.lowercased() })
let tagOverlap = noteTags.intersection(otherTags).count
if tagOverlap >= 2 {
    score += Double(tagOverlap) * 1.5
}
// Single tag overlap removed — too weak to indicate genuine relevance
```

```swift
// Before (line 68):
guard score > 0 else { continue }

// After:
guard score >= 3.0 else { continue }
```

```swift
// Before (line 78):
return Array(candidates.sorted { $0.score > $1.score }.prefix(maxCandidates))

// After — remove maxCandidates default limit:
return candidates.sorted { $0.score > $1.score }
```

Update function signature to remove default `maxCandidates`:

```swift
// Before:
func generateCandidates(
    for note: NoteInfo,
    allNotes: [NoteInfo],
    mocEntries: [ContextMapEntry],
    maxCandidates: Int = 10,
    ...

// After:
func generateCandidates(
    for note: NoteInfo,
    allNotes: [NoteInfo],
    mocEntries: [ContextMapEntry],
    ...
```

Remove `maxCandidates` parameter entirely (no longer used).

**Step 2: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/SemanticLinker/LinkCandidateGenerator.swift
git commit -m "feat: strengthen link candidate scoring — remove single-tag, raise threshold"
```

---

### Task 6: Improve LinkAIFilter

프롬프트 강화, max 제한 완화.

**Files:**
- Modify: `Sources/Services/SemanticLinker/LinkAIFilter.swift`

**Step 1: Update filterBatch prompt**

In `filterBatch()`, update the prompt rules section (around line 37):

```swift
// Before:
let prompt = """
각 노트에 대해 가장 관련 깊은 후보를 최대 \(maxResultsPerNote)개씩 선택하세요.

...

## 규칙
1. 실질적 맥락 연관성 기준 선택 (단순 태그 일치 불충분)
2. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
3. 관련 없는 후보 제외
4. relation: 관계 유형을 하나 선택
...

// After:
let prompt = """
각 노트에 대해 진짜 관련있는 후보를 모두 선택하세요.

...

## 규칙
1. 핵심 기준: "이 연결을 따라가면 새로운 인사이트를 얻을 수 있는가?"
2. 단순히 같은 주제라서가 아니라, 실제로 함께 읽을 가치가 있는 문서만 선택
3. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
4. 관련 없는 후보는 반드시 제외
5. relation: 관계 유형을 하나 선택
...
```

Remove `maxResultsPerNote` constraint from the prompt text (keep parameter for caller flexibility but default higher).

**Step 2: Update filterSingle prompt similarly**

Apply same prompt strengthening to `filterSingle()` (around line 73).

**Step 3: Update default maxResults**

```swift
// Before:
func filterBatch(
    notes: ...,
    maxResultsPerNote: Int = 5
) async throws -> [[FilteredLink]] {

// After:
func filterBatch(
    notes: ...,
    maxResultsPerNote: Int = 15
) async throws -> [[FilteredLink]] {
```

```swift
// Before:
func filterSingle(
    ...
    maxResults: Int = 5
) async throws -> [FilteredLink] {

// After:
func filterSingle(
    ...
    maxResults: Int = 15
) async throws -> [FilteredLink] {
```

**Step 4: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 5: Commit**

```bash
git add Sources/Services/SemanticLinker/LinkAIFilter.swift
git commit -m "feat: strengthen AI link filter — stricter criteria, no artificial limit"
```

---

### Task 7: Improve reverse link context in SemanticLinker

역방향 링크의 "X에서 참조" 컨텍스트를 relation 기반 의미있는 설명으로 변경.

**Files:**
- Modify: `Sources/Services/SemanticLinker/SemanticLinker.swift:137-141`

**Step 1: Update reverse link context generation**

In `linkAll()`, around line 136:

```swift
// Before:
var reverseLinks: [String: [(name: String, context: String, relation: String)]] = [:]
for entry in allLinks {
    for link in entry.links {
        let reverseContext = "\(entry.noteName)에서 참조"
        reverseLinks[link.name, default: []].append((name: entry.noteName, context: reverseContext, relation: "related"))
    }
}

// After:
var reverseLinks: [String: [(name: String, context: String, relation: String)]] = [:]
let reverseRelationContext: [String: String] = [
    "prerequisite": "이 문서를 선행 지식으로 활용",
    "project": "이 자료를 활용하는 프로젝트",
    "reference": "이 문서를 참고 자료로 인용",
    "related": "관련 주제를 다루는 문서",
]
for entry in allLinks {
    for link in entry.links {
        let reverseContext = reverseRelationContext[link.relation] ?? "관련 문서"
        reverseLinks[link.name, default: []].append((name: entry.noteName, context: reverseContext, relation: link.relation))
    }
}
```

**Step 2: Apply same fix in linkNotes() (line 270)**

```swift
// Before (line 271):
let reverseLink = LinkAIFilter.FilteredLink(name: entry.noteName, context: "\(entry.noteName)에서 참조", relation: "related")

// After:
let reverseContext = reverseRelationContext[link.relation] ?? "관련 문서"
let reverseLink = LinkAIFilter.FilteredLink(name: entry.noteName, context: reverseContext, relation: link.relation)
```

Move `reverseRelationContext` to a static property or top-level constant so both methods can use it.

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add Sources/Services/SemanticLinker/SemanticLinker.swift
git commit -m "feat: meaningful reverse link context based on relation type"
```

---

### Task 8: Add CLAUDE.md Vault Navigation rules

Claude Code가 볼트 작업 시 인덱스와 링크를 활용하는 규칙 추가.

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Vault Navigation section**

Add after the `## Key Patterns` section:

```markdown
## Vault Navigation (for Claude Code)
- Read `_meta/note-index.json` first for vault structure overview
- Use tags, summary, project from index to identify relevant notes
- Prioritize `status: active` notes
- Follow `[[wiki-links]]` in `## Related Notes` for context expansion
- Relation type priority: prerequisite > project > reference > related
- Traversal depth: self-determined by task relevance (no fixed limit)
- Resolve note names to file paths via index (no grep needed)
```

**Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add Vault Navigation rules for Claude Code"
```

---

### Task 9: Add _meta/ to .gitignore and PKMPathManager

인덱스 파일의 경로를 PKMPathManager에 추가하고, 볼트 초기화 시 _meta/ 폴더 생성.

**Files:**
- Modify: `Sources/Services/FileSystem/PKMPathManager.swift`

**Step 1: Add metaPath to PKMPathManager**

Add after `archivePath` (line 14):

```swift
var metaPath: String { (root as NSString).appendingPathComponent("_meta") }
var noteIndexPath: String { (metaPath as NSString).appendingPathComponent("note-index.json") }
```

**Step 2: Add _meta/ to initializeStructure**

In `initializeStructure()` (line 123), add metaPath:

```swift
let folders = [inboxPath, projectsPath, areaPath, resourcePath, archivePath,
               documentsAssetsPath, imagesAssetsPath, metaPath]
```

**Step 3: Build and verify**

Run: `swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
git add Sources/Services/FileSystem/PKMPathManager.swift
git commit -m "feat: add _meta/ path to PKMPathManager for note index"
```

---

### Task 10: Final integration build and verify

전체 빌드 및 기능 확인.

**Step 1: Clean build**

Run: `swift build 2>&1 | tail -10`
Expected: Build Succeeded with zero warnings

**Step 2: Verify no remaining MOCGenerator references**

Run: `grep -r "MOCGenerator" Sources/`
Expected: No output (zero references)

**Step 3: Verify NoteIndexGenerator is used at all former MOC call sites**

Run: `grep -r "NoteIndexGenerator" Sources/`
Expected: References in AppState, InboxProcessor, VaultReorganizer, FolderReorganizer, PARAManageView, NoteIndexGenerator.swift itself

**Step 4: Final commit with all changes**

If any fixups were needed, commit them:

```bash
git add -A
git commit -m "chore: vault AI navigation integration complete"
```
