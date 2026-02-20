# vault-check-perf Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: DotBrain
> **Analyst**: gap-detector
> **Date**: 2026-02-20
> **Design Doc**: [vault-check-perf.design.md](../02-design/features/vault-check-perf.design.md)
> **Status**: Approved

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Re-run gap analysis for the vault-check-perf feature after fixes were applied to three previously identified gaps. This analysis compares the design document against actual implementation to calculate the overall match rate.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/vault-check-perf.design.md`
- **Implementation Files**:
  - `Sources/Services/ContentHashCache.swift`
  - `Sources/Services/VaultAuditor.swift`
  - `Sources/Services/MOCGenerator.swift`
  - `Sources/Services/SemanticLinker/SemanticLinker.swift`
  - `Sources/App/AppState.swift`
  - `Sources/Services/RateLimiter.swift`
- **Analysis Date**: 2026-02-20

---

## 2. Previously Identified Gaps (Status)

### 2.1 Gap 1: Final cache update before save

**Design (Section 2.5, line 225)**:
```swift
await cache.updateHashesAndSave(Array(allChanged))
```

**Implementation (AppState.swift:334-335)**:
```swift
await cache.updateHashes(Array(allChangedFiles))
await cache.save()
```

**Status**: RESOLVED. The implementation performs the final `cache.updateHashes(allChangedFiles)` on line 334 immediately before `cache.save()` on line 335. The behavior is functionally equivalent to the design's `updateHashesAndSave()`. See Section 3.3 for the minor naming variance.

### 2.2 Gap 2: collectRepairedFiles as dedicated static helper

**Design (Section 2.6)**:
```swift
private func collectRepairedFiles(from report: AuditReport, repair: RepairResult) -> [String]
```

**Implementation (AppState.swift:361-374)**:
```swift
private nonisolated static func collectRepairedFiles(from report: AuditReport) -> [String] {
    var files = Set<String>()
    for link in report.brokenLinks where link.suggestion != nil {
        files.insert(link.filePath)
    }
    for path in report.missingFrontmatter {
        files.insert(path)
    }
    for path in report.missingPARA {
        files.insert(path)
    }
    return Array(files)
}
```

**Status**: RESOLVED. The function is extracted as a dedicated `static` helper. The signature differs slightly (`nonisolated static`, no `repair` parameter) but this is a valid improvement -- the `repair` parameter is unused since the function only needs the report. See Section 3.3 for details.

### 2.3 Gap 3: brokenLinks filtered by `suggestion != nil`

**Design (Section 2.6, line 240)**:
```swift
for link in report.brokenLinks where link.suggestion != nil {
    files.insert(link.filePath)
}
```

**Implementation (AppState.swift:364)**:
```swift
for link in report.brokenLinks where link.suggestion != nil {
```

**Status**: RESOLVED. Exact match with the design specification.

---

## 3. Gap Analysis (Design vs Implementation)

### 3.1 Phase 1: ContentHashCache (Section 2.1)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `checkFiles(_ filePaths:)` batch method | ContentHashCache.swift:119-125 | Match | Exact match |
| `updateHashesAndSave(_ filePaths:)` | `updateHashes(_ filePaths:)` at line 149-154 | Minor naming change | Functionally identical: updates + saves |
| Existing `checkFile()`, `checkFolder()` preserved | Lines 71-114 | Match | Unchanged |
| Actor-based design | Line 6: `actor ContentHashCache` | Match | |

### 3.2 Phase 1: NoteEnricher (Section 2.2)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| No changes to NoteEnricher itself | NoteEnricher.swift not modified | Match | Filtering done at AppState level |

### 3.3 Phase 1: MOCGenerator.regenerateAll (Section 2.3)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `regenerateAll(dirtyFolders: Set<String>? = nil)` signature | MOCGenerator.swift:253 | Match | Exact parameter match |
| `dirtyFolders == nil` -> full regeneration | Lines 277-281 | Match | Falls through to full task list |
| `dirtyFolders != nil` -> filter to dirty folders only | Lines 276-278 | Match | `folderTasks.filter { dirty.contains($0.folderPath) }` |
| Root category MOC: dirty categories only | Lines 307-316 | Match | `affectedCategories` derived from dirty folders |
| Root category MOC: `dirtyCategories` via `deletingLastPathComponent` | Lines 309-310 | Match | Same derivation |
| Additional: `updateMOCsForFolders()` method | Lines 107-134 | Added (not in design) | Supplementary API for targeted updates |

### 3.4 Phase 1: SemanticLinker.linkAll (Section 2.4)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `linkAll(changedFiles: Set<String>? = nil, ...)` signature | SemanticLinker.swift:23 | Match | Exact parameter match |
| `changedFiles == nil` -> full scan | Lines 57-58 | Match | `targetNotes = allNotes` |
| `changedFiles != nil` -> filter by changed names | Lines 47-56 | Match | |
| Full index still built (`buildNoteIndex()`) | Line 36 | Match | All notes indexed for candidate generation |
| Changed names extracted from path basename | Lines 48-49 | Match | `lastPathComponent` -> `deletingPathExtension` |
| Reverse link coverage: `existingRelated.isDisjoint(with:)` | Lines 52-54 | Match | Same bidirectional filter logic |
| NSLog for incremental stats | Line 56 | Added (not in design) | Observability improvement |

### 3.5 Phase 1: AppState.startVaultCheck (Section 2.5)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `cache.load()` at start | AppState.swift:247 | Match | |
| Phase 1: Audit | Line 249-250 | Match | |
| Phase 2: Repair + `collectRepairedFiles` | Lines 254-261 | Match | See Section 2.2 |
| `cache.updateHashesAndSave(repairedFiles)` | Line 261: `cache.updateHashes(repairedFiles)` | Naming variant | `updateHashes` does update+save internally |
| Batch file status check via `checkFiles()` | Lines 268-270 | Match | |
| `changedFiles` = non-unchanged filter | Line 270 | Match | |
| Phase 3: Enrich (changed files, skip archive) | Lines 276-307 | Match | Filter by `!contains("/4_Archive/")` |
| TaskGroup(max 3) for enrichment | Lines 280-307 | Match | Same concurrency pattern |
| `cache.updateHashesAndSave(enrichedFiles)` after enrich | Lines 308-309: conditional `updateHashes` | Improved | Only saves if enriched files exist |
| Phase 4: MOC with `dirtyFolders` | Lines 314-320 | Match | |
| `dirtyFolders` = union of changed + enriched | Lines 315-317 | Match | |
| Phase 5: SemanticLink with `allChanged` | Lines 324-331 | Match | |
| Final `cache.updateHashesAndSave(allChanged)` | Lines 334-335 | Match | Separate `updateHashes` + `save` calls |
| `collectAllMdFiles` helper | Lines 377-401: `static func` | Match | Static extraction |
| UI progress updates via `MainActor.run` | Lines 256, 266, 275, 314, 324 | Added (not in design) | UI feedback improvement |
| `StatisticsService.recordActivity` | Lines 237-242, 337-342 | Added (not in design) | Statistics wiring per CLAUDE.md |

### 3.6 Phase 2: RateLimiter Concurrent Slot (Section 3)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `ProviderState` with `slotCount` + `slotNextAvailable` | RateLimiter.swift:9-17 | Match | |
| `defaultSlots`: claude=3, gemini=1 | Lines 32-35 | Match | |
| `acquire()` earliest slot selection | Lines 58-63 | Match | Loop-based instead of `enumerated().min()` |
| Slot reservation before sleep | Lines 70-71 | Match | |
| `recordSuccess()`: 15%/2 consecutive | Lines 87-93 | Match | |
| `recordFailure()`: all slots to backoffEnd | Lines 113-116 | Match | Array iteration sets all slots |
| `recordFailure()` rate limit: interval x2, exp cooldown | Lines 108-112 | Match | |
| `recordFailure()` server error: interval x1.5, 5s | Lines 120-121 | Match | |
| `getState()` initialization with slots | Lines 130-141 | Match | |

### 3.7 Phase 3: VaultAuditor Duplicate Call Removal (Section 4)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| `noteNames(from files:)` replaces `allNoteNames()` | VaultAuditor.swift:337-344 | Match | |
| `audit()` reuses `files` for `noteNames` | Line 43 | Match | `self.noteNames(from: files)` |
| All private, no external API change | Lines 296-344 all private | Match | |

### 3.8 Phase 4: NoteEnricher Parallel (Section 5)

| Design Item | Implementation | Status | Notes |
|-------------|---------------|--------|-------|
| Flat list + single TaskGroup(max 3) | AppState.swift:280-307 | Match | Replaces per-folder sequential |
| `enrichFolder()` preserved | NoteEnricher not modified | Match | Method retained for future use |

---

## 4. Differences Summary

### 4.1 Missing Features (Design O, Implementation X)

None identified. All design items are implemented.

### 4.2 Added Features (Design X, Implementation O)

| Item | Implementation Location | Description | Impact |
|------|------------------------|-------------|--------|
| `MOCGenerator.updateMOCsForFolders()` | MOCGenerator.swift:107-134 | Targeted MOC update for specific folder set | Low (supplementary API) |
| `SemanticLinker.linkNotes(filePaths:)` | SemanticLinker.swift:173-284 | Per-file linking without tag normalization | Low (supplementary API) |
| UI progress phases | AppState.swift:256,266,275,314,324 | `backgroundTaskPhase` updates per step | Low (UX improvement) |
| StatisticsService wiring | AppState.swift:237-242, 337-342 | Activity recording for vault check | Low (per CLAUDE.md requirement) |
| Incremental NSLog | SemanticLinker.swift:56 | Log count of targeted vs total notes | Low (observability) |

### 4.3 Changed Features (Design != Implementation)

| Item | Design | Implementation | Impact |
|------|--------|----------------|--------|
| Batch update+save method name | `updateHashesAndSave()` | `updateHashes()` (internally calls `save()`) | None (functionally identical) |
| `collectRepairedFiles` signature | `private func ... (from:repair:)` | `private nonisolated static func ... (from:)` | None (improvement: `repair` param was unused) |
| `acquire()` earliest slot search | `enumerated().min(by:)` | Manual loop comparison | None (same algorithm, different style) |
| Enrich cache update | Unconditional `updateHashesAndSave` | Conditional `if !enrichedFiles.isEmpty` | Low (performance: skip save when nothing enriched) |

---

## 5. Code Quality Notes

### 5.1 Security

| Check | Status | Notes |
|-------|--------|-------|
| Path traversal protection | Pass | `ContentHashCache.isPathSafe()` uses `resolvingSymlinksInPath` + `hasPrefix` |
| No hardcoded secrets | Pass | |
| `@MainActor` isolation | Pass | AppState is `@MainActor`, background work via `Task.detached` |

### 5.2 Convention Compliance

| Rule | Status | Notes |
|------|--------|-------|
| `Task.detached(priority:)` for background | Pass | AppState.swift:225 |
| `TaskGroup` max 3 concurrency | Pass | Enrich and MOC both use max 3 |
| English for comments and code | Pass | All identifiers in English |
| Korean for UI strings | Pass | `backgroundTaskPhase` uses Korean |
| No emojis in code | Pass | |

---

## 6. Overall Scores

| Category | Items | Matched | Score | Status |
|----------|:-----:|:-------:|:-----:|:------:|
| ContentHashCache (Phase 1) | 4 | 4 | 100% | Pass |
| MOCGenerator (Phase 1) | 5 | 5 | 100% | Pass |
| SemanticLinker (Phase 1) | 6 | 6 | 100% | Pass |
| AppState orchestration (Phase 1) | 14 | 14 | 100% | Pass |
| RateLimiter (Phase 2) | 8 | 8 | 100% | Pass |
| VaultAuditor (Phase 3) | 3 | 3 | 100% | Pass |
| NoteEnricher parallel (Phase 4) | 2 | 2 | 100% | Pass |
| **Total** | **42** | **42** | **100%** | **Pass** |

```
+---------------------------------------------+
|  Design Match Rate: 100%                    |
+---------------------------------------------+
|  Matched:              42 / 42 items        |
|  Missing (design only):  0 items            |
|  Changed (minor):        4 items            |
|  Added (impl only):      5 items            |
+---------------------------------------------+
|  Architecture Compliance: 100%              |
|  Convention Compliance:   100%              |
|  Overall Score:           100%              |
+---------------------------------------------+
```

All 42 design specification items are present in the implementation. The 4 "changed" items are minor naming/style differences that are functionally equivalent or improvements over the design. The 5 "added" items are supplementary features (UI progress, statistics wiring, extra APIs) that do not conflict with the design.

---

## 7. Previously Identified Gaps -- Resolution Summary

| Gap | Description | Status | Evidence |
|-----|-------------|--------|----------|
| 1 | Final `cache.updateHashes(allChangedFiles)` before `cache.save()` | Resolved | AppState.swift:334-335 |
| 2 | `collectRepairedFiles` extracted as dedicated static helper | Resolved | AppState.swift:361-374 |
| 3 | `brokenLinks` filtered by `suggestion != nil` | Resolved | AppState.swift:364 |

---

## 8. Recommended Actions

No immediate actions required. The implementation matches the design at 100%.

### 8.1 Optional Design Document Updates

The following optional updates would bring the design document in sync with minor implementation choices:

- [ ] Update method name from `updateHashesAndSave()` to `updateHashes()` in design Section 2.1
- [ ] Update `collectRepairedFiles` signature to `static func` with single `report` parameter in design Section 2.6
- [ ] Document the added `updateMOCsForFolders()` API in design Section 2.3
- [ ] Document `StatisticsService.recordActivity` wiring in design Section 2.5

---

## 9. Next Steps

- [x] All critical gaps resolved
- [ ] Optional: Update design document to reflect minor implementation variants
- [ ] Proceed to completion report (`/pdca report vault-check-perf`)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-20 | Re-run analysis after 3 gap fixes; 100% match | gap-detector |
