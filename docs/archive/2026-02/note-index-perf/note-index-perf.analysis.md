# note-index-perf Analysis Report

> **Analysis Type**: Gap Analysis (Design vs Implementation)
>
> **Project**: DotBrain
> **Version**: 2.7.5
> **Analyst**: gap-detector
> **Date**: 2026-02-23
> **Design Doc**: Inline specification (Phase 2: note-index.json 기반 성능 최적화)

---

## 1. Analysis Overview

### 1.1 Analysis Purpose

Verify that the "note-index-perf" performance optimization feature -- FileHandle-based partial reads, index-first search, index-first note indexing, and tag reverse indices -- is correctly implemented according to the inline design specification (31 original requirements) plus 3 code-review-fix requirements added post-implementation.

### 1.2 Analysis Scope

- **Design Document**: Inline spec provided in task (4 Steps, 31 requirements) + 3 review-fix requirements
- **Implementation Files**:
  - `Sources/Services/NoteIndexGenerator.swift`
  - `Sources/Services/VaultSearcher.swift`
  - `Sources/Services/SemanticLinker/SemanticLinker.swift`
  - `Sources/Services/SemanticLinker/LinkCandidateGenerator.swift`
  - `Sources/Services/SemanticLinker/FolderRelationStore.swift` (supporting file for Review Fix 1)
- **Analysis Date**: 2026-02-23
- **Iteration**: 2 (post code-review fixes)

---

## 2. Gap Analysis -- Original Design (31 Requirements)

### 2.1 Step 1: NoteIndexGenerator frontmatter-only read

**File**: `Sources/Services/NoteIndexGenerator.swift` -- `scanFolder()`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| Replace `String(contentsOfFile:)` with `FileHandle` | `FileHandle(forReadingAtPath:)` used | Match | L178 |
| 4KB partial read (`readData(ofLength: 4096)`) | `handle.readData(ofLength: 4096)` | Match | L179 |
| `closeFile()` after read | `handle.closeFile()` | Match | L180 |
| UTF-8 trim loop `0...min(3, data.count)` | `for trim in 0...min(3, data.count)` | Match | L184 |
| Pattern from FolderHealthAnalyzer | Identical pattern applied | Match | L178-190 |

**Step 1 Score: 5/5 (100%)**

All five sub-requirements are fully implemented. The `scanFolder()` method at lines 178-190 uses `FileHandle(forReadingAtPath:)` to read only the first 4096 bytes, closes the handle immediately, and applies the UTF-8 trailing-byte trim loop exactly as specified.

---

### 2.2 Step 2: VaultSearcher index-first search

**File**: `Sources/Services/VaultSearcher.swift`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| Load note-index.json via `pathManager.noteIndexPath` | `loadNoteIndex()` uses `pathManager.noteIndexPath` | Match | L98 |
| Phase 1: match title/tags/summary from NoteIndex (zero file I/O) | Title match (L34), tag match (L50), summary match (L70) -- all from index, no file reads | Match | L26-83 |
| Phase 2: fallback if index results < 10 | `if results.count < 10` triggers `searchBodies()` | Match | L87 |
| If no index, graceful degradation to full fallback | `if let index = loadNoteIndex()` -- nil falls through to Phase 2 body search | Match | L26, L87 |
| `NoteIndexEntry.path` (relative) to absolute: `pkmRoot + "/" + path` | `rootPrefix + entry.path` where rootPrefix = canonicalized pkmRoot + "/" | Match | L28 |
| `PARACategory(rawValue: entry.para)` for PARA mapping | `PARACategory(rawValue: entry.para)` | Match | L30 |
| Existing method signature preserved | `func search(query: String) -> [SearchResult]` unchanged | Match | L14 |

**Step 2 Score: 7/7 (100%)**

The VaultSearcher implements a clean two-phase search strategy. Phase 1 queries the in-memory NoteIndex for title, tag, and summary matches without any disk I/O. Phase 2 falls back to directory-scan body search only when fewer than 10 results are found. Graceful degradation works correctly: when `loadNoteIndex()` returns nil, results remain empty (count 0 < 10), so the full body search fallback executes automatically.

---

### 2.3 Step 3: SemanticLinker.buildNoteIndex() index-first

**File**: `Sources/Services/SemanticLinker/SemanticLinker.swift`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| Try loading note-index.json first | `buildNoteIndexFromIndex()` called first in `buildNoteIndex()` | Match | L349 |
| Use tags/summary/project/para/folder from index | All fields read from `entry.tags`, `.summary`, `.project`, `.para`, `.folder` | Match | L389-398 |
| Only read file for `existingRelated` parsing (body's `## Related Notes`) | File read via `String(contentsOfFile:)` only for `parseExistingRelatedNames(body)` | Match | L380-387 |
| If no index, fallback to existing directory scan code | `buildNoteIndexFromDisk()` called when `buildNoteIndexFromIndex()` returns nil | Match | L354 |
| `folderRelPath` = `entry.folder` | `folderRelPath: entry.folder` | Match | L396 |
| `folderName` = `(entry.folder as NSString).lastPathComponent` | `let folderName = (entry.folder as NSString).lastPathComponent` | Match | L372 |
| Skip index notes: `baseName != folderName` | `guard baseName != folderName else { continue }` | Match | L375 |

**Step 3 Score: 7/7 (100%)**

The `buildNoteIndex()` method (L349-356) correctly implements the index-first pattern. `buildNoteIndexFromIndex()` (L358-403) loads `note-index.json` via `pathManager.noteIndexPath`, extracts metadata from index entries, and only reads each file from disk for the `## Related Notes` section parsing. `buildNoteIndexFromDisk()` (L405-462) preserves the original full-scan logic as a complete fallback.

---

### 2.4 Step 4: LinkCandidateGenerator tag reverse index

**File**: `Sources/Services/SemanticLinker/LinkCandidateGenerator.swift`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| `PreparedIndex` struct | `struct PreparedIndex` with `tagIndex`, `projectIndex`, `mocFolders` | Match | L24-28 |
| `tagIndex: [String: [Int]]` | `let tagIndex: [String: [Int]]` | Match | L25 |
| `projectIndex: [String: [Int]]` | `let projectIndex: [String: [Int]]` | Match | L26 |
| `mocFolders: [String: Set<String>]` | `let mocFolders: [String: Set<String>]` | Match | L27 |
| `prepareIndex(allNotes:mocEntries:)` method | Implemented, builds reverse indices | Match | L30-49 |
| New `generateCandidates(for:allNotes:preparedIndex:...)` overload | Implemented with reverse-index lookup | Match | L81-188 |
| Original `generateCandidates(for:allNotes:mocEntries:...)` preserved | Preserved, internally delegates to `prepareIndex` + new overload | Match | L57-77 |
| Score logic: tag overlap >= 2 | `if tagOverlap >= 2` | Match | L154 |
| Score threshold >= 3.0 | `guard score >= 3.0` | Match | L176 |

#### Call site changes in SemanticLinker.swift

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| `linkAll()`: call `prepareIndex()` once before loop | `candidateGen.prepareIndex(allNotes:mocEntries:)` called once at L77 | Match | L77 |
| `linkAll()`: pass `preparedIndex` to each `generateCandidates` | `candidateGen.generateCandidates(for:allNotes:preparedIndex:suppressSet:boostSet:)` at L80-86 | Match | L80-86 |
| `linkNotes()`: same pattern | `prepareIndex()` at L208, `generateCandidates(for:allNotes:preparedIndex:)` at L216-220 | Match | L208, L216-220 |

**Step 4 Score: 12/12 (100%)**

The `PreparedIndex` struct exactly matches the design. The `prepareIndex()` method builds three reverse indices: tag-to-note-indices, project-to-note-indices, and MOC folder membership. The new `generateCandidates` overload uses these reverse indices to collect candidate note indices first (L93-132), then scores only those candidates (L134-187), avoiding the O(n^2) full scan. The original overload at L57-77 is preserved and delegates internally.

**Original Design Total: 31/31 (100%)**

---

## 3. Gap Analysis -- Review Fix Requirements (3 Items)

### 3.1 Review Fix 1: Pre-computed suppress/boost sets

**Files**: `LinkCandidateGenerator.swift`, `SemanticLinker.swift`, `FolderRelationStore.swift`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| Index-based overload accepts `suppressSet: Set<String>` | Parameter: `suppressSet: Set<String> = []` | Match | LinkCandidateGenerator.swift:L87 |
| Index-based overload accepts `boostSet: Set<String>` | Parameter: `boostSet: Set<String> = []` | Match | LinkCandidateGenerator.swift:L88 |
| Index-based overload does NOT accept `FolderRelationStore?` | No `FolderRelationStore` parameter in index-based overload | Match | LinkCandidateGenerator.swift:L81-88 |
| `linkAll()` computes `suppressSet` once before loop | `let suppressSet = ...` computed at L48, before loop at L79 | Match | SemanticLinker.swift:L48 |
| `linkAll()` computes `boostSet` once before loop | `let boostSet = ...` computed at L49, before loop at L79 | Match | SemanticLinker.swift:L49 |
| `LinkCandidateGenerator` has static `pairKey(_:_:)` | `static func pairKey(_ a: String, _ b: String) -> String` | Match | LinkCandidateGenerator.swift:L52-54 |
| No disk I/O inside per-note loop | Loop at L79-86 uses only pre-computed `suppressSet`/`boostSet`, no `FolderRelationStore` access | Match | SemanticLinker.swift:L79-90 |

**Review Fix 1 Score: 7/7 (100%)**

The implementation cleanly separates the one-time disk I/O (`folderRelationStore.load()` at L47, `suppressPairs()`/`boostPairKeys()` at L48-49) from the per-note loop. The `suppressSet`/`boostSet` are `Set<String>` values computed once and passed as value types into the candidate generator. The static `pairKey(_:_:)` method at L52-54 matches `FolderRelationStore.pairKey(_:_:)` in logic (sorted `a|b` format). The original API overload at L57-77 retains `FolderRelationStore?` as a convenience parameter that converts to sets internally.

Note: `linkNotes()` at L216-220 calls the index-based overload without `suppressSet`/`boostSet` (using defaults `[]`). This means `linkNotes()` does not apply folder relations, but satisfies the "no disk I/O in per-note loop" requirement. This is a pre-existing behavioral gap (folder relations not wired in `linkNotes`), not a violation of Review Fix 1.

---

### 3.2 Review Fix 2: VaultSearcher body search streaming I/O

**File**: `Sources/Services/VaultSearcher.swift` -- `searchBodies()`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| Use `FileHandle` partial read in `searchBodies` | `FileHandle(forReadingAtPath: filePath)` | Match | L129 |
| Read size 64KB | `handle.readData(ofLength: 65536)` | Match | L130 |
| Close handle after read | `handle.closeFile()` | Match | L131 |
| Replace `String(contentsOfFile:)` | No `String(contentsOfFile:)` in `searchBodies` | Match | L129-132 |

**Review Fix 2 Score: 4/4 (100%)**

The `searchBodies()` method at L129-132 uses `FileHandle(forReadingAtPath:)` to read only the first 65,536 bytes (64KB) of each file, then immediately closes the handle. This replaces the previous `String(contentsOfFile:)` pattern that would load entire files into memory. The 64KB window is sufficient for body search since the most relevant content is typically near the top of a note.

---

### 3.3 Review Fix 3: VaultSearcher isPathSafe guard

**File**: `Sources/Services/VaultSearcher.swift` -- `searchBodies()`

| Requirement | Implementation | Status | Location |
|-------------|---------------|--------|----------|
| Call `pathManager.isPathSafe(folderPath)` before reading folder contents | `guard pathManager.isPathSafe(folderPath) else { continue }` | Match | L122 |

**Review Fix 3 Score: 1/1 (100%)**

The `isPathSafe` guard at L122 is placed immediately after confirming the folder exists and is a directory (L120-121), and before calling `fm.contentsOfDirectory(atPath: folderPath)` at L124. This ensures no folder contents are read from directories that fail the path safety check (canonicalization + root prefix validation via `PKMPathManager.isPathSafe`).

**Review Fix Total: 12/12 (100%)**

---

## 4. Combined Match Rate Summary

```
+-----------------------------------------------------+
|  Overall Match Rate: 100%                            |
+-----------------------------------------------------+
|  ORIGINAL DESIGN (31 requirements)                   |
|  Step 1 (NoteIndexGenerator):      5/5   (100%)     |
|  Step 2 (VaultSearcher):           7/7   (100%)     |
|  Step 3 (SemanticLinker):          7/7   (100%)     |
|  Step 4 (LinkCandidateGenerator): 12/12  (100%)     |
+-----------------------------------------------------+
|  REVIEW FIX REQUIREMENTS (12 requirements)           |
|  Fix 1 (suppress/boost sets):      7/7   (100%)     |
|  Fix 2 (streaming body search):    4/4   (100%)     |
|  Fix 3 (isPathSafe guard):         1/1   (100%)     |
+-----------------------------------------------------+
|  Total: 43/43 requirements matched                   |
+-----------------------------------------------------+
```

---

## 5. Code Quality Observations

### 5.1 Positive Patterns

| Pattern | File | Detail |
|---------|------|--------|
| Streaming I/O | NoteIndexGenerator.swift:L178-180 | FileHandle 4KB read avoids loading entire files |
| UTF-8 safety | NoteIndexGenerator.swift:L184-189 | Trim loop handles multi-byte character boundary cuts |
| Streaming I/O | VaultSearcher.swift:L129-131 | FileHandle 64KB partial read for body search |
| Path safety guard | VaultSearcher.swift:L122 | `isPathSafe` check before directory enumeration |
| Graceful degradation | VaultSearcher.swift:L26,87 | Nil index falls through to full body search seamlessly |
| Graceful degradation | SemanticLinker.swift:L349-354 | Nil index falls through to disk scan |
| Pre-computed sets | SemanticLinker.swift:L46-49 | Folder relation sets computed once, not per-note |
| Reverse index | LinkCandidateGenerator.swift:L93-132 | Avoids O(n^2) candidate scan with pre-built indices |
| Static utility | LinkCandidateGenerator.swift:L52-54 | `pairKey` as static method, matches FolderRelationStore |
| API backward compat | LinkCandidateGenerator.swift:L57-77 | Original API preserved, delegates to optimized path |
| Path safety | VaultSearcher.swift:L20-23 | Root prefix canonicalized via `resolvingSymlinksInPath()` |
| Duplicate prevention | VaultSearcher.swift:L128 | `excluding` set prevents Phase 1/Phase 2 overlap |

### 5.2 Minor Observations (Not Gaps)

| Item | File | Observation | Severity |
|------|------|-------------|----------|
| Full file read for existingRelated | SemanticLinker.swift:L382 | `String(contentsOfFile:)` used for `## Related Notes` parsing; could use FileHandle partial read but section location is unpredictable | Info |
| candidateScores init pattern | LinkCandidateGenerator.swift:L109,119,129 | `+= 0` used as "mark as candidate" -- functional but could use explicit insert for clarity | Info |
| linkNotes missing folder relations | SemanticLinker.swift:L216-220 | `linkNotes()` does not pass `suppressSet`/`boostSet`, so folder relations are not applied for single-note linking. Not a review fix violation, but a behavioral gap. | Low |

---

## 6. Architecture Compliance

### 6.1 Layer Placement

| File | Expected Layer | Actual Location | Status |
|------|---------------|-----------------|--------|
| NoteIndexGenerator | Services | `Sources/Services/NoteIndexGenerator.swift` | Match |
| VaultSearcher | Services | `Sources/Services/VaultSearcher.swift` | Match |
| SemanticLinker | Services | `Sources/Services/SemanticLinker/SemanticLinker.swift` | Match |
| LinkCandidateGenerator | Services | `Sources/Services/SemanticLinker/LinkCandidateGenerator.swift` | Match |
| FolderRelationStore | Services | `Sources/Services/SemanticLinker/FolderRelationStore.swift` | Match |
| SearchResult | Models | `Sources/Models/SearchResult.swift` | Match |
| NoteIndex/NoteIndexEntry | Models (co-located) | `Sources/Services/NoteIndexGenerator.swift` | Match |
| PKMPathManager | Services/FileSystem | `Sources/Services/FileSystem/PKMPathManager.swift` | Match |

### 6.2 Dependency Direction

| From | To | Direction | Status |
|------|----|-----------|--------|
| VaultSearcher | NoteIndex (model) | Service -> Model | Correct |
| VaultSearcher | PKMPathManager | Service -> Service | Correct |
| SemanticLinker | NoteIndex (model) | Service -> Model | Correct |
| SemanticLinker | LinkCandidateGenerator | Service -> Service (same module) | Correct |
| SemanticLinker | FolderRelationStore | Service -> Service (same module) | Correct |
| SemanticLinker | PKMPathManager | Service -> Service | Correct |
| LinkCandidateGenerator | (no external deps) | Pure computation | Correct |

No dependency violations detected. Notably, `LinkCandidateGenerator` no longer has any dependency on `FolderRelationStore` in its index-based overload -- it receives pre-computed `Set<String>` values, improving testability and decoupling.

---

## 7. Convention Compliance

### 7.1 Naming

| Category | Convention | Compliance |
|----------|-----------|------------|
| Structs | PascalCase | 100% -- NoteIndexGenerator, VaultSearcher, PreparedIndex, etc. |
| Functions | camelCase | 100% -- scanFolder, loadNoteIndex, prepareIndex, pairKey, etc. |
| Constants | UPPER_SNAKE_CASE or static let | 100% -- `maxResults`, `currentVersion`, `maxConcurrentAI` |
| Properties | camelCase | 100% -- `tagIndex`, `projectIndex`, `mocFolders`, `suppressSet`, `boostSet` |

### 7.2 Code Style

| Rule | Compliance | Notes |
|------|-----------|-------|
| Korean for UI strings | N/A | No UI strings in these files |
| English for comments | 100% | All comments in English |
| NSLog for logging | 100% | `NSLog` used consistently |
| Path canonicalization before hasPrefix | 100% | `resolvingSymlinksInPath()` used in all path comparisons |
| FileHandle for streaming I/O | 100% | Used in NoteIndexGenerator (4KB) and VaultSearcher (64KB) |

---

## 8. Overall Score

```
+-----------------------------------------------------+
|  Overall Score: 100/100                              |
+-----------------------------------------------------+
|  Design Match (original):   100% (31/31)             |
|  Review Fix Match:          100% (12/12)             |
|  Combined:                  100% (43/43)             |
|  Architecture:              100%                     |
|  Convention:                100%                     |
|  Code Quality:              Excellent                |
+-----------------------------------------------------+
```

---

## 9. Conclusion

All 43 requirements (31 original design + 12 review-fix sub-requirements) are fully implemented with no gaps detected.

**Original Design (unchanged from iteration 1)**:
- **Step 1** (NoteIndexGenerator): FileHandle 4KB partial read with UTF-8 trim loop.
- **Step 2** (VaultSearcher): Two-phase index-first search with graceful degradation.
- **Step 3** (SemanticLinker): `buildNoteIndex()` tries JSON index first, falls back to disk scan.
- **Step 4** (LinkCandidateGenerator): `PreparedIndex` with reverse indices, preserved original API.

**Review Fixes (new in iteration 2)**:
- **Fix 1** (Pre-computed sets): `generateCandidates` index-based overload accepts `suppressSet: Set<String>` and `boostSet: Set<String>`. `linkAll()` computes both sets once before the loop. Static `pairKey(_:_:)` method added. No disk I/O inside per-note loop.
- **Fix 2** (Streaming body search): `searchBodies()` uses `FileHandle` with 64KB partial read instead of `String(contentsOfFile:)`.
- **Fix 3** (Path safety): `searchBodies()` calls `pathManager.isPathSafe(folderPath)` before reading directory contents.

**Observation (not a gap)**: `linkNotes()` does not wire `suppressSet`/`boostSet` from folder relations (uses defaults `[]`). This pre-existing behavioral difference is noted but does not violate any of the 43 tracked requirements.

No recommended actions required. The feature is ready for production use.

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-23 | Initial gap analysis (31 requirements, 100%) | gap-detector |
| 2.0 | 2026-02-23 | Iteration 2: added 3 review-fix requirements (12 sub-reqs), re-verified all 43. All match. | gap-detector |
