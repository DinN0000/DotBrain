# Plan: Code Quality Review Fixes (v2 — Intent-Based)

> 11-agent parallel code review 후 의도 기반 재검토. 36건 -> 15건으로 축소.

## Overview

- **Feature**: code-quality-review-fixes
- **Created**: 2026-02-19
- **Status**: Completed (2026-02-22)
- **Scope**: 15건 실제 버그/개선 (12건 false positive + 9건 수용 가능 제거)

## Background

v2.1.0 릴리즈 후 11개 에이전트 병렬 코드 리뷰 수행.
에이전트가 "모범 사례" 기준으로 판정한 항목 중 의도적 설계를 재분류.

### False Positive 제거 근거

| 제거된 이슈 | 판정 근거 |
|------------|----------|
| MOC 전체 덮어쓰기 | MOC는 auto-generated 인덱스 — 매번 재생성이 설계 의도 |
| AppState `Task { @MainActor }` | `AppState`가 `@MainActor`, `process()`는 async — await 시 자연히 off-main |
| `isProcessing` 취소 리셋 | `cancelProcessing()`에서 직접 `isProcessing = false` 세팅 |
| `moveTextFile` 전체 로드 | frontmatter inject/strip에 전체 콘텐츠 필요 — streaming 불가 |
| `extractContext` 전체 로드 | md 노트 크기 실질적으로 작음 + frontmatter strip 필요 |
| `VaultAuditor` 전체 로드 | frontmatter + body wiki-link 스캔 한 패스 처리 |
| `fileBodyHash` md 전체 로드 | frontmatter strip 후 body 해싱 — 전체 로드 필수 |
| `StatisticsService` read 레이스 | UserDefaults는 Apple 문서상 thread-safe for reads |
| Frontmatter 이중 초기화 | 빈 array flush는 no-op — 실제 동작 정상 |
| 인라인 배열 쉼표 파싱 | DotBrain 태그는 쉼표 없는 단어/구. round-trip 정상 |
| `AssetMigrator` isPathSafe | PARA 폴더 내부에서만 실행 — symlink 시나리오 극히 드묾 |
| `KeychainService` HKDF salt | UUID 128bit 고엔트로피 — salt 재사용 시 실질적 차이 미미 |

## Implementation Phases

### Phase 1: Data Safety (P0) — 3건

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 1 | `OnboardingView.swift` | 866 | `removeItem` 영구삭제 | `trashItem` 변경 |
| 2 | `AICompanionService.swift` | 121 | end-marker 검색 미제한 | start-marker 이후로 검색 범위 제한 |
| 3 | `PARAMover.swift` | 123 | 에셋 이동 `try?` 실패 후 디렉터리 삭제 | 에러 핸들링 + 이동 실패 시 삭제 방지 |

### Phase 2: Logic Bugs (P1) — 6건

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 4 | `RateLimiter.swift` | 40 | `backoffUntil` sleep 후 미초기화 | sleep 후 `ps.backoffUntil = nil` |
| 5 | `Classifier.swift` | 142 | Stage2 parse 실패 -> confidence 0.9 | `?? 0.0`으로 변경 |
| 6 | `AIService.swift` | 127 | fallback empty catch | NSLog 에러 로깅 추가 |
| 7 | `ProjectManager.swift` | 18 | `isPathSafe` 오용 — `.alreadyExists` 에러 | 올바른 에러 타입으로 변경 |
| 8 | `FolderReorganizer.swift` | 259 | `failed: 0` 하드코딩 | 실제 실패 카운트 전달 |
| 9 | `VaultReorganizer.swift` | 262 | source folder MOC 미갱신 | source 폴더 경로도 `affectedFolders`에 포함 |

### Phase 3: Security (P1) — 2건

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 10 | `PPTXExtractor.swift` | 91 | ZIP 압축 해제 크기 무제한 | `readEntry`에 maxBytes 제한 |
| 11 | `KeychainService.swift` | 174 | `migrationDone` TOCTOU race | NSLock 보호 |

### Phase 4: Convention (P2) — 4건

| # | File | Line | Issue | Fix |
|---|------|------|-------|-----|
| 12 | `ProjectContextBuilder.swift` | 81 | 이모지 리터럴 | 이모지 제거 |
| 13 | `OnboardingView.swift` | 201+ | 이모지 리터럴 | SF Symbols 변환 |
| 14 | `ContextLinker.swift` | 46 | `completedBatches` 이중 카운트 | drain loop에서만 카운트 |
| 15 | `FolderReorganizer.swift` | 295 | `flattenFolder` `_Assets/` 미스킵 | `_Assets` 디렉터리 `skipDescendants()` |

## Constraints

- Zero warnings policy 유지
- 기존 기능 동작 변경 없음 (방어적 수정만)
- `swift build` 통과 필수
- 각 Phase 완료 후 빌드 확인

## Success Criteria

- 15건 전수 수정
- `swift build -c release` 경고 0
- 기존 파이프라인 동작 유지

## Risk

- `AICompanionService` marker 검색 변경 시 기존 파일 호환성
- `RateLimiter` 동작 변경 시 API 호출 타이밍 영향
- `flattenFolder` _Assets 스킵 시 기존 reorganization 동작 변경

## Estimated Scope

- Phase 1: 3 파일
- Phase 2: 5 파일
- Phase 3: 2 파일
- Phase 4: 4 파일
- Total: ~12 파일
