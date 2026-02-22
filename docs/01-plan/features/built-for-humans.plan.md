# Built for Humans UX Improvements

> **Summary**: 5-agent review 결과 기반, "Built for humans" 측 UX 개선 3건
>
> **Project**: DotBrain
> **Version**: 2.5.1
> **Date**: 2026-02-21
> **Status**: Completed

---

## 1. Overview

### 1.1 Purpose

DotBrain의 캐치프레이즈 "Built for humans. Optimized for AI."에서 "Optimized for AI" 측은 7.5~8점으로 잘 구현되어 있으나, "Built for humans" 측이 6.5점으로 부족하다. 5개 Opus 에이전트 병렬 리뷰에서 도출된 핵심 문제 중 실사용자가 체감하는 항목만 선별하여 개선한다.

### 1.2 Background

5개 관점 리뷰 결과 8개 FR 도출 → 실사용자 검토 후 3개 승인:

| 관점 | 점수 | 핵심 문제 |
|------|:----:|----------|
| UX Flow & Interaction | 7.5 | 피드백 소멸, Finder 열기 제한 |
| Error Handling & Recovery | 6.5 | 파이프라인 에러가 파일 결과로 위장 |

### 1.3 Related Documents

- 5-Agent Review: 이 세션에서 수행 (2026-02-21)
- Architecture: `docs/plans/2026-02-21-boundary-rules-design.md`

---

## 2. Scope

### 2.1 In Scope

- [x] 백그라운드 작업 완료 표시 유지 (자동 소멸 제거)
- [x] "Finder에서 열기" 공통 상위 폴더 열기
- [x] 파이프라인 에러를 별도 배너로 표시

### 2.2 Out of Scope (사용자 Rejected)

- ~~결과 자동이동 제거~~ — 실사용 불편 없음
- ~~macOS 네이티브 알림~~ — FR-02로 충분
- ~~용어 한국어화~~ — PKM 유저 대상이므로 기술 용어 유지
- ~~Confidence 뱃지~~ — 사용자 불안 유발 가능
- ~~자동복구 미리보기~~ — 복구는 안전한 작업이므로 불필요

### 2.3 Out of Scope (규모/장기 과제)

- Undo/Rollback 메커니즘
- AI 학습 피드백 루프
- 키보드 단축키
- 팝오버 크기 동적 조정

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status | Source |
|----|-------------|----------|--------|--------|
| FR-02 | 백그라운드 작업 완료 표시를 자동 소멸(3초) 대신 유지. 팝오버 열 때 확인 가능하도록. | High | Done | UX Agent |
| FR-07 | "Finder에서 열기"가 첫 파일 폴더 대신 모든 성공 파일의 공통 상위 폴더를 열기 | Medium | Done | UX Agent |
| FR-08 | 파이프라인 수준 오류(API 실패, 네트워크 등)를 결과 리스트 위 별도 빨간 배너로 표시 | Medium | Done | UX Agent |

### 3.2 Non-Functional Requirements

| Category | Criteria | Verification |
|----------|----------|-------------|
| Safety | 기존 인박스/볼트 점검 동작 변경 없음 | 수동 테스트 |
| Build | Zero warnings | `swift build` |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [x] 3개 FR 구현 완료
- [x] `swift build` 0 warnings
- [x] 수동 테스트: 인박스 처리 플로우 정상 동작
- [x] 수동 테스트: 볼트 점검 완료 표시 유지 확인

### 4.2 Quality Criteria

- [x] Zero build warnings
- [x] CLAUDE.md Code Placement Rules 준수

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| 완료 표시 유지가 시각적으로 지저분함 | Low | Medium | 팝오버 다시 열 때 자동 클리어, 또는 fade 처리 |
| 공통 상위 폴더가 PKM 루트일 경우 의미 없음 | Low | Low | 파일이 1개일 때는 기존 동작(해당 파일 폴더) 유지 |
| 에러 배너 추가로 결과 화면 레이아웃 변경 | Low | Low | 에러 없을 때는 배너 미표시 (기존과 동일) |

---

## 6. Architecture Considerations

### 6.1 변경 파일 목록

| File | Change Type | FR |
|------|------------|-----|
| `Sources/App/AppState.swift` | 완료 후 3초 sleep 제거, completed 상태 유지 | FR-02 |
| `Sources/UI/ResultsView.swift` | Finder 열기 로직 변경 + 에러 배너 컴포넌트 | FR-07, FR-08 |
| `Sources/App/AppState.swift` | 파이프라인 에러 시 별도 상태 사용 | FR-08 |

### 6.2 Code Placement Rules 준수

- **AppState**: `@Published` 속성 변경만 (완료 표시 유지, 에러 상태 분리)
- **UI**: ResultsView 표현 변경 (Finder 열기 로직, 에러 배너)
- **Pipeline/Services**: 변경 없음

### 6.3 기존 기능 보호

| 보호 대상 | 방법 |
|----------|------|
| 인박스 처리 로직 | InboxProcessor 변경 없음 |
| 볼트 점검 로직 | VaultCheckPipeline 변경 없음 |
| AI 분류 정확도 | Classifier 변경 없음 |
| 파일 이동 안전성 | FileMover, PARAMover 변경 없음 |

---

## 7. Implementation Order

1. **FR-02**: 백그라운드 완료 표시 유지 (`AppState.swift` ~5줄 변경)
2. **FR-07**: Finder 열기 공통 폴더 (`ResultsView.swift` ~10줄 변경)
3. **FR-08**: 에러 배너 분리 (`ResultsView.swift` + `AppState.swift`)

---

## 8. Next Steps

1. [x] Plan 문서 작성 + 사용자 승인
2. [x] 구현 (3건 모두 소규모, Design 스킵)
3. [x] Build 확인
4. [x] Gap Analysis — code review로 대체

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-21 | 5-agent review 기반 초안 (8 FR) | Claude |
| 1.0 | 2026-02-21 | 사용자 검토 후 3 FR로 확정 | Claude |
| 1.1 | 2026-02-22 | All FRs implemented, status updated to Completed | Claude |
