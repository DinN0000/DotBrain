# DotBrain 온보딩 개선 설계

## 개요

첫 실행 사용자를 위한 스텝 위저드 온보딩, 코치마크 튜토리얼, 빈 상태 UI 개선, PARA 자동생성, 미사용 코드 정리를 포함하는 온보딩 전면 개선.

## 변경 범위

### 1. 온보딩 위저드 (새 파일)

**파일:** `Sources/UI/OnboardingView.swift`

3단계 스텝 위저드. 상단에 진행 표시기(● ● ○). 360×480 팝오버 내에서 동작.

**Step 1: 환영 + PARA 소개**
- "DotBrain에 오신 걸 환영합니다" 타이틀
- PARA 방법론 간단 소개: Project/Area/Resource/Archive 각각 아이콘 + 한줄 설명
- [시작하기] 버튼

**Step 2: API 키 설정**
- Claude API 키 입력 SecureField (`APIKeyInputView` 컴포넌트 재사용)
- Keychain 저장 + `sk-ant-` prefix 검증
- 비용 안내 인라인 표시 (Haiku ~$0.002/파일, Sonnet ~$0.01/파일)
- [다음] 버튼 — 키 저장 완료 시에만 활성화

**Step 3: PKM 폴더 설정**
- 경로 선택 (기본값 `~/Documents/DotBrain` 표시)
- PARA 구조 없으면 → [폴더 구조 만들기] 버튼 (자동생성)
- 구조 확인됨 녹색 체크 표시
- [완료] 버튼 → `onboardingCompleted = true` 저장, `.inbox`로 전환

### 2. 코치마크 튜토리얼 (새 파일)

**파일:** `Sources/UI/CoachMarkOverlay.swift`

온보딩 완료 후 인박스 첫 진입 시 1회 표시. `UserDefaults`에 `hasSeenCoachMarks` 플래그.

3단계 순차 말풍선 오버레이:

1. **드래그 영역 하이라이트** — "파일을 여기로 드래그하거나 ⌘V로 붙여넣기하세요"
2. **정리하기 버튼 하이라이트** — "파일을 추가한 후 이 버튼을 누르면 AI가 자동 분류합니다"
3. **설정 버튼 하이라이트** — "여기서 언제든 API 키와 폴더 경로를 변경할 수 있어요"

각 단계에서 해당 영역만 밝게, 나머지 반투명 어둡게. [다음] 클릭으로 진행. 하단에 [건너뛰기] 링크.

### 3. 빈 상태 UI 개선 (기존 파일 수정)

**파일:** `Sources/UI/InboxStatusView.swift`

파일 0개일 때 표시되는 빈 상태 개선:

- SF Symbol `arrow.down.doc` 크게 표시
- "파일을 드래그하거나 ⌘V로 붙여넣기" 안내 텍스트
- idle 상태에서 아이콘 부드러운 bounce 애니메이션
- 파일 존재 시 기존 파일 카운트 + 정리하기 버튼 UI로 전환 (기존 로직 유지)

### 4. PARA 폴더 자동생성 (기존 파일 수정)

**파일:** `Sources/Services/FileSystem/PKMPathManager.swift`

`initializeStructure()` 메서드 추가:

```swift
func initializeStructure() throws {
    let folders = ["_Inbox", "1_Project", "2_Area", "3_Resource", "4_Archive"]
    for folder in folders {
        let path = rootPath + "/" + folder
        try FileManager.default.createDirectory(
            atPath: path, withIntermediateDirectories: true
        )
    }
}
```

호출 위치:
- 온보딩 Step 3의 [폴더 구조 만들기] 버튼
- `SettingsView`에서 PARA 구조 없을 때 동일 버튼 추가

### 5. AppState 변경 (기존 파일 수정)

**파일:** `Sources/App/AppState.swift`

Screen enum에 `.onboarding` 추가:

```swift
enum Screen {
    case onboarding
    case inbox
    case processing
    case results
    case settings
}
```

초기화 로직 변경:

```swift
init() {
    if !UserDefaults.standard.bool(forKey: "onboardingCompleted") {
        currentScreen = .onboarding
    } else if !hasAPIKey {
        currentScreen = .settings
    } else {
        currentScreen = .inbox
    }
}
```

### 6. API 키 입력 컴포넌트 분리 (새 파일)

**파일:** `Sources/UI/Components/APIKeyInputView.swift`

기존 `SettingsView`의 API 키 입력 섹션을 재사용 가능한 SwiftUI View로 분리. 온보딩 Step 2와 SettingsView 양쪽에서 사용.

### 7. MenuBarPopover 라우팅 추가 (기존 파일 수정)

**파일:** `Sources/UI/MenuBarPopover.swift`

switch문에 `.onboarding` 케이스 추가:

```swift
case .onboarding:
    OnboardingView()
```

### 8. 코드 정리 (삭제)

- `Sources/UI/ClassificationConfirmView.swift` 삭제
- 관련 참조 제거 (있을 경우)

## 파일 변경 요약

| 작업 | 파일 | 유형 |
|------|------|------|
| OnboardingView | `Sources/UI/OnboardingView.swift` | 신규 |
| CoachMarkOverlay | `Sources/UI/CoachMarkOverlay.swift` | 신규 |
| APIKeyInputView | `Sources/UI/Components/APIKeyInputView.swift` | 신규 |
| AppState | `Sources/App/AppState.swift` | 수정 |
| MenuBarPopover | `Sources/UI/MenuBarPopover.swift` | 수정 |
| InboxStatusView | `Sources/UI/InboxStatusView.swift` | 수정 |
| PKMPathManager | `Sources/Services/FileSystem/PKMPathManager.swift` | 수정 |
| SettingsView | `Sources/UI/SettingsView.swift` | 수정 |
| ClassificationConfirmView | `Sources/UI/ClassificationConfirmView.swift` | 삭제 |

## UserDefaults 키 추가

- `onboardingCompleted: Bool` — 온보딩 완료 여부
- `hasSeenCoachMarks: Bool` — 코치마크 표시 여부
