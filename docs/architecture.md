# DotBrain Architecture

macOS 메뉴바 앱. Obsidian 볼트의 `_Inbox/` 폴더에 드롭된 파일을 AI로 분류하여 PARA 구조(`1_Project/`, `2_Area/`, `3_Resource/`, `4_Archive/`)로 자동 정리한다.

## System Context

```
+------------------+     +-------------------+     +-----------------+
|  macOS Menubar   |     |   Obsidian Vault  |     |   AI Providers  |
|  (NSPopover)     |<--->|   (파일시스템)      |     |  Claude / Gemini|
|  360x480 popover |     |   PARA 구조        |     |  이중 프로바이더  |
+------------------+     +-------------------+     +-----------------+
        |                         ^                        ^
        v                         |                        |
+--------------------------------------------------+      |
|                    DotBrain                       |------+
|  AppState → Pipeline → Services → Models         |
+--------------------------------------------------+
```

- **macOS menubar app**: `NSStatusItem` + `NSPopover`, dock 아이콘 없음 (`.accessory` policy)
- **Obsidian 호환**: 동일 볼트 폴더를 공유. 마크다운 + YAML frontmatter + `[[wikilink]]` 형식 사용
- **AI 이중 프로바이더**: Claude (Haiku + Sonnet) 또는 Gemini (Flash + Pro). 런타임 전환 가능, fallback 지원

## Layer Architecture

```
┌─────────────────────────────────────────────────┐
│  App Layer                                       │
│  DotBrainApp → AppDelegate → AppState (singleton)│
├─────────────────────────────────────────────────┤
│  UI Layer                         Pipeline Layer │
│  SwiftUI Views (11 screens)      InboxProcessor  │
│  MenuBarPopover (root)           FolderReorganizer│
│  BreadcrumbView, etc.            VaultReorganizer │
│                                  VaultAuditor     │
├─────────────────────────────────────────────────┤
│  Service Layer                                   │
│  AI / FileSystem / Extraction / SemanticLinker   │
│  Knowledge Mgmt / Project Mgmt / Utilities      │
├─────────────────────────────────────────────────┤
│  Model Layer                                     │
│  PARACategory, ClassifyResult, Frontmatter, etc. │
└─────────────────────────────────────────────────┘
```

의존성 방향: App → UI / Pipeline → Services → Models. 역방향 의존 없음.

## App Layer

`Sources/App/` — 4개 파일.

| 파일 | 역할 |
|------|------|
| `DotBrainApp.swift` | `@main` 진입점. `AppDelegate`를 `@NSApplicationDelegateAdaptor`로 연결 |
| `AppDelegate.swift` | `@MainActor`. NSStatusItem(메뉴바), NSPopover(360x480), Combine으로 아이콘 상태 관찰 |
| `AppState.swift` | `@MainActor final class`, singleton(`shared`), `ObservableObject`. 화면 전환, 처리 상태, 설정 관리 |
| `AppIconGenerator.swift` | Core Graphics로 `·_·` 얼굴 아이콘 렌더링 |

**AppState**는 모든 UI와 파이프라인을 연결하는 중심 허브:
- `Screen` enum으로 화면 라우팅 (11개 화면)
- `@Published` 속성으로 처리 진행률, 결과, 설정을 UI에 전파
- 파이프라인 실행(`startProcessing`, `startReorganizing`)과 사용자 확인(`confirmClassification`)을 조율

> 상세: [models-and-data.md](models-and-data.md) — AppState Screen enum, Published 속성 목록

## Pipeline Layer

`Sources/Pipeline/` — 핵심 비즈니스 로직. 파일 → AI 분류 → 이동의 흐름을 조율.

| 파이프라인 | 파일 | 단계 수 | 트리거 |
|-----------|------|---------|--------|
| **InboxProcessor** | `InboxProcessor.swift` | 6단계 | 사용자가 "정리하기" 클릭 |
| **FolderReorganizer** | `FolderReorganizer.swift` | 5단계 | PARA 폴더 재정리 |
| **VaultReorganizer** | `VaultReorganizer.swift` | 2페이즈 (scan + execute) | 볼트 전체 재분류 |
| **VaultAuditor** | `VaultAuditor.swift` | audit + repair | 대시보드에서 볼트 점검 |
| **SemanticLinker** | `Services/SemanticLinker/SemanticLinker.swift` | 6단계 | 처리 후 자동 실행 |

> 상세: [pipelines.md](pipelines.md) — 각 파이프라인의 단계별 상세, 충돌 감지, 에지 케이스

## Service Layer

`Sources/Services/` — 39개 파일, 6개 하위 디렉토리.

| 그룹 | 주요 서비스 | 역할 |
|------|------------|------|
| **AI** | AIService(actor), Classifier(actor), RateLimiter(actor), ClaudeAPIClient(actor), GeminiAPIClient(actor) | AI 호출, 2단계 분류, 적응형 rate limiting |
| **FileSystem** | FileMover, PKMPathManager, InboxScanner, InboxWatchdog, FrontmatterWriter, AssetMigrator | 파일 이동, 경로 관리, 볼트 감시, frontmatter 주입 |
| **Extraction** | FileContentExtractor, BinaryExtractor, PDF/PPTX/XLSX/DOCX/ImageExtractor | 텍스트/바이너리 콘텐츠 추출 |
| **SemanticLinker** | SemanticLinker, TagNormalizer, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter | 태그 정규화, 후보 생성, AI 필터링, wikilink 작성 |
| **Knowledge Mgmt** | NoteIndexGenerator, VaultAuditor, VaultSearcher, NoteEnricher, AICompanionService | 노트 인덱스 생성, 볼트 감사, 검색, AI 컴패니언 파일 |
| **Project/Folder** | ProjectManager, PARAMover, FolderHealthAnalyzer | 프로젝트 생명주기, PARA 이동, 폴더 건강 분석 |
| **Utility** | StatisticsService, KeychainService, TemplateService, NotificationService | 통계, 암호화 키 저장, 템플릿, 알림 |
| **Data/Cache** | ContentHashCache(actor), APIUsageLogger(actor) | SHA256 파일 변경 감지, 실제 토큰 기반 API 비용 추적 |

> 상세: [services.md](services.md) — 각 서비스의 public API, 의존성, actor 격리 모델

## UI Layer

`Sources/UI/` — 11개 화면 + 3개 재사용 컴포넌트.

```
MenuBarPopover (root, 화면 전환)
├── OnboardingView       (.onboarding)      — 5단계 초기 설정
├── InboxStatusView      (.inbox)           — 파일 드래그&드롭, 처리 시작
│   ├── ProcessingView   (.processing)      — 실시간 진행률
│   └── ResultsView      (.results)         — 처리 결과, 사용자 확인
├── DashboardView        (.dashboard)       — 통계, 볼트 점검, 도구
│   ├── PARAManageView   (.paraManage)      — 폴더 CRUD
│   ├── SearchView       (.search)          — 볼트 검색
│   ├── VaultInspectorView (.vaultInspector) — 볼트 점검 + AI 재분류 (통합)
│   └── AIStatisticsView (.aiStatistics)    — AI 사용량 통계, 토큰 비용
├── FolderRelationExplorer (.folderRelationExplorer) — 폴더 관계 탐색 (Tinder-style 카드)
└── SettingsView         (.settings)        — AI 프로바이더, 키, 경로
```

**FolderRelationExplorer 추가**: 폴더 간 관계를 Tinder-style 카드 UI로 탐색. 기존 boost 관계(파란 배지)와 새 AI 추천(주황 배지)을 2:1 비율로 인터리브. 스와이프/키보드로 Dot it!(연결) / Unmatch(해제) / Skip(건너뛰기) 액션.

**VaultReorganizeView 제거**: 기존 `.vaultReorganize` 화면은 `VaultInspectorView`에 흡수됨. VaultInspectorView는 Level 1 폴더 목록 + Level 2 폴더 상세 + 재분류 기능을 통합 제공.

**AIStatisticsView 추가**: 실제 토큰 사용량 기반 API 비용 통계. APIUsageLogger에서 데이터를 읽어 operation별 비용, 최근 API 호출 내역을 표시.

**네비게이션 모델**: `NavigationStack` 미사용. `AppState.currentScreen` (Screen enum)으로 화면 전환. 각 Screen은 optional `parent` 속성으로 계층 구성. 하단 4탭 (Inbox, Dashboard, Explore, Settings).

**재사용 컴포넌트**: `BreadcrumbView` (뒤로가기 + 제목), `APIKeyInputView` (Claude/Gemini 키 입력), `FileThumbnailView` (QuickLook 썸네일).

## Data Flow: Inbox Processing

```
사용자: 파일 드롭 → _Inbox/
         │
         ▼
┌─ InboxProcessor ──────────────────────────────────────┐
│  1. Scan      InboxScanner로 파일 목록 수집              │
│  2. Extract   FileContentExtractor로 병렬 추출 (max 5)   │
│  3. Classify  Classifier 2단계:                         │
│               Stage1 (Haiku/Flash 배치, 5개/요청, 3병렬)  │
│               Stage2 (Sonnet/Pro 정밀, 신뢰도<0.8만)     │
│  4. Conflict  4유형 감지:                               │
│               lowConfidence / indexNoteConflict /       │
│               nameConflict / unmatchedProject           │
│  5. Move      FileMover로 PARA 폴더에 이동              │
│  6. Finish    노트 인덱스 갱신 + SemanticLinker 연결      │
└────────────────────────────────────────────────────────┘
         │                    │
         ▼                    ▼
   ProcessedFileResult   PendingConfirmation
   (자동 처리 결과)       (사용자 확인 필요)
```

## Key Architecture Decisions

| 결정 | 근거 |
|------|------|
| `@MainActor` singleton AppState | 모든 UI 상태를 단일 진실 원천으로 관리. 스레드 안전성 보장 |
| Actor 기반 AI 서비스 | Swift concurrency의 data race 방지. GCD 대신 actor 격리 |
| 2단계 AI 분류 (Haiku→Sonnet) | 비용 최적화: 빠른 모델로 1차 분류, 불확실한 것만 정밀 모델 |
| 이중 AI 프로바이더 | 가용성. 하나가 실패하면 fallback 전환 |
| YAML frontmatter 사용 | Obsidian 호환. 기계/사람 모두 읽기 가능한 메타데이터 |
| `[[wikilink]]` 기반 연결 | Obsidian의 네이티브 링크 형식. 양방향 연결 지원 |
| 1MB 스트리밍 I/O | 대용량 파일 처리 시 메모리 보호 |
| Marker 기반 AI 컴패니언 업데이트 | `<!-- DotBrain:start/end -->` 마커로 사용자 수정 보존 |

## Cross-References

- **파이프라인 상세**: [pipelines.md](pipelines.md)
- **서비스 레퍼런스**: [services.md](services.md)
- **데이터 모델**: [models-and-data.md](models-and-data.md)
- **보안/동시성**: [security-and-concurrency.md](security-and-concurrency.md)
