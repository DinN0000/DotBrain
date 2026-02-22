# DotBrain Architecture

> v1.7.7 기준 — 2026-02-15 작성

---

## 개요

DotBrain은 macOS 메뉴바 앱으로, AI 기반 PARA 방법론 개인 지식 관리(PKM) 시스템이다.
`_Inbox/`에 파일을 넣으면 AI가 자동으로 분류·태깅·링킹하여 적절한 PARA 폴더로 이동시킨다.

- **플랫폼**: macOS 13+ (menu bar app, NSPopover)
- **언어**: Swift 5.9+
- **빌드**: Swift Package Manager (Universal Binary: arm64 + x86_64)
- **외부 의존성**: ZIPFoundation 0.9.19 (DOCX/XLSX/PPTX 추출용)
- **Bundle ID**: `com.hwaa.dotbrain`

---

## 폴더 구조

```
DotBrain/
├── Sources/
│   ├── App/                  # 앱 진입점, AppDelegate, AppState
│   ├── Models/               # 데이터 모델 (8개)
│   ├── Pipeline/             # 핵심 처리 파이프라인 (3개)
│   ├── Services/             # 비즈니스 로직 (40+개)
│   │   ├── Claude/           # Claude API 클라이언트
│   │   ├── Gemini/           # Gemini API 클라이언트
│   │   ├── FileSystem/       # 파일 시스템 작업
│   │   └── Extraction/       # 바이너리 파일 추출 (6개)
│   └── UI/                   # SwiftUI 뷰 (9개 + 컴포넌트)
├── Resources/
│   ├── app-icon.png
│   └── Info.plist
├── Package.swift
└── docs/                     # 설계 문서 (이 파일)
```

---

## 핵심 아키텍처 패턴

### 1. Singleton + Actor 기반 동시성

```
┌──────────────────────────────────────────────┐
│  @MainActor                                  │
│  AppState.shared (ObservableObject)          │
│  ├── @Published currentScreen                │
│  ├── @Published isProcessing                 │
│  └── @Published inboxFileCount               │
└────────────────────┬─────────────────────────┘
                     │ 호출
┌────────────────────┴─────────────────────────┐
│  actor AIService.shared                      │
│  ├── classifyBatch() → ClaudeAPI / GeminiAPI │
│  ├── provider 자동 전환 (fallback)            │
│  └── RateLimiter.shared 통합                 │
├──────────────────────────────────────────────┤
│  actor RateLimiter.shared                    │
│  ├── Provider별 적응형 스로틀링               │
│  ├── 429 → 2x backoff                       │
│  └── 연속 성공 → 5% 가속                     │
├──────────────────────────────────────────────┤
│  actor ClaudeAPIClient                       │
│  actor GeminiAPIClient                       │
│  actor Classifier                            │
└──────────────────────────────────────────────┘
```

**설계 이유**: Actor로 동시성 안전 보장. Lock-free. AI API 호출이 많아 race condition 방지 필수.

### 2. 화면 상태 머신 (Screen Enum)

```swift
enum Screen {
    case onboarding      // 초기 설정
    case inbox           // 인박스 대기
    case processing      // 처리 중
    case results         // 결과 표시
    case settings        // 설정
    case dashboard       // 통계/대시보드
    case search          // 볼트 검색
    case paraManage      // PARA 폴더 관리
    case vaultReorganize // 볼트 전체 재정리
}
```

`AppState.currentScreen`으로 전체 UI 전환 제어. SwiftUI의 `@Published` + NSPopover 내 단일 뷰 구조.

### 3. 메뉴바 아이콘 상태 표현

```
·‿·    온보딩
·_·!   인박스 (파일 있음)
·_·    인박스 (비어있음)
·_·…   처리 중
^‿^    결과 (성공)
·_·;   결과 (에러/보류)
·_·?   설정/검색/기타
```

---

## 데이터 흐름: 인박스 처리 파이프라인

```
사용자가 _Inbox/에 파일 드롭
          │
          ▼
┌─ InboxWatchdog (FSEvents) ─────────────────────────┐
│  파일 변경 감지 → refreshInboxCount()               │
└────────────────────────┬───────────────────────────┘
                         ▼
┌─ InboxProcessor.process() ─────────────────────────┐
│                                                     │
│  1. InboxScanner.scan()                            │
│     └─ 코드 프로젝트/개발 파일 필터링               │
│                                                     │
│  2. 콘텐츠 추출 (TaskGroup, 병렬)                   │
│     ├─ 텍스트 파일: 직접 읽기                       │
│     └─ 바이너리: BinaryExtractor 디스패치           │
│        ├─ PDFExtractor                             │
│        ├─ DOCXExtractor                            │
│        ├─ XLSXExtractor                            │
│        ├─ PPTXExtractor                            │
│        └─ ImageExtractor (OCR)                     │
│                                                     │
│  3. 볼트 컨텍스트 구축 (ProjectContextBuilder)       │
│     ├─ 프로젝트 목록 + 요약                         │
│     ├─ 하위 폴더 구조                               │
│     └─ 가중치: Project > Area/Resource > Archive    │
│                                                     │
│  4. Stage 1 분류 (Haiku/Flash) — 배치 10개          │
│     └─ confidence ≥ 0.8 → 확정                      │
│                                                     │
│  5. Stage 2 분류 (Sonnet/Pro) — 불확실한 것만        │
│     └─ confidence < 0.8인 파일 정밀 분류             │
│                                                     │
│  6. 시맨틱 링킹 (ContextLinker)                      │
│     └─ AI가 볼트 내 관련 노트 [[위키링크]] 추천      │
│                                                     │
│  7. 충돌 해결 + 파일 이동 (FileMover)                │
│     ├─ 인덱스 노트 충돌 확인                         │
│     ├─ 이름 충돌 확인                                │
│     └─ 대상 PARA 폴더로 이동                         │
│                                                     │
│  8. 프론트매터 주입 (FrontmatterWriter)              │
│     └─ para, tags, summary, created, status          │
└────────────────────────┬───────────────────────────┘
                         ▼
         AppState.processedResults 표시
         (성공/이동/건너뜀/에러/보류)
```

---

## 모듈 구조

### Pipeline (핵심 처리)

| 모듈 | 역할 |
|------|------|
| `InboxProcessor` | 인박스 처리 오케스트레이터: 스캔 → 추출 → 분류 → 이동 |
| `FolderReorganizer` | 기존 폴더 재정리: 플랫화, 중복 제거, 재분류 |
| `ProjectContextBuilder` | AI 프롬프트용 볼트 컨텍스트 구축 |

### AI & 분류

| 모듈 | 역할 |
|------|------|
| `AIService` | Provider 라우터 (Claude/Gemini), fallback, 재시도 |
| `Classifier` | 2단계 분류 (Fast → Precise), 배치 동시성 |
| `ClaudeAPIClient` | Anthropic v1/messages API (URLSession actor) |
| `GeminiAPIClient` | Google Gemini API (URLSession actor) |
| `RateLimiter` | Provider별 적응형 스로틀링 |

### 파일 시스템

| 모듈 | 역할 |
|------|------|
| `PKMPathManager` | PARA → 폴더 매핑, 경로 검증, traversal 방지 |
| `InboxScanner` | _Inbox/ 스캔, 코드 프로젝트 필터링 |
| `InboxWatchdog` | FSEvents 감시 → 인박스 파일 수 갱신 |
| `FileMover` | 파일 이동, 충돌 해결, 인덱스 노트 생성 |
| `FrontmatterWriter` | YAML 프론트매터 주입/갱신 |

### 콘텐츠 추출

| 모듈 | 역할 |
|------|------|
| `BinaryExtractor` | 바이너리 포맷 디스패처 |
| `PDFExtractor` | PDF → 텍스트 + 메타데이터 |
| `DOCXExtractor` | Word → 텍스트 |
| `XLSXExtractor` | Excel → 셀 텍스트 |
| `PPTXExtractor` | PowerPoint → 슬라이드 텍스트 |
| `ImageExtractor` | 이미지 → OCR + 설명 |

### 컨텍스트 & 링킹

| 모듈 | 역할 |
|------|------|
| `ContextLinker` | AI 시맨틱 링킹 — 관련 노트 [[위키링크]] 추천 |
| `ContextMapBuilder` | 볼트 전체 시맨틱 그래프 구축 |
| `ContextMap` | 파일 → 메타데이터 + 시맨틱 관계 데이터 구조 |

### 유틸리티

| 모듈 | 역할 |
|------|------|
| `AICompanionService` | CLAUDE.md, AGENTS.md, .cursorrules, agent/skill 파일 생성 |
| `KeychainService` | 하드웨어 UUID 기반 AES-GCM 암호화 키 저장 |
| `StatisticsService` | 파일 수, API 비용, 활동 이력 추적 |
| `VaultAuditor` | 깨진 링크, 프론트매터 누락, 태그 누락 탐지 |
| `VaultSearcher` | 이름/내용/태그 기반 볼트 검색 |

### UI (SwiftUI)

| 뷰 | 역할 |
|----|------|
| `MenuBarPopover` | 360×480 루트 컨테이너 + 하단 네비게이션 |
| `InboxStatusView` | 파일 수 표시, 드래그앤드롭, "처리" 버튼 |
| `ProcessingView` | 진행률 + 상태 업데이트 |
| `ResultsView` | 처리 결과 목록, 보류 항목 확인 |
| `SettingsView` | API 키, PKM 경로, Provider 선택 |
| `DashboardView` | 통계: 파일 수, API 비용, 활동 이력 |
| `SearchView` | 볼트 검색 |
| `PARAManageView` | PARA 폴더 관리 (생성/이동/삭제/건강 표시) |
| `VaultReorganizeView` | 볼트 전체 재정리 (AI 재분류) |
| `OnboardingView` | 5단계 초기 설정 위자드 |

---

## 데이터 모델

### PARACategory

```swift
enum PARACategory: String {
    case project    // 1_Project/ — 진행 중 프로젝트 (목표 + 기한)
    case area       // 2_Area/ — 지속 관리 영역 (기한 없는 책임)
    case resource   // 3_Resource/ — 참고 자료
    case archive    // 4_Archive/ — 완료/비활성
}
```

### ClassifyResult

```swift
struct ClassifyResult: Codable {
    let para: PARACategory       // 분류 결과
    let tags: [String]           // AI 추천 태그
    let summary: String          // 콘텐츠 요약
    let targetFolder: String     // 하위 폴더
    var project: String?         // 프로젝트명 (para == .project일 때)
    var confidence: Double       // 0.0 ~ 1.0
    var relatedNotes: [RelatedNote]  // [[위키링크]] 목록
}
```

### ProcessedFileResult

```swift
struct ProcessedFileResult {
    enum Status {
        case success              // 정상 분류 완료
        case relocated(from:)     // 재분류로 이동됨
        case skipped(String)      // 건너뜀 (이유)
        case deleted              // 중복으로 삭제
        case deduplicated(String) // 중복 감지
        case error(String)        // 에러 발생
    }
}
```

### Frontmatter (YAML)

```yaml
---
para: resource
tags: [ai, documentation]
created: 2026-02-15
status: active          # active | draft | completed | on-hold
summary: "2-3문장 요약"
source: import          # original | meeting | literature | import
project: "프로젝트명"
file:                   # 바이너리 동반 노트만
  name: "document.pdf"
  format: pdf
  size_kb: 245.5
---
```

---

## 보안

### API 키 저장

- **방식**: 하드웨어 UUID + Salt → AES-GCM 암호화
- **저장 위치**: `~/Library/Application Support/com.hwaa.dotbrain/keys.enc`
- **파일 권한**: 0o600 (소유자만 읽기)
- **레거시 마이그레이션**: OS Keychain → 자체 암호화 자동 전환

### 파일 안전

- 경로 정제: `../` traversal 공격 방지
- 심볼릭 링크: PKM 루트 내부 가리키는 것만 허용
- 코드 프로젝트: .git, Package.swift 등 감지 시 자동 스킵
- 대용량 경고: > 100MB 파일 로깅

---

## Rate Limiting 전략

```
┌─ Provider 기본값 ──────────────────────────┐
│  Gemini:  4.2초/요청 (14 RPM)             │
│  Claude:  0.5초/요청 (120 RPM)            │
└────────────────────────────────────────────┘

성공 연속 3회 → interval * 0.95 (5% 가속)
429 응답     → interval * 2.0 (2배 백오프)
연속 실패    → 지수 쿨다운

Primary 실패 → Alternate provider로 자동 전환
```

---

## 배포

```bash
# 빌드
swift build -c release --arch arm64 --arch x86_64

# 릴리즈 에셋
DotBrain       # Universal Binary
AppIcon.icns   # 앱 아이콘

# 설치
curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash

# 설치 경로
~/Applications/DotBrain.app
```

---

## 설계 결정 기록

| 결정 | 이유 |
|------|------|
| Menu Bar Only (NSPopover) | 최소 UI, 어디서든 빠른 접근 |
| Actor 기반 동시성 | Lock 없이 AI API 동시 호출 안전 보장 |
| 2단계 분류 | 비용 효율: Fast 모델로 대부분 처리, 불확실한 것만 Precise |
| 하드웨어 바인딩 암호화 | OS Keychain 대신 자체 관리 → 디바이스 종속 보안 |
| Provider Agnostic | Claude/Gemini 자유 전환 + fallback |
| ZIPFoundation만 의존 | 외부 의존성 최소화, Swift 기본 API 활용 |
| 적응형 Rate Limiting | Provider별 최적 속도 자동 학습 |
| 가중치 컨텍스트 매칭 | Project > Area/Resource > Archive 우선순위 |
