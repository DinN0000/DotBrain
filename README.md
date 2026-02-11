<p align="center">
  <img src="Resources/app-icon.png" width="128" alt="AI-PKM MenuBar Icon">
</p>

# AI-PKM MenuBar

### Built for Humans. Optimized for AI.

파일을 던지면 AI가 알아서 정리합니다. 당신은 생각에 집중하세요.

```
·‿·  →  ·_·!  →  ·_·…  →  ^‿^
대기      파일있음    처리중     완료
```

---

## 왜 만들었나

지식 관리의 병목은 **정리**입니다.

메모를 쓰고, 자료를 모으고, 문서를 만드는 건 쉽습니다. 하지만 그걸 체계적으로 분류하고, 태그를 달고, 적절한 위치에 놓는 건 별개의 노동입니다. PARA 방법론(Projects, Areas, Resources, Archive)이 좋은 프레임워크라는 건 알지만, 매번 수동으로 분류하다 보면 결국 인박스에 파일이 쌓이기만 합니다.

**AI-PKM MenuBar**는 이 정리 과정을 AI에게 맡깁니다:

- **파일을 인박스에 드롭하면** AI가 내용을 읽고, PARA 분류하고, 적절한 폴더로 이동
- **프론트매터**를 자동 생성하여 Obsidian 위키링크와 완벽 호환
- **기존 폴더도 재정리** — 중첩된 계층을 플랫화하고, 잘못된 분류를 찾아내고, 오래된 메타데이터를 최신 규격으로 교체
- **중복 파일**은 SHA256 해시로 감지하여 태그 병합 후 정리
- **Claude + Gemini 이중 제공자** — 한쪽이 실패하면 자동 폴백

당신이 할 일은 파일을 메뉴바에 던지는 것뿐입니다. 나머지는 AI가 합니다.

---

## 동작 방식

### 1. 인박스 처리 파이프라인

```
_Inbox/에 파일 추가 (드래그앤드롭 / Cmd+V)
    ↓
InboxScanner — 파일 목록 수집 (시스템 파일 필터, 심볼릭 링크 검증)
    ↓
ProjectContextBuilder — 기존 프로젝트/폴더 구조를 AI 컨텍스트로 변환
    ↓
내용 추출 — 텍스트/PDF/이미지/PPTX/XLSX/DOCX 각각 전용 추출기
    ↓
2단계 AI 분류
    ├── Stage 1: Fast (Haiku/Flash) — 배치 분류, 신뢰도 산출
    └── Stage 2: Precise (Sonnet/Pro) — 신뢰도 < 0.8인 파일만 재분류
    ↓
충돌 검사
    ├── 신뢰도 < 0.5 → 사용자에게 확인 요청
    ├── 인덱스 노트 이름 충돌 → 확인 요청
    └── 동명 파일 존재 → 확인 요청
    ↓
FileMover — 파일 이동 + 프론트매터 교체 + 중복 감지
    ├── 텍스트: 기존 frontmatter 완전 교체 → AI-PKM 규격 주입
    ├── 바이너리: _Assets/로 이동 + 동반 마크다운 생성
    └── 폴더: 통째로 이동 + [[위키링크]] 인덱스 노트 생성
    ↓
결과 화면 — 성공/건너뜀/삭제/중복/오류별 상태 표시
```

### 2. 폴더 재정리

기존 PARA 폴더를 AI가 다시 정리합니다. 외부에서 가져온 복잡한 폴더 구조도 처리합니다:

```
폴더 선택 (Project/Area/Resource/Archive 전체)
    ↓
플랫화 — 중첩된 하위 폴더에서 콘텐츠 파일을 최상위로 이동
    ├── placeholder 파일 삭제 (폴더명.md, _접두사 파일)
    └── 빈 디렉토리 정리
    ↓
중복 제거 — 같은 폴더 내 동일 내용 파일 병합
    ↓
AI 재분류 — 현재 위치가 맞는지 판단
    ├── 위치 맞음 → 기존 frontmatter 교체 (AI-PKM 규격으로)
    └── 위치 틀림 → 사용자에게 이동 제안
```

**예시:** Obsidian vault에서 가져온 `DOJANG/DOJANG/1_Project/Shinhan_Bank_DeFi/` 같은 4단계 중첩 구조를 → `DOJANG/` 아래 플랫한 파일들로 정리하고, 오래된 `level`, `workspace`, `parent` 같은 메타데이터를 AI-PKM 표준 frontmatter로 교체합니다.

### 3. AI 분류 전략

**Stage 1 (Fast Model)** — 파일당 ~$0.002
- 파일명 + 200자 미리보기로 빠르게 분류
- 배치 처리 (10개씩)
- 신뢰도 0.0~1.0 산출

**Stage 2 (Precise Model)** — 파일당 ~$0.01
- 전체 내용으로 정밀 분류
- Stage 1에서 신뢰도 < 0.8인 파일만
- 기존 프로젝트/폴더 컨텍스트 활용

**분류 기준:**
| 카테고리 | 기준 | 예시 |
|----------|------|------|
| Project | 진행 중인 작업, 마감일, 체크리스트 | 프로젝트 기획서, TODO |
| Area | 지속 관리 영역, 운영, 모니터링 | 건강관리, 재무, DevOps |
| Resource | 참고 자료, 가이드, 학습 | 튜토리얼, API 문서 |
| Archive | 완료/비활성, 더 이상 안 쓰는 것 | 지난 분기 보고서 |

---

## Frontmatter 규격

AI-PKM이 생성하고 관리하는 프론트매터 표준:

```yaml
---
para: project
tags: [defi, shinhan, blockchain]
created: 2026-02-11
status: active
summary: "신한은행 DeFi 시스템 구축 프로젝트"
source: import
project: DOJANG
---
```

| 필드 | 설명 |
|------|------|
| `para` | PARA 카테고리 (project/area/resource/archive) |
| `tags` | AI가 내용 기반으로 생성한 태그 |
| `created` | 최초 생성일 (기존 값 보존) |
| `status` | active / draft / completed / on-hold |
| `summary` | AI가 생성한 한줄 요약 |
| `source` | original / meeting / literature / import |
| `project` | 연관 프로젝트명 |

**기존 파일의 frontmatter는 완전히 교체됩니다.** `level`, `workspace`, `parent`, `type` 같은 다른 시스템의 메타데이터는 제거되고 위 규격으로 통일됩니다. `created` 날짜만 보존합니다.

---

## 폴더 구조

```
PKM Root/
├── _Inbox/                          ← 여기에 파일을 넣으면
├── 1_Project/
│   └── MyProject/
│       ├── MyProject.md             ← 인덱스 노트 (자동 생성)
│       ├── plan.md
│       └── _Assets/
│           └── diagram.png
├── 2_Area/
│   └── DevOps/
│       ├── DevOps.md
│       └── monitoring-guide.md
├── 3_Resource/
│   └── Python/
│       ├── Python.md
│       └── asyncio-patterns.md
└── 4_Archive/
    └── 2024-Q1/
        └── quarterly-report.md
```

---

## 지원 파일 형식

| 형식 | 추출 방식 | 추출 내용 |
|------|-----------|-----------|
| `.md`, `.txt` 등 | 직접 읽기 | 전체 텍스트 (5000자) |
| `.pdf` | PDFKit | 텍스트 + 페이지수/저자/제목 |
| `.docx` | ZIPFoundation + XML | 본문 텍스트 + 메타데이터 |
| `.pptx` | ZIPFoundation + XML | 슬라이드 텍스트 |
| `.xlsx` | ZIPFoundation + XML | 셀 데이터 |
| `.jpg`, `.png`, `.heic` 등 | ImageIO | EXIF (촬영일, 카메라, GPS) |
| 폴더 | 내부 파일 순회 | 포함 파일 내용 종합 |

## 중복 감지

| 상황 | 감지 방식 | 처리 |
|------|-----------|------|
| 같은 내용, 다른 이름 | SHA256 본문 해시 (프론트매터 제외) | 태그 병합 → 중복 삭제 |
| 같은 내용 바이너리 | SHA256 전체 파일 해시 | 태그 병합 → 중복 삭제 |
| 같은 이름, 다른 내용 | 파일명 비교 | 사용자에게 확인 요청 |
| 인덱스 노트와 이름 충돌 | `폴더명.md` 비교 | 사용자에게 확인 요청 |

---

## 설치

### 원클릭 설치 (권장)

```bash
curl -sL https://raw.githubusercontent.com/DinN0000/AI-PKM-Bar/main/install.sh | bash
```

이 한 줄로 끝입니다:
- `~/Applications/AI-PKM-MenuBar`에 바이너리 설치
- 로그인 시 자동 시작 등록 (LaunchAgent)
- 비정상 종료 시 자동 재시작
- 설치 직후 바로 실행

메뉴바에 `·‿·` 아이콘이 나타나면 성공입니다.

### 설치 중 문제가 생기면

<details>
<summary><b>"확인되지 않은 개발자" / "손상되어 열 수 없음" 경고</b></summary>

이 앱은 Apple 코드서명이 없어서 macOS Gatekeeper가 차단할 수 있습니다.
설치 스크립트가 자동으로 처리하지만, 직접 다운로드한 경우:

```bash
xattr -cr ~/Applications/AI-PKM-MenuBar
```

또는: **시스템 설정 → 개인정보 보호 및 보안** → 하단의 "확인 없이 열기" 클릭
</details>

<details>
<summary><b>폴더 접근 권한 팝업</b></summary>

첫 실행 시 PKM 폴더에 접근할 때 macOS가 권한을 물어봅니다.
**"허용"을 눌러주세요** — 이게 없으면 파일을 읽거나 이동할 수 없습니다.
</details>

<details>
<summary><b>메뉴바에 아이콘이 안 보임</b></summary>

메뉴바 공간이 부족하면 아이콘이 숨겨질 수 있습니다.
메뉴바 왼쪽의 다른 아이콘을 ⌘+드래그로 제거하거나, Bartender/Ice 같은 앱으로 정리하세요.
</details>

### 제거

```bash
pkill -f AI-PKM-MenuBar 2>/dev/null; \
launchctl bootout gui/$(id -u)/com.ai-pkm.menubar 2>/dev/null; \
rm -f ~/Library/LaunchAgents/com.ai-pkm.menubar.plist; \
rm -f ~/Applications/AI-PKM-MenuBar; \
echo "제거 완료"
```

### 소스에서 직접 빌드

```bash
git clone https://github.com/DinN0000/AI-PKM-Bar.git
cd AI-PKM-Bar
swift build -c release
# 바이너리: .build/release/AI-PKM-MenuBar
```

### 요구사항
- macOS 13+
- API 키: [Anthropic Claude](https://console.anthropic.com/settings/keys) 또는 [Google Gemini](https://aistudio.google.com/apikey) (하나만 있어도 동작)

### 초기 설정
1. 앱 실행 → 메뉴바의 `·‿·` 클릭 → 온보딩 시작
2. AI 제공자 선택 (Gemini / Claude) → API 키 입력
3. PKM 폴더 경로 선택 → PARA 구조 자동 생성
4. `_Inbox/`에 파일 드롭 → 끝

---

## 기술 스택

- **Swift 5.9** + SwiftUI + Combine
- **macOS 메뉴바 앱** — `NSStatusItem` + `NSPopover`
- **AI** — Claude (Haiku 4.5 + Sonnet 4.5) / Gemini (Flash + Pro) — 이중 제공자 + 자동 폴백
- **의존성** — ZIPFoundation (DOCX/PPTX/XLSX 처리)
- **보안** — API 키는 macOS Keychain에 저장 (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- **상태관리** — `AppState` 싱글턴, `@Published` + `@EnvironmentObject`
- **안정성** — 지수 백오프 재시도, 제공자 폴백, 경로 탐색 보호, TOCTOU 완화

## 비용

| 제공자 | Fast 모델 | Precise 모델 | 파일당 비용 |
|--------|-----------|--------------|-------------|
| Claude | Haiku 4.5 | Sonnet 4.5 | ~$0.002 / ~$0.01 |
| Gemini | Flash | Pro | 무료 티어 가능 |

대부분의 파일은 Fast 모델만으로 처리됩니다. 100개 파일 기준 Claude ~$0.20~0.30, Gemini는 무료 티어 내에서 가능합니다.
