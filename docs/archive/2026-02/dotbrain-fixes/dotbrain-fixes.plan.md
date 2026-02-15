# DotBrain Fixes Planning Document

> **Summary**: 5개 에이전트 종합 리뷰에서 발견된 Critical/High 버그, 보안 이슈, 리팩토링, 문서 동기화 통합 수정
>
> **Project**: DotBrain
> **Version**: v1.5.5 → v1.6.0
> **Author**: hwai
> **Date**: 2026-02-15
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

pragmatic-architect, code-analyzer, gap-detector, security-architect, code-reviewer 5개 에이전트가 DotBrain 코드베이스를 종합 리뷰한 결과, Critical 4건 / High 5건 / Refactoring 6건 / 문서 동기화 미흡(85%) 이슈를 발견했다. 이를 체계적으로 수정하여 안정성, 보안, 유지보수성을 높인다.

### 1.2 Background

DotBrain v1.5.5는 기능적으로 완성도가 높으나, 에지 케이스에서 크래시나 데이터 유실 가능성이 있는 코드가 발견되었다. 특히 RateLimiter overflow, Gemini API 키 노출, 대용량 파일 처리 시 UI 블로킹 등은 실사용에서 직접 영향을 줄 수 있는 문제다.

### 1.3 Related Documents

- Architecture: [architecture.design.md](../../02-design/architecture.design.md)
- Security Spec: [security-spec.md](../../02-design/security-spec.md)

---

## 2. Scope

### 2.1 In Scope

- [ ] Critical 버그 4건 수정
- [ ] High 보안/안정성 이슈 5건 수정
- [ ] 코드 중복 제거 및 리팩토링 6건
- [ ] architecture.design.md 문서 동기화 (85% → 95%+)
- [ ] AICompanionService version 업데이트

### 2.2 Out of Scope

- 새로운 기능 추가
- UI/UX 변경
- 새로운 AI Provider 추가
- 성능 최적화 (이번은 정확성/안전성 중심)

---

## 3. Requirements

### 3.1 Functional Requirements — Critical (P0)

| ID | Requirement | 영향 | 대상 파일 |
|----|-------------|------|-----------|
| CR-01 | RateLimiter `pow()` overflow 방지 — 연속 실패 시 `consecutiveFailures`가 커지면 `pow(2.0, Double(consecutiveFailures))`에서 `Double.infinity` 발생. `min()` 클램핑 필요 | 앱 크래시 | `RateLimiter.swift` |
| CR-02 | Classifier TaskGroup 카운터 불일치 — `processedCount` 증가 로직이 성공/실패 모든 경로에서 호출되지 않음. UI 진행률 100% 도달 불가 | UI 고착 | `Classifier.swift` |
| CR-03 | FileMover 대용량 파일 UI 블로킹 — `FileManager.moveItem`이 메인 스레드에서 호출될 수 있어 긴 파일 이동 시 팝오버 무응답 | UI 프리징 | `FileMover.swift` |
| CR-04 | Gemini API 키 URL 노출 — API 키가 쿼리 파라미터로 전송되어 로그/프록시에 평문 노출 | 보안 취약 | `GeminiAPIClient.swift` |

### 3.2 Functional Requirements — High (P1)

| ID | Requirement | 영향 | 대상 파일 |
|----|-------------|------|-----------|
| HI-01 | KeychainService KDF 미사용 — 하드웨어 UUID를 직접 키로 사용. PBKDF2/HKDF 파생 필요 | 보안 약화 | `KeychainService.swift` |
| HI-02 | install.sh 체크섬 미검증 — 다운로드된 바이너리 무결성 미확인 | 공급망 리스크 | `install.sh` |
| HI-03 | FolderReorganizer `moveItem` 실패 무시 — 에러 catch 후 `continue`로 넘어가며 사용자에게 알리지 않음 | 데이터 유실 가능 | `FolderReorganizer.swift` |
| HI-04 | InboxWatchdog fd leak — `stopWatching()` 호출되지 않는 경로 존재. FSEvents 스트림 해제 누락 | 리소스 누수 | `InboxWatchdog.swift` |
| HI-05 | StatisticsService race condition — 여러 처리가 동시에 통계를 쓸 때 데이터 경합 가능 | 통계 부정확 | `StatisticsService.swift` |

### 3.3 Functional Requirements — Refactoring (P2)

| ID | Requirement | 설명 |
|----|-------------|------|
| RF-01 | `extractContent` 중복 제거 | InboxProcessor + FolderReorganizer에 동일 추출 로직 중복 → 공통 유틸 추출 |
| RF-02 | JSON 파싱 유틸 통합 | Claude/Gemini 응답 JSON 파싱이 각 클라이언트에 중복 → 공통 파서 |
| RF-03 | AIAPIError 통합 | Claude/Gemini 각각 에러 타입 → 공통 `AIAPIError` 프로토콜 또는 enum |
| RF-04 | Model 타입 AppState에서 분리 | AppState에 모델 정의가 혼재 → `Models/` 폴더로 이동 |
| RF-05 | Classifier.swift 서비스 폴더로 이동 | Pipeline이 아닌 Services/AI/ 하위가 적절 |
| RF-06 | `categoryFromPath` 통합 | 여러 파일에 PARA 카테고리 추출 로직 중복 → PKMPathManager로 통합 |

### 3.4 Non-Functional Requirements — 문서 동기화 (P2)

| ID | Requirement | 설명 |
|----|-------------|------|
| DC-01 | architecture.design.md 누락 모듈 추가 | ContextMapBuilder, ContextMap, VaultAuditor, VaultSearcher 등 9개 모듈 |
| DC-02 | 누락 UI 뷰 추가 | OnboardingView, SearchView, DashboardView 3개 뷰 |
| DC-03 | 데이터 모델 섹션 업데이트 | ProcessedFileResult, Frontmatter 상세화 |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [ ] Critical 4건 모두 수정 완료
- [ ] High 5건 모두 수정 완료
- [ ] Refactoring 최소 4건 완료
- [ ] `swift build` 성공 (arm64 + x86_64)
- [ ] architecture.design.md 갱신 (gap 90%+)
- [ ] AICompanionService version 증가

### 4.2 Quality Criteria

- [ ] 빌드 에러 0개
- [ ] 기존 기능 동작 유지 (인박스 처리, 재정리, 검색)
- [ ] RateLimiter 극한값 테스트 통과

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Refactoring 시 기존 로직 깨짐 | High | Medium | 단계별 빌드 확인, 최소 변경 원칙 |
| Gemini API 키 전송 방식 변경 시 API 호출 실패 | High | Low | Google API 문서 확인 후 헤더 방식 가능 여부 검증 |
| KDF 도입 시 기존 저장된 키 복호화 실패 | High | Medium | 마이그레이션 로직 추가 (기존 → KDF 자동 전환) |
| 파일 이동 중 에러 핸들링 강화 시 UX 복잡도 증가 | Medium | Low | 에러 카운트만 결과에 포함, 세부사항은 로그 |

---

## 6. Architecture Considerations

### 6.1 Project Level

| Level | Selected |
|-------|:--------:|
| **Starter** | ☐ |
| **Dynamic** | ☒ |
| **Enterprise** | ☐ |

Swift Package, 단일 앱, 외부 의존성 1개 — Dynamic 수준.

### 6.2 Key Architectural Decisions

| Decision | 현재 | 유지/변경 | 이유 |
|----------|------|-----------|------|
| Actor 기반 동시성 | Actor + @MainActor | 유지 | 안전하고 적절 |
| Singleton 패턴 | AppState.shared 등 | 유지 | 메뉴바 앱에 적합 |
| 2단계 분류 | Fast → Precise | 유지 | 비용 효율적 |
| 자체 암호화 | AES-GCM + HW UUID | 강화 (KDF 추가) | 키 파생 보안 강화 |
| Provider Agnostic | Claude/Gemini 전환 | 유지 + 에러 타입 통합 | 유지보수성 향상 |

### 6.3 수정 순서

```
Phase 1: Critical 버그 (CR-01 ~ CR-04)
  ├── RateLimiter overflow 클램핑
  ├── Classifier 카운터 수정
  ├── FileMover async 이동
  └── Gemini API 키 전송 방식 변경

Phase 2: High 이슈 (HI-01 ~ HI-05)
  ├── KeychainService KDF 도입 + 마이그레이션
  ├── install.sh 체크섬 추가
  ├── FolderReorganizer 에러 보고
  ├── InboxWatchdog fd 정리
  └── StatisticsService actor 전환

Phase 3: Refactoring (RF-01 ~ RF-06)
  ├── extractContent 공통 추출
  ├── JSON 파서 통합
  ├── AIAPIError 통합
  ├── Model 분리
  ├── Classifier 위치 이동
  └── categoryFromPath 통합

Phase 4: 문서 동기화 (DC-01 ~ DC-03)
  ├── architecture.design.md 갱신
  └── AICompanionService version 증가
```

---

## 7. Convention Prerequisites

### 7.1 Existing Project Conventions

- [x] `CLAUDE.md` 존재 (프로젝트 루트)
- [x] `docs/02-design/architecture.design.md` 존재
- [ ] 별도 `CONVENTIONS.md` 없음 (CLAUDE.md에 포함)
- [x] Swift Package Manager (`Package.swift`)
- [x] Actor 기반 동시성 패턴

### 7.2 Conventions to Follow

| Category | Rule |
|----------|------|
| **Naming** | Swift API Design Guidelines 준수 |
| **동시성** | 공유 상태 → Actor, UI 바인딩 → @MainActor |
| **에러 처리** | do-catch 필수, 에러 로깅 후 사용자 통지 |
| **파일 구조** | Sources/{App,Models,Pipeline,Services,UI} 유지 |
| **빌드** | 모든 변경 후 `swift build` 확인 (Hook 자동) |

---

## 8. Implementation Estimate

| Phase | 항목 수 | 복잡도 |
|-------|---------|--------|
| Phase 1: Critical | 4 | 중간 (Gemini API 변경이 핵심) |
| Phase 2: High | 5 | 높음 (KDF 마이그레이션이 핵심) |
| Phase 3: Refactoring | 6 | 낮음~중간 |
| Phase 4: Docs | 3 | 낮음 |

---

## 9. Next Steps

1. [ ] 이 Plan 문서 리뷰 및 승인
2. [ ] Design 문서 작성 (`/pdca design dotbrain-fixes`)
3. [ ] Phase 1 Critical부터 순차 구현
4. [ ] Gap Analysis (`/pdca analyze dotbrain-fixes`)

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-15 | Initial draft — 5-agent review 결과 기반 | hwai |
