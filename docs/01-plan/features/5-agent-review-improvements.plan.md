# Plan: 5-Agent Review Improvements

> 5-Opus-Agent 병렬 리뷰 (Architecture, Security, Code Quality, Performance, Documentation) 결과 기반 개선 계획.
> 기존 기능 안정성을 최우선으로, 각 항목별 장단점 분석 포함.

## Overview

- **Feature**: 5-agent-review-improvements
- **Created**: 2026-02-21
- **Status**: Phase 1 Completed (2026-02-22), Phase 2 partial KEEP, Phase 3 CLOSED
- **Prior**: `code-quality-review-fixes.plan.md` (2026-02-19, 15건) 과 일부 중복 — 중복 항목 표시

## Scope Decision

5개 리뷰에서 총 ~40건 발견. 아래 기준으로 3단계 분류:

| 분류 | 기준 | 건수 |
|------|------|------|
| **Phase 1: Safe Fixes** | 기존 동작 변경 없음, 방어적 수정만 | 12건 |
| **Phase 2: Careful Fixes** | 동작 변경 있으나 제한적, 테스트 가능 | 8건 |
| **Phase 3: Architectural** | 구조 변경, 높은 리스크 — 별도 feature branch 권장 | 5건 |
| **Deferred** | 현재 스케일에서 불필요하거나 ROI 낮음 | ~15건 |

---

## Phase 1: Safe Fixes (기존 동작 무변경)

### 1-1. ContentHashCache.save() 인박스 처리 후 미호출

| 항목 | 내용 |
|------|------|
| 소스 | Code Quality C2 |
| 파일 | `InboxProcessor.swift:280-286` |
| 장점 | 다음 볼트체크에서 이미 처리된 파일 재처리 방지, I/O 절약 |
| 단점 | 없음 (save는 이미 다른 경로에서 호출됨, 패턴 동일) |
| 리스크 | **없음** — 캐시 저장 추가일 뿐, 실패해도 기존 동작 유지 |

### 1-2. FolderReorganizer ContentHashCache 미갱신

| 항목 | 내용 |
|------|------|
| 소스 | Code Quality C3 |
| 파일 | `FolderReorganizer.swift` |
| 장점 | 폴더 재정리 후 볼트체크에서 불필요한 재처리 방지 |
| 단점 | FolderReorganizer에 ContentHashCache 의존성 추가 |
| 리스크 | **없음** — 추가 동작, 기존 흐름 변경 없음 |

### 1-3. LinkAIFilter.generateContextOnly 토큰 미추적

| 항목 | 내용 |
|------|------|
| 소스 | Code Quality C1 |
| 파일 | `LinkAIFilter.swift:150` |
| 장점 | API 비용 추적 정확도 향상, api-usage.json 완전성 |
| 단점 | 없음 |
| 리스크 | **없음** — sendFast -> sendFastWithUsage 변경 + logTokenUsage 추가 |

### 1-4. Frontmatter projects 더블이스케이프

| 항목 | 내용 |
|------|------|
| 소스 | Security M3 |
| 파일 | `Frontmatter.swift:253-255` |
| 장점 | projects 필드 YAML 정상 출력, 파싱 호환성 개선 |
| 단점 | 기존에 이미 저장된 더블이스케이프 데이터는 수동 수정 필요할 수 있음 |
| 리스크 | **낮음** — projects 필드 사용 빈도 낮음, 새로 쓰는 파일부터 적용 |

### 1-5. FolderReorganizer 위키링크 미살균

| 항목 | 내용 |
|------|------|
| 소스 | Security M2 |
| 파일 | `FolderReorganizer.swift:536-546` |
| 장점 | AI 응답에 `]]` 등 포함 시 마크다운 깨짐 방지 |
| 단점 | 없음 (FrontmatterWriter.sanitizeWikilink 이미 존재, 호출만 추가) |
| 리스크 | **없음** — 입력 살균 추가일 뿐 |

### 1-6. Task.sleep(nanoseconds:) deprecated API 5곳

| 항목 | 내용 |
|------|------|
| 소스 | Code Quality I3 |
| 파일 | `AppState.swift:976`, `SettingsView.swift:479,651`, `PARAManageView.swift:78,624` |
| 장점 | deprecation 경고 제거, 코드 일관성 |
| 단점 | 없음 |
| 리스크 | **없음** — `Task.sleep(for: .seconds(N))` 으로 1:1 교체 |

### 1-7. DispatchQueue.main.asyncAfter 2곳

| 항목 | 내용 |
|------|------|
| 소스 | Code Quality I2 |
| 파일 | `InboxStatusView.swift:422`, `SettingsView.swift:542` |
| 장점 | CLAUDE.md 컨벤션 준수, GCD 의존 제거 |
| 단점 | 없음 |
| 리스크 | **없음** — `Task { @MainActor in try? await Task.sleep(for:) }` 패턴 |

### 1-8. Classifier.stripParaPrefix() regex 매 호출 컴파일

| 항목 | 내용 |
|------|------|
| 소스 | Performance R8 |
| 파일 | `Classifier.swift:540,546` |
| 장점 | 파일당 2회 regex 컴파일 제거 |
| 단점 | 없음 |
| 리스크 | **없음** — static 프로퍼티로 이동 |

### 1-9. NoteIndexGenerator isPathSafe 누락

| 항목 | 내용 |
|------|------|
| 소스 | Security L1 |
| 파일 | `NoteIndexGenerator.swift:109-115` |
| 장점 | 다른 서비스와 일관된 경로 안전 검증 |
| 단점 | 없음 |
| 리스크 | **없음** — guard 추가, continue로 건너뛰기 |

### 1-10. VaultAuditor isPathSafe 누락

| 항목 | 내용 |
|------|------|
| 소스 | Security L3 |
| 파일 | `VaultAuditor.swift:296-333` |
| 장점 | symlink 기반 볼트 외부 파일 접근 방지 |
| 단점 | 없음 |
| 리스크 | **없음** — guard 추가 |

### 1-11. Classifier classifyBatchStage1 실패 시 무로그

| 항목 | 내용 |
|------|------|
| 소스 | Code Quality I6 |
| 파일 | `Classifier.swift:220-230` |
| 장점 | AI 응답 파싱 실패 원인 진단 가능 |
| 단점 | 없음 |
| 리스크 | **없음** — NSLog 추가 |

### 1-12. TagNormalizer 파일 이중 읽기

| 항목 | 내용 |
|------|------|
| 소스 | Performance R9 |
| 파일 | `TagNormalizer.swift:58,76` |
| 장점 | 프로젝트 필드 있는 파일마다 1회 I/O 절약 |
| 단점 | addTagIfMissing 시그니처 변경 |
| 리스크 | **낮음** — 내부 private 메서드, 외부 API 변경 없음 |

---

## Phase 2: Careful Fixes (동작 변경 있으나 제한적)

> **Triage (2026-02-22)**: KEEP 4건 (2-1, 2-2, 2-3, 2-5), CLOSE 4건 (2-4, 2-6, 2-7, 2-8)

### 2-1. VaultSearcher에서 note-index.json 활용 — KEEP

| 항목 | 내용 |
|------|------|
| 소스 | Performance R1 (HIGH) |
| 파일 | `VaultSearcher.swift` |
| 장점 | 검색 성능 대폭 개선 (1K 노트: 2GB -> ~수MB), UI 프리징 해소 |
| 단점 | bodyMatch 시 여전히 파일 읽기 필요, 인덱스 stale 가능성 |
| 리스크 | **중간** — 검색 결과가 달라질 수 있음 (인덱스에 없는 필드 검색 불가). 기존 검색과 A/B 비교 필요 |

### 2-2. SemanticLinker.buildNoteIndex()에서 note-index.json 활용 — KEEP

| 항목 | 내용 |
|------|------|
| 소스 | Performance R2 (HIGH) |
| 파일 | `SemanticLinker.swift:311-358` |
| 장점 | 메모리 스파이크 제거 (1K 노트: ~2GB -> ~수MB) |
| 단점 | existingRelated 정보가 인덱스에 없어 별도 파싱 필요 |
| 리스크 | **중간** — 링크 품질이 인덱스 정확도에 의존. 인덱스 갱신 타이밍 중요 |

### 2-3. LinkCandidateGenerator O(N^2) 개선 — KEEP

| 항목 | 내용 |
|------|------|
| 소스 | Performance R3 (HIGH) |
| 파일 | `LinkCandidateGenerator.swift` |
| 장점 | 1K+ 노트에서 semantic linking 실행 가능 |
| 단점 | 태그 역인덱스 구축 시 메모리 추가 사용, 후보 cap으로 연결 누락 가능 |
| 리스크 | **중간** — 기존에 연결되던 노트가 cap에 의해 누락될 수 있음. cap을 넉넉히 (30+) 설정 |

### 2-4. ContentHashCache 스트리밍 해시 — CLOSED (hash 방식 변경 시 캐시 전면 무효화, ROI 낮음)

| 항목 | 내용 |
|------|------|
| 소스 | Performance R4 |
| 파일 | `ContentHashCache.swift:89,144` |
| 장점 | 볼트체크 시 메모리 사용 감소 |
| 단점 | frontmatter strip 후 body만 해싱하던 기존 로직 변경 필요 — 전체 파일 해시로 변경 시 기존 캐시 무효화 |
| 리스크 | **중간** — 해시 방식 변경 시 첫 볼트체크에서 모든 파일이 "changed"로 감지됨. 마이그레이션 전략 필요 |

### 2-5. NoteIndexGenerator frontmatter-only 읽기 — KEEP

| 항목 | 내용 |
|------|------|
| 소스 | Performance R5 |
| 파일 | `NoteIndexGenerator.swift:169` |
| 장점 | 인덱스 빌드 I/O 대폭 감소 (전체 -> 4KB) |
| 단점 | 4KB 내에 frontmatter가 잘리는 경우 파싱 실패 가능 (극히 드묾) |
| 리스크 | **낮음** — FolderHealthAnalyzer에서 이미 동일 패턴 사용 중. fallback으로 전체 읽기 추가 |

### 2-6. SettingsView /tmp/ 스크립트 보안 강화 — CLOSED (로컬 전용 앱, 실질 위협 없음)

| 항목 | 내용 |
|------|------|
| 소스 | Security M1 |
| 파일 | `SettingsView.swift:456-485` |
| 장점 | 예측 가능한 temp 파일 경로 제거, TOCTOU 방지 |
| 단점 | 없음 |
| 리스크 | **낮음** — `mkstemp` 또는 고유 파일명 + 0o700 퍼미션 |

### 2-7. 볼트체크 다중 패스 통합 — CLOSED (높은 리스크, 기존 동작 변경 과다)

| 항목 | 내용 |
|------|------|
| 소스 | Performance R6 |
| 파일 | `AppState.swift startVaultCheck()` |
| 장점 | 볼트체크 I/O ~50% 감소, 전체 시간 단축 |
| 단점 | 단일 패스로 통합 시 코드 복잡도 증가, audit + hash + enrich 결합 |
| 리스크 | **높음** — 기존 볼트체크 동작 변경. 실패 모드가 달라짐. 충분한 수동 테스트 필요 |

### 2-8. ProjectContextBuilder 결과 캐싱 — CLOSED (캐시 무효화 복잡성, stale context 오분류 위험)

| 항목 | 내용 |
|------|------|
| 소스 | Performance R7 |
| 파일 | `ProjectContextBuilder.swift` |
| 장점 | 인박스 처리마다 수백 회 파일 읽기 제거 |
| 단점 | 캐시 무효화 타이밍 관리 필요, stale context로 분류 품질 저하 가능 |
| 리스크 | **중간** — 볼트 구조 변경 후 캐시 미갱신 시 오분류 가능. TTL 또는 변경 감지 필요 |

---

## Phase 3: Architectural — CLOSED (전체)

> **Triage (2026-02-22)**: 전체 CLOSE. 3-1은 이미 VaultCheckPipeline.swift로 분리 완료. 3-2~3-5는 현재 스케일에서 ROI 낮음.

### 3-1. VaultCheck 파이프라인을 AppState에서 분리 — CLOSED (이미 구현됨)

| 항목 | 내용 |
|------|------|
| 소스 | Architecture ISSUE 1 |
| 파일 | `AppState.swift:222-397` -> 새 `Pipeline/VaultCheckPipeline.swift` |
| 장점 | AppState 982줄 -> ~600줄, 테스트 가능, 책임 분리 |
| 단점 | AppState와 새 파이프라인 간 상태 동기화 복잡성 |
| 리스크 | **높음** — 가장 핵심적인 백그라운드 로직 이동. UI 상태 업데이트 타이밍 변경 가능 |

### 3-2. UI 뷰에서 서비스 직접 참조 제거 — CLOSED (높은 리스크, ROI 낮음)

| 항목 | 내용 |
|------|------|
| 소스 | Architecture ISSUE 2 |
| 파일 | `VaultInspectorView.swift`, `PARAManageView.swift` (~250줄 비즈니스 로직) |
| 장점 | 비즈니스 로직 테스트 가능, 레이어 분리, 코드 가독성 |
| 단점 | 서비스 파사드 또는 AppState 메서드 추가 필요, 중간 레이어 복잡성 |
| 리스크 | **높음** — UI 동작 변경 가능, 전체 UX 흐름 수동 테스트 필수 |

### 3-3. 파이프라인 코드 중복 제거 — CLOSED (각 파이프라인 특수 케이스 많음, 추상화 과도)

| 항목 | 내용 |
|------|------|
| 소스 | Architecture ISSUE 4 |
| 파일 | `InboxProcessor.swift`, `FolderReorganizer.swift`, `VaultReorganizer.swift` (~90줄 중복) |
| 장점 | 단일 수정 지점, 일관된 동작 보장 |
| 단점 | 공유 유틸리티 추출 시 각 파이프라인 특수 케이스 처리 복잡 |
| 리스크 | **중간** — 3개 파이프라인 모두 영향. 개별 빌드 테스트 필요 |

### 3-4. PARACategory에서 SwiftUI 분리 — CLOSED (현재 스케일에서 불필요)

| 항목 | 내용 |
|------|------|
| 소스 | Architecture ISSUE 5 |
| 파일 | `PARACategory.swift` -> `PARACategory+UI.swift` |
| 장점 | Models 레이어의 프레임워크 독립성 |
| 단점 | 기존 PARACategory.color 참조 모두 수정 필요 |
| 리스크 | **낮음** — 컴파일 타임에 모든 오류 감지 가능. 단, 참조 지점이 많을 수 있음 |

### 3-5. Protocol 추상화 / DI 도입 — CLOSED (단일 개발자 앱, ROI 매우 낮음)

| 항목 | 내용 |
|------|------|
| 소스 | Architecture ISSUE 3 |
| 파일 | 전체 서비스 |
| 장점 | 유닛 테스트 가능, 서비스 교체 용이 |
| 단점 | 전체 서비스에 프로토콜 정의 + 주입 패턴 추가 — 대규모 리팩토링 |
| 리스크 | **매우 높음** — 현재 단일 개발자 앱에서 ROI 낮음. 테스트 코드 없이는 의미 제한적 |

---

## Deferred (현재 불필요 / ROI 낮음)

| 이슈 | 근거 |
|------|------|
| note-index.json compact JSON (R10) | 현재 스케일에서 영향 미미 |
| VaultSearcher async 전환 (R11) | 2-1과 함께 처리 시 자연스럽게 해결 |
| FileMover.BodyHashCache actor 전환 (I5) | 현재 순차 사용, 문서화로 충분 |
| AssetMigrator isPathSafe (L2) | PARA 내부 전용, 리스크 극히 낮음 |
| KeychainService 랜덤 salt (L6) | 하드웨어 UUID 128bit로 충분 |
| NSLog 민감 데이터 (L5) | 에러 응답 200자만 로깅, 실질 위험 낮음 |
| ContentHashCache/APIUsageLogger 파일 퍼미션 (M5) | 민감 데이터 아님, 644 적절 |
| ContextLinker 참조 (I14 기존 plan) | **이미 삭제됨** — 코드에서 ContextLinker 자체가 없음 |

---

## Implementation Strategy

```
Phase 1 (Safe) ─── 빌드 확인 ─── Phase 2 (Careful) ─── 빌드+수동테스트 ─── Phase 3 (Architectural)
   12건              0 risk          8건                  중간 risk           feature branch
   ~2시간                             ~반나절                                   별도 계획
```

### Phase 1 원칙
- 한 파일씩 수정 -> `swift build` 확인
- 기존 동작 변경 없는 순수 추가/교체만
- 실패해도 기존 동작에 영향 없는 방어적 수정

### Phase 2 원칙
- 수정 전/후 동작 비교 가능한 항목부터
- VaultSearcher(2-1)는 기존 메서드 유지 + 새 메서드 추가 후 전환하는 방식
- 해시 캐시(2-4) 변경 시 마이그레이션 전략 필수

### Phase 3 원칙
- feature branch에서 작업
- 항목당 독립 PR
- 수동 UX 테스트 체크리스트 작성 후 진행

## Constraints

- Zero warnings policy 유지
- `swift build -c release` 통과 필수
- 기존 사용자 볼트 데이터 호환 (프론트매터, 인덱스, 해시 캐시)
- 기존 `code-quality-review-fixes` 계획과 중복 항목은 해당 계획 우선

## Success Criteria

- Phase 1: 12건 수정, 빌드 통과
- Phase 2: 8건 수정, 빌드 통과 + 인박스 처리/볼트체크/검색 수동 확인
- Phase 3: 개별 PR 단위로 빌드+테스트 통과

## Risk Summary

| Phase | 건수 | 리스크 | 기존 기능 영향 |
|-------|------|--------|--------------|
| Phase 1 | 12 | 없음~낮음 | 없음 |
| Phase 2 | 8 | 낮음~높음 | 검색 결과, 해시 캐시, 볼트체크 타이밍 |
| Phase 3 | 5 | 높음~매우높음 | AppState 구조, UI 동작, 파이프라인 흐름 |
| Deferred | ~15 | - | - |
