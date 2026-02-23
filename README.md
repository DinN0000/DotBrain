<p align="center">
  <img src="Resources/app-icon.png" width="128" alt="DotBrain Icon">
</p>

<h1 align="center">DotBrain</h1>

<p align="center">
  <strong>Built for Humans. Optimized for AI.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/DinN0000/DotBrain" alt="License"></a>
  <a href="https://github.com/DinN0000/DotBrain/releases/latest"><img src="https://img.shields.io/github/v/release/DinN0000/DotBrain" alt="Latest Release"></a>
</p>

DotBrain은 로컬 문서를 PARA 방법론에 따라 체계적으로 정리합니다.<br>
이 구조는 사람에게는 직관적인 지식 체계가 되고,

AI에게는 이해할 수 있는 Context를 부여합니다.<br>
Context는 AI의 탐색 기반이 되어, 당신의 지식을 더 깊이 이해하고 사고할 수 있게 합니다.

```
·‿·  →  ·_·!  →  ·_·…  →  ^‿^
               
```

---

## 🧐 What is DotBrain?

지식 관리의 병목은 축적이 아니라 **활용**입니다.<br>
자료는 쉽게 쌓이지만,<br>
찾기 좋게 정리하고 맥락을 연결하는 일은 어렵습니다.

더 어려운 일은,<br>
AI가 이해하고 활용할 수 있는 형태로 그 지식을 구조화하는 것입니다.

**The Problem: Human vs. AI**
- **PARA의 딜레마 (Human Overhead):** PARA 방법론은 사람의 인지 구조에는 훌륭하지만, 매번 수동으로 분류해야 하는 유지보수 비용이 큽니다. 결국 정리는 밀리고 인박스에는 파일만 쌓입니다.
- **AI의 불협화음 (Context Gap):** 정리가 안 된 문서는 AI조차 맥락을 파악하기 어렵습니다. 단순한 파일 저장은 사람과 AI 모두에게 쓸모없는 데이터 덤프가 될 뿐입니다.

**The Solution: DotBrain**
DotBrain은 이 '정리의 병목'을 AI에게 위임합니다.
- **Zero-Friction Sort:** 인박스에 파일을 던지면 AI가 내용을 읽고, PARA 체계에 맞춰 자동으로 이동시킵니다.
- **Semantic Structure:** Obsidian 호환 프론트매터와 위키링크를 자동 생성하여 문서 간의 맥락을 연결합니다.
- **Self-Healing:** 중첩된 폴더 구조를 플랫화하고, 깨진 링크와 누락된 프론트매터를 복구하며, SHA256 해시로 중복 파일을 감지해 병합합니다.
- **Reliability:** Claude와 Gemini를 동시에 지원하며, 한쪽이 실패하면 자동으로 다른 쪽이 처리하는(Fallback) 이중 안전장치를 갖췄습니다.

---

## 🚀 Quick Start
터미널에서 한 줄로 설치할 수 있습니다.
```bash
npx dotbrain
```

또는 curl로 직접 설치:
```bash
curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash
```

메뉴바에 `·‿·` 가 나타나면 설치 완료입니다. 아이콘을 클릭하여 온보딩을 시작하세요.

> **필요한 것:** macOS 13 (Ventura) 이상 / Node.js 18+ (npx 사용 시) / [Gemini API 키](https://aistudio.google.com/apikey) 또는 [Claude API 키](https://console.anthropic.com/settings/keys)

<details>
<summary><b>소스에서 직접 빌드</b></summary>

```bash
git clone https://github.com/DinN0000/DotBrain.git ~/Developer/DotBrain
cd ~/Developer/DotBrain
swift build -c release
# 바이너리: .build/release/DotBrain
```
</details>

---

## ⚙️ How it Works

### 인박스 처리

인박스에 파일을 넣으면 자동으로 처리됩니다 :

```
_Inbox/에 파일 추가 (드래그앤드롭)
    ↓
내용 추출 (텍스트/PDF/이미지/PPTX/XLSX/DOCX)
    ↓
2단계 AI 분류
    ├── Stage 1: Fast (Haiku/Flash) — 배치 분류
    └── Stage 2: Precise (Sonnet/Pro) — 신뢰도 낮은 파일만
    ↓
파일 이동 + 프론트매터 주입 + 관련 노트 연결 + MOC 갱신
    ↓
분류 완료
```

### AI 분류 전략

| 단계 | 모델 | 비용 | 방식 |
|------|------|------|------|
| Stage 1 (Fast) | Haiku / Flash | ~$0.002/파일 | 파일명 + 미리보기로 배치 분류 |
| Stage 2 (Precise) | Sonnet / Pro | ~$0.01/파일 | 전체 내용으로 정밀 분류 (신뢰도 < 0.8만) |

대부분의 파일은 Stage 1에서 끝납니다. 100개 파일 기준 Claude ~$0.20, Gemini는 무료 티어 내 가능.

### 폴더 정리

기존 PARA 폴더를 AI가 다시 정리합니다:

```
폴더 선택
    ↓
플랫화 — 중첩 하위 폴더에서 콘텐츠를 최상위로 이동 (SHA256 중복 제거)
    ↓
AI 재분류
    ├── 위치 맞음 → frontmatter 갱신
    └── 위치 틀림 → 올바른 폴더로 자동 이동
```

### 볼트 관리 

- **PARA 관리** — 카테고리 간 폴더 이동, 프로젝트 생성, 폴더별 자동 정리                                                                     
- **전체 재정리** — 볼트 전체를 AI가 스캔하여 잘못된 분류 이동 제안 (사용자 승인 후 실행)         
- **볼트 감사** — 깨진 링크, 누락된 프론트매터 자동 수정

### Frontmatter 표준화

DotBrain은 모든 노트에 대해 사람과 AI가 모두 이해할 수 있는 표준 규격을 적용합니다.

```yaml
---
para: project
tags: [defi, ethereum, blockchain]
created: 2026-02-11
status: active
summary: "DeFi 시스템 구축 프로젝트"
source: import
project: DOJANG
---
```

| 필드 | 설명 |
|------|------|
| `para` | PARA 카테고리 (Project/Area/Resource/Archive) |
| `tags` | 파일 내용 기반으로 자동 태깅 |
| `created` | 최초 생성일 (기존 값 보존) |
| `status` | active / draft / completed / on-hold |
| `summary` | 파일 내용을 한줄로 요약 |
| `source` | original / meeting / literature / import |
| `project` | 연관 프로젝트명 |
| `area` | 연관 Area 이름 |
| `projects` | 연관 프로젝트 목록 (Area 내 문서용) |
| `file` | 원본 파일명 (비텍스트 파일의 경우) |

---

## 📂 Folder Structure
DotBrain이 관리하는 PKM(Personal Knowledge Management) 폴더 구조입니다.

```
PKM Root/
├── _Inbox/                          ← 여기에 파일을 넣으면
├── _Assets/                         ← 바이너리 파일 중앙 저장소
│   └── diagram.png
├── 1_Project/
│   └── MyProject/
│       ├── MyProject.md             ← 인덱스 노트 (자동 생성)
│       └── plan.md
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

## 🛠 Technical Details

### 지원 파일 형식

| 형식 | 추출 방식 | 추출 내용 |
|------|-----------|-----------|
| `.md`, `.txt` 등 | 직접 읽기 | 전체 텍스트 |
| `.pdf` | PDFKit | 텍스트 + 페이지수/저자/제목 |
| `.docx` | ZIPFoundation + XML | 본문 텍스트 + 메타데이터 |
| `.pptx` | ZIPFoundation + XML | 슬라이드 텍스트 |
| `.xlsx` | ZIPFoundation + XML | 셀 데이터 |
| `.jpg`, `.png`, `.heic` 등 | ImageIO | EXIF (촬영일, 카메라, GPS) |
| 폴더 | 내부 파일 순회 | 포함 파일 내용 종합 |

### 중복 감지

| 상황 | 감지 방식 | 처리 |
|------|-----------|------|
| 같은 내용, 다른 이름 | SHA256 본문 해시 (frontmatter 제외) | 태그 병합 → 삭제 |
| 같은 내용 바이너리 | SHA256 해시 (≤500MB) 또는 크기+수정일 (>500MB) | 태그 병합 → 삭제 |
| 같은 이름, 다른 내용 | 파일명 비교 | 사용자에게 확인 |
| 인덱스 노트와 이름 충돌 | `폴더명.md` 비교 | 사용자에게 확인 |

### 기술 스택

- **Swift 5.9** + SwiftUI + Combine
- **macOS 메뉴바 앱** — `NSStatusItem` + `NSPopover`
- **AI** — Claude (Haiku + Sonnet) / Gemini (Flash + Pro) — 이중 제공자, 자동 폴백
- **의존성** — ZIPFoundation (DOCX/PPTX/XLSX 처리)
- **보안** — API 키는 AES-GCM 암호화 파일로 기기 종속 저장 (하드웨어 UUID + HKDF)
- **안정성** — 지수 백오프 재시도, 제공자 폴백, 경로 탐색 보호

---

## 🎨 Design Philosophy

### 당신의 맥락을, AI가 읽을 수 있게

AI는 주어진 자료를 바탕으로 판단합니다.
하지만 대부분의 경우, 사용자가 직접 파일을 선택해서 전달해야 합니다.

- 파일 단위로 전달하면 개별 분석은 가능하지만, 자료 간 맥락 연결이 어렵습니다
- 대량으로 전달하면 컨텍스트 제한에 도달합니다
- 매 대화마다 동일한 배경 설명을 반복해야 합니다

AI가 사용자의 지식 전체를 활용하려면, **AI 스스로 탐색할 수 있는 구조화된 지식베이스**가 필요합니다.

DotBrain은 파일을 받아 분류하고, 태그를 부여하고, 문서 간 연결 관계를 생성합니다.
어떤 AI 도구든 이 지식베이스를 열었을 때, 구조만으로 관련 맥락을 탐색할 수 있는 상태를 만듭니다.

### Frontmatter — 사람과 AI 모두를 위한 메타데이터

모든 파일에는 YAML frontmatter가 부여됩니다.

```yaml
---
para: project
tags: [defi, ethereum, blockchain]
summary: "DeFi 시스템 구축 프로젝트"
---
```

사람에게는 Obsidian에서 바로 보이고 직접 편집할 수 있는 메타데이터입니다.
AI에게는 파싱 한 번으로 분류, 검색, 요약에 필요한 정보가 추출되는 구조화된 데이터입니다.

**생성과 관리는 AI가 하고, 편집 권한은 사람이 갖습니다.**
사용자는 메타데이터를 직접 채우는 노동에서 벗어나고, AI는 일관된 규격의 데이터를 확보합니다.

### Wiki-links + MOC — 사람에게는 목차, AI에게는 인덱스

각 폴더에는 MOC(Map of Content)가 자동 생성됩니다.
MOC는 해당 폴더의 모든 문서를 `[[위키링크]]`와 함께 **각 문서의 요약**을 정리한 인덱스 노트입니다.

```markdown
# DOJANG

> DeFi 시스템 구축 프로젝트. 아키텍처 설계부터 스마트컨트랙트 감사까지 포함.

## 문서 목록
- [[DeFi 아키텍처 설계]] — L2 기반 DeFi 시스템의 전체 아키텍처 설계 문서
- [[파트너사 미팅 0211]] — 2차 요구사항 미팅. API 연동 방식 확정
- [[스마트컨트랙트 감사 리포트]] — Slither 정적 분석 결과 및 취약점 3건 조치 내역
```

사람에게 이 링크는 클릭으로 이동하는 목차이고, 요약은 열어보지 않아도 내용을 파악할 수 있는 가이드입니다.
AI에게 이 링크는 그래프의 엣지이고, 요약은 탐색 우선순위를 판단하는 컨텍스트입니다.
어떤 문서를 먼저 읽어야 하는지, 어떤 문서가 현재 질문과 관련 있는지를 MOC만으로 판단할 수 있습니다.

**같은 구조가 사람에게는 네비게이션으로, AI에게는 탐색 그래프로 작동합니다.**

### AI Companion Files — 볼트를 AI-ready로

DotBrain은 사용자의 볼트에 `CLAUDE.md`, `AGENTS.md`, `.cursorrules` 같은 AI 컴패니언 파일을 자동 생성합니다.
이 파일들이 있으면 Claude Code, Cursor 같은 AI 도구가 볼트를 열었을 때 폴더 구조, 분류 규칙, 태그 체계를 즉시 파악합니다.

볼트 전체를 읽지 않아도, 컴패니언 파일 하나로 **"이 지식베이스는 이렇게 구성되어 있고, 이런 규칙을 따른다"**를 전달할 수 있습니다.

업데이트 시에는 `<!-- DotBrain:start -->` / `<!-- DotBrain:end -->` 마커 사이만 갱신합니다.
마커 바깥에 사용자가 추가한 내용은 보존됩니다.

### 프로젝트는 사람이, 분류는 AI가

PARA 프레임워크(Projects, Areas, Resources, Archive)가 분류의 기본 구조를 제공합니다.
이 구조 안에서 AI가 파일을 자동으로 분류합니다.

사용자가 하는 일은 **프로젝트를 정의하는 것**입니다.
"PoC-Alpha", "PoC-Beta", "DotBrain" — 어떤 프로젝트가 진행 중인지는 사용자만 압니다.
프로젝트가 설정되면, 어떤 파일이 어디에 속하는지는 AI가 판단합니다.

---

지식베이스가 구조화되면, AI는 단순한 질의응답을 넘어섭니다.
관련 자료를 스스로 탐색하고, 문서 간 연결에서 패턴을 발견하고, 사용자의 맥락 위에서 사고합니다.

DotBrain은 그 시작점을 만듭니다.

---

## ❓ Troubleshooting

<details>
<summary><b>"확인되지 않은 개발자" / "손상되어 열 수 없음"</b></summary>

```bash
xattr -cr ~/Applications/DotBrain.app
```

또는: **시스템 설정 → 개인정보 보호 및 보안** → "확인 없이 열기"를 클릭하세요.
</details>

<details>
<summary><b>폴더 접근 권한 팝업</b></summary>

첫 실행 시 PKM 폴더 접근 권한 요청에 반드시 **"허용"**을 선택해야 합니다.
</details>

<details>
<summary><b>메뉴바에 아이콘이 안 보임</b></summary>

메뉴바 공간 부족일 수 있습니다. 다른 아이콘을 ⌘+드래그로 제거하거나, Bartender/Ice로 정리하세요.
</details>

<details>
<summary><b>앱 제거</b></summary>

```bash
npx dotbrain --uninstall
```

또는 수동으로:
```bash
pkill -f DotBrain 2>/dev/null; \
launchctl bootout gui/$(id -u)/com.dotbrain.app 2>/dev/null; \
rm -f ~/Library/LaunchAgents/com.dotbrain.app.plist; \
rm -rf ~/Applications/DotBrain.app; \
echo "제거 완료"
```

</details>

---

## 💬 그래서 DotBrain은?

> DotBrain은 macOS 메뉴바에서 동작하는 AI PKM 앱입니다.
> 파일을 인박스에 넣으면 AI가 내용을 분석해서 PARA 구조로 자동 분류하고, 프론트매터 작성, 관련 노트 연결, MOC 생성까지 다 해줍니다.
>
> **노트 정리하는 시간을 없애줍니다.** 어디에 넣을지 고민하고, 태그 달고, 관련 문서 찾아서 연결하는 작업을 AI가 대신 하니까, 사용자는 쓰고 읽는 것만 하면 됩니다. 쌓기만 하고 안 보는 노트앱이 아니라, 알아서 정리되니까 실제로 다시 찾아 쓰게 됩니다.
>
> 그리고 진짜 핵심은, **이렇게 정리된 볼트를 AI가 읽을 때 성능이 확 올라갑니다.** 구조화된 프론트매터, MOC, 관련 노트 링크 덕분에 AI가 맥락을 정확히 파악하고, 필요한 문서를 빠르게 찾아냅니다. 내 지식이 잘 정리될수록 AI가 더 똑똑하게 일하는 구조입니다.
>
> Obsidian 호환이고, Claude Code나 Cursor용 에이전트도 자동으로 심어줘서 "볼트 점검해줘" 한마디로 전체 건강 검사까지 됩니다.

---

<p align="center">
Made by Hwaa
</p>
