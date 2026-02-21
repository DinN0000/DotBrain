# Models and Data

데이터 모델, frontmatter 스키마, 상태 관리. `Sources/Models/` — 9개 파일.

## AppState Screen Enum

`Sources/App/AppState.swift`

```swift
enum Screen {
    case onboarding       // 초기 설정 (5단계)
    case inbox            // 메인 인박스
    case processing       // 처리 중
    case results          // 결과 표시
    case settings         // 설정
    case dashboard        // 대시보드 허브
    case search           // 볼트 검색
    case paraManage       // PARA 폴더 관리
    case vaultInspector   // 볼트 점검 + AI 재분류 (통합)
    case aiStatistics     // AI 사용량 통계
}
```

**변경**: `.vaultReorganize` 제거, `.vaultInspector`와 `.aiStatistics` 추가. VaultInspectorView가 기존 볼트 점검 + AI 재분류 기능을 통합.

각 Screen은 optional `parent` 속성을 가짐:
- `.paraManage.parent = .dashboard`
- `.search.parent = .dashboard`
- `.vaultInspector.parent = .dashboard`
- `.aiStatistics.parent = .dashboard`
- `.results.parent` = `processingOrigin` (inbox 또는 paraManage)

## AppState Published Properties

`Sources/App/AppState.swift` — `@MainActor final class`, `ObservableObject`, singleton.

| 속성 | 타입 | 용도 |
|------|------|------|
| `currentScreen` | `Screen` | 현재 화면 |
| `inboxFileCount` | `Int` | 인박스 파일 수 |
| `isProcessing` | `Bool` | 처리 진행 중 |
| `processingProgress` | `Double` | 진행률 (0.0–1.0) |
| `processingStatus` | `String` | 상태 메시지 |
| `processingPhase` | `ProcessingPhase` | 현재 처리 단계 |
| `processingCurrentFile` | `String` | 현재 파일명 |
| `processingCompletedCount` | `Int` | 완료 파일 수 |
| `processingTotalCount` | `Int` | 전체 파일 수 |
| `processedResults` | `[ProcessedFileResult]` | 처리 결과 목록 |
| `pipelineError` | `String?` | 파이프라인 수준 오류 메시지 |
| `pendingConfirmations` | `[PendingConfirmation]` | 사용자 확인 대기 |
| `affectedFolders` | `Set<String>` | 영향받은 폴더 |
| `processingOrigin` | `Screen` | 처리 시작 화면 |
| `navigationId` | `UUID` | 네비게이션 갱신용 |
| `pkmRootPath` | `String` | PKM 볼트 루트 경로 |
| `selectedProvider` | `AIProvider` | 선택된 AI 프로바이더 |
| `hasAPIKey` | `Bool` | API 키 존재 여부 |
| `hasClaudeKey` | `Bool` | Claude 키 존재 |
| `hasGeminiKey` | `Bool` | Gemini 키 존재 |
| `reorganizeCategory` | `PARACategory?` | 재정리 대상 카테고리 |
| `reorganizeSubfolder` | `String?` | 재정리 대상 하위 폴더 |
| `paraManageInitialCategory` | `PARACategory?` | PARA 관리 초기 카테고리 |

## PARACategory

`Sources/Models/PARACategory.swift`

```swift
enum PARACategory: String, Codable, CaseIterable {
    case project   // folderName: "1_Project"
    case area      // folderName: "2_Area"
    case resource  // folderName: "3_Resource"
    case archive   // folderName: "4_Archive"
}
```

| 속성 | project | area | resource | archive |
|------|---------|------|----------|---------|
| `folderName` | `1_Project` | `2_Area` | `3_Resource` | `4_Archive` |
| `displayName` | Project | Area | Resource | Archive |
| `icon` (SF Symbol) | `folder.fill` | `square.stack.3d.up.fill` | `book.fill` | `archivebox.fill` |
| `color` | blue | green | orange | gray |

- `init?(folderPrefix:)` — 폴더명에서 카테고리 초기화
- `static func fromPath(_:)` — 경로에서 PARA 카테고리 감지

## ClassifyResult

`Sources/Models/ClassifyResult.swift` — AI 분류 결과.

```swift
struct ClassifyResult: Codable {
    var para: PARACategory
    let tags: [String]
    let summary: String
    var targetFolder: String
    var project: String?          // 프로젝트 이름 (para == .project일 때)
    var confidence: Double        // 0.0–1.0 (mutable: Stage 2에서 업데이트)
    var relatedNotes: [RelatedNote] = []  // 기본값 빈 배열
    var suggestedProject: String? // fuzzyMatch 실패 시 AI 원본 프로젝트명
}

struct RelatedNote: Codable, Equatable {
    let name: String     // 노트 이름
    let context: String  // 연결 맥락 (15자 이내)
}
```

### Stage1Item / Stage2Item

2단계 AI 분류에서 사용하는 중간 타입.

```swift
// Stage 1: Haiku/Flash 배치 분류 결과 (5개 파일 동시)
struct Stage1Item: Codable {
    let fileName: String
    let para: PARACategory
    let tags: [String]
    let summary: String
    let confidence: Double
    var project: String?
    var targetFolder: String?
}

// Stage 2: Sonnet/Pro 정밀 분류 결과 (1개 파일)
struct Stage2Item: Codable {
    let para: PARACategory
    let tags: [String]
    let summary: String
    let targetFolder: String
    var project: String?
    var confidence: Double?
}
```

**ClassifyInput** — 분류 입력:
```swift
struct ClassifyInput {
    let filePath: String
    let content: String       // 전체 추출 텍스트 (5000자, Stage 2용)
    let fileName: String
    let preview: String       // 압축 프리뷰 (800자, Stage 1 배치용)
}
```

## Frontmatter

`Sources/Models/Frontmatter.swift` — YAML frontmatter 파싱/생성.

### YAML Schema

```yaml
---
para: resource          # PARACategory (project|area|resource|archive)
tags: ["tag1", "tag2"]  # 항상 더블 쿼트 (YAML injection 방지)
created: 2026-02-19     # YYYY-MM-DD
status: active          # NoteStatus
summary: "요약 텍스트"   # AI 생성 요약
source: import          # NoteSource
project: "MyProject"    # 소속 프로젝트 (optional)
file:                   # 바이너리 파일 메타데이터 (optional)
  name: "report.pdf"
  format: "pdf"
  size_kb: 1234.5
---
```

### NoteStatus

```swift
enum NoteStatus: String, Codable {
    case active
    case draft
    case completed
    case onHold = "on-hold"
}
```

### NoteSource

```swift
enum NoteSource: String, Codable {
    case original    // 직접 작성
    case meeting     // 회의록
    case literature  // 문헌
    case `import`    // 외부 가져오기
}
```

### FileMetadata

```swift
struct FileMetadata: Codable {
    let name: String      // 원본 파일명
    let format: String    // 확장자
    let sizeKB: Double    // 파일 크기 (KB)
}
```
CodingKey: `sizeKB` → `"size_kb"`

### 주요 메서드

| 메서드 | 역할 |
|--------|------|
| `parse(markdown:)` | 마크다운에서 frontmatter와 body 분리 |
| `stringify()` | Frontmatter를 YAML 문자열로 변환 |
| `inject(into:)` | 기존 마크다운에 frontmatter 병합 (기존 값 우선) |
| `createDefault(...)` | 기본 frontmatter 팩토리 |
| `escapeYAML(_:)` | YAML 특수문자 이스케이프 (`:`, `#`, `"`, `\n` 등) |

## ProcessingModels

`Sources/Models/ProcessingModels.swift`

### ProcessingPhase

```swift
enum ProcessingPhase: String {
    case preparing  = "준비"
    case extracting = "분석"
    case classifying = "AI 분류"
    case linking    = "노트 연결"
    case processing = "정리"
    case finishing  = "마무리"
}
```

### ProcessedFileResult

```swift
struct ProcessedFileResult: Identifiable {
    let fileName: String
    let para: PARACategory
    let targetPath: String
    let tags: [String]
    var status: Status

    enum Status {
        case success
        case relocated(from: String)      // 위치 변경됨
        case skipped(String)              // 건너뜀 (사유)
        case deleted                       // 삭제됨
        case deduplicated(String)          // 중복 제거됨
        case error(String)                 // 에러
    }

    // Computed properties
    var isSuccess: Bool    // success, relocated, deduplicated → true
    var isError: Bool      // error → true
    var error: String?     // error 메시지 추출
    var displayTarget: String  // targetPath의 마지막 2 컴포넌트 (예: "2_Area/DevOps")
}
```

### PendingConfirmation

```swift
struct PendingConfirmation: Identifiable {
    let fileName: String
    let filePath: String
    let content: String
    let options: [ClassifyResult]   // AI 분류 선택지
    var reason: Reason
    var suggestedProjectName: String?

    enum Reason {
        case lowConfidence       // 신뢰도 낮음
        case indexNoteConflict   // 인덱스 노트 충돌
        case nameConflict        // 파일명 충돌
        case misclassified       // 오분류
        case unmatchedProject    // 매칭 프로젝트 없음
    }
}
```

## AIProvider

`Sources/Models/AIProvider.swift`

```swift
enum AIProvider: String, CaseIterable, Identifiable {
    case claude = "Claude"
    case gemini = "Gemini"
}
```

| 속성 | claude | gemini |
|------|--------|--------|
| `displayName` | "Claude (Anthropic)" | "Gemini (Google)" |
| `modelPipeline` | "Haiku 4.5 → Sonnet 4.5" | "Flash → Pro" |
| `costInfo` | "파일당 약 $0.002 (Haiku 4.5)" | "무료 티어: 분당 15회, 일 1500회" |
| `keyPrefix` | `"sk-ant-"` | `"AIza"` |
| `keyPlaceholder` | `"sk-ant-..."` | `"AIza..."` |

메서드: `hasAPIKey()`, `saveAPIKey(_:)`, `deleteAPIKey()`

## AIResponse

`Sources/Models/AIResponse.swift` — AI 응답 + 토큰 사용량.

```swift
struct AIResponse {
    let text: String          // AI 응답 텍스트
    let usage: TokenUsage?    // 토큰 사용량 (프로바이더가 반환하지 않으면 nil)
}
```

`sendFastWithUsage()`, `sendPreciseWithUsage()` 메서드의 반환 타입. 기존 `sendFast()` / `sendPrecise()`는 `String`만 반환하지만, WithUsage 변형은 `AIResponse`를 반환하여 실제 토큰 추적이 가능.

## TokenUsage

`Sources/Models/AIResponse.swift`

```swift
struct TokenUsage: Codable {
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int      // 캐시된 입력 토큰 (Gemini cachedContentTokenCount)
    var totalTokens: Int {     // computed: inputTokens + outputTokens
        inputTokens + outputTokens
    }
}
```

ClaudeAPIClient의 `Usage` struct와 GeminiAPIClient의 `UsageMetadata` struct에서 각각 변환되어 생성됨.

## APIUsageEntry

`Sources/Services/APIUsageLogger.swift`

```swift
struct APIUsageEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let operation: String      // "classify", "enrich", "moc", "link-filter", "move" 등
    let model: String          // 실제 모델명 (예: "claude-haiku-4-5-20251001")
    let inputTokens: Int
    let outputTokens: Int
    let cachedTokens: Int
    let cost: Double           // 계산된 비용 (USD)
}
```

`.dotbrain/api-usage.json`에 JSON 배열로 저장됨. AIStatisticsView에서 operation별 비용 집계 및 최근 호출 내역 표시에 사용.

## PKMStatistics

`Sources/Models/PKMStatistics.swift`

```swift
struct PKMStatistics {
    var totalFiles: Int = 0
    var byCategory: [String: Int] = [:]   // "project", "area", "resource", "archive"
    var recentActivity: [ActivityEntry] = []
    var apiCost: Double = 0
    var duplicatesFound: Int = 0
}

struct ActivityEntry: Identifiable {
    let fileName: String
    let category: String
    let date: Date
    let action: String   // "classified", "reorganized", "relocated", "error", "started", "completed"
    let detail: String
}
```

## SearchResult

`Sources/Models/SearchResult.swift`

```swift
struct SearchResult: Identifiable {
    let noteName: String
    let filePath: String
    let para: PARACategory?
    let tags: [String]
    let summary: String
    let matchType: MatchType
    let relevanceScore: Double
    let isArchived: Bool

    enum MatchType: String {
        case tagMatch     = "태그 일치"    // score 0.5–0.9
        case bodyMatch    = "본문 일치"    // score 0.3
        case summaryMatch = "요약 일치"    // score 0.6
        case titleMatch   = "제목 일치"    // score 1.0
    }
}
```

## ExtractResult

`Sources/Models/ExtractResult.swift`

```swift
struct ExtractResult {
    let success: Bool
    let file: FileInfo?
    let metadata: [String: Any]
    let text: String?
    let error: String?

    struct FileInfo {
        let name: String
        let format: String
        let sizeKB: Double
    }
}
```

## ContextMap Types

`Sources/Services/ContextMap.swift` — note-index.json 기반 볼트 컨텍스트 맵. AI 분류 프롬프트에 사용.

```swift
struct ContextMapEntry: Sendable {
    let noteName: String        // "Aave_Analysis"
    let summary: String         // 프론트매터 요약
    let folderName: String      // "DeFi"
    let para: PARACategory      // .resource
    let folderSummary: String   // 폴더 전체 요약
    let tags: [String]          // 폴더 태그 클라우드
}

struct VaultContextMap: Sendable {
    let entries: [ContextMapEntry]
    let folderCount: Int
    let buildDate: Date
}
```

`VaultContextMap.toPromptText()` — PARA 카테고리별로 그룹화된 프롬프트 텍스트 생성. 빈 볼트일 경우 "볼트에 기존 문서 없음" 반환.

## Data Flow Between Layers

```
Models (순수 데이터)
  │
  ├─ ClassifyInput ──→ Services (Classifier)
  │                        │
  │                        ├─ Stage1Item (Haiku 배치 결과)
  │                        ├─ Stage2Item (Sonnet 정밀 결과)
  │                        ▼
  ├─ ClassifyResult ──→ Pipeline (InboxProcessor)
  │                        │
  │                        ├─ ProcessedFileResult (자동 처리)
  │                        ├─ PendingConfirmation (사용자 확인)
  │                        ▼
  └─────────────────→ App (AppState @Published)
                           │
                           ▼
                        UI (SwiftUI Views)
```

## Cross-References

- **레이어 구조**: [architecture.md](architecture.md)
- **파이프라인 데이터 흐름**: [pipelines.md](pipelines.md)
- **Frontmatter 보안**: [security-and-concurrency.md](security-and-concurrency.md) — YAML injection 방지
