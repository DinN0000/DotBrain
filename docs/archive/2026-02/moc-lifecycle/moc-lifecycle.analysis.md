# moc-lifecycle Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: DotBrain
> **Analyst**: gap-detector agent
> **Date**: 2026-02-18
> **Design Doc**: [moc-lifecycle.design.md](../02-design/features/moc-lifecycle.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Verify that all three functional requirements (FR-01, FR-02, FR-03) from the moc-lifecycle design document are fully implemented in the codebase.

### 1.2 Analysis Scope

- **Design Document**: `docs/02-design/features/moc-lifecycle.design.md`
- **Implementation Files**:
  - `Sources/Services/MOCGenerator.swift` (FR-01)
  - `Sources/Pipeline/VaultReorganizer.swift` (FR-02, FR-03)
  - `Sources/Pipeline/FolderReorganizer.swift` (FR-03)
- **Analysis Date**: 2026-02-18

---

## 2. Gap Analysis (Design vs Implementation)

### 2.1 FR-01: Root MOC Tag/Doc Listing Bug Fix — PASS

**Design Requirement**: Add debug logs and defensive code to `generateCategoryRootMOC()` to trace why `folderTags` returns empty at runtime.

| Check Item | Design Spec | Implementation | Status |
|------------|-------------|----------------|--------|
| Debug log when `folderTags` is empty | `print("[MOCGenerator] ROOT-DEBUG ...")` with tag count and summary | Line 158-160: `print("[MOCGenerator] ROOT-MOC \(entry): tags empty (summary=\(summary.prefix(40))...)")` | PASS |
| Debug log when subfolder MOC read fails | `print("[MOCGenerator] ROOT-DEBUG ...): MOC 읽기 실패")` | Line 162: `print("[MOCGenerator] ROOT-MOC \(entry): failed to read \(subMOCPath)")` | PASS |
| Debug log when per-document file read fails | `print("[MOCGenerator] ROOT-DEBUG   doc FAIL: ...")` | Line 183: `print("[MOCGenerator] ROOT-MOC doc read failed: \(file)")` | PASS |
| Debug log when docs is empty but mdFiles is not | Design Section 3.3 specifies this check | Line 186-188: `print("[MOCGenerator] ROOT-MOC \(entry): \(mdFiles.count) md files but 0 docs parsed")` | PASS |
| Warning log when `topTags` is empty but subfolders exist | Design Section 3.5 defensive code | Lines 206-209: `print("[MOCGenerator] WARNING: root MOC \(categoryName) has 0 tags -- subfolder tags: \(tagStatus)")` | PASS |

**Notes on minor deviations**:

- The design uses the log prefix `[MOCGenerator] ROOT-DEBUG` while the implementation uses `[MOCGenerator] ROOT-MOC`. This is a cosmetic naming difference that does not affect functionality. The log content and placement match the design intent exactly.
- The warning log in the implementation uses English text (`"root MOC ... has 0 tags"`) rather than the Korean shown in design (`"루트 MOC 태그 0개"`). This actually aligns with the CLAUDE.md convention: "English for comments and code."

**Verdict**: All five debug/warning log points specified in the design are present in the implementation with equivalent logic and placement. The naming of the log prefix differs from the design (`ROOT-MOC` vs `ROOT-DEBUG`) but the diagnostic purpose is identical.

---

### 2.2 FR-02: VaultReorganizer MOC Update — PASS

**Design Requirement**: After `execute()` moves files, collect affected folders and call `MOCGenerator.updateMOCsForFolders()`.

| Check Item | Design Spec (Section 4.2) | Implementation (Lines 221-231) | Status |
|------------|---------------------------|-------------------------------|--------|
| Collect affected folders from successful results | `Set(results.filter(\.isSuccess).compactMap { ... })` | Line 222: `Set(results.filter(\.isSuccess).compactMap { result -> String? in` | PASS |
| Extract directory from `targetPath` | `(result.targetPath as NSString).deletingLastPathComponent` | Line 223: `let dir = (result.targetPath as NSString).deletingLastPathComponent` | PASS |
| Guard against empty dir | `return dir.isEmpty ? nil : dir` | Line 224: `return dir.isEmpty ? nil : dir` | PASS |
| Create MOCGenerator and call updateMOCsForFolders | `MOCGenerator(pkmRoot: pkmRoot)` + `updateMOCsForFolders(affectedFolders)` | Lines 229-230: exact match | PASS |
| Progress callback at 0.95 for MOC phase | Not explicitly in design pseudocode but implied by pattern | Line 228: `onProgress?(0.95, "MOC 갱신 중...")` | PASS |
| MOC update placed before final `onProgress?(1.0, "완료!")` | Design shows MOC block before `onProgress?(1.0, ...)` | Lines 221-231 appear before Line 233: `onProgress?(1.0, "완료!")` | PASS |

**Verdict**: The implementation follows the FolderReorganizer pattern exactly as specified in the design. The code structure, variable names, and logic are a near-exact match to the design pseudocode in Section 4.2. The progress callback at 0.95 is an improvement not explicitly in the design but consistent with the existing pattern and adds user feedback during the MOC update phase.

---

### 2.3 FR-03: Cost Estimate Unification — PASS

**Design Requirement**: Change `0.001` to `0.005` in both VaultReorganizer and FolderReorganizer.

| File | Design Target | Implementation | Status |
|------|---------------|----------------|--------|
| `VaultReorganizer.swift:140` | `Double(inputs.count) * 0.005` | `let estimatedCost = Double(inputs.count) * 0.005` | PASS |
| `FolderReorganizer.swift:133` | `Double(inputs.count) * 0.005` | `let estimatedCost = Double(inputs.count) * 0.005  // ~$0.005 per file` | PASS |

**Verdict**: Both cost values have been changed from `0.001` to `0.005` as specified. The implementation matches the design exactly.

---

### 2.4 Additional Checks

| Check Item | Status | Notes |
|------------|--------|-------|
| No new files created | PASS | All changes are edits to existing 3 files |
| English comments in code | PASS | All code comments are in English |
| No emojis in code | PASS | No emoji characters in any of the 3 files |
| Korean UI strings | PASS | User-facing strings like "MOC 갱신 중...", "완료!" are in Korean |
| `@MainActor` / `Task.detached` patterns | N/A | No new UI update code added |
| StatisticsService wiring | PASS | Pre-existing `StatisticsService.addApiCost` call at VaultReorganizer:141 remains correct |

---

## 3. Match Rate Summary

```
+---------------------------------------------+
|  Overall Match Rate: 100%                    |
+---------------------------------------------+
|  FR-01 (Debug logs):       5/5 items  PASS   |
|  FR-02 (MOC update):       6/6 items  PASS   |
|  FR-03 (Cost unification): 2/2 items  PASS   |
|  Convention compliance:    4/4 items  PASS   |
+---------------------------------------------+
|  Total: 17/17 check items passed             |
+---------------------------------------------+
```

---

## 4. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match | 100% | PASS |
| Architecture Compliance | 100% | PASS |
| Convention Compliance | 100% | PASS |
| **Overall** | **100%** | **PASS** |

---

## 5. Differences Found

### Missing Features (Design present, Implementation absent)

None.

### Added Features (Design absent, Implementation present)

| Item | Implementation Location | Description | Impact |
|------|------------------------|-------------|--------|
| Progress callback 0.95 | VaultReorganizer.swift:228 | `onProgress?(0.95, "MOC 갱신 중...")` before MOC update | Low (positive -- adds user feedback) |

This is an additive improvement that follows the existing pattern from FolderReorganizer and does not conflict with the design.

### Changed Features (Design differs from Implementation)

| Item | Design | Implementation | Impact |
|------|--------|----------------|--------|
| Log prefix | `ROOT-DEBUG` | `ROOT-MOC` | None (cosmetic -- same diagnostic purpose) |
| Warning message language | Korean (`루트 MOC 태그 0개`) | English (`root MOC ... has 0 tags`) | None (aligns with CLAUDE.md English comment convention) |

Both deviations are cosmetic and the English warning text is actually more consistent with the project's CLAUDE.md convention of using English for code and comments.

---

## 6. FR-by-FR Verdict

| FR | Description | Verdict | Explanation |
|----|-------------|---------|-------------|
| FR-01 | Root MOC tag/doc listing debug logs | **PASS** | All 5 debug/warning log points implemented. Log prefix uses `ROOT-MOC` instead of `ROOT-DEBUG` -- cosmetic only. |
| FR-02 | VaultReorganizer MOC update | **PASS** | `execute()` collects affected folders, calls `updateMOCsForFolders()`, includes 0.95 progress callback. Exact match to design pseudocode. |
| FR-03 | Cost estimate unification | **PASS** | Both `VaultReorganizer.swift:140` and `FolderReorganizer.swift:133` now use `0.005`. |

---

## 7. Recommended Actions

No immediate actions required. Design and implementation are fully aligned.

### Documentation Updates

- [ ] Consider updating the design document Section 3.3 to reflect the actual log prefix `ROOT-MOC` instead of `ROOT-DEBUG` (optional, low priority)
- [ ] Consider updating design Section 3.5 warning message to show English text matching the implementation (optional, low priority)

---

## 8. Overall Assessment

The implementation achieves a **100% match rate** against the moc-lifecycle design document. All three functional requirements (FR-01 through FR-03) are fully implemented in the correct files with the correct logic. The two minor cosmetic deviations (log prefix naming and warning message language) are both reasonable improvements that better align with the project's coding conventions defined in CLAUDE.md.

No gaps requiring action. The feature is ready for runtime testing as described in the design document's Test Plan (Section 7).

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-18 | Initial gap analysis -- 100% match | gap-detector |
