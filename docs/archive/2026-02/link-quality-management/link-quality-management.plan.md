# Link Quality Management Planning Document

> **Summary**: 폴더 관계 탐색 UI + Obsidian 링크 편집 감지를 통한 시맨틱 링크 품질 관리 시스템
>
> **Project**: DotBrain
> **Version**: 2.6.8
> **Author**: hwai
> **Date**: 2026-02-22
> **Status**: Completed

---

## 1. Overview

### 1.1 Purpose

SemanticLinker가 생성한 노트 간 링크의 품질을 지속적으로 관리한다. 사용자가 폴더 단위 관계를 가이드하면 AI가 그에 맞춰 노트 단위 링크를 생성/억제하고, 사용자의 Obsidian 내 자연스러운 편집 행동에서 피드백을 수집한다.

### 1.2 Background

현재 시스템의 한계:
- AI가 링크를 생성만 하고, 삭제하거나 품질을 재평가하지 않음
- 사용자 피드백 루프 없음 (CorrectionMemory는 분류 전용)
- 폴더 수준의 관계 가이드 없음 — AI가 태그/프로젝트 점수만으로 판단
- 불필요한 링크가 축적되어도 정리 수단 없음

3개 관점(UX/기술/데이터) 리뷰에서 도출된 핵심 원칙:
- **DotBrain은 "자동으로 해주는 앱"** — 능동적 리뷰 UI는 핵심 가치와 충돌
- **사용자의 기존 워크플로(Obsidian)를 방해하지 않는 피드백 수집** 필요
- **단일 사용자 PKM에서 학습 루프는 느림** — 즉시 가치를 줄 수 있는 수동 설정 병행

### 1.3 Related Documents

- Brainstorming: 5 HCI 관점 (Calm/Progressive/Nudge/Direct/Trust)
- 3-agent review: UX, 기술, 데이터/학습 관점

---

## 2. Scope

### 2.1 In Scope

- [ ] **폴더 관계 탐색 UI** — 별도 메뉴, 스와이프/키보드 기반 폴더 쌍 판단
- [ ] **folder-relations.json** — 폴더 간 boost/suppress 규칙 저장
- [ ] **LinkCandidateGenerator 점수 반영** — boost +3.0, suppress 제외
- [ ] **Obsidian 링크 삭제 감지** — vault check 시 이전 vs 현재 diff
- [ ] **LinkFeedbackStore** — 링크 피드백 별도 저장소
- [ ] **폴더 상세에서 관계 직접 편집** — 파워 유저용
- [ ] **AI 사전 분석** — 폴더 쌍 관계를 AI가 미리 채워서 카드 준비

### 2.2 Out of Scope

- 노트 단위 링크 리뷰 UI (Tinder 카드) — v2 검토
- 자동 링크 삭제/만료 — 링크 삭제는 사용자만 가능
- CorrectionMemory 스키마 변경 — 별도 LinkFeedbackStore 사용
- confirmed/unconfirmed 링크 상태 구분 — v2 검토

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | 폴더 관계 탐색 화면: 폴더 쌍 카드를 AI가 미리 분석하여 hint/relationType 채움 | High | Done |
| FR-02 | 3방향 입력: → 맞아(boost), ← 아니야(suppress), ↓ 글쎄(skip). 마우스+키보드 | High | Done |
| FR-03 | folder-relations.json 저장/로드 (source, target, type, hint, origin) | High | Done |
| FR-04 | LinkCandidateGenerator에 folder-relations 반영 (boost +2.0, suppress 제외) | High | Done |
| FR-05 | AI hint를 LinkAIFilter 프롬프트에 전달하여 context 생성 품질 향상 | Medium | Done |
| FR-06 | Obsidian 링크 삭제 감지: vault check 시 이전 링크 상태와 현재 diff | Medium | Done |
| FR-07 | LinkFeedbackStore: 링크 피드백 별도 저장 (CorrectionMemory와 분리) | Medium | Done |
| FR-08 | 삭제 패턴 AI 프롬프트 반영: "사용자가 이 폴더 쌍 링크를 자주 삭제함" | Medium | Done |
| FR-09 | 폴더 상세 화면에서 관계 직접 추가/편집/삭제 | Low | Deferred |
| FR-10 | 카드 큐 스마트 정렬: 기존 노트 연결 수 > 태그 겹침 > 같은 PARA 순 | Medium | Done |

### 3.2 Non-Functional Requirements

| Category | Criteria | Measurement Method |
|----------|----------|-------------------|
| Performance | 카드 큐 생성 AI 호출 1회 (배치 10-20쌍) | API call count |
| Performance | 폴더 관계 탐색 UI 전환 < 100ms | 체감 측정 |
| UX | 키보드만으로 전체 플로우 완료 가능 | 수동 테스트 |
| Data | folder-relations.json < 50KB | 파일 크기 |
| Build | swift build 0 warnings | 빌드 검증 |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [x] 폴더 관계 탐색 화면에서 카드 스와이프 가능
- [x] 키보드 ←→↓ 동작 확인
- [x] boost 규칙 → 해당 폴더 쌍 노트 링크 증가 확인
- [x] suppress 규칙 → 해당 폴더 쌍 노트 링크 생성 안 됨 확인
- [x] Obsidian에서 링크 삭제 → 다음 vault check에서 감지 확인
- [x] swift build 0 warnings

### 4.2 Quality Criteria

- [x] Zero build warnings
- [x] 기존 SemanticLinker 테스트 통과
- [x] 폴더 이름 변경/삭제 시 folder-relations 정리 확인 (pruneStale in VaultCheckPipeline)

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| AI 사전 분석 비용 | Medium | Medium | 배치 호출로 1회에 10-20쌍 처리, 캐시 |
| 폴더 쌍 조합이 너무 많음 | Low | Low | 스마트 정렬로 의미 있는 쌍만 상위 노출 |
| 폴더 이름 변경 시 relations 깨짐 | Medium | Medium | FolderRelationStore.renamePath() |
| boost +3.0이 과도하게 공격적 | Medium | Medium | 초기값 +2.0으로 시작, 관찰 후 조정 |
| suppress가 boost보다 빠르게 축적 | Low | High | suppress는 명시적 선언만 허용 (탐색에서만) |
| VaultInspectorView 코드 비대화 | Medium | High | 별도 FolderRelationExplorer.swift 뷰 파일 |

---

## 6. Architecture Considerations

### 6.1 설계 핵심 결정

| Decision | Options | Selected | Rationale |
|----------|---------|----------|-----------|
| 링크 피드백 저장소 | CorrectionMemory 확장 / 별도 store | 별도 LinkFeedbackStore | 스키마 불일치, FIFO 경쟁 방지 |
| confirmed 상태 추적 | note-index / link-state.json / markdown 주석 | v1에서는 미구현 | 복잡도 대비 가치 낮음, v2 검토 |
| 폴더 관계 탐색 위치 | VaultInspector 내부 / 별도 Screen | 별도 Screen | UI 독립성, VaultInspectorView 비대화 방지 |
| AI 분석 시점 | 메뉴 진입 시 / vault check 후 | 메뉴 진입 시 (캐시) | 사용자 대기 최소화 |
| boost 가중치 | +3.0 / +2.0 | +2.0 (보수적 시작) | 기존 태그 2개 overlap(3.0)보다 낮게 |
| 관계 유형 | 4종 (비교/적용/확장/관련) | AI가 선택, 사용자는 확인만 | 사용자 부담 최소화 |

### 6.2 새 파일 구조

```
Sources/
├── Services/SemanticLinker/
│   ├── FolderRelationStore.swift      (NEW: folder-relations.json CRUD)
│   ├── LinkFeedbackStore.swift        (NEW: 링크 피드백 저장)
│   ├── LinkStateDetector.swift        (NEW: 링크 삭제 감지 diff)
│   ├── LinkCandidateGenerator.swift   (MODIFY: folderRelations 파라미터)
│   ├── LinkAIFilter.swift             (MODIFY: hint 프롬프트 주입)
│   └── SemanticLinker.swift           (MODIFY: folder-relations 로드)
├── UI/
│   └── FolderRelationExplorer.swift   (NEW: 탐색 화면)
├── App/
│   └── AppState.swift                 (MODIFY: 새 Screen 추가)
└── Pipeline/
    └── VaultCheckPipeline.swift       (MODIFY: Phase 4.5 링크 삭제 감지)
```

### 6.3 데이터 모델

```json
// .meta/folder-relations.json
{
  "version": 1,
  "updated": "2026-02-22T...",
  "relations": [
    {
      "source": "2_Area/SwiftUI-패턴",
      "target": "1_Project/iOS-개발",
      "type": "boost",
      "hint": "프레임워크 패턴을 프로젝트에 적용할 때",
      "relationType": "적용",
      "origin": "explore",
      "created": "2026-02-22T..."
    }
  ]
}
```

```json
// .meta/link-feedback.json
{
  "version": 1,
  "removals": [
    {
      "date": "2026-02-22T...",
      "source": "SwiftUI-상태관리.md",
      "target": "요리-레시피.md",
      "sourceFolderPair": "SwiftUI-패턴 / 요리-레시피",
      "relation": "reference"
    }
  ]
}
```

### 6.4 Pipeline 통합

```
Phase 1: Audit (0% -> 10%)
Phase 2: Repair (10% -> 20%)
Phase 2.5: Create missing index notes
Phase 3: Enrich (25% -> 60%)
Phase 4: Note Index (60% -> 70%)
Phase 4.5: Link State Diff (70% -> 72%)    ← NEW
Phase 5: Semantic Link (72% -> 95%)         ← MODIFY (folder-relations 반영)
```

---

## 7. 사용자 경험 흐름

### 7.1 폴더 관계 탐색 (능동적, 심심할 때)

```
메뉴바 → "폴더 관계 탐색" 클릭
  ↓
AI가 미리 분석한 카드 큐 표시
  ↓
카드: 폴더A ↔ 폴더B, AI hint, 관계 유형, 근거
  ↓
→ 맞아! / ← 아니야 / ↓ 글쎄 (키보드 또는 클릭)
  ↓
folder-relations.json에 즉시 저장
  ↓
다음 카드 (0.3초 전환 애니메이션)
```

### 7.2 Obsidian 편집 감지 (수동적, 평소)

```
사용자가 Obsidian에서 노트 읽다가 이상한 링크 삭제
  ↓
다음 볼트 점검 시 Phase 4.5에서 감지
  ↓
link-feedback.json에 기록
  ↓
패턴 축적 → AI 프롬프트에 반영
```

### 7.3 폴더 상세에서 직접 설정 (파워 유저, 가끔)

```
VaultInspector → 폴더 메뉴 → "관계 설정"
  ↓
기존 관계 목록 + 추가/편집/삭제
```

---

## 8. Next Steps

1. [x] Write design document (`link-quality-management.design.md`) — skipped, plan was sufficient
2. [x] 구현 Phase 순서: FolderRelationStore → LinkCandidateGenerator 반영 → 탐색 UI → 링크 삭제 감지
3. [x] swift build 검증

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-22 | Initial draft from brainstorming + 3-agent review | hwai |
| 1.0 | 2026-02-22 | All FRs implemented, status updated to Completed | hwai |
