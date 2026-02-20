# same-folder-auto-link Design Document

> **Summary**: PARA 카테고리별 차등 전략으로 같은 폴더 노트 간 연결 강화
>
> **Project**: DotBrain
> **Version**: 2.1.12
> **Author**: hwaa
> **Date**: 2026-02-20
> **Status**: Draft
> **Planning Doc**: [same-folder-auto-link.plan.md](../01-plan/features/same-folder-auto-link.plan.md)

---

## 1. Overview

### 1.1 Design Goals

- Project/Area 같은 폴더 노트는 AI 필터 없이 자동 연결 (맥락 생성은 AI 사용)
- Resource/Archive 같은 폴더 노트는 후보 가산점 상향으로 선정률 향상
- 기존 코드 구조 최소 변경 (3개 파일만 수정)

### 1.2 Design Principles

- PARA 카테고리별 차등 처리는 SemanticLinker에서 분기 (하위 컴포넌트는 범용 유지)
- 자동 연결 노트도 맥락 품질은 기존과 동일 수준 유지
- 5개 링크 제한 내에서 자동 연결 우선, 남은 슬롯에 AI 필터 연결

---

## 2. Architecture

### 2.1 변경 전 데이터 흐름

```
buildNoteIndex()
    |
    v
모든 노트 ──> LinkCandidateGenerator.generateCandidates()
                  |  (태그+폴더+프로젝트 점수, score > 0만 통과)
                  v
              [Candidate 목록]
                  |
                  v
              LinkAIFilter.filterBatch()
                  |  (AI가 선택 + 맥락 생성)
                  v
              [FilteredLink 목록]
                  |
                  v
              RelatedNotesWriter.writeRelatedNotes()
```

### 2.2 변경 후 데이터 흐름

```
buildNoteIndex()
    |
    v
PARA 카테고리 분기
    |
    +── Project/Area 노트 ──> 같은 폴더 siblings 수집
    |       |
    |       +── siblings <= 5 ──> 전원 자동 연결 대상
    |       +── siblings > 5  ──> 태그 겹침 점수로 상위 5개 선별
    |       |
    |       v
    |   LinkAIFilter.generateContextOnly()  ← [NEW]
    |       |  (AI가 맥락만 생성, 거부 불가)
    |       v
    |   RelatedNotesWriter.writeRelatedNotes()
    |       |
    |       +── 남은 슬롯 있으면 ──> 다른 폴더 후보 → AI 필터 → 기록
    |
    +── Resource/Archive 노트 ──> LinkCandidateGenerator.generateCandidates()
            |  (폴더 가산점 +1.0 → +2.5)
            v
        기존 흐름과 동일 (AI 필터 → 기록)
```

### 2.3 Dependencies

| Component | Depends On | Purpose |
|-----------|-----------|---------|
| SemanticLinker | LinkCandidateGenerator | 후보 점수 계산 (Resource/Archive + 크로스폴더) |
| SemanticLinker | LinkAIFilter | AI 필터 + 맥락 전용 생성 |
| SemanticLinker | RelatedNotesWriter | Related Notes 기록 |
| LinkAIFilter | AIService | Claude API 호출 |

---

## 3. Detailed Changes

### 3.1 LinkCandidateGenerator.swift

**변경 사항**: 폴더 가산점을 외부에서 주입 가능하게 변경

```swift
// BEFORE
let sharedFolders = noteFolders.intersection(otherFolders)
if !sharedFolders.isEmpty {
    score += Double(sharedFolders.count) * 1.0
}

// AFTER
let sharedFolders = noteFolders.intersection(otherFolders)
if !sharedFolders.isEmpty {
    score += Double(sharedFolders.count) * folderBonus
}
```

**`generateCandidates` 시그니처 변경**:

```swift
func generateCandidates(
    for note: NoteInfo,
    allNotes: [NoteInfo],
    mocEntries: [ContextMapEntry],
    maxCandidates: Int = 10,
    folderBonus: Double = 1.0,        // NEW: 기본값 유지
    excludeSameFolder: Bool = false    // NEW: Project/Area에서 true
) -> [Candidate]
```

- `folderBonus`: Resource/Archive에서 `2.5` 전달
- `excludeSameFolder`: Project/Area에서 `true` 전달 (같은 폴더는 별도 처리하므로 후보에서 제외)

**`excludeSameFolder` 로직**:

```swift
for other in allNotes {
    guard other.name != note.name else { continue }
    guard !note.existingRelated.contains(other.name) else { continue }

    // NEW: 같은 폴더 제외 옵션
    if excludeSameFolder && other.folderName == note.folderName {
        continue
    }

    // ... 기존 점수 계산
}
```

---

### 3.2 LinkAIFilter.swift

**새 메서드 추가**: `generateContextOnly`

같은 폴더 노트 쌍에 대해 맥락 설명만 생성. AI는 거부할 수 없고 모든 쌍에 대해 context + relation을 반환해야 함.

```swift
func generateContextOnly(
    notes: [(name: String, summary: String, tags: [String],
             siblings: [(name: String, summary: String, tags: [String])])]
) async throws -> [[FilteredLink]]
```

**프롬프트 설계**:

```
다음 노트들은 같은 폴더에 있는 문서입니다.
각 노트의 형제 노트에 대해 연결 맥락을 작성하세요.

### 노트 0: DeFi_Protocol
태그: DeFi, Ethereum
요약: DeFi 프로토콜 설계 문서
형제:
  [0] DeFi_Risk_Analysis — 태그: DeFi, Risk — DeFi 리스크 분석
  [1] DeFi_Tokenomics — 태그: Tokenomics — 토큰 이코노미 설계

## 규칙
1. 모든 형제에 대해 반드시 context를 작성 (건너뛰기 불가)
2. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
3. relation: prerequisite / project / reference / related 중 하나

## 응답 (순수 JSON)
[{"noteIndex": 0, "links": [{"index": 0, "context": "리스크 평가할 때", "relation": "reference"}]}]
```

**핵심**: "모든 형제에 대해 반드시" — 기존 `filterBatch`와의 차이점

---

### 3.3 SemanticLinker.swift

**`linkAll` 변경 — 핵심 분기 로직**:

```swift
// STEP 1: 노트를 PARA별로 분리
let projectAreaNotes = allNotes.filter { $0.para == .project || $0.para == .area }
let resourceArchiveNotes = allNotes.filter { $0.para == .resource || $0.para == .archive }

// STEP 2: Project/Area — 같은 폴더 자동 연결
let autoLinked = await processAutoLinks(
    notes: projectAreaNotes,
    allNotes: allNotes,
    noteNames: noteNames,
    contextMap: contextMap
)

// STEP 3: Project/Area — 다른 폴더 AI 필터 연결 (남은 슬롯)
let crossFolderLinked = await processCrossFolderLinks(
    notes: projectAreaNotes,
    allNotes: allNotes,
    contextMap: contextMap,
    autoLinkedCounts: autoLinked.linkCounts,
    noteNames: noteNames
)

// STEP 4: Resource/Archive — 기존 흐름 (가산점 상향)
let standardLinked = await processStandardLinks(
    notes: resourceArchiveNotes,
    allNotes: allNotes,
    contextMap: contextMap,
    folderBonus: 2.5,
    noteNames: noteNames
)
```

**`processAutoLinks` (새 private 메서드)**:

```swift
private func processAutoLinks(
    notes: [LinkCandidateGenerator.NoteInfo],
    allNotes: [LinkCandidateGenerator.NoteInfo],
    noteNames: Set<String>,
    contextMap: ContextMap
) async -> (notesLinked: Int, linksCreated: Int,
             linkCounts: [String: Int])   // 노트별 자동 연결 수
```

로직:
1. 노트를 `folderName`으로 그룹핑
2. 각 노트의 siblings 수집 (같은 폴더, existingRelated 제외)
3. siblings > 5이면 태그 겹침 점수로 상위 5개 선별
4. `LinkAIFilter.generateContextOnly()` 배치 호출
5. `RelatedNotesWriter.writeRelatedNotes()` 기록
6. 역방향 링크 생성
7. 노트별 자동 연결 수 반환 (다음 단계에서 남은 슬롯 계산용)

**siblings > 5일 때 선별 로직**:

```swift
// 같은 폴더 siblings를 태그 겹침으로 정렬
let noteTags = Set(note.tags.map { $0.lowercased() })
let scored = siblings.map { sibling -> (NoteInfo, Double) in
    let sibTags = Set(sibling.tags.map { $0.lowercased() })
    let overlap = Double(noteTags.intersection(sibTags).count)
    return (sibling, overlap)
}
let top5 = scored.sorted { $0.1 > $1.1 }.prefix(5).map { $0.0 }
```

**`processCrossFolderLinks` (새 private 메서드)**:

```swift
private func processCrossFolderLinks(
    notes: [LinkCandidateGenerator.NoteInfo],
    allNotes: [LinkCandidateGenerator.NoteInfo],
    contextMap: ContextMap,
    autoLinkedCounts: [String: Int],   // 노트별 이미 연결된 수
    noteNames: Set<String>
) async -> (notesLinked: Int, linksCreated: Int)
```

로직:
1. 각 노트에 대해 `remainingSlots = 5 - autoLinkedCounts[note.name]`
2. `remainingSlots <= 0`이면 skip
3. `LinkCandidateGenerator.generateCandidates(excludeSameFolder: true, maxCandidates: remainingSlots * 2)`
4. 기존 `LinkAIFilter.filterBatch()` 호출
5. 결과를 `remainingSlots`만큼만 기록

**`processStandardLinks` (새 private 메서드)**:

기존 `linkAll`의 로직을 추출. `folderBonus` 파라미터만 추가.

**`linkNotes` 변경**:

동일한 분기 로직 적용. 대상 노트의 PARA에 따라 자동 연결 / 가산점 상향 분기.

---

## 4. Edge Cases

| Case | Handling |
|------|----------|
| 같은 폴더에 노트 1개 (siblings 없음) | 자동 연결 건너뜀, 크로스폴더 AI 필터만 |
| 같은 폴더에 노트 6+개 | 태그 겹침 상위 5개만 자동 연결 |
| 자동 연결 5개로 슬롯 꽉 참 | 크로스폴더 연결 생략 |
| 이미 Related Notes에 같은 폴더 노트 존재 | `existingRelated` 체크로 중복 방지 |
| AI 맥락 생성 실패 | fallback context: "같은 폴더 문서" |
| Resource 노트인데 같은 폴더에 3개만 있음 | 가산점 +2.5로 후보 되지만 AI가 최종 판단 |

---

## 5. Implementation Order

1. [ ] **LinkCandidateGenerator.swift** — `folderBonus`, `excludeSameFolder` 파라미터 추가
2. [ ] **LinkAIFilter.swift** — `generateContextOnly` 메서드 추가
3. [ ] **SemanticLinker.swift** — PARA 분기 + `processAutoLinks` / `processCrossFolderLinks` / `processStandardLinks`
4. [ ] **빌드 검증** — `swift build` 통과

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-20 | Initial draft | hwaa |
