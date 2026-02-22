# Pipeline Optimization Planning Document

> **Summary**: 인박스 파이프라인의 분류 정확도, API 비용 효율, Context Build 성능을 개선한다.
>
> **Project**: DotBrain
> **Author**: hwai
> **Date**: 2026-02-18
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

200개 파일 처리 시 발견된 3가지 문제를 해결한다:
- **버그**: Unmatched Project 확인 옵션에서 Area 카테고리 누락
- **비용 역효과**: Stage 1의 800자 제한이 정확도를 낮춰 비싼 Stage 2 호출을 증가시킴
- **성능 병목**: Context Build가 볼트 전체 폴더의 개별 MOC 파일을 읽어 I/O 과다

### 1.2 Background

코드 전수 검토에서 확인된 사항:

**Area 옵션 버그**: `generateUnmatchedProjectOptions()` (InboxProcessor.swift:371-410)에서 AI가 파일을 project로 분류했으나 매칭 프로젝트가 없을 때, 사용자에게 Resource/Archive/기존프로젝트만 제시하고 Area를 빠뜨림. 반면 `generateOptions()` (저confidence 케이스)는 `PARACategory.allCases`를 순회하여 모든 카테고리를 올바르게 제시함.

**Stage 1 프리뷰 800자 제한**: 3단계 Extracting에서 이미 5000자 Smart 4-part 추출을 완료했음에도, 4단계 Stage 1에서 별도로 800자 `extractPreview()`를 생성하여 AI에 전달. 파일 I/O 비용은 이미 3단계에서 지불됐고, API 토큰 비용 차이는:

```
800자 Stage 1 → 정확도 하락 → confidence < 0.8 비율 증가 → 비싼 Stage 2(Sonnet/Pro) 호출 증가
5000자 Stage 1 → 정확도 상승 → confidence >= 0.8 비율 증가 → Stage 2 호출 감소
```

Haiku/Flash의 토큰 단가는 Sonnet/Pro의 1/10~1/5 수준이므로, Stage 1에서 6배 더 보내도 Stage 2 한 건을 줄이면 순이득.

**Context Build 성능**: `buildWeightedContext()`가 1_Project 하위 프로젝트별 인덱스 + 문서 10개, 2_Area/3_Resource 하위 폴더별 인덱스 + fallback 5개 파일을 개별 읽기. 볼트에 폴더 50개면 50+ 파일 읽기. 대신 이미 MOCGenerator가 생성하는 루트 MOC(1_Project.md, 2_Area.md 등) 4개만 읽으면 동일 컨텍스트 확보 가능.

### 1.3 Related Documents

- 200개 파일 처리 상세 플로우 (이전 세션 검토 결과)
- `Sources/Pipeline/InboxProcessor.swift` -- 파이프라인 오케스트레이터
- `Sources/Services/Claude/Classifier.swift` -- 2단계 AI 분류
- `Sources/Pipeline/ProjectContextBuilder.swift` -- 컨텍스트 빌더
- `Sources/Services/MOCGenerator.swift` -- MOC 생성

---

## 2. Scope

### 2.1 In Scope

- [x] FR-01: Unmatched Project 확인 옵션에 Area 추가 (버그 수정)
- [x] FR-02: Stage 1 프리뷰를 800자에서 전체 추출 내용(5000자)으로 변경
- [x] FR-03: Context Build를 루트 MOC 4개 읽기로 최적화
- [x] FR-04: 루트 MOC 내용 보강 (태그 집계, 프로젝트 문서 목록 포함)

### 2.2 Out of Scope

- 이미지 OCR 지원 (별도 계획 필요 -- Vision API 또는 on-device OCR 검토)
- ContextLinker의 300자 프리뷰 제한 개선 (linking은 semantic matching이라 현행 유지)
- 텍스트 중복 감지 O(n^2) 최적화 (별도 이슈)

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | `generateUnmatchedProjectOptions()` 개선: (a) `.area` 옵션 추가, (b) 기존 프로젝트 옵션 제거 → ARA + 건너뛰기 4개, (c) `relatedNotes` 유실 버그 수정 -- 양쪽 generate 함수 모두. | High | Pending |
| FR-02 | Classifier Stage 1에서 `extractPreview(maxLength: 800)` 대신 `ClassifyInput.content` (최대 5000자)를 직접 사용. `previewLength` 상수 제거. | High | Pending |
| FR-03 | `buildWeightedContext()`를 루트 MOC 4개 파일 읽기로 교체. 기존 `buildProjectDocuments()`, `buildFolderSummaries()`, `buildArchiveSummary()` 대체. | Medium | Pending |
| FR-04 | `generateCategoryRootMOC()`에서 루트 MOC에 집계 태그 포함, 1_Project 루트 MOC에 프로젝트별 문서 목록(최대 10개, 태그 3개) 포함. | Medium | Pending |

### 3.2 Non-Functional Requirements

| Category | Criteria | Measurement Method |
|----------|----------|-------------------|
| Performance | Context Build 시간 50% 이상 단축 (폴더 50개 볼트 기준) | 처리 시간 로그 비교 |
| Cost | Stage 2 호출 비율 30% 이상 감소 | 동일 테스트셋 Stage 2 진입 파일 수 비교 |
| Accuracy | 전체 분류 정확도 하락 없음 | 동일 테스트셋 분류 결과 비교 |
| Zero Warnings | 빌드 경고 0개 유지 | `swift build` |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [ ] FR-01~04 모두 구현 완료
- [ ] `swift build` 경고 0개
- [ ] InboxProcessor 파이프라인 수동 테스트 (10개 파일 분류)
- [ ] FolderReorganizer 파이프라인 수동 테스트 (FR-03 영향 -- 동일 ProjectContextBuilder 사용)
- [ ] Area 옵션이 PendingConfirmation UI에 표시됨
- [ ] AICompanionService.swift 문서 업데이트 (Stage 1 스펙 변경 반영)

### 4.2 Quality Criteria

- [ ] 빌드 성공
- [ ] 기존 frontmatter/MOC 형식과 호환
- [ ] 루트 MOC가 없는 신규 볼트에서도 graceful fallback

---

## 5. Risks and Mitigation

| Risk                                                 | Impact | Likelihood | Mitigation                                                 |
| ---------------------------------------------------- | ------ | ---------- | ---------------------------------------------------------- |
| Stage 1에 5000자 보내면 배치당 토큰이 6배 증가하여 Haiku/Flash 속도 저하 | Medium | Medium     | batchSize를 10에서 5로 줄여 배치당 총 토큰량 유지. 또는 배치 내 파일 수 자동 조절 로직. |
| 루트 MOC가 아직 생성 안 된 신규 볼트에서 빈 컨텍스트                     | Low    | High       | 루트 MOC 없으면 기존 `buildWeightedContext()` 로직으로 fallback       |
| 루트 MOC 내용이 최신이 아닐 수 있음 (마지막 처리 이후 수동 변경)             | Low    | Medium     | 파이프라인 시작 시 MOC 갱신 여부 체크 (mtime 비교)                         |
| ~~삭제~~ | | | 옵션은 Resource/Area/Archive/Inbox잔류 = 4개. 기존 프로젝트 재제시는 제거. |

---

## 6. Architecture Considerations

### 6.1 변경 대상 파일

| File | Change | FR |
|------|--------|----|
| `Sources/Pipeline/InboxProcessor.swift` | `generateUnmatchedProjectOptions()` + `generateOptions()` Area 옵션 추가, relatedNotes 전달 | FR-01 |
| `Sources/Services/Claude/Classifier.swift` | Stage 1 프롬프트에 `file.content` 직접 전달, `previewLength` 상수 제거, batchSize 10→5, 프롬프트 라벨 "미리보기:"→"내용:" | FR-02 |
| `Sources/Pipeline/ProjectContextBuilder.swift` | `buildWeightedContext()` 루트 MOC 읽기로 교체 (FolderReorganizer도 동일 클래스 사용 -- 자동 반영) | FR-03 |
| `Sources/Services/MOCGenerator.swift` | `generateCategoryRootMOC()` 태그 집계 및 프로젝트 문서 목록 추가 | FR-04 |
| `Sources/Services/AICompanionService.swift` | Stage 1 스펙 문서 업데이트 (line 760) | FR-02 |

### 6.2 핵심 설계 결정

| Decision | Options | Selected | Rationale |
|----------|---------|----------|-----------|
| Stage 1 컨텐츠 길이 | 800자 유지 / 2000자 / 5000자 전체 | 5000자 전체 | 이미 추출 완료된 데이터. Haiku 토큰 비용 미미. Stage 2 감소 효과가 큼. |
| Stage 1 batchSize 조정 | 10 유지 / 5로 축소 / 동적 조절 | 5로 축소 | 5000자 x 10 = 50K 토큰은 Haiku context에 과다. 5개 = 25K가 적정. |
| Context Build 방식 | 현행 유지 / 루트 MOC만 / 하이브리드 | 루트 MOC + fallback | 루트 MOC 있으면 4파일만 읽기, 없으면 기존 방식 |
| 루트 MOC 보강 시점 | 매 처리 전 / 매 처리 후(현행) / 별도 명령 | 매 처리 후(현행) | 7단계 Finishing에서 이미 MOC 갱신함. 순서 유지. |

### 6.3 데이터 흐름 변경

```
[현행]
3단계: 파일 → extractMarkdownSmart(5000자) → ClassifyInput.content
4단계: ClassifyInput.content → extractPreview(800자) → Stage 1 AI
                              → content 그대로 → Stage 2 AI

[변경 후]
3단계: 파일 → extractMarkdownSmart(5000자) → ClassifyInput.content
4단계: ClassifyInput.content → 그대로 → Stage 1 AI  ← preview 단계 제거
                              → content 그대로 → Stage 2 AI
```

```
[현행 Context Build]
buildWeightedContext()
├── buildProjectDocuments()    → 1_Project/ 각 폴더 MOC + 문서 10개씩 읽기
├── buildFolderSummaries()     → 2_Area/ 각 폴더 MOC + fallback 5개씩 읽기
├── buildFolderSummaries()     → 3_Resource/ 각 폴더 MOC + fallback 5개씩 읽기
└── buildArchiveSummary()      → 4_Archive/ 폴더명 + 파일 수만
= 총 12~50+ 파일 I/O

[변경 후 Context Build]
buildWeightedContext()
├── read 1_Project/1_Project.md   (태그 + 프로젝트별 문서 목록 포함)
├── read 2_Area/2_Area.md         (태그 + 폴더별 요약 포함)
├── read 3_Resource/3_Resource.md (태그 + 폴더별 요약 포함)
└── read 4_Archive/4_Archive.md   (폴더명 + 파일 수)
= 총 4 파일 I/O (fallback: 기존 방식)
```

---

## 7. Implementation Order

| 순서 | FR | 작업 | 이유 |
|------|-----|------|------|
| 1 | FR-01 | Area 옵션 버그 수정 | 버그. 1개 함수, 10줄 미만 변경. |
| 2 | FR-02 | Stage 1 프리뷰 제거 (800→5000) | 비용 최적화. Classifier.swift만 수정. batchSize 조정 포함. |
| 3 | FR-04 | 루트 MOC 보강 | FR-03의 선행 조건. MOCGenerator.swift 수정. |
| 4 | FR-03 | Context Build 최적화 | FR-04 완료 후 ProjectContextBuilder.swift 교체. |

---

## 8. Detailed Change Spec

### FR-01: Area 옵션 추가

**파일**: `Sources/Pipeline/InboxProcessor.swift`
**함수**: `generateUnmatchedProjectOptions()` (lines 371-410)

**현재 생성하는 옵션**:
1. Resource (confidence 0.7)
2. Archive (confidence 0.5)
3. 기존 프로젝트 최대 3개 (confidence 0.5)

**변경 후 옵션** (기존 프로젝트 재제시 제거, ARA 완성):
1. Resource
2. Area (targetFolder 유지)
3. Archive
4. Inbox 잔류 (건너뛰기) -- UI에서 "건너뛰기" 버튼으로 처리

**confidence 값**: frontmatter에 저장되지 않는 임시 값. 확인 옵션에서는 현행 유지 (변경 불필요).

**relatedNotes 유실 버그 수정** (기존 버그 발견):
현재 `generateUnmatchedProjectOptions()`는 새 `ClassifyResult`를 생성할 때 `relatedNotes`를 전달하지 않아 기본값 `[]`이 적용됨. 5단계 Linking에서 찾은 관련 노트가 전부 유실됨.
- `generateUnmatchedProjectOptions()`: 모든 옵션에서 `relatedNotes: base.relatedNotes` 추가
- `generateOptions()`: 대안 옵션(line 420-427)에서도 `relatedNotes: base.relatedNotes` 추가 (원본 옵션은 `[base]`로 이미 유지됨)

AI fuzzy matching이 이미 실패한 상태에서 기존 프로젝트를 다시 나열하는 것은 불필요. 사용자가 직접 프로젝트 배정이 필요하면 수동 이동하는 것이 자연스러움.

---

### FR-02: Stage 1 프리뷰 800→5000

**파일**: `Sources/Services/Claude/Classifier.swift`

**변경 1**: `previewLength` 상수 제거 (line 9)
```
- private let previewLength = 800
```

**변경 2**: `batchSize` 축소 (line 7)
```
- private let batchSize = 10
+ private let batchSize = 5
```

**변경 3**: Stage 1 프롬프트 빌드에서 `extractPreview` 호출을 `file.content` 직접 사용으로 교체

현재 (추정 lines 183-188):
```swift
let preview = FileContentExtractor.extractPreview(
    from: file.filePath,
    content: file.content,
    maxLength: previewLength
)
```

변경 후:
```swift
// 3단계에서 이미 Smart 4-part 추출된 content를 그대로 사용
let preview = file.content
```

**변경 4**: 프롬프트 내 라벨 변경
```
- "미리보기:" → "내용:"
```

**영향 범위**:
- Stage 1 배치 수: 200/10=20 → 200/5=40 (배치 수 2배, 하지만 maxConcurrentBatches=3 유지)
- Stage 1 배치당 토큰: ~8K → ~25K (Haiku context window 충분)
- Stage 2 진입 파일 수: 대폭 감소 예상 (각 Sonnet 호출 절약)

---

### FR-04: 루트 MOC 보강

**파일**: `Sources/Services/MOCGenerator.swift`
**함수**: `generateCategoryRootMOC()` (lines 135-191)

**변경 1**: 태그 집계 추가

현재 (line 168-174):
```swift
let frontmatter = Frontmatter.createDefault(
    para: para,
    tags: [],  // 항상 빈 배열
    ...
)
```

변경 후:
```swift
// 하위 폴더 MOC에서 태그 읽어 빈도 집계 → 상위 10개
var categoryTags: [String: Int] = [:]
for subfolder in subfolders {
    let subMOCPath = /* subfolder MOC path */
    // parse frontmatter → extract tags → aggregate counts
}
let topTags = categoryTags.sorted { $0.value > $1.value }
    .prefix(10).map { $0.key }

let frontmatter = Frontmatter.createDefault(
    para: para,
    tags: topTags,
    ...
)
```

**변경 2**: 1_Project 루트 MOC에 프로젝트별 문서 목록 추가

현재: 폴더 목록만 (`- [[ProjectA]] -- summary (N개)`)

추가할 섹션:
```markdown
## 폴더 목록

- [[ProjectA]] -- summary [tag1, tag2] (10개)
  - [[doc1]]: tags -- summary
  - [[doc2]]: tags -- summary
  ...

- [[ProjectB]] -- summary [tag3] (5개)
  - [[doc3]]: tags -- summary
```

Project에만 문서 목록 추가 (Area/Resource는 폴더 요약 + 태그로 충분).

**변경 3**: Area/Resource 루트 MOC에 폴더별 태그 표시

현재: `- [[DevOps]] -- summary (12개)`
변경: `- [[DevOps]] -- summary [k8s, ci-cd, monitoring] (12개)`

---

### FR-03: Context Build 최적화

**파일**: `Sources/Pipeline/ProjectContextBuilder.swift`
**함수**: `buildWeightedContext()` (lines 81-109)

**전략**: 루트 MOC 우선, 없으면 기존 방식 fallback

```swift
func buildWeightedContext() -> String {
    // 1. 루트 MOC 파일 4개 읽기 시도
    let rootMOCs = readRootMOCs()

    // 2. 루트 MOC가 하나라도 있으면 사용
    if !rootMOCs.isEmpty {
        return formatRootMOCContext(rootMOCs)
    }

    // 3. fallback: 기존 방식 (신규 볼트, MOC 미생성 상태)
    return buildWeightedContextLegacy()
}
```

기존 `buildProjectDocuments()`, `buildFolderSummaries()`, `buildArchiveSummary()`는 `buildWeightedContextLegacy()`로 rename하여 보존.

---

## 9. Future Items (Out of Scope)

| Item | Description | Priority |
|------|-------------|----------|
| 이미지 OCR | Vision API 또는 on-device Core ML OCR로 이미지 텍스트 추출. 현재 이미지는 `[바이너리 파일: name]`만 전달되어 파일명으로만 분류됨. | Medium |
| 텍스트 중복 감지 O(n^2) | 같은 폴더에 200개 파일 이동 시 매 파일마다 폴더 전체 .md 스캔. 해시 캐시로 O(n) 가능. | Low |
| ContextLinker 300자 제한 | linking용 프리뷰가 300자로 과도하게 짧음. 800자 정도로 확대 검토. | Low |
| Activity history 100개 제한 | 200개 파일 처리 시 이전 기록 밀림. 파일 기반 로깅 또는 limit 확대. | Low |

---

## 10. API Call Impact Estimate (200 files)

### Before (현행)

| Stage | Calls | Model | Est. Cost/call |
|-------|-------|-------|---------------|
| Stage 1 | 20 (200/10) | Haiku/Flash | ~$0.001 |
| Stage 2 | ~80 (40% fail) | Sonnet/Pro | ~$0.01 |
| **Total classify** | **~100** | | **~$0.82** |

### After (변경 후)

| Stage | Calls | Model | Est. Cost/call |
|-------|-------|-------|---------------|
| Stage 1 | 40 (200/5) | Haiku/Flash | ~$0.003 |
| Stage 2 | ~20 (10% fail) | Sonnet/Pro | ~$0.01 |
| **Total classify** | **~60** | | **~$0.32** |

Stage 1 비용 +$0.10 증가, Stage 2 비용 -$0.60 감소 = **순 절감 ~$0.50/batch**

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-18 | Initial draft | hwai |
