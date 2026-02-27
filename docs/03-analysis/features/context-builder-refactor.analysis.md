# context-builder-refactor Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: DotBrain
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-27
> **Design Doc**: [context-builder-refactor.design.md](../../02-design/features/context-builder-refactor.design.md)
> **Plan Doc**: [context-builder-refactor.plan.md](../../01-plan/features/context-builder-refactor.plan.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Verify that the "context-builder-refactor" feature has been fully implemented according to the design document. Compare each FR (FR-01 through FR-06) and shared infrastructure changes against the actual codebase.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/context-builder-refactor.design.md`
- **Plan Document**: `docs/01-plan/features/context-builder-refactor.plan.md`
- **Implementation Files**:
  - `Sources/Services/NoteIndexGenerator.swift`
  - `Sources/Pipeline/ProjectContextBuilder.swift`
  - `Sources/Services/Claude/Classifier.swift`
  - `Sources/Services/FileSystem/FrontmatterWriter.swift`
  - `Sources/Services/FileSystem/PKMPathManager.swift`
  - `Sources/Services/PARAMover.swift`
  - `Sources/Services/ProjectManager.swift`
  - `Sources/UI/OnboardingView.swift`
  - `Sources/Pipeline/VaultCheckPipeline.swift`
  - `Sources/Pipeline/InboxProcessor.swift`
  - `Sources/Pipeline/VaultReorganizer.swift`
  - `Sources/Pipeline/FolderReorganizer.swift`

---

## 2. Per-FR Gap Analysis

### 2.1 FR-06: NoteIndexEntry `area` field -- MATCH

**Design**: Add `area: String?` to `NoteIndexEntry`, populate from `frontmatter.area` in `scanFolder()`.

**Implementation** (`Sources/Services/NoteIndexGenerator.swift`):

```swift
// Line 14: area field present
struct NoteIndexEntry: Codable, Sendable {
    let path: String
    let folder: String
    let para: String
    let tags: [String]
    let summary: String
    let project: String?
    let status: String?
    let area: String?       // IMPLEMENTED
}

// Lines 196-204: scanFolder() populates area from frontmatter
let noteEntry = NoteIndexEntry(
    ...
    area: frontmatter.area  // IMPLEMENTED
)
```

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `area: String?` field | NoteIndexEntry | Line 14 | Match |
| `scanFolder()` populates area | `frontmatter.area` | Line 204 | Match |
| Version unchanged (optional field) | No version bump | `currentVersion = 1` | Match |

**Verdict**: Match (100%)

---

### 2.2 FR-01: buildTagVocabulary() Index-First -- MATCH

**Design**: Index-first with full note tag aggregation, `encodeTopTags` helper extracted, disk fallback preserved as `buildTagVocabularyFromDisk()`.

**Implementation** (`Sources/Pipeline/ProjectContextBuilder.swift`):

```swift
// Lines 209-223: Index-first path
func buildTagVocabulary() -> String {
    if let index = noteIndex {
        var tagCounts: [String: Int] = [:]
        for (_, note) in index.notes {
            for tag in note.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        return encodeTopTags(tagCounts)
    }
    return buildTagVocabularyFromDisk()
}

// Lines 225-255: Disk fallback preserved (with prefix(5))
// Lines 257-265: encodeTopTags helper extracted
```

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Index-first path | Full note tag aggregation | Lines 211-218 | Match |
| `encodeTopTags` helper | Extracted as private func | Lines 257-265 | Match |
| Disk fallback | `buildTagVocabularyFromDisk()` | Lines 225-255 | Match |
| Top 50 limit | `prefix(50)` | Line 259 | Match |

**Verdict**: Match (100%)

---

### 2.3 FR-03: buildProjectContext() Index-First + extractScope Deleted -- MATCH

**Design**: Index-first with `index.folders` iteration for project context, disk fallback, `extractScope()` deleted.

**Implementation** (`Sources/Pipeline/ProjectContextBuilder.swift`):

```swift
// Lines 18-36: Index-first with folder iteration
func buildProjectContext() -> String {
    if let index = noteIndex {
        var lines: [String] = []
        for (folderKey, folder) in index.folders.sorted(by: { $0.key < $1.key })
            where folder.para == "project" { ... }
        return lines.isEmpty ? "..." : lines.joined(separator: "\n")
    }
    return buildProjectContextFromDisk()
}
```

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Index-first path | `index.folders where para == "project"` | Lines 20-31 | Match |
| Area info from notes | `index.notes.values.first(where:)` | Lines 26-27 | Match |
| Disk fallback | `buildProjectContextFromDisk()` | Lines 38-70 | Match |
| `extractScope()` deleted | No longer exists | Grep: 0 matches | Match |

**Verdict**: Match (100%)

---

### 2.4 FR-02: buildSubfolderContext() Enriched JSON + Classifier Prompts -- MATCH

**Design**: Output enriched JSON with `name/tags/summary/noteCount` per folder. Classifier Stage1/Stage2 prompts updated with new instructions.

**Implementation** (`Sources/Pipeline/ProjectContextBuilder.swift`, `Sources/Services/Claude/Classifier.swift`):

```swift
// Lines 107-161: Enriched JSON with tags/summary/noteCount
func buildSubfolderContext() -> String {
    let subfolders = pathManager.existingSubfolders()
    // Pre-compute note counts per folder
    var folderNoteCounts: [String: Int] = [:]
    if let index = noteIndex { ... }
    // Build enriched entries with name/tags/summary/noteCount
    ...
}
```

Classifier prompts updated (both Stage1 at line 360-361 and Stage2 at line 461-462):
```
각 폴더의 name, tags, summary, noteCount를 참고하여 가장 적합한 폴더를 선택하세요.
새 폴더가 필요하면 targetFolder에 "NEW:폴더명"을 사용하세요. 기존 폴더와 비슷한 이름이 있으면 반드시 기존 이름을 사용하세요.
```

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Enriched JSON output | `name/tags/summary/noteCount` | Lines 131-149 | Match |
| Disk scan for folder list | `pathManager.existingSubfolders()` | Line 109 | Match |
| Index enrichment | `index.folders[folderKey]` | Lines 134-147 | Match |
| Stage1 prompt updated | New subfolder instructions | Lines 360-361 | Match |
| Stage2 prompt updated | New subfolder instructions | Lines 461-462 | Match |
| noteCount optimization | Pre-computed folderNoteCounts | Lines 118-123 | Match (better than design) |

**Note**: Implementation adds a performance optimization (pre-computed `folderNoteCounts` dictionary) that avoids repeated O(N) scans per folder. This is an improvement over the design's inline `index.notes.values.filter` approach.

**Verdict**: Match (100%)

---

### 2.5 FR-04: buildWeightedContext() Fallback Deleted -- MATCH

**Design**: Keep root index note body reading, delete 4 fallback functions (`buildCategoryFallback`, `buildProjectDocuments`, `buildFolderSummaries`, `buildArchiveSummary`), return `""` when empty.

**Implementation** (`Sources/Pipeline/ProjectContextBuilder.swift`):

```swift
// Lines 179-203: Simplified to root index note body only
func buildWeightedContext() -> String {
    let categories = [...]
    var sections: [String] = []
    for (basePath, label, weight) in categories {
        let categoryName = (basePath as NSString).lastPathComponent
        let mocPath = (basePath as NSString).appendingPathComponent("...")
        if let content = try? String(contentsOfFile: mocPath, encoding: .utf8) {
            let (_, body) = Frontmatter.parse(markdown: content)
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("### \(label) (\(weight))\n\(trimmed)")
            }
        }
        // No fallback
    }
    return sections.isEmpty ? "" : sections.joined(separator: "\n\n")
}
```

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Root index note body retained | 4 category MOC reads | Lines 179-203 | Match |
| `buildCategoryFallback` deleted | Not found | Grep: 0 matches | Match |
| `buildProjectDocuments` deleted | Not found | Grep: 0 matches | Match |
| `buildFolderSummaries` deleted | Not found | Grep: 0 matches | Match |
| `buildArchiveSummary` deleted | Not found | Grep: 0 matches | Match |
| Returns `""` when empty | `sections.isEmpty ? "" : ...` | Line 202 | Match |

**Verdict**: Match (100%)

---

### 2.6 FR-05: Area Projects CRUD + Call Sites -- MATCH

**Design**: 4 functions in FrontmatterWriter (`removeProjectFromArea`, `renameProjectInArea`, `findAreaForProject`, `addProjectToArea`), 7 call sites across PARAMover/ProjectManager/OnboardingView/VaultCheckPipeline.

**Implementation** (`Sources/Services/FileSystem/FrontmatterWriter.swift`):

| Function | Design | Implementation Location | Status |
|----------|--------|------------------------|--------|
| `findAreaForProject()` | FrontmatterWriter extension | Lines 133-160 | Match |
| `removeProjectFromArea()` | FrontmatterWriter extension | Lines 163-179 | Match |
| `renameProjectInArea()` | FrontmatterWriter extension | Lines 182-198 | Match |
| `addProjectToArea()` | FrontmatterWriter extension | Lines 201-218 | Match |

**Design Note**: The design specified `removeProjectFromArea(projectName:areaName:pkmRoot:)` with an explicit `areaName` parameter. The implementation uses `removeProjectFromArea(projectName:pkmRoot:)` which internally calls `findAreaForProject` to auto-discover the area. This is a simplification that reduces caller burden -- an improvement.

**Call Sites**:

| File | Method | Design Action | Implementation | Status |
|------|--------|---------------|----------------|--------|
| PARAMover | `deleteFolder()` | removeProjectFromArea | Line 77 | Match |
| PARAMover | `moveFolder()` | removeProjectFromArea | Line 53 | Match |
| PARAMover | `mergeFolder()` | removeProjectFromArea (source) | Line 194 | Match |
| PARAMover | `renameFolder()` | renameProjectInArea | Line 258 | Match |
| ProjectManager | `completeProject()` | removeProjectFromArea | Line 77 | Match |
| ProjectManager | `reactivateProject()` | addProjectToArea | Line 118 | Match |
| OnboardingView | `removeProject()` | removeProjectFromArea | Line 1139 | Match |

**VaultCheckPipeline** (`Sources/Pipeline/VaultCheckPipeline.swift`):

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `pruneStaleAreaProjects()` | Static function | Lines 318-342 | Match |
| Called after audit phase | Phase 1 post-processing | Line 44 | Match |
| `collectExistingProjectNames()` | Helper function | Called at line 43 | Match |

**Verdict**: Match (100%)

---

### 2.7 Shared Infrastructure: PKMPathManager.loadNoteIndex() + Init Changes -- MATCH

**Design**: Add `loadNoteIndex()` to PKMPathManager, add `noteIndex` parameter to ProjectContextBuilder init, update 3 call sites.

**Implementation**:

PKMPathManager (`Sources/Services/FileSystem/PKMPathManager.swift`):
```swift
// Lines 177-181
func loadNoteIndex() -> NoteIndex? {
    guard let data = FileManager.default.contents(atPath: noteIndexPath) else { return nil }
    return try? JSONDecoder().decode(NoteIndex.self, from: data)
}
```

ProjectContextBuilder (`Sources/Pipeline/ProjectContextBuilder.swift`):
```swift
// Lines 4-11
struct ProjectContextBuilder {
    let pkmRoot: String
    let noteIndex: NoteIndex?

    init(pkmRoot: String, noteIndex: NoteIndex? = nil) {
        self.pkmRoot = pkmRoot
        self.noteIndex = noteIndex
    }
}
```

**Call Sites**:

| File | Design | Implementation | Status |
|------|--------|----------------|--------|
| InboxProcessor | `loadNoteIndex()` + inject | Lines 39-40 | Match |
| VaultReorganizer | `loadNoteIndex()` + inject | Lines 93-94 | Match |
| FolderReorganizer | `loadNoteIndex()` + inject | Lines 91-92 | Match |

**Verdict**: Match (100%)

---

## 3. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| FR-06: NoteIndexEntry area field | 100% | Match |
| FR-01: buildTagVocabulary index-first | 100% | Match |
| FR-03: buildProjectContext + extractScope deleted | 100% | Match |
| FR-02: buildSubfolderContext enriched + Classifier | 100% | Match |
| FR-04: buildWeightedContext fallback deleted | 100% | Match |
| FR-05: Area projects CRUD + 7 call sites | 100% | Match |
| Shared: PKMPathManager.loadNoteIndex + init + 3 call sites | 100% | Match |
| **Overall** | **100%** | Match |

---

## 4. Deviations (Improvements over Design)

These are intentional implementation improvements that deviate from the design in a positive direction:

### 4.1 noteCount Pre-computation (FR-02)

**Design**: `index.notes.values.filter { $0.folder == folderKey }.count` per folder (O(N*M) where N=folders, M=notes).

**Implementation**: Pre-computed `folderNoteCounts` dictionary via single O(M) pass, then O(1) lookup per folder.

**Impact**: Performance improvement for large vaults. No functional change.

### 4.2 Simplified removeProjectFromArea API (FR-05)

**Design**: `removeProjectFromArea(projectName:areaName:pkmRoot:)` -- caller must know area name.

**Implementation**: `removeProjectFromArea(projectName:pkmRoot:)` -- auto-discovers area via `findAreaForProject()`.

**Impact**: Simpler API, fewer parameters, callers don't need to pre-resolve area name. No functional change.

### 4.3 Sorted folder iteration (FR-03)

**Design**: Iterates `index.folders` without explicit sort order.

**Implementation**: `.sorted(by: { $0.key < $1.key })` for deterministic output.

**Impact**: Consistent classifier context across runs.

---

## 5. Missing/Added Features

### 5.1 Missing Features (Design present, Implementation absent)

**None found.** All 6 FRs and shared infrastructure changes are fully implemented.

### 5.2 Added Features (Implementation present, Design absent)

**None found.** No undocumented features were added.

---

## 6. Architecture Compliance

| Rule | Status | Notes |
|------|--------|-------|
| Pipeline code in `Sources/Pipeline/` | Match | ProjectContextBuilder remains in Pipeline |
| Services code in `Sources/Services/` | Match | FrontmatterWriter, PKMPathManager in Services |
| UI Views read AppState only | Match | OnboardingView calls FrontmatterWriter through its own private method |
| Index-first search pattern (CLAUDE.md) | Match | All 5 functions follow index-first, disk-fallback |
| No `DispatchQueue.global` | Match | No threading changes |
| TaskGroup concurrency limits | Match | Pre-existing limits preserved |

---

## 7. Match Rate Summary

```
+-----------------------------------------------+
|  Overall Match Rate: 100%                      |
+-----------------------------------------------+
|  Match:               7/7 items (100%)         |
|  Missing (design only):  0 items (0%)          |
|  Not implemented:        0 items (0%)          |
|  Deviations:          3 (all improvements)     |
+-----------------------------------------------+
```

---

## 8. Recommended Actions

### 8.1 No Immediate Actions Required

All FRs are fully implemented with 100% match rate. The 3 deviations noted are improvements over the design and do not require correction.

### 8.2 Documentation Update

- [ ] Update design document status from "Draft" to "Approved"
- [ ] Record the 3 implementation improvements in the design document for future reference

### 8.3 Validation (from Design Section 7)

- [ ] Run `swift build` -- confirm 0 warnings
- [ ] Test with index present: classification results quality
- [ ] Test with index absent (delete `.meta/note-index.json`): fallback behavior identical to pre-refactor
- [ ] Verify buildTagVocabulary output (full tag coverage vs prefix(5) sampling)
- [ ] Verify project delete/move cleans Area projects field
- [ ] Verify VaultCheck prunes stale project references

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-27 | Initial gap analysis | bkit-gap-detector |
