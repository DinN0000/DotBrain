# dotbrain-fixes Gap Analysis

> **Summary**: Design 문서 (v0.2 Act 반영) 대비 구현 갭 분석 결과
>
> **Author**: Claude
> **Created**: 2026-02-15
> **Last Modified**: 2026-02-15
> **Status**: Approved
> **Match Rate**: 100% (11 MATCH / 0 PARTIAL / 0 DEVIATION / 0 MISSING)

---

## Analysis Overview

- **Analysis Target**: dotbrain-fixes (Critical/High 버그 수정 + 리팩토링)
- **Design Document**: `docs/02-design/features/dotbrain-fixes.design.md` (v0.2)
- **Implementation Path**: `Sources/`
- **Analysis Date**: 2026-02-15
- **Previous Analysis**: v1.0 (Match Rate 71%) -- pre-Act Design update

## Overall Scores

| Category | Score | Status |
|----------|:-----:|:------:|
| Design Match | 100% | PASS |
| Architecture Compliance | 100% | PASS |
| Convention Compliance | 100% | PASS |
| **Overall** | **100%** | **PASS** |

## Design Scope (v0.2)

The updated Design document defines **11 in-scope items** across 4 phases.
3 items (RF-02, RF-03, Phase 4a) were moved to "Future Work" and are **excluded from scoring**.

| Phase | In-Scope Items |
|-------|---------------|
| Phase 1: Critical (3) | CR-01, CR-03, CR-04 |
| Phase 2: High (5) | HI-01, HI-02, HI-03, HI-04, HI-05 |
| Phase 3: Refactoring (2) | RF-01, RF-06 |
| Phase 4: Docs (1) | AICompanionService version + install.sh checksum |
| Future Work (excluded) | RF-02, RF-03, Phase 4a |

---

## Detailed Results

### MATCH (11/11) -- All Items Pass

#### Phase 1: Critical

| ID | Item | Design Spec | Implementation | Verdict |
|----|------|-------------|----------------|---------|
| CR-01 | RateLimiter pow() clamping | `let capped = min(ps.consecutiveFailures, 6)` before pow() | `Sources/Services/RateLimiter.swift` line 89: `let capped = min(ps.consecutiveFailures, 6)` | MATCH |
| CR-03 | FileMover >500MB metadata dedup | `findDuplicateByMetadata(fileSize:filePath:in:)` using size + modificationDate | `Sources/Services/FileSystem/FileMover.swift` lines 204-215: hash for <=500MB, `findDuplicateByMetadata` for >500MB comparing size + date | MATCH |
| CR-04 | Gemini API key header auth | Remove `?key=` from URL, use `x-goog-api-key` header | `Sources/Services/Gemini/GeminiAPIClient.swift` lines 85-107: URL has no `?key=`, header set via `setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")` | MATCH |

#### Phase 2: High

| ID | Item | Design Spec | Implementation | Verdict |
|----|------|-------------|----------------|---------|
| HI-01 | KeychainService HKDF + V1 migration | HKDF<SHA256>.deriveKey() for V2, SHA256 for V1 legacy, auto-migration on load | `Sources/Services/KeychainService.swift` lines 62-74: HKDF V2 key; lines 77-82: V1 legacy key; lines 84-105: loadStore() tries V2 then V1 with auto-migration | MATCH |
| HI-02 | install.sh checksum verification | Download `checksums.txt`, compare SHA256, fail on mismatch | `install.sh` lines 46-58: downloads checksums.txt, compares `shasum -a 256`, exits on mismatch | MATCH |
| HI-03 | FolderReorganizer try? to do-catch | Replace `try?` with `do-catch` + error logging for moveItem and removeItem | `Sources/Pipeline/FolderReorganizer.swift` lines 278-321: all file moves and removals use `do-catch` with `print("[FolderReorganizer]...")` error messages | MATCH |
| HI-04 | InboxWatchdog debounce cleanup | `debounceWorkItem = nil` in stop(), `setCancelHandler { close(fd) }` | `Sources/Services/FileSystem/InboxWatchdog.swift` line 65: `debounceWorkItem = nil`; lines 52-54: `setCancelHandler { close(fd) }` | MATCH |
| HI-05 | StatisticsService thread safety (DispatchQueue) | `private static let serialQueue = DispatchQueue(...)`, wrap read-modify-write in `serialQueue.sync` | `Sources/Services/StatisticsService.swift` line 8: `private static let serialQueue = DispatchQueue(label: "com.hwaa.dotbrain.statistics")`; lines 43-57, 60-65, 68-73: `serialQueue.sync { ... }` wrapping | MATCH |

#### Phase 3: Refactoring

| ID | Item | Design Spec | Implementation | Verdict |
|----|------|-------------|----------------|---------|
| RF-01 | FileContentExtractor common extractor | New `FileContentExtractor` struct/enum with `extract(from:maxLength:)`, callers updated | `Sources/Services/Extraction/FileContentExtractor.swift`: enum with `static func extract(from:maxLength:)`; Callers: `InboxProcessor.swift:279`, `FolderReorganizer.swift:490`, `VaultReorganizer.swift:262` all use `FileContentExtractor.extract(from:)` | MATCH |
| RF-06 | PARACategory.fromPath() | `PARACategory` extension with `static func fromPath(_ path:) -> PARACategory?` checking path segments | `Sources/Models/PARACategory.swift` lines 49-55: exact implementation with `/1_Project/`, `/2_Area/`, `/3_Resource/`, `/4_Archive/` checks; Callers: `VaultAuditor.swift:286`, `MOCGenerator.swift:249`; No remaining inline contains patterns | MATCH |

#### Phase 4: Documentation

| ID | Item | Design Spec | Implementation | Verdict |
|----|------|-------------|----------------|---------|
| Phase 4 | AICompanionService version bump + install.sh checksum | version +1 (implicit: 9 -> 10); install.sh checksum covered in HI-02 | `Sources/Services/AICompanionService.swift` line 9: `static let version = 10`; install.sh checksum: verified above | MATCH |

---

## Future Work Items (Excluded from Scoring)

The following items are explicitly listed in Design v0.2 Section 6 "Future Work" and are NOT counted as gaps:

| ID | Item | Reason for Deferral |
|----|------|-------------------|
| RF-02 | AIResponseParser common extraction | Claude/Gemini client-wide changes needed, separate PR |
| RF-03 | AIAPIError unified error type | Provider error mapping scope large, independent refactoring |
| Phase 4a | architecture.design.md update | Documentation-only, no code changes |

---

## Act Phase Changes Verified

The following Design v0.2 updates (from Act phase) are confirmed synchronized with implementation:

| Change | Design v0.2 Text | Implementation Status |
|--------|-------------------|----------------------|
| HI-05: DispatchQueue (not actor) | Section 3.5: "actor 대신 DispatchQueue 사용" | StatisticsService uses `DispatchQueue` -- ALIGNED |
| RF-06: PARACategory.fromPath() (not PKMPathManager) | Section 4.2: "PARACategory에 경로 기반 카테고리 감지 메서드 추가" | PARACategory.swift has `fromPath()` -- ALIGNED |
| RF-02, RF-03: Future Work | Section 6: explicitly listed as out-of-scope | Not implemented -- CORRECT |
| Phase 4a: Removed from scope | Section 6: explicitly listed as out-of-scope | Not implemented -- CORRECT |

---

## Match Rate Calculation

```
In-scope items:  11
Matched:         11
Partial:          0
Deviation:        0
Missing:          0

Match Rate = 11/11 = 100%
```

**Previous (pre-Act)**: 71% (9/14 match, 1 partial, 1 deviation, 3 missing)
**Current (post-Act)**: 100% (11/11 match, 3 items moved to Future Work)

The Act phase achieved alignment by updating the Design document to reflect:
1. Intentional implementation decisions (HI-05 DispatchQueue, RF-06 PARACategory placement)
2. Scope adjustments (RF-02, RF-03, Phase 4a deferred to Future Work)

---

## Recommendation

Match Rate >= 90%. Design and implementation are fully aligned.
Proceed to `/pdca report dotbrain-fixes` for completion report.

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 1.0 | 2026-02-15 | Initial gap analysis (71% match rate) | Claude |
| 2.0 | 2026-02-15 | Re-analysis against updated Design v0.2 (100% match rate) | Claude |
