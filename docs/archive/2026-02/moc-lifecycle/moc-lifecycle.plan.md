# MOC Lifecycle Planning Document

> **Summary**: MOC(Map of Content) 생성/갱신/품질 보장의 전체 생명주기를 설계한다. 현재 발견된 버그 수정 + 구조적 설계 개선.
>
> **Project**: DotBrain
> **Author**: hwai
> **Date**: 2026-02-18
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

pipeline-optimization (FR-03/04)에서 Context Build가 루트 MOC에 의존하게 변경되었으나, MOC 품질을 보장하는 메커니즘이 불완전하다. 3가지 문제를 해결한다:

1. **버그**: FR-04 코드가 있으나 루트 MOC에 태그/문서목록이 반영 안 됨
2. **구조적 누락**: VaultReorganizer가 파일 이동 후 MOC를 갱신하지 않음
3. **비용 불일치**: VaultReorganizer/FolderReorganizer의 비용 추정이 옛날 값

### 1.2 Background

**MOC가 사용되는 곳**:
- `buildWeightedContext()` — 인박스 처리, 전체 재정리, 폴더 재정리 모두 호출
- AI 분류 프롬프트에 볼트 컨텍스트로 주입됨
- 루트 MOC 품질 = 분류 정확도에 직접 영향

**현재 MOC 갱신이 일어나는 시점**:

| 기능 | MOC 갱신 여부 | 메서드 |
|------|:------------:|--------|
| 인박스 처리 | O (해당 폴더) | `updateMOCsForFolders()` |
| 폴더 재정리 (FolderReorganizer) | O (해당 폴더 + 이동 대상) | `generateMOC()` + `updateMOCsForFolders()` |
| 전체 재정리 (VaultReorganizer) | X | 없음 |
| 볼트 점검 (DashboardView) | O (전체) | `regenerateAll()` |

**발견된 문제들**:

1. **FR-04 루트 MOC 태그/문서목록 미반영**: `generateCategoryRootMOC()` 코드에 태그 집계(lines 187-194)와 문서 목록(lines 167-179)이 있으나, 실제 출력에서 누락됨. 하위 MOC에는 태그가 정상 존재.

2. **VaultReorganizer MOC 미갱신**: `execute()`에서 파일 이동 후 MOC를 전혀 갱신하지 않음. 파일이 대량 이동되면 MOC가 현실과 불일치.

3. **비용 추정 불일치**:
   - InboxProcessor: `$0.005` (pipeline-optimization에서 갱신)
   - VaultReorganizer: `$0.001` (line 140) — 미갱신
   - FolderReorganizer: `$0.001` (line 133) — 미갱신

### 1.3 Related Documents

- `docs/archive/2026-02/pipeline-optimization/` — FR-03/04 설계/구현 기록
- `Sources/Services/MOCGenerator.swift` — MOC 생성기
- `Sources/Pipeline/ProjectContextBuilder.swift` — Context Build (MOC 소비자)
- `Sources/Pipeline/VaultReorganizer.swift` — 전체 재정리
- `Sources/Pipeline/FolderReorganizer.swift` — 폴더 재정리
- `Sources/Services/VaultAuditor.swift` — 볼트 점검
- `Sources/UI/DashboardView.swift` — 볼트 점검 UI (runVaultCheck)

---

## 2. Scope

### 2.1 In Scope

- [x] FR-01: 루트 MOC 태그/문서목록 미반영 버그 수정
- [x] FR-02: VaultReorganizer에 MOC 갱신 추가
- [x] FR-03: 비용 추정 통일 ($0.005)

### 2.2 Out of Scope

- AI summary 품질 검증 (잘린 문장 감지) — 별도 이슈
- MOC mtime 기반 stale 감지 — 현재 볼트점검이 regenerateAll() 호출하므로 충분
- 자동 MOC 갱신 트리거 (파일 변경 감지) — 과도한 I/O, 현행 유지

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | `generateCategoryRootMOC()` 루트 MOC에 태그 집계 + Project 문서 목록이 실제로 출력되도록 버그 수정 | High | Pending |
| FR-02 | `VaultReorganizer.execute()` 완료 후 영향받은 폴더의 MOC 갱신 (`updateMOCsForFolders`) | High | Pending |
| FR-03 | VaultReorganizer/FolderReorganizer 비용 추정을 `$0.005`로 통일 | Low | Pending |

### 3.2 Non-Functional Requirements

| Category | Criteria |
|----------|----------|
| 정합성 | 모든 파이프라인(인박스/폴더재정리/전체재정리/볼트점검) 완료 후 MOC가 최신 상태 |
| 빌드 | `swift build` 경고 0개 |

---

## 4. Architecture Considerations

### 4.1 변경 대상 파일

| File | Change | FR |
|------|--------|----|
| `Sources/Services/MOCGenerator.swift` | `generateCategoryRootMOC()` 버그 수정 | FR-01 |
| `Sources/Pipeline/VaultReorganizer.swift` | `execute()` 끝에 MOC 갱신 추가 + 비용 수정 | FR-02, FR-03 |
| `Sources/Pipeline/FolderReorganizer.swift` | 비용 추정 수정 | FR-03 |

### 4.2 FR-01 디버깅 방향

루트 MOC에 태그가 안 나오는 원인 후보:
1. `Frontmatter.createDefault()` → `stringify()` 경로에서 tags 누락
2. `topTags`가 실제로 빈 배열 (하위 MOC parse 실패?)
3. 병렬 실행 타이밍 이슈 (하위 MOC 쓰기 완료 전에 루트 MOC가 읽음)
4. `Frontmatter.parse()`가 특정 YAML 형식의 tags를 못 읽음

→ Design 단계에서 디버그 로그 삽입 또는 단위 테스트로 원인 특정 필요

### 4.3 FR-02 설계 방향

FolderReorganizer의 기존 패턴을 따름:
```swift
// VaultReorganizer.execute() 끝에 추가
let affectedFolders = Set(results.compactMap { ... })
let mocGenerator = MOCGenerator(pkmRoot: pkmRoot)
await mocGenerator.updateMOCsForFolders(affectedFolders)
```

---

## 5. Implementation Order

| 순서 | FR | 작업 | 이유 |
|------|-----|------|------|
| 1 | FR-01 | 루트 MOC 태그 버그 수정 | 핵심 버그. 디버깅 우선. |
| 2 | FR-02 | VaultReorganizer MOC 갱신 | 구조적 누락 수정. |
| 3 | FR-03 | 비용 추정 통일 | 2줄 변경. |

---

## 6. Success Criteria

- [ ] 볼트점검 후 루트 MOC frontmatter에 `tags:` 필드 존재
- [ ] 볼트점검 후 1_Project 루트 MOC에 프로젝트별 문서 목록 존재
- [ ] 전체 재정리 후 영향받은 폴더의 MOC가 최신 상태
- [ ] `swift build` 경고 0개

---

## 7. Risks

| Risk | Impact | Mitigation |
|------|--------|-----------|
| FR-01이 코드 버그가 아니라 환경 문제일 경우 | Medium | 디버그 로그로 원인 특정 후 수정 |
| VaultReorganizer에 MOC 갱신 추가 시 처리 시간 증가 | Low | 이미 인박스/폴더재정리에서 동일 패턴 사용 중 |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-18 | Initial draft | hwai |
