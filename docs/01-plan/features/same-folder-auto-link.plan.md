# same-folder-auto-link Planning Document

> **Summary**: PARA 카테고리별 차등 전략으로 같은 폴더 노트 간 연결 강화
>
> **Project**: DotBrain
> **Version**: 2.1.12
> **Author**: hwaa
> **Date**: 2026-02-20
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

같은 폴더에 넣었다는 것은 사용자의 의도적 분류이므로, 같은 폴더 노트 간 연결이 더 적극적으로 이루어져야 한다.
현재는 태그가 다르면 같은 폴더여도 후보조차 안 되는 문제가 있다.

### 1.2 Background

현재 `LinkCandidateGenerator`의 같은 폴더 가산점은 `+1.0`으로, 태그 겹침 2개(`+3.0`)나 같은 프로젝트(`+2.0`)보다 낮다.
태그가 전혀 다르고 프로젝트 필드도 없는 경우 같은 폴더 노트가 `score=1.0`으로 후보에 포함되긴 하지만, AI 필터에서 탈락하는 경우가 빈번하다.

### 1.3 현재 동작 (변경 전)

```
모든 노트 쌍 → 점수 계산(태그+폴더+프로젝트) → score > 0만 후보 → AI 필터(선택+맥락 생성) → Related Notes 기록
```

- 같은 폴더 가산점: `+1.0`
- PARA 카테고리 무관하게 동일 로직

---

## 2. Scope

### 2.1 In Scope

- [x] Project/Area: 같은 폴더 노트는 AI 필터 없이 자동 연결
- [x] Project/Area: 자동 연결 시 맥락(context) 생성을 위한 AI 호출 (필터가 아닌 맥락 전용)
- [x] Resource/Archive: 같은 폴더 가산점 `+1.0` → `+2.5`로 상향
- [x] `LinkCandidateGenerator`에 PARA 카테고리 인식 추가

### 2.2 Out of Scope

- RelatedNotesWriter 포맷 변경 (기존 wiki-link 형식 유지)
- MOC 생성 로직 변경
- 노트 당 최대 5개 링크 제한 변경

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | Project/Area 같은 폴더 노트는 AI 필터링 단계를 건너뛰고 자동으로 Related Notes에 추가 | High | Pending |
| FR-02 | 자동 연결된 노트에도 맥락 설명이 있어야 함 (예: "DeFi 설계할 때", "같은 프로젝트 문서") | High | Pending |
| FR-03 | Resource/Archive는 기존 AI 필터 유지, 같은 폴더 가산점만 +1.0 → +2.5 상향 | Medium | Pending |
| FR-04 | 자동 연결도 역방향 링크(reverse link) 생성 | High | Pending |
| FR-05 | 노트 당 최대 5개 링크 제한 내에서 자동 연결 + AI 연결 혼합 | Medium | Pending |

### 3.2 Non-Functional Requirements

| Category | Criteria | Measurement Method |
|----------|----------|-------------------|
| Performance | 자동 연결 시 AI 호출 횟수 감소 (Project/Area 같은 폴더는 필터 호출 불필요) | API cost 로그 비교 |
| Quality | 맥락 설명이 기존과 동일 수준 유지 ("~하려면", "~할 때" 형식) | 수동 검증 |

---

## 4. Design Direction

### 4.1 PARA별 차등 전략

| PARA | 같은 폴더 전략 | AI 필터 | 맥락 생성 |
|------|--------------|---------|----------|
| **Project** | 자동 연결 | 건너뜀 | AI 맥락 전용 호출 |
| **Area** | 자동 연결 | 건너뜀 | AI 맥락 전용 호출 |
| **Resource** | 가산점 상향 (+2.5) | 유지 | 기존 AI 필터에서 생성 |
| **Archive** | 가산점 상향 (+2.5) | 유지 | 기존 AI 필터에서 생성 |

### 4.2 변경 후 흐름

**Project/Area:**
```
같은 폴더 노트 수집 → AI에 맥락만 요청 (거부 불가) → 자동 기록
다른 폴더 노트 → 기존 후보 점수 → AI 필터 → 기록
```

**Resource/Archive:**
```
모든 노트 → 후보 점수 (폴더 가산점 +2.5) → AI 필터 → 기록
```

### 4.3 수정 대상 파일

| File | Change |
|------|--------|
| `LinkCandidateGenerator.swift` | PARA 인식, 폴더 가산점 상향 |
| `SemanticLinker.swift` | Project/Area 자동 연결 경로 분리 |
| `LinkAIFilter.swift` | 맥락 전용 생성 메서드 추가 |

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| 같은 폴더 노트가 많으면 5개 제한 초과 | Medium | Medium | 자동 연결 우선, 남은 슬롯에 AI 연결 배정 |
| 맥락 전용 AI 호출이 비용 추가 | Low | High | 배치 처리로 호출 횟수 최소화 |
| 자동 연결이 노이즈가 될 수 있음 | Low | Low | Project/Area는 폴더 자체가 주제 한정적이므로 노이즈 적음 |

---

## 6. Success Criteria

### 6.1 Definition of Done

- [ ] Project/Area 같은 폴더 노트가 100% Related Notes에 포함
- [ ] 모든 연결에 맥락 설명 존재 (빈 맥락 없음)
- [ ] Resource/Archive에서 같은 폴더 노트의 후보 선정률 향상
- [ ] 기존 테스트 통과 + 빌드 성공

---

## 7. Next Steps

1. [ ] Design 문서 작성 (`same-folder-auto-link.design.md`)
2. [ ] 구현
3. [ ] 빌드 검증

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-20 | Initial draft | hwaa |
