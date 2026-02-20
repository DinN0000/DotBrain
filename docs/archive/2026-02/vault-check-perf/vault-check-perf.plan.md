# Plan: vault-check-perf

> 전체 점검(startVaultCheck) 성능 최적화

## 1. Problem Statement

전체 점검 기능이 100개 노트 기준 수 분 소요된다. AI 호출 120-194회가 누적되며, 동일 파일을 3-4회 반복 읽고, 변경 없는 파일도 매번 AI를 호출한다.

### 기준 환경: Claude Pro Plan

- Claude API: 500ms 간격, 250ms floor (~120 RPM)
- 120회 AI 호출 x 0.5초 = **60초** (RateLimiter 대기만)
- 동시 3개가 실제로 동시 발사되면: **~20초**

### Gemini 무료 티어 한계 (해결 대상 아님)

Gemini 무료는 15 RPM 제한 (4200ms 간격). 120회 x 4.2초 = 504초(8.4분). 이건 API rate limit 자체의 제약이므로 앱 레벨에서 해결할 수 없다. Gemini 무료 사용자는 느린 것이 정상이며, Claude Pro 또는 Gemini 유료 전환을 안내하는 것이 올바른 대응이다.

### Root Causes (Claude Pro 기준 재평가)

| # | 원인 | 위치 | Claude Pro 영향도 |
|---|------|------|-------------------|
| 1 | **ContentHashCache 미사용** — 변경 없는 파일도 매번 AI 호출 | AppState/MOCGenerator/SemanticLinker | **최대** — 호출 120회→5-10회 |
| 2 | **RateLimiter actor 직렬화** — max 3이 사실상 직렬 | `RateLimiter.swift:35-65` | **높음** — 60초→20초 가능 |
| 3 | **동일 파일 3-4회 중복 읽기** | VaultAuditor/NoteEnricher/SemanticLinker | 중간 — 수백ms~수초 |
| 4 | **NoteEnricher 폴더간 순차** | AppState.swift:259-267 | 중간 — Phase 2에 의존 |

## 2. Goals

- 전체 점검 소요 시간: **100노트 기준 30초 이내** (Claude Pro)
- 2회차 이후 실행 (변경 없음): **10초 이내**
- AI API 호출 횟수: 변경 파일 수에 비례 (변경 0 → 호출 ~0)
- 기존 동작(결과물)은 동일하게 유지
- 빌드 warning 0개 유지

## 3. Scope

### In Scope

- ContentHashCache를 전체 점검 파이프라인에 통합
- RateLimiter concurrent slot 방식으로 재설계
- VaultAuditor.allMarkdownFiles() 중복 호출 제거
- NoteEnricher 폴더간 병렬화

### Out of Scope

- UX/UI 개선 (진행률 바, 취소 지원) → `feature/vault-check-ux`
- SemanticLinker O(N^2) 알고리즘 변경 → 후속 작업
- Gemini 무료 티어 최적화 → 해결 불가, 유료 전환 안내로 대체
- 문서화 → `feature/vault-check-docs`

## 4. Implementation Plan

### Phase 1: ContentHashCache 통합 (최고 ROI)

**목표**: 변경되지 않은 파일에 대한 AI 호출 완전 제거

**대상 파일**:
- `Sources/Services/ContentHashCache.swift`
- `Sources/App/AppState.swift:213-305`
- `Sources/Services/NoteEnricher.swift`
- `Sources/Services/MOCGenerator.swift:251-306`
- `Sources/Services/SemanticLinker/SemanticLinker.swift`

**작업 내용**:
1. startVaultCheck() 시작 시 `cache.load()`, 종료 시 `cache.save()`
2. NoteEnricher.enrichNote()에서 `cache.checkFile() == .unchanged`이면 조기 반환
3. MOCGenerator.regenerateAll()에서 폴더 내 변경 파일 없으면 스킵
4. SemanticLinker.linkAll()에서 변경된 노트만 AI 필터링 대상
5. repair()/enrichNote()가 파일 수정 시 즉시 해시 갱신 (`cache.updateHash()`)

**사이드이펙트 대응**:
- ContentHashCache가 actor라서 `checkFile()` 호출이 직렬화됨 → 배치 메서드 `checkFiles(_ paths: [String]) -> [String: FileStatus]` 추가하여 한 번의 actor 진입으로 처리
- repair() 후 수정된 파일의 해시 미갱신 위험 → repair 결과에서 수정된 파일 목록 추출, 즉시 updateHash 호출
- 첫 실행 시 이점 없음 → 수용 (2회차부터 효과)

**기대 효과**: 2회차 이후 AI 호출 120회 → 5-10회

### Phase 2: RateLimiter concurrent slot

**목표**: max 3 concurrent가 실제로 동시 발사되도록

**대상 파일**:
- `Sources/Services/RateLimiter.swift`

**작업 내용**:
1. 단일 `lastRequestTime` → N개 slot의 `nextAvailableTime` 배열로 변경
2. `acquire()`가 가장 빠른 slot을 선택, 해당 slot의 다음 시간을 예약
3. slot 수를 provider 기본값으로 설정: Claude 3, Gemini 1
4. 429 발생 시 전체 slot에 backoff 전파
5. backoff 회복: 5%/3성공 → 15%/2성공으로 개선

**사이드이펙트 대응**:
- `RateLimiter.shared` 싱글턴이라 전체 앱에 영향 → Claude는 120 RPM 여유 있어서 slot 3도 안전. Gemini는 slot 1 유지 (기존 동작 보존)
- 429 시 slot 간 연쇄 호출 방지 → 429 감지하면 모든 slot의 nextAvailableTime을 backoff 시점으로 갱신
- consecutiveSuccesses/Failures 집계 → provider 단위 유지 (slot 단위 아님)

**기대 효과**: Claude Pro 기준 AI 대기 시간 1/3 단축

### Phase 3: VaultAuditor 중복 호출 제거

**목표**: `allMarkdownFiles()` 2회 → 1회

**대상 파일**:
- `Sources/Services/VaultAuditor.swift:41-43, 337-345`

**작업 내용**:
1. `audit()` 내에서 `allMarkdownFiles()` 결과를 `allNoteNames()` 계산에 재사용
2. `allNoteNames()` 메서드를 `noteNames(from files: [String]) -> Set<String>`으로 변경

**사이드이펙트**: 없음 (private 메서드 시그니처만 변경)

**기대 효과**: 파일시스템 전체 순회 1회 감소

### Phase 4: NoteEnricher 폴더간 병렬화

**목표**: 폴더별 순차 → 전체 파일을 단일 TaskGroup(max 3)으로

**대상 파일**:
- `Sources/App/AppState.swift:259-267`

**작업 내용**:
1. 3개 카테고리 x N개 폴더의 모든 .md 파일을 flat list로 수집
2. Phase 1의 ContentHashCache로 변경된 파일만 필터
3. 단일 TaskGroup(max 3)으로 enrichNote() 병렬 실행
4. enrichFolder() 내부 TaskGroup 제거 (상위에서 관리)

**사이드이펙트 대응**:
- CLAUDE.md의 `max 3` 규칙 준수 확인 → 단일 TaskGroup이므로 정확히 3개 유지
- Phase 2(RateLimiter) 없이는 효과 미미 → Phase 2 완료 후 적용

**기대 효과**: 폴더 수에 무관하게 동시 3개 AI 호출 유지

## 5. Implementation Order

```
Phase 1 (ContentHashCache) ── 최우선, 독립 ──>
Phase 3 (VaultAuditor 중복 제거) ── 독립, 간단 ──>
Phase 2 (RateLimiter slot) ── Phase 1과 병렬 가능 ──>
Phase 4 (NoteEnricher 병렬화) ── Phase 2 완료 후 ──>
```

Phase 1과 3은 독립적이며 즉시 착수 가능.
Phase 2는 Phase 1과 병렬 진행 가능하나 변경 범위가 넓으므로 별도 진행.
Phase 4는 Phase 2의 RateLimiter slot이 동작해야 의미 있음.

## 6. Risks & Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| ContentHashCache actor 직렬화가 새 병목 | 중 | 배치 API 추가 (`checkFiles`) |
| repair() 후 해시 미갱신 → 다음 Phase 오탐 | 높음 | repair 결과에서 수정 파일 추출, 즉시 갱신 |
| RateLimiter slot 변경 → 다른 기능 영향 | 중 | Claude slot=3, Gemini slot=1 (기존 유지) |
| Phase간 데이터 공유 시 메모리 증가 | 낮음 | Phase 3에서 frontmatter만 캐시 (body 제외) |
| SemanticLinker incremental의 역방향 링크 누락 | 높음 | 변경된 노트 + 해당 노트의 기존 Related Notes 대상도 재처리 |

## 7. Not Solving (의도적 제외)

| 항목 | 이유 |
|------|------|
| Gemini 무료 속도 | API rate limit 자체 제약. 앱에서 해결 불가. |
| SemanticLinker O(N^2) | 알고리즘 변경 필요 (tag index 등). 이 PR 범위 초과. |
| VaultScanResult 전체 공유 구조 | repair() 후 스냅샷 불일치 문제가 복잡. Phase 3은 VaultAuditor 내부 최적화만. |

## 8. Success Metrics (Claude Pro 기준)

- [ ] 100노트 전체 점검 초회: 30초 이내
- [ ] 100노트 전체 점검 2회차 (변경 0): 10초 이내
- [ ] AI 호출 수: 변경 파일 수에 비례
- [ ] 빌드 warning 0개
- [ ] 기존 전체 점검 결과물과 동일한 출력
