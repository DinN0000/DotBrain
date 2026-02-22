# Link Quality Management Design Document

> **Summary**: 폴더 관계 탐색 UI + Obsidian 링크 편집 감지를 통한 시맨틱 링크 품질 관리
>
> **Plan**: `docs/01-plan/features/link-quality-management.plan.md`
> **Date**: 2026-02-22
> **Status**: Draft

---

## 1. Data Models

### 1.1 FolderRelation (folder-relations.json)

```swift
struct FolderRelation: Codable, Sendable {
    let source: String       // "2_Area/SwiftUI-패턴" (relative path)
    let target: String       // "1_Project/iOS-개발"
    let type: String         // "boost" | "suppress"
    let hint: String?        // AI 생성: "프레임워크 패턴을 프로젝트에 적용할 때"
    let relationType: String? // AI 생성: "비교/대조" | "적용" | "확장" | "관련"
    let origin: String       // "explore" | "manual" | "detected"
    let created: String      // ISO 8601
}

struct FolderRelations: Codable, Sendable {
    let version: Int         // 1
    var updated: String      // ISO 8601
    var relations: [FolderRelation]
}
```

파일 경로: `.meta/folder-relations.json`

### 1.2 LinkFeedback (link-feedback.json)

```swift
struct LinkFeedbackEntry: Codable, Sendable {
    let date: String         // ISO 8601
    let sourceNote: String   // "SwiftUI-상태관리"
    let targetNote: String   // "요리-레시피"
    let sourceFolder: String // "SwiftUI-패턴"
    let targetFolder: String // "요리-레시피"
    let action: String       // "removed" (사용자가 Obsidian에서 삭제)
}

struct LinkFeedback: Codable, Sendable {
    let version: Int
    var entries: [LinkFeedbackEntry]
}
```

파일 경로: `.meta/link-feedback.json`
FIFO cap: 500개 (CorrectionMemory 200과 별도)

### 1.3 FolderPairCandidate (메모리 전용, 저장 안 함)

```swift
struct FolderPairCandidate {
    let sourceFolder: String    // relative path
    let targetFolder: String
    let sourcePara: PARACategory
    let targetPara: PARACategory
    let sourceNoteCount: Int
    let targetNoteCount: Int
    let existingLinkCount: Int  // 이미 연결된 노트 수
    let sharedTagCount: Int     // 겹치는 태그 수
    let topSharedTags: [String] // 상위 3개 공유 태그

    // AI가 채우는 필드
    var hint: String?           // "프레임워크 패턴을 비교할 때"
    var relationType: String?   // "비교/대조"
    var confidence: Double      // 0.0~1.0
}
```

---

## 2. New Files

### 2.1 FolderRelationStore.swift (Services/SemanticLinker/)

```swift
struct FolderRelationStore: Sendable {
    let pkmRoot: String

    // CRUD
    func load() -> FolderRelations
    func save(_ relations: FolderRelations)
    func addRelation(_ relation: FolderRelation)
    func removeRelation(source: String, target: String)

    // Query
    func relationType(source: String, target: String) -> String?
    func hint(source: String, target: String) -> String?
    func boostPairs() -> [(source: String, target: String, hint: String?)]
    func suppressPairs() -> Set<String>  // "source|target" 형식

    // Maintenance
    func renamePath(from: String, to: String)
    func pruneStale(existingFolders: Set<String>)
}
```

- 양방향 조회: `(A,B)` 또는 `(B,A)` 모두 매칭
- 파일 경로: `.meta/folder-relations.json`

### 2.2 LinkFeedbackStore.swift (Services/SemanticLinker/)

```swift
struct LinkFeedbackStore: Sendable {
    let pkmRoot: String
    private static let maxEntries = 500

    func load() -> LinkFeedback
    func save(_ feedback: LinkFeedback)
    func recordRemoval(sourceNote: String, targetNote: String,
                       sourceFolder: String, targetFolder: String)

    /// AI 프롬프트용 패턴 요약 생성
    func buildPromptContext() -> String
    // 출력 예: "사용자가 SwiftUI-패턴 ↔ 요리-레시피 폴더 간 링크를 3회 삭제함"
}
```

### 2.3 LinkStateDetector.swift (Services/SemanticLinker/)

```swift
struct LinkStateDetector: Sendable {
    let pkmRoot: String

    struct LinkSnapshot: Codable, Sendable {
        var noteLinks: [String: Set<String>]  // noteName → Set<targetName>
    }

    /// 이전 스냅샷 로드 (.meta/link-snapshot.json)
    func loadSnapshot() -> LinkSnapshot?
    func saveSnapshot(_ snapshot: LinkSnapshot)

    /// 현재 vault의 Related Notes 파싱하여 스냅샷 생성
    func buildCurrentSnapshot(allNotes: [LinkCandidateGenerator.NoteInfo]) -> LinkSnapshot

    /// diff: 이전에 있었는데 현재 없는 링크 = 사용자 삭제
    func detectRemovals(
        previous: LinkSnapshot,
        current: LinkSnapshot,
        noteInfoMap: [String: LinkCandidateGenerator.NoteInfo]
    ) -> [LinkFeedbackEntry]
}
```

파일 경로: `.meta/link-snapshot.json`

**중요**: Phase 5 (SemanticLink)가 새 링크를 쓰기 **전에** diff를 수행해야 함. 순서가 바뀌면 DotBrain이 쓴 링크를 "사용자 삭제"로 오인.

### 2.4 FolderRelationAnalyzer.swift (Services/SemanticLinker/)

```swift
struct FolderRelationAnalyzer: Sendable {
    let pkmRoot: String
    private let aiService = AIService.shared

    /// 규칙 없는 폴더 쌍 중 후보 추출 + AI 사전 분석
    func generateCandidates(
        allNotes: [LinkCandidateGenerator.NoteInfo],
        existingRelations: FolderRelations
    ) async -> [FolderPairCandidate]
}
```

**후보 생성 로직**:
1. 모든 폴더 쌍 열거 (PARA 루트 제외, 숨김/언더스코어 제외)
2. 이미 규칙 있는 쌍 제외
3. 점수 계산: 기존 노트 연결 수 × 3 + 공유 태그 수 × 1
4. 상위 20쌍 선택
5. AI 배치 호출 1회로 hint + relationType + confidence 채움

**AI 프롬프트**:
```
다음 폴더 쌍들의 관계를 분석하세요.

[0] SwiftUI-패턴 (area, 12 notes, tags: SwiftUI, MVVM, 상태관리)
    ↔ React-패턴 (resource, 8 notes, tags: React, Hooks, 상태관리)
    기존 연결 노트 3개, 공유 태그: 상태관리

[1] ...

## 규칙
1. hint: "~할 때", "~를 비교할 때" 형식, 한국어 20자 이내
2. relationType: "비교/대조" | "적용" | "확장" | "관련" 중 하나
3. confidence: 0.0~1.0 (관계 확신도)
4. 관련 없는 쌍은 confidence 0.0

## 응답 (순수 JSON)
[{"index": 0, "hint": "패턴을 비교할 때", "relationType": "비교/대조", "confidence": 0.85}]
```

### 2.5 FolderRelationExplorer.swift (UI/)

별도 SwiftUI 뷰 파일. AppState.Screen에 `.folderRelationExplorer` 추가.

**State**:
```swift
@State private var candidates: [FolderPairCandidate] = []
@State private var currentIndex: Int = 0
@State private var isLoading: Bool = true
@State private var animationDirection: AnimationDirection = .none

enum AnimationDirection { case none, left, right, down }
```

**Layout** (360×480 popover 내):
```
┌─────────────────────────────────────────────┐
│ ← 폴더 관계 탐색               {n} / {total} │
│─────────────────────────────────────────────│
│                                             │
│         ┌───────────────────┐               │
│         │  📁 {sourceFolder} │               │
│         │  {para} · {n} notes│               │
│         └─────────┬─────────┘               │
│                   │                         │
│    "{hint}"                                 │
│    {relationType}                           │
│                   │                         │
│         ┌─────────┴─────────┐               │
│         │  📁 {targetFolder} │               │
│         │  {para} · {n} notes│               │
│         └───────────────────┘               │
│                                             │
│  근거: 공유 태그 {n}개 · 기존 연결 {n}개      │
│                                             │
│  ┌─────────┐ ┌─────────┐ ┌─────────┐      │
│  │ ← 아니야 │ │ ↓ 글쎄  │ │ → 맞아!  │      │
│  └─────────┘ └─────────┘ └─────────┘      │
│                                             │
│  ← → ↓ 키보드로도 가능                       │
└─────────────────────────────────────────────┘
```

**키보드 처리**:
```swift
.onKeyPress(.rightArrow) { handleAction(.boost); return .handled }
.onKeyPress(.leftArrow) { handleAction(.suppress); return .handled }
.onKeyPress(.downArrow) { handleAction(.skip); return .handled }
```

**카드 전환 애니메이션**:
- → 맞아: 카드가 오른쪽으로 슬라이드 아웃 (green tint)
- ← 아니야: 카드가 왼쪽으로 슬라이드 아웃 (red tint)
- ↓ 글쎄: 카드가 아래로 페이드 아웃
- 전환 시간: 0.25초
- 다음 카드: 반대쪽에서 슬라이드 인

**빈 상태**:
- 후보가 0개: "모든 폴더 관계를 검토했습니다" + [돌아가기]
- 로딩 중: 스피너 + "AI가 폴더 관계를 분석하고 있습니다..."

---

## 3. Modified Files

### 3.1 LinkCandidateGenerator.swift

**변경**: `generateCandidates` 에 `folderRelations` 파라미터 추가

```swift
func generateCandidates(
    for note: NoteInfo,
    allNotes: [NoteInfo],
    mocEntries: [ContextMapEntry],
    folderBonus: Double = 1.0,
    excludeSameFolder: Bool = false,
    folderRelations: FolderRelationStore? = nil  // NEW
) -> [Candidate] {
    // ... 기존 스코어링 ...

    // NEW: folder relation 적용
    if let store = folderRelations {
        let noteFolder = /* note의 relative folder path */
        let otherFolder = /* other의 relative folder path */

        if let relType = store.relationType(source: noteFolder, target: otherFolder) {
            switch relType {
            case "boost":
                score += 2.0  // 보수적 시작
            case "suppress":
                continue  // 후보에서 완전 제외
            default: break
            }
        }
    }

    guard score >= 3.0 else { continue }
    // ...
}
```

**주의**: NoteInfo에 폴더 relative path가 필요. 현재 `folderName`은 폴더 이름만 있고 PARA prefix가 없음. SemanticLinker.buildNoteIndex()에서 relative folder path를 추가해야 함.

→ `NoteInfo`에 `folderRelPath: String` 필드 추가 (예: `"2_Area/SwiftUI-패턴"`)

### 3.2 LinkAIFilter.swift

**변경**: filterBatch/filterSingle 프롬프트에 folder relation hint 주입

```swift
// filterBatch의 프롬프트에 추가:
let folderHints = buildFolderHintSection(notes, folderRelations)
// → "## 폴더 관계 가이드\n- SwiftUI-패턴 ↔ iOS-개발: '패턴을 적용하는 관계'\n..."

let prompt = """
각 노트에 대해 진짜 관련있는 후보를 모두 선택하세요.

\(noteDescriptions)

\(folderHints)  // NEW

## 규칙
...
"""
```

`filterBatch`, `filterSingle`에 `folderRelations: FolderRelationStore?` 옵셔널 파라미터 추가. nil이면 기존 동작.

### 3.3 SemanticLinker.swift

**변경 1**: linkAll()에서 FolderRelationStore 로드 + 주입

```swift
func linkAll(changedFiles: Set<String>? = nil, ...) async -> LinkResult {
    // 기존 코드 ...

    let folderRelationStore = FolderRelationStore(pkmRoot: pkmRoot)

    let candidateGen = LinkCandidateGenerator()
    for note in targetNotes {
        let candidates = candidateGen.generateCandidates(
            for: note,
            allNotes: allNotes,
            mocEntries: contextMap.entries,
            folderRelations: folderRelationStore  // NEW
        )
        // ...
    }

    // AI filter에도 전달
    // ...
}
```

**변경 2**: buildNoteIndex()에서 `folderRelPath` 채우기

```swift
notes.append(LinkCandidateGenerator.NoteInfo(
    name: baseName,
    filePath: filePath,
    tags: frontmatter.tags,
    summary: frontmatter.summary ?? "",
    project: frontmatter.project,
    folderName: folder,
    folderRelPath: relativeFolderPath,  // NEW: "2_Area/SwiftUI-패턴"
    para: para,
    existingRelated: existingRelated
))
```

### 3.4 VaultCheckPipeline.swift

**변경**: Phase 4.5 링크 삭제 감지 추가 (Phase 5 직전)

```swift
// Phase 4.5: Link State Diff (70% -> 72%)
onProgress(Progress(phase: "링크 변경 감지 중...", fraction: 0.70))
let linkDetector = LinkStateDetector(pkmRoot: pkmRoot)
let allNotes = SemanticLinker(pkmRoot: pkmRoot).buildNoteIndex()
// ↑ buildNoteIndex를 internal로 변경 필요 (현재 private)

let previousSnapshot = linkDetector.loadSnapshot()
let currentSnapshot = linkDetector.buildCurrentSnapshot(allNotes: allNotes)

if let prev = previousSnapshot {
    let noteInfoMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0) })
    let removals = linkDetector.detectRemovals(
        previous: prev, current: currentSnapshot, noteInfoMap: noteInfoMap
    )
    if !removals.isEmpty {
        let feedbackStore = LinkFeedbackStore(pkmRoot: pkmRoot)
        for removal in removals {
            feedbackStore.recordRemoval(
                sourceNote: removal.sourceNote,
                targetNote: removal.targetNote,
                sourceFolder: removal.sourceFolder,
                targetFolder: removal.targetFolder
            )
        }
        NSLog("[VaultCheck] %d link removals detected", removals.count)
    }
}

// 스냅샷은 Phase 5 완료 후에 저장 (새 링크 포함)
// ... Phase 5 실행 ...
let finalSnapshot = linkDetector.buildCurrentSnapshot(allNotes: /* re-scan */)
linkDetector.saveSnapshot(finalSnapshot)
```

**buildNoteIndex 접근성**: SemanticLinker.buildNoteIndex()는 현재 `private`. `internal`로 변경하거나, 별도 유틸로 추출.

### 3.5 AppState.swift

**변경 1**: Screen enum에 추가

```swift
enum Screen {
    // ... 기존 ...
    case folderRelationExplorer  // NEW

    var parent: Screen? {
        switch self {
        case .folderRelationExplorer:
            return .dashboard  // 또는 .vaultInspector
        // ...
        }
    }

    var displayName: String {
        switch self {
        case .folderRelationExplorer: return "폴더 관계 탐색"
        // ...
        }
    }
}
```

**변경 2**: 탐색 시작 메서드

```swift
func startFolderRelationExplorer() {
    navigate(to: .folderRelationExplorer)
}
```

---

## 4. Implementation Order

```
Phase 1: 데이터 레이어
├── FolderRelationStore.swift (CRUD, 양방향 조회)
├── LinkFeedbackStore.swift (FIFO 500)
└── 모델 정의 (FolderRelation, LinkFeedback, etc.)

Phase 2: 스코어링 통합
├── NoteInfo에 folderRelPath 추가
├── LinkCandidateGenerator에 folderRelations 반영
├── LinkAIFilter에 hint 프롬프트 주입
└── SemanticLinker에서 FolderRelationStore 로드+주입

Phase 3: 링크 삭제 감지
├── LinkStateDetector.swift (스냅샷 diff)
├── VaultCheckPipeline Phase 4.5 추가
└── LinkFeedbackStore에 기록

Phase 4: 탐색 UI
├── FolderRelationAnalyzer.swift (후보 생성 + AI 분석)
├── FolderRelationExplorer.swift (카드 UI + 키보드)
├── AppState.Screen 추가
└── 대시보드/VaultInspector에 진입점 추가
```

Phase 1-2만으로 `.meta/folder-relations.json`을 수동 편집해서 효과 확인 가능.
Phase 3은 사용자 행동 없이도 자동 수집.
Phase 4가 메인 UX.

---

## 5. Edge Cases

### 5.1 폴더 이름 변경

`FolderRelationStore.renamePath(from:to:)` — `source`, `target` 모두에서 경로 치환. 호출 시점: `FileMover` 사용하는 모든 경로 (FolderReorganizer, reorg 실행).

### 5.2 폴더 삭제

`FolderRelationStore.pruneStale(existingFolders:)` — VaultCheckPipeline Phase 1 이후에 호출. 존재하지 않는 폴더 참조 관계 제거.

### 5.3 노트 폴더 간 이동

folder-relations.json은 폴더 단위이므로 영향 없음. link-snapshot.json의 노트 키는 노트 이름(경로 아님)이므로 이동에 무관.

### 5.4 양방향 매칭

`(A,B)` 규칙은 `(B,A)` 방향에도 동일 적용. `FolderRelationStore.relationType()`에서 양방향 조회.

### 5.5 AI 분석 실패

FolderRelationAnalyzer에서 AI 호출 실패 시 → hint/relationType 없이 후보만 표시. 근거(공유 태그, 기존 연결 수)는 로컬 데이터이므로 항상 표시 가능.

### 5.6 link-snapshot.json 없음 (첫 실행)

이전 스냅샷 없으면 diff 건너뜀. 현재 스냅샷만 저장. 다음 vault check부터 감지 시작.

---

## 6. Verification Checklist

1. `swift build` — 0 warnings
2. folder-relations.json 수동 작성 → boost 폴더 쌍 노트 링크 증가 확인
3. folder-relations.json에 suppress → 해당 폴더 쌍 노트 링크 미생성 확인
4. 폴더 관계 탐색 → AI 카드 로드 → ←→↓ 키보드 동작
5. → 맞아 → folder-relations.json에 boost 저장 확인
6. ← 아니야 → folder-relations.json에 suppress 저장 확인
7. Obsidian에서 Related Notes 링크 삭제 → 볼트 점검 → link-feedback.json에 기록 확인
8. 폴더 이름 변경 후 relations 경로 업데이트 확인

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-22 | Initial design from plan + brainstorming | hwai |
