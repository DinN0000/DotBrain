<p align="center">
  <img src="Resources/app-icon.png" width="128" alt="DotBrain Icon">
</p>

# DotBrain

### Built for Humans. Optimized for AI.

파일을 던지면 AI가 알아서 정리합니다. 당신은 생각에 집중하세요.

```
·‿·  →  ·_·!  →  ·_·…  →  ^‿^
대기      파일있음    처리중     완료
```

---

## 이게 뭔가요

지식 관리의 병목은 **정리**입니다.

메모를 쓰고, 자료를 모으고, 문서를 만드는 건 쉽습니다. 하지만 체계적으로 분류하고, 태그를 달고, 적절한 위치에 놓는 건 별개의 노동입니다. PARA 방법론이 좋은 프레임워크라는 건 알지만, 매번 수동으로 분류하다 보면 결국 인박스에 파일이 쌓이기만 합니다.

DotBrain은 이 정리를 AI에게 맡깁니다:

- **인박스에 드롭** → AI가 내용을 읽고, PARA 분류하고, 폴더로 이동
- **프론트매터 자동 생성** → Obsidian 위키링크 호환
- **기존 폴더 재정리** → 중첩 구조 플랫화, 잘못된 분류 교정, 메타데이터 교체
- **중복 감지** → SHA256 해시로 동일 파일 병합
- **Claude + Gemini** → 이중 제공자, 자동 폴백

---

## Quick Start

```bash
curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash
```

메뉴바에 `·‿·` 가 나타나면 설치 완료. 클릭하면 단계별 온보딩이 시작됩니다.

> **필요한 것:** macOS 13+ / [Gemini API 키](https://aistudio.google.com/apikey) 또는 [Claude API 키](https://console.anthropic.com/settings/keys) 하나

<details>
<summary><b>소스에서 직접 빌드</b></summary>

```bash
# PKM 데이터 폴더(~/Documents/DotBrain)와 겹치지 않도록 별도 경로에 클론
git clone https://github.com/DinN0000/DotBrain.git ~/Developer/DotBrain
cd ~/Developer/DotBrain
swift build -c release
# 바이너리: .build/release/DotBrain
```
</details>

---

## 동작 방식

### 인박스 처리

```
_Inbox/에 파일 추가 (드래그앤드롭 / Cmd+V)
    ↓
파일 스캔 + 기존 프로젝트 컨텍스트 로드
    ↓
내용 추출 (텍스트/PDF/이미지/PPTX/XLSX/DOCX)
    ↓
2단계 AI 분류
    ├── Stage 1: Fast (Haiku/Flash) — 배치 분류
    └── Stage 2: Precise (Sonnet/Pro) — 신뢰도 낮은 파일만
    ↓
파일 이동 + 프론트매터 주입 + 중복 감지
    ↓
결과 화면
```

### 폴더 재정리

기존 PARA 폴더를 AI가 다시 정리합니다:

```
폴더 선택
    ↓
플랫화 — 중첩 하위 폴더에서 콘텐츠를 최상위로 이동
    ↓
중복 제거 — 동일 내용 파일 태그 병합 후 삭제
    ↓
AI 재분류
    ├── 위치 맞음 → frontmatter 교체 (DotBrain 규격)
    └── 위치 틀림 → 사용자에게 이동 제안
```

### AI 분류 전략

| 단계 | 모델 | 비용 | 방식 |
|------|------|------|------|
| Stage 1 (Fast) | Haiku / Flash | ~$0.002/파일 | 파일명 + 미리보기로 배치 분류 |
| Stage 2 (Precise) | Sonnet / Pro | ~$0.01/파일 | 전체 내용으로 정밀 분류 (신뢰도 < 0.8만) |

대부분의 파일은 Stage 1에서 끝납니다. 100개 파일 기준 Claude ~$0.20, Gemini는 무료 티어 내 가능.

---

## Frontmatter 규격

DotBrain이 생성하고 관리하는 표준:

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

기존 파일의 frontmatter는 완전히 교체됩니다. `created` 날짜만 보존합니다.

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
│       └── monitoring-guide.md
├── 3_Resource/
│   └── Python/
│       └── asyncio-patterns.md
└── 4_Archive/
    └── 2024-Q1/
        └── quarterly-report.md
```

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
| 같은 내용, 다른 이름 | SHA256 본문 해시 (frontmatter 제외) | 태그 병합 → 삭제 |
| 같은 내용 바이너리 | SHA256 전체 파일 해시 | 태그 병합 → 삭제 |
| 같은 이름, 다른 내용 | 파일명 비교 | 사용자에게 확인 |
| 인덱스 노트와 이름 충돌 | `폴더명.md` 비교 | 사용자에게 확인 |

---

## 설치 참고

### 설치 스크립트가 하는 일

- `~/Applications/DotBrain.app` 번들 생성
- 로그인 시 자동 시작 (LaunchAgent)
- 비정상 종료 시 자동 재시작

### 문제 해결

<details>
<summary><b>"확인되지 않은 개발자" / "손상되어 열 수 없음"</b></summary>

Apple 코드서명이 없어서 Gatekeeper가 차단할 수 있습니다. 설치 스크립트가 자동 처리하지만, 직접 다운로드한 경우:

```bash
xattr -cr ~/Applications/DotBrain.app
```

또는: **시스템 설정 → 개인정보 보호 및 보안** → "확인 없이 열기"
</details>

<details>
<summary><b>폴더 접근 권한 팝업</b></summary>

첫 실행 시 PKM 폴더 접근 권한을 물어봅니다. **"허용"** 필수.
</details>

<details>
<summary><b>메뉴바에 아이콘이 안 보임</b></summary>

메뉴바 공간 부족일 수 있습니다. 다른 아이콘을 ⌘+드래그로 제거하거나, Bartender/Ice로 정리하세요.
</details>

### 제거

```bash
pkill -f DotBrain 2>/dev/null; \
launchctl bootout gui/$(id -u)/com.dotbrain.app 2>/dev/null; \
rm -f ~/Library/LaunchAgents/com.dotbrain.app.plist; \
rm -rf ~/Applications/DotBrain.app; \
echo "제거 완료"
```

---

## 기술 스택

- **Swift 5.9** + SwiftUI + Combine
- **macOS 메뉴바 앱** — `NSStatusItem` + `NSPopover`
- **AI** — Claude (Haiku 4.5 + Sonnet 4.5) / Gemini (Flash + Pro) — 이중 제공자, 자동 폴백
- **의존성** — ZIPFoundation (DOCX/PPTX/XLSX 처리)
- **보안** — API 키는 macOS Keychain 저장
- **안정성** — 지수 백오프 재시도, 제공자 폴백, 경로 탐색 보호

---

## Design Philosophy

DotBrain의 모든 설계 결정에는 하나의 질문이 깔려 있습니다:

> **"사람이 쓰기 좋은 것"과 "AI가 다루기 좋은 것"은 왜 항상 따로일까?**

답은 — 따로일 필요가 없다는 것. DotBrain은 그 둘이 같은 것이 될 수 있도록 설계되었습니다.

### Frontmatter as Contract

YAML frontmatter는 사람과 AI 사이의 **계약서**입니다.

사람 쪽에서 보면, Obsidian을 열었을 때 바로 보이고 직접 고칠 수 있는 익숙한 포맷입니다. AI 쪽에서 보면, 파싱 한 번이면 분류·검색·요약에 필요한 모든 정보가 나오는 구조화된 데이터입니다.

핵심 원칙은 이렇습니다: **사람이 언제든 편집할 수 있되, 생성과 관리는 AI가 한다.** 사용자는 메타데이터를 직접 채우는 노동에서 해방되고, AI는 일관된 규격의 데이터를 얻습니다. 서로 양보한 게 아니라, 둘 다 원하는 걸 가져간 겁니다.

### Wiki-links + MOC — 양쪽 모두를 위한 네비게이션

MOC는 **Map of Content**, 쉽게 말해 "이 폴더에 뭐가 있는지 한눈에 보여주는 인덱스 노트"입니다. 예를 들어 `1_Project/DOJANG/` 폴더에 파일이 10개 있으면, DotBrain은 `DOJANG.md`라는 MOC를 자동 생성해서 그 안에 있는 노트들을 `[[위키링크]]`로 정리해둡니다.

`[[위키링크]]`는 Obsidian 사용자에게 클릭 한 번으로 노트 간 점프가 가능한 당연한 기능이죠. 그런데 AI 에이전트 입장에서 보면, 이건 **그래프의 엣지**입니다. MOC는 그래프의 진입점이 되고, 위키링크를 따라가면 관련 노트를 전부 탐색할 수 있습니다.

같은 구조가 사람에게는 **목차**로, AI에게는 **인덱스**로 작동합니다. 별도의 AI 전용 포맷 없이.

### AI Companion Files — 볼트를 AI-ready로

DotBrain은 사용자의 Obsidian 볼트에 `CLAUDE.md`, `AGENTS.md`, `.cursorrules` 같은 파일을 자동으로 생성합니다. 이 파일들이 있으면 Claude Code, Cursor 같은 AI 코딩 도구가 볼트를 열었을 때 **"아, 이 폴더는 이런 구조고, 이런 규칙을 따르는구나"** 를 즉시 이해합니다.

여기서 중요한 건 **업데이트 방식**입니다. `<!-- DotBrain:start -->` / `<!-- DotBrain:end -->` 마커 사이의 내용만 DotBrain이 관리하고, 마커 바깥은 절대 건드리지 않습니다. 사용자가 직접 추가한 커스텀 지시사항이 앱 업데이트 때마다 날아가는 일은 없습니다.

### 분류는 AI가, 구조는 사람이

PARA(Projects, Areas, Resources, Archive) 프레임워크는 사람이 설계한 체계입니다. DotBrain의 AI는 이 체계 **안에서** 파일을 분류할 뿐, 체계 자체를 만들거나 바꾸지 않습니다.

2단계 분류 전략(Fast → Precise)도 같은 철학입니다. 대부분의 파일은 가벼운 모델로 빠르게 분류하고, 정말 애매한 것만 정밀 모델에 보냅니다. "AI가 다 해줄 테니 비싼 모델 쓰세요"가 아니라, **사용자의 비용 감각을 존중하는 설계**입니다.

### 코드 파일 필터링

PKM 폴더에 개발 파일이 섞이면 생기는 문제, 다들 경험해보셨을 겁니다. AI가 `node_modules`를 "리소스"로 분류한다거나, `.gitignore`에 프론트매터를 주입한다거나.

DotBrain은 코드 파일(`.swift`, `.py`, `.js` 등)이 인박스에 들어오면 자동으로 건너뛰고 경고를 띄웁니다. 지식 관리 도구가 개발 환경을 침범하지 않도록, 그리고 그 반대도 일어나지 않도록.
