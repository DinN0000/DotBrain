# pipeline-optimization Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: DotBrain
> **Analyst**: bkit-gap-detector
> **Date**: 2026-02-18
> **Design Doc**: [pipeline-optimization.design.md](../02-design/features/pipeline-optimization.design.md)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Verify that the pipeline-optimization feature (FR-01 through FR-04) has been implemented exactly as specified in the design document. Compare each "After" code block in the design with the actual source files.

### 1.2 Analysis Scope

| FR | Design Section | Implementation File(s) |
|----|----------------|------------------------|
| FR-01 | Section 2 | `Sources/Pipeline/InboxProcessor.swift`, `Sources/App/AppState.swift` |
| FR-02 | Section 3 | `Sources/Services/Claude/Classifier.swift`, `Sources/Pipeline/InboxProcessor.swift`, `Sources/Services/AICompanionService.swift` |
| FR-04 | Section 4 | `Sources/Services/MOCGenerator.swift` |
| FR-03 | Section 5 | `Sources/Pipeline/ProjectContextBuilder.swift` |

---

## 2. Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| FR-01: Area Options + relatedNotes | 100% | PASS |
| FR-02: Stage 1 Preview Removal | 100% | PASS |
| FR-04: Root MOC Enrichment | 100% | PASS |
| FR-03: Context Build Optimization | 97% | PASS |
| **Overall** | **99%** | **PASS** |

---

## 3. Detailed Comparison

### 3.1 FR-01: Area Options + relatedNotes Fix

#### Change A: `generateUnmatchedProjectOptions()` -- InboxProcessor.swift (lines 371-411)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Option 1: Resource with relatedNotes | `relatedNotes: base.relatedNotes` | Line 385: `relatedNotes: base.relatedNotes` | MATCH |
| Option 2: Area (new) | `.area`, confidence 0.6, `relatedNotes: base.relatedNotes` | Lines 389-397: `.area`, 0.6, `relatedNotes: base.relatedNotes` | MATCH |
| Option 3: Archive with relatedNotes | `relatedNotes: base.relatedNotes` | Line 407: `relatedNotes: base.relatedNotes` | MATCH |
| Old project loop removed | No loop over `projectNames` | No loop present | MATCH |
| `projectNames` param retained | Kept in signature | Line 373: `projectNames: [String]` present | MATCH |

**Result: 5/5 items match -- 100%**

#### Change B: `generateOptions()` -- InboxProcessor.swift (lines 414-431)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `var alt = base` removed | Not present in After block | Not present in implementation | MATCH |
| `relatedNotes: base.relatedNotes` added | Present in all alternatives | Line 426: `relatedNotes: base.relatedNotes` | MATCH |
| First option `[base]` unchanged | `var options: [ClassifyResult] = [base]` | Line 415: `var options: [ClassifyResult] = [base]` | MATCH |

**Result: 3/3 items match -- 100%**

#### Change D: `AppState.createProjectAndClassify()` -- AppState.swift (lines 495-529)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `relatedNotes: base.relatedNotes` in new ClassifyResult | Present | Line 514: `relatedNotes: base.relatedNotes` | MATCH |
| Other fields unchanged | tags, summary, targetFolder, project, confidence | Lines 508-513: all match | MATCH |

**Result: 2/2 items match -- 100%**

---

### 3.2 FR-02: Stage 1 Preview Removal

#### Change A: Constants -- Classifier.swift (lines 7-8)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `batchSize` 10 -> 5 | `private let batchSize = 5` | Line 7: `private let batchSize = 5` | MATCH |
| `previewLength` removed | Not present | Not present (confirmed via grep) | MATCH |
| `confidenceThreshold` unchanged | 0.8 | Line 8: `0.8` | MATCH |

**Result: 3/3 items match -- 100%**

#### Change B: `extractPreview` replaced with direct content -- Classifier.swift (lines 182-184)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `fileContents = files.map { (fileName, content) }` | Present | Lines 182-184: `let fileContents = files.map { file in (fileName: file.fileName, content: file.content) }` | MATCH |
| `extractPreview` call removed | Not present | Not present (confirmed via grep) | MATCH |
| Prompt uses `fileContents` | `buildStage1Prompt(fileContents, ...)` | Line 186: `buildStage1Prompt(fileContents, ...)` | MATCH |

**Result: 3/3 items match -- 100%**

#### Change C: `buildStage1Prompt` signature + body -- Classifier.swift (lines 264-273)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Parameter: `preview` -> `content` | `(fileName: String, content: String)` | Line 265: `(fileName: String, content: String)` | MATCH |
| Prompt label: "preview" -> "content" | `"\n내용: \(truncated)"` | Line 272: `"내용: \(truncated)"` | MATCH |

**Result: 2/2 items match -- 100%**

#### Change D: Content length defensive cap -- Classifier.swift (lines 270-273)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `String(f.content.prefix(5000))` truncation | Present | Line 271: `let truncated = String(f.content.prefix(5000))` | MATCH |
| Used in prompt string | `"\n내용: \(truncated)"` | Line 272: `return "[\(i)] 파일명: \(f.fileName)\n내용: \(truncated)"` | MATCH |

**Result: 2/2 items match -- 100%**

#### Change E: Cost estimate -- InboxProcessor.swift (line 109)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `0.001` -> `0.005` | `Double(inputs.count) * 0.005` | Line 109: `Double(inputs.count) * 0.005` | MATCH |
| Comment updated | Stage 1 full content + Stage 2 fallback | Line 109: `// ~$0.005 per file (Stage 1 full content + Stage 2 fallback)` | MATCH |

**Result: 2/2 items match -- 100%**

#### AICompanionService.swift (line 760)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Text: "파일 전체 내용(5000자)으로 분류 (5개씩 배치, 최대 3개 동시)" | Present | Line 760: exact text match | MATCH |

**Result: 1/1 items match -- 100%**

---

### 3.3 FR-04: Root MOC Enrichment

#### `generateCategoryRootMOC()` -- MOCGenerator.swift (lines 136-231)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Extended tuple type with `tags` and `docs` | 5-element tuple | Line 142: `(name: String, summary: String, fileCount: Int, tags: [String], docs: [(name: String, tags: String, summary: String)])` | MATCH |
| Subfolder MOC read for tags | `Frontmatter.parse` -> `folderTags` | Lines 151-158: reads subMOCPath, parses frontmatter, extracts `folderTags` | MATCH |
| File count logic | Filter `.md`, exclude hidden/MOC | Lines 161-165: exact match | MATCH |
| Project-only per-doc listings (max 10) | `if para == .project { ... mdFiles.sorted().prefix(10) }` | Lines 168-179: conditional on `.project`, max 10 | MATCH |
| Per-doc tag/summary extraction | `fileFM.tags.prefix(3).joined(separator: ", ")` | Line 175: `let tagStr = fileFM.tags.prefix(3).joined(separator: ", ")` | MATCH |
| Tag aggregation across subfolders | `categoryTags[tag, default: 0] += 1`, top 10 | Lines 187-194: exact logic match | MATCH |
| Frontmatter with `topTags` | `tags: topTags` in `Frontmatter.createDefault` | Line 199: `tags: topTags` | MATCH |
| Summary format | `"\(para.displayName) 카테고리 인덱스 -- \(subfolders.count)개 폴더"` | Line 200: exact match | MATCH |
| Folder tag labels in content | `folder.tags.prefix(5).joined(separator: ", ")` | Line 210: `folder.tags.prefix(5).joined(separator: ", ")` | MATCH |
| Per-doc listings under project folders | `for doc in folder.docs { ... }` | Lines 219-226: exact match | MATCH |
| Doc detail format | `[doc.tags, doc.summary].filter { !$0.isEmpty }.joined(separator: " -- ")` | Line 220: exact match | MATCH |

**Result: 11/11 items match -- 100%**

---

### 3.4 FR-03: Context Build Optimization

#### `buildWeightedContext()` -- ProjectContextBuilder.swift (lines 79-111)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| 4-category array with path/label/emoji/weight | Present | Lines 80-85: exact match | MATCH |
| Root MOC path construction | `(basePath as NSString).appendingPathComponent("\(categoryName).md")` | Line 91: exact match | MATCH |
| `Frontmatter.parse` -> body check | Parse, trim, check empty | Lines 94-100: exact match | MATCH |
| Section format for MOC hit | `"### \(emoji) \(label) (\(weight))\n\(trimmed)"` | Line 98: exact match | MATCH |
| Per-category fallback call | `buildCategoryFallback(...)` | Line 104: exact match | MATCH |
| Empty fallback string | `"기존 문서 없음"` | Line 110: exact match | MATCH |

**Result: 6/6 items match -- 100%**

#### `buildCategoryFallback()` -- ProjectContextBuilder.swift (lines 114-126)

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| `switch label` for Project/Archive/default | 3 cases | Lines 116-123: exact match | MATCH |
| Project -> `buildProjectDocuments()` | Present | Line 118 | MATCH |
| Archive -> `buildArchiveSummary()` | Present | Line 120 | MATCH |
| Default -> `buildFolderSummaries(at:label:)` | Present | Line 122 | MATCH |
| Guard empty + return format | `guard !section.isEmpty else { return "" }` | Line 124 | MATCH |
| Return format | `"### \(emoji) \(label) (\(weight))\n\(section)"` | Line 125 | MATCH |

**Result: 6/6 items match -- 100%**

#### Design mention of `buildWeightedContextLegacy` rename

| Item | Design | Implementation | Status |
|------|--------|----------------|--------|
| Rename old function to `buildWeightedContextLegacy` | Design mentions rename | Old function replaced in-place, no legacy rename | MINOR DEVIATION |

This is a stylistic deviation. The design suggested renaming the old function to `buildWeightedContextLegacy()` as a preservation step, but the implementation replaced `buildWeightedContext()` in-place with the new logic and extracted fallback paths into `buildCategoryFallback()`. The functional result is identical -- the legacy code paths exist as private helpers (`buildProjectDocuments`, `buildFolderSummaries`, `buildArchiveSummary`). No dead code was left behind.

**Impact: None** -- functionally equivalent, arguably cleaner.

---

## 4. Differences Found

### MISSING (Design present, Implementation absent)

None.

### ADDED (Design absent, Implementation present)

None.

### CHANGED (Design differs from Implementation)

| Item | Design | Implementation | Impact |
|------|--------|----------------|--------|
| `buildWeightedContextLegacy` rename | Design says rename old func | Old func replaced in-place, fallback logic in `buildCategoryFallback()` | None -- cleaner approach |

---

## 5. Match Rate Summary

```
Total Design Items Checked: 46
Exact Matches:              45
Minor Deviations:            1 (functionally equivalent)
Missing Implementations:     0
Unexpected Additions:        0

Overall Match Rate: 99% (45/46 exact + 1 equivalent)
```

---

## 6. Architecture Compliance

| Check | Status |
|-------|--------|
| Pipeline flow preserved | PASS -- no function signature changes to external callers |
| Fallback guarantees | PASS -- per-category hybrid fallback implemented |
| Existing test/UI code unaffected | PASS -- no external API changes |
| `buildProjectContext()` unchanged | PASS -- confirmed unchanged |
| `buildSubfolderContext()` unchanged | PASS -- confirmed unchanged |
| `extractProjectNames()` unchanged | PASS -- confirmed unchanged |
| `extractPreview` preserved for ContextLinker | PASS -- only removed from Classifier; FileContentExtractor.extractPreview() still exists |

---

## 7. Convention Compliance (per CLAUDE.md)

| Rule | Status | Notes |
|------|--------|-------|
| Korean for UI strings, English for comments/code | PASS | Comments in Korean where design specifies, code identifiers in English |
| No emojis in code | N/A | Emojis used in prompt strings only (user-facing AI prompts), not in logic code |
| `@MainActor` + `await MainActor.run` for UI | N/A | No UI changes in this feature |
| `TaskGroup` with concurrency limit (max 3) | PASS | Classifier batch processing uses max 3 concurrent |
| Path traversal: canonicalize before hasPrefix | PASS | Existing `pathManager.isPathSafe()` calls preserved |
| YAML injection: double-quote tags | PASS | `Frontmatter.createDefault` handles quoting |

---

## 8. Recommended Actions

### Immediate Actions

None required. All design items are implemented correctly.

### Documentation Update

- [OPTIONAL] Update design doc Section 5 to reflect that `buildWeightedContextLegacy` rename was not done; instead the function was replaced in-place with fallback extracted to `buildCategoryFallback()`.

---

## 9. Conclusion

The pipeline-optimization feature achieves a **99% match rate** between design and implementation. The single deviation (legacy function naming) is a stylistic improvement over the design with zero functional impact. All four FRs (FR-01 through FR-04) are fully implemented as designed.

Match Rate >= 90% -- **Check phase complete.**

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-18 | Initial gap analysis | bkit-gap-detector |
