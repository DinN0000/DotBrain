# DotBrain UX Improvement Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** PKM 초보자가 사내에서 바로 사용할 수 있도록 DotBrain의 전반적 UX를 개선한다.

**Architecture:** 기존 SwiftUI + AppState 싱글턴 패턴 유지. Screen enum과 MenuBarPopover 라우팅을 3계층 구조로 재편. 온보딩 4→5단계 확장, 대시보드를 허브 역할로 전환, 용어를 사용자 친화적으로 교체.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 13+, AppKit (NSStatusItem, QuickLookThumbnailing)

**Design Doc:** `docs/plans/2026-02-15-ux-improvement-design.md`

---

## Phase 1: 네비게이션 구조 재편 (기반 작업)

### Task 1: Screen enum 정리 및 네비게이션 계층 추가

**Files:**
- Modify: `Sources/App/AppState.swift` — Screen enum (라인 17-29), navigateBack() (라인 529-548)

**Step 1: Screen enum에 vaultManage 추가, 부모-자식 관계 정의**

기존 Screen enum에 `vaultManage` case 추가. 화면 간 부모 관계를 반환하는 computed property 추가.

```swift
enum Screen {
    case onboarding
    case inbox
    case processing
    case results
    case settings
    case reorganize
    case dashboard
    case search
    case projectManage
    case paraManage
    case vaultReorganize
    case vaultManage      // NEW: 통합 볼트 관리

    /// 부모 화면 (breadcrumb용)
    var parent: Screen? {
        switch self {
        case .paraManage, .projectManage, .search, .vaultManage:
            return .dashboard
        case .vaultReorganize, .reorganize:
            return .vaultManage
        case .results:
            return nil  // processingOrigin에 따라 동적 결정
        default:
            return nil
        }
    }

    /// 사용자에게 보이는 화면 이름
    var displayName: String {
        switch self {
        case .inbox: return "인박스"
        case .dashboard: return "대시보드"
        case .settings: return "설정"
        case .paraManage: return "PARA 관리"
        case .projectManage: return "프로젝트 관리"
        case .search: return "검색"
        case .vaultManage: return "볼트 관리"
        case .vaultReorganize: return "전체 재정리"
        case .reorganize: return "폴더 정리"
        case .results: return "정리 결과"
        default: return ""
        }
    }
}
```

**Step 2: navigateBack() 수정 — parent 기반 네비게이션**

```swift
func navigateBack() {
    if currentScreen == .results {
        // 결과 화면은 processingOrigin 기반
        if processingOrigin == .paraManage { currentScreen = .paraManage }
        else if processingOrigin == .reorganize { currentScreen = .reorganize }
        else if processingOrigin == .vaultReorganize { currentScreen = .vaultReorganize }
        else { currentScreen = .inbox }
    } else if let parent = currentScreen.parent {
        currentScreen = parent
    } else {
        currentScreen = .inbox
    }
    // 기존 상태 초기화 유지
    processedResults = []
    pendingConfirmations = []
    affectedFolders = []
    navigationId = UUID()
}
```

**Step 3: 빌드 확인**

Run: `cd ~/Developer/DotBrain && swift build 2>&1 | tail -5`
Expected: Build complete!

**Step 4: Commit**

```bash
git add Sources/App/AppState.swift
git commit -m "refactor: add screen hierarchy and vaultManage screen"
```

---

### Task 2: 하단 푸터 3탭으로 간소화

**Files:**
- Modify: `Sources/UI/MenuBarPopover.swift` (88줄)

**Step 1: 기존 5버튼 푸터를 3탭(인박스/대시보드/설정)으로 변경**

현재 푸터 (라인 42-80쯤): 설정, 대시보드, 검색, 도움말, "DotBrain", 종료

변경: 인박스 / 대시보드 / 설정 3개 탭. 종료는 설정 안으로. 도움말도 설정 안으로.

```swift
// Footer — 3탭
if ![.onboarding, .processing].contains(appState.currentScreen) {
    Divider()
    HStack(spacing: 0) {
        footerTab(icon: "tray.and.arrow.down", label: "인박스", screen: .inbox)
        footerTab(icon: "square.grid.2x2", label: "대시보드", screen: .dashboard)
        footerTab(icon: "gearshape", label: "설정", screen: .settings)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
}
```

```swift
private func footerTab(icon: String, label: String, screen: Screen) -> some View {
    Button(action: { appState.currentScreen = screen }) {
        VStack(spacing: 2) {
            Image(systemName: icon)
                .font(.system(size: 16))
            Text(label)
                .font(.caption2)
        }
        .frame(maxWidth: .infinity)
        .foregroundColor(appState.currentScreen == screen ? .accentColor : .secondary)
    }
    .buttonStyle(.plain)
}
```

**Step 2: processing 화면에서는 푸터 숨김 (취소 버튼만)**

기존 `.settings`, `.onboarding` 조건에 `.processing` 추가.

**Step 3: 빌드 확인**

Run: `cd ~/Developer/DotBrain && swift build 2>&1 | tail -5`

**Step 4: Commit**

```bash
git add Sources/UI/MenuBarPopover.swift
git commit -m "refactor: simplify footer to 3-tab navigation"
```

---

### Task 3: Breadcrumb 네비게이션 컴포넌트

**Files:**
- Create: `Sources/UI/Components/BreadcrumbView.swift`
- Modify: `Sources/UI/DashboardView.swift` — 헤더 교체
- Modify: `Sources/UI/PARAManageView.swift` — 헤더 교체
- Modify: `Sources/UI/SearchView.swift` — 헤더 교체
- Modify: `Sources/UI/ProjectManageView.swift` — 헤더 교체

**Step 1: BreadcrumbView 생성**

```swift
import SwiftUI

struct BreadcrumbView: View {
    @EnvironmentObject var appState: AppState
    let current: Screen
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        HStack(spacing: 4) {
            if let parent = current.parent {
                Button(action: { appState.currentScreen = parent }) {
                    HStack(spacing: 2) {
                        Image(systemName: "chevron.left")
                            .font(.caption)
                        Text(parent.displayName)
                            .font(.caption)
                    }
                    .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)

                Text("›")
                    .font(.caption)
                    .foregroundColor(.quaternary)
            }

            Text(current.displayName)
                .font(.headline)

            Spacer()

            if let trailing = trailing {
                trailing()
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }
}
```

**Step 2: 각 하위 화면의 기존 헤더를 BreadcrumbView로 교체**

각 뷰의 기존 `HStack { Button("뒤로") ... Text("제목") ... }` 패턴을 `BreadcrumbView(current: .화면이름)` 으로 교체. trailing 파라미터로 기존 우측 버튼(+ 등) 유지.

**Step 3: 빌드 확인**

Run: `cd ~/Developer/DotBrain && swift build 2>&1 | tail -5`

**Step 4: Commit**

```bash
git add Sources/UI/Components/BreadcrumbView.swift Sources/UI/DashboardView.swift \
      Sources/UI/PARAManageView.swift Sources/UI/SearchView.swift Sources/UI/ProjectManageView.swift
git commit -m "feat: add breadcrumb navigation to all sub-screens"
```

---

## Phase 2: 온보딩 재설계

### Task 4: 온보딩 Step 1 — 동기부여 (Before/After)

**Files:**
- Modify: `Sources/UI/OnboardingView.swift` — welcomeStep 교체 (현재 step 0)

**Step 1: 기존 welcomeStep을 Before/After 비교로 교체**

현재: PARA 개념을 텍스트로 설명하는 welcomeStep
변경: Before/After 시각화 + "파일을 던지면, AI가 알아서 정리합니다" 핵심 메시지

Before 영역: 산재한 파일명 목록 시각화 (회색 배경, 기울어진 파일 아이콘들)
```
회의록_최종_진짜최종.pdf
보고서(2).docx
스크린샷 2026-01-15.png
이름없는문서.txt
```

After 영역: 깔끔한 폴더 트리 시각화 (초록 배경)
```
📁 Project/마케팅 캠페인/
    회의록.pdf
📁 Resource/
    보고서.docx
```

하단: "파일을 던지면, AI가 알아서 정리합니다" 한 문장.

**Step 2: 빌드 확인**

Run: `cd ~/Developer/DotBrain && swift build 2>&1 | tail -5`

**Step 3: Commit**

```bash
git add Sources/UI/OnboardingView.swift
git commit -m "feat: redesign onboarding step 1 with before/after visualization"
```

---

### Task 5: 온보딩 Step 2 — 폴더 설정 + PARA 설명 + 라이브 프리뷰

**Files:**
- Modify: `Sources/UI/OnboardingView.swift` — folderStep 교체 (현재 step 1)

**Step 1: 폴더 선택 + PARA 설명 + 라이브 프리뷰 트리 결합**

상단: 폴더 선택 버튼 (기존 유지)

중단: PARA 4개 폴더를 일상 비유로 설명
```
📁 Project — 책상 위   "진행 중인 일. 마감이 있는 것"
📁 Area    — 서랍     "늘 관리하는 것. 건강, 재무, 팀 운영"
📁 Resource — 책장    "참고 자료. 가이드, 레퍼런스"
📁 Archive  — 창고    "끝난 것. 완료된 프로젝트"
```

하단: 폴더 선택 시 라이브 프리뷰 — 선택한 경로 아래에 생성될 폴더 구조를 트리로 표시

```swift
// 라이브 프리뷰 예시
private func folderPreview(root: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
        Text(root).font(.caption).foregroundColor(.secondary)
        ForEach(["1_Project", "2_Area", "3_Resource", "4_Archive"], id: \.self) { folder in
            HStack(spacing: 4) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentColor)
                    .font(.caption2)
                Text(folder).font(.caption).monospaced()
            }
            .padding(.leading, 16)
        }
    }
    .padding(12)
    .background(Color.primary.opacity(0.03))
    .cornerRadius(8)
}
```

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add Sources/UI/OnboardingView.swift
git commit -m "feat: redesign onboarding step 2 with PARA explanation and live preview"
```

---

### Task 6: 온보딩 Step 3 — 프로젝트 등록 강화

**Files:**
- Modify: `Sources/UI/OnboardingView.swift` — projectStep 교체 (현재 step 2)

**Step 1: 프로젝트 등록 UX 개선**

핵심 변경:
- 상단 안내: "지금 진행 중인 일에 이름을 붙여주세요"
- 예시 플레이스홀더: "예: 2026 마케팅 캠페인, 신규 서비스 런칭"
- **핵심 안내 박스** (파란 배경): "AI는 여기 등록된 프로젝트 안에서만 파일을 분류합니다. 새 프로젝트가 필요하면 언제든 추가할 수 있습니다."
- 최소 1개 필수 유지
- 기존 프로젝트 목록 + 삭제 기능 유지

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add Sources/UI/OnboardingView.swift
git commit -m "feat: redesign onboarding step 3 with project guidance"
```

---

### Task 7: 온보딩 Step 4 — AI 연결 + Claude Code 안내

**Files:**
- Modify: `Sources/UI/OnboardingView.swift` — providerAndKeyStep 교체 (현재 step 3)

**Step 1: API 키 설정 개선**

핵심 변경:
- 상단 설명: "AI가 파일을 읽고 분류합니다. API 키가 필요합니다."
- API 키 발급 링크 버튼 추가 (Claude: console.anthropic.com, Gemini: aistudio.google.com)
- 키 입력 후 즉시 연결 테스트 실행 + 성공/실패 피드백 (기존 APIKeyInputView 활용)
- **새로운 안내 박스** (회색 배경): "API 키 없이도, 만들어진 폴더에 Claude Code를 연결해서 사용할 수 있습니다."
- "건너뛰기" 버튼 추가 (API 키 없이 다음 단계로)

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add Sources/UI/OnboardingView.swift
git commit -m "feat: redesign onboarding step 4 with API test and Claude Code note"
```

---

### Task 8: 온보딩 Step 5 — 첫 파일 체험 (NEW)

**Files:**
- Modify: `Sources/UI/OnboardingView.swift` — step 4 추가 (5단계로 확장)
- Modify: `Sources/App/AppState.swift` — 온보딩 완료 조건 변경 (step 3 → step 4)

**Step 1: step enum 확장 (0-4)**

기존 `step` 범위: 0-3 → 0-4로 확장. stepIndicator도 5개로.

**Step 2: 체험 단계 구현**

API 키가 있는 경우:
- 드래그 & 드롭 영역 표시 + "첫 파일을 넣어보세요!" 안내
- 파일 1~2개 드롭 → 실제 InboxProcessor 호출 → 결과 인라인 표시
- "정리 완료! 이제 시작할 준비가 되었습니다" 메시지

API 키가 없는 경우 (건너뛴 경우):
- "설정에서 API 키를 입력하면 AI 자동 분류를 사용할 수 있습니다" 안내
- "시작하기" 버튼만 표시

**Step 3: 온보딩 완료 조건 변경**

`completeOnboarding()` 호출을 step 4 완료 시로 변경.

**Step 4: 빌드 확인**

**Step 5: Commit**

```bash
git add Sources/UI/OnboardingView.swift Sources/App/AppState.swift
git commit -m "feat: add onboarding step 5 with first-file trial experience"
```

---

## Phase 3: 처리 흐름 개선

### Task 9: ProcessingView — 파일 카운터 + 현재 파일 표시

**Files:**
- Modify: `Sources/UI/ProcessingView.swift` (82줄)
- Modify: `Sources/App/AppState.swift` — 처리 상태 프로퍼티 추가

**Step 1: AppState에 처리 중 파일 정보 추가**

```swift
@Published var processingCurrentFile: String = ""     // 현재 처리 중 파일명
@Published var processingCompletedCount: Int = 0       // 완료 수
@Published var processingTotalCount: Int = 0           // 전체 수
```

이 값은 InboxProcessor/FolderReorganizer의 onProgress 콜백에서 갱신.

**Step 2: ProcessingView 재설계**

```swift
VStack(spacing: 16) {
    Spacer()

    Text(originTitle)
        .font(.headline)

    // 카운터 (큰 숫자)
    HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text("\(appState.processingCompletedCount)")
            .font(.title)
            .fontWeight(.bold)
            .monospacedDigit()
        Text("/")
            .font(.title3)
            .foregroundColor(.secondary)
        Text("\(appState.processingTotalCount)")
            .font(.title3)
            .foregroundColor(.secondary)
            .monospacedDigit()
    }

    // 프로그레스 바
    ProgressView(value: appState.processingProgress)
        .progressViewStyle(.linear)
        .padding(.horizontal, 40)

    // 현재 처리 중 파일
    if !appState.processingCurrentFile.isEmpty {
        HStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text(appState.processingCurrentFile)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 40)
    }

    Spacer()

    Button("취소") { appState.cancelProcessing() }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .padding(.bottom, 4)
}
```

**Step 3: InboxProcessor의 onProgress에서 현재 파일명 전달**

기존 `onProgress?(progress, statusMessage)` 콜백에서 현재 파일명과 카운트 정보를 AppState에 직접 설정하도록 수정. 기존 Classifier의 `onProgress` 인터페이스를 변경하지 않고, AppState 프로퍼티를 별도로 업데이트.

**Step 4: 빌드 확인**

**Step 5: Commit**

```bash
git add Sources/UI/ProcessingView.swift Sources/App/AppState.swift \
      Sources/Pipeline/InboxProcessor.swift Sources/Pipeline/FolderReorganizer.swift
git commit -m "feat: show file counter and current file in processing view"
```

---

### Task 10: ResultsView — 용어 교체 및 확인 UX 개선

**Files:**
- Modify: `Sources/UI/ResultsView.swift` (766줄)

**Step 1: ResultRow 용어 교체 (라인 125-258)**

| 현재 | 변경 |
|------|------|
| `"relocated"` 상태 텍스트 | "더 적합한 위치로 옮겨짐" |
| confidence 수치 표시 | 제거 (낮을 때만 확인 요청으로) |
| PARA 경로 표시 `"project/MyApp"` | "MyApp 프로젝트로 정리됨" |

**Step 2: ConfirmationRow 문구 개선 (라인 261-413)**

| 현재 | 변경 |
|------|------|
| unmatchedProject 메시지 | "등록된 프로젝트에 맞는 곳이 없습니다. 새 프로젝트를 만드시겠습니까?" |
| 일반 확인 메시지 | "이 파일이 어디에 들어갈지 모르겠어요. 골라주세요" |

**Step 3: ResultsSummaryCard 문구 개선 (라인 417-507)**

"태그, 요약, 관련 노트 링크가 적용되었습니다" → "태그와 요약이 자동으로 추가되었습니다"

**Step 4: 빌드 확인**

**Step 5: Commit**

```bash
git add Sources/UI/ResultsView.swift
git commit -m "feat: replace technical terms with user-friendly language in results"
```

---

### Task 11: InboxStatusView — 파일 미리보기 썸네일 + 예상 시간

**Files:**
- Modify: `Sources/UI/InboxStatusView.swift` (273줄)
- Create: `Sources/UI/Components/FileThumbnailView.swift`

**Step 1: FileThumbnailView 컴포넌트 생성**

QuickLookThumbnailing 프레임워크 사용하여 파일 썸네일 생성.

```swift
import SwiftUI
import QuickLookThumbnailing

struct FileThumbnailView: View {
    let url: URL
    @State private var thumbnail: NSImage?

    var body: some View {
        Group {
            if let thumbnail {
                Image(nsImage: thumbnail)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Image(systemName: iconForExtension(url.pathExtension))
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .task { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = QLThumbnailGenerator.Request(
            fileAt: url, size: CGSize(width: 80, height: 80),
            scale: 2.0, representationTypes: .thumbnail
        )
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            thumbnail = rep.nsImage
        }
    }

    private func iconForExtension(_ ext: String) -> String {
        switch ext.lowercased() {
        case "pdf": return "doc.richtext"
        case "docx", "doc": return "doc.text"
        case "pptx", "ppt": return "doc.text.image"
        case "xlsx", "xls": return "tablecells"
        case "png", "jpg", "jpeg", "gif": return "photo"
        default: return "doc"
        }
    }
}
```

**Step 2: InboxStatusView에 파일 목록 + 썸네일 + 예상 시간 추가**

파일이 있을 때 (Active State):
- 기존 트레이 아이콘 대신 파일 목록 (최대 5개 표시 + "외 N개")
- 각 파일에 FileThumbnailView + 파일명
- 예상 시간: `"N개 파일, 약 \(estimatedSeconds)초"` (파일당 ~3초 기준)
- "정리하기" 버튼 더 크게, .borderedProminent 스타일

**Step 3: 빌드 확인**

**Step 4: Commit**

```bash
git add Sources/UI/InboxStatusView.swift Sources/UI/Components/FileThumbnailView.swift
git commit -m "feat: add file thumbnails and estimated time to inbox view"
```

---

## Phase 4: 대시보드 & 볼트 관리 재편

### Task 12: 대시보드를 허브로 재설계

**Files:**
- Modify: `Sources/UI/DashboardView.swift` (524줄)

**Step 1: 대시보드를 카드 기반 허브로 변경**

현재: 통계 + 인라인 실행 기능이 혼재
변경: 통계 요약 + 하위 기능으로의 진입 카드

```
[통계 요약: 전체 N개 파일 | Project N | Area N | Resource N | Archive N]

[📁 PARA 관리]        [📂 프로젝트 관리]
 폴더 이동, 생성        프로젝트 추가/아카이브

[🔍 검색]             [🔧 볼트 관리]
 파일, 태그 검색        오류 검사, 정리, 보완

[최근 활동 — 최근 5개]
```

- 기존 인라인 실행 기능(오류 검사, 태그 보완, MOC 갱신)은 볼트 관리로 이동
- CategoryBar 차트 → 한 줄 요약으로 간소화
- 최근 활동은 5개로 축소 (더보기 링크)

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add Sources/UI/DashboardView.swift
git commit -m "refactor: redesign dashboard as hub with entry cards"
```

---

### Task 13: VaultManageView 생성 — 유지보수 기능 통합

**Files:**
- Create: `Sources/UI/VaultManageView.swift`
- Modify: `Sources/UI/MenuBarPopover.swift` — vaultManage case 추가
- Modify: `Sources/UI/DashboardView.swift` — 기존 인라인 기능 코드 제거 (Task 12에서 이미 제거)

**Step 1: VaultManageView 생성**

DashboardView에 있던 인라인 기능을 독립 화면으로 이동:

```
BreadcrumbView(current: .vaultManage)

ScrollView {
    [오류 검사]
    깨진 링크, 프론트매터 누락, 태그 없음, PARA 미지정
    "검사 시작" → 결과 인라인 → "자동 복구"

    [태그·요약 보완]
    AI로 비어있는 메타데이터 채우기
    "보완 시작" → 진행률 → 완료

    [폴더 요약 업데이트]  (기존 "MOC 갱신")
    각 폴더 인덱스 노트 재생성

    [전체 재정리]
    볼트 전체 AI 점검 → VaultReorganizeView로 이동

    [폴더별 정리]
    특정 폴더 선택 후 정리 → ReorganizeView로 이동
}
```

**Step 2: MenuBarPopover에 case 추가**

```swift
case .vaultManage: VaultManageView()
```

**Step 3: 빌드 확인**

**Step 4: Commit**

```bash
git add Sources/UI/VaultManageView.swift Sources/UI/MenuBarPopover.swift
git commit -m "feat: create VaultManageView consolidating maintenance features"
```

---

### Task 14: SettingsView에 도움말 + 종료 추가

**Files:**
- Modify: `Sources/UI/SettingsView.swift` (156줄)

**Step 1: 설정 하단에 도움말 링크 + 앱 종료 추가**

기존 푸터에서 제거된 도움말과 종료를 설정 화면 하단에 배치.

```swift
Divider()

// 도움말
Button(action: {
    NSWorkspace.shared.open(URL(string: "https://github.com/DinN0000/DotBrain")!)
}) {
    HStack {
        Image(systemName: "questionmark.circle")
        Text("도움말 및 문의")
        Spacer()
        Image(systemName: "arrow.up.right")
            .font(.caption)
            .foregroundColor(.secondary)
    }
}
.buttonStyle(.plain)

// 앱 종료
Button(action: { NSApplication.shared.terminate(nil) }) {
    HStack {
        Image(systemName: "power")
        Text("DotBrain 종료")
        Spacer()
    }
    .foregroundColor(.red)
}
.buttonStyle(.plain)
```

**Step 2: 빌드 확인**

**Step 3: Commit**

```bash
git add Sources/UI/SettingsView.swift
git commit -m "feat: move help and quit to settings view"
```

---

## Phase 5: 최종 점검

### Task 15: 전체 빌드 + 화면 전환 흐름 검증

**Files:** (읽기 전용 검증)

**Step 1: 전체 빌드**

Run: `cd ~/Developer/DotBrain && swift build 2>&1 | tail -10`

**Step 2: 미사용 코드 정리**

- DashboardView에서 VaultManageView로 옮긴 후 남은 데드코드 확인
- 기존 footer 관련 미사용 코드 제거

**Step 3: 빌드 확인**

**Step 4: Commit**

```bash
git add -A
git commit -m "chore: clean up dead code after UX restructuring"
```

---

## Task 의존성

```
Phase 1 (기반)
  Task 1 (Screen enum) ──┬── Task 2 (Footer)
                         └── Task 3 (Breadcrumb)

Phase 2 (온보딩) — Phase 1 완료 후
  Task 4 → Task 5 → Task 6 → Task 7 → Task 8 (순차)

Phase 3 (처리 흐름) — Phase 1 완료 후, Phase 2와 병렬 가능
  Task 9 (ProcessingView)
  Task 10 (ResultsView 용어)
  Task 11 (InboxStatusView 썸네일)

Phase 4 (대시보드) — Phase 1 완료 후
  Task 12 (Dashboard 허브) → Task 13 (VaultManageView)
  Task 14 (Settings에 도움말/종료)

Phase 5 (점검) — 모든 Phase 완료 후
  Task 15 (빌드 + 정리)
```

## 병렬 가능한 작업

- Phase 2 (온보딩)와 Phase 3 (처리 흐름)과 Phase 4 (대시보드)는 서로 독립적이므로 병렬 진행 가능
- 단, 모두 Phase 1 완료가 전제
