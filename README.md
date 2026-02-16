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
- **Self-Healing:** 중첩된 폴더 구조를 플랫화하고, 잘못된 분류를 교정하며, SHA256 해시로 중복 파일을 감지해 병합합니다.
- **Reliability:** Claude와 Gemini를 동시에 지원하며, 한쪽이 실패하면 자동으로 다른 쪽이 처리하는(Fallback) 이중 안전장치를 갖췄습니다.

---

## 🚀 Quick Start
터미널에서 한 줄로 설치할 수 있습니다.
```bash
curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash
```

메뉴바에 `·‿·` 가 나타나면 설치 완료입니다. 아이콘을 클릭하여 온보딩을 시작하세요.

> **필요한 것:** macOS 13 (Ventura) 이상 / [Gemini API 키](https://aistudio.google.com/apikey) 또는 [Claude API 키](https://console.anthropic.com/settings/keys)

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

### 폴더 정리

기존 PARA 폴더를 AI가 다시 정리합니다:

```
폴더 선택
    ↓
플랫화 — 중첩 하위 폴더에서 콘텐츠를 최상위로 이동 (SHA256 중복 제거)
    ↓
AI 재분류
    ├── 위치 맞음 → frontmatter 갱신
    └── 위치 틀림 → 올바른 폴더로 이동 제안
```

### 볼트 관리 

- **PARA 관리** — 카테고리 간 폴더 이동, 프로젝트 생성, 폴더별 자동 정리                                                                     
- **전체 재정리** — 볼트 전체를 AI가 스캔하여 잘못된 분류 교정         
- **볼트 감사** — 깨진 링크, 누락된 프론트매터, 태그 불일치 자동 수

### Frontmatter 표준화

DotBrain은 모든 노트에 대해 사람과 AI가 모두 이해할 수 있는 표준 규격을 적용합니다.

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
| `para` | PARA 카테고리 (Project/Area/Resource/Archive) |
| `tags` | 파일 내용 기반으로 자동 태깅 |
| `created` | 최초 생성일 (기존 값 보존) |
| `status` | active / draft / completed / on-hold |
| `summary` | 파일 내용을 한줄로 요약 |
| `source` | original / meeting / literature / import |
| `project` | 연관 프로젝트명 |

---

## 📂 Folder Structure
DotBrain이 관리하는 PKM(Personal Knowledge Management) 폴더 구조입니다.

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

## 🛠 Techinical Details

### 지원 파일 형식

| 형식 | 추출 방식 | 추출 내용 |
|------|-----------|-----------|
| `.md`, `.txt` 등 | 직접 읽기 | 전체 텍스트 |
| `.pdf` | PDFKit | 텍스트 + 메타데이터 |
| `.docx` | ZIPFoundation + XML | 본문 텍스트 |
| `.pptx` | ZIPFoundation + XML | 슬라이드 텍스트 |
| `.xlsx` | ZIPFoundation + XML | 셀 데이터 |
| `.jpg`, `.png`, `.heic` 등 | ImageIO | EXIF 정보 |

### 기술 스택

- **Swift 5.9** + SwiftUI + Combine
- **macOS 메뉴바 앱** — `NSStatusItem` + `NSPopover`
- **AI** — Claude (Haiku + Sonnet) / Gemini (Flash + Pro) — 이중 제공자, 자동 폴백
- **의존성** — ZIPFoundation (DOCX/PPTX/XLSX 처리)
- **보안** — API 키는 AES-GCM 암호화 파일로 기기 종속 저장 (하드웨어 UUID + HKDF)
- **안정성** — 지수 백오프 재시도, 제공자 폴백, 경로 탐색 보호

---

## 🎨 Design Philosophy

> **"사람이 사용하기 좋은 것"과 "AI를 사용하기 최적화된 것" 두 개의 병목 지점?**

DotBrain은 그 둘이 같은 것이 될 수 있도록 설계되었습니다.

### Frontmatter as Contract

YAML Frontmatter는 사람과 AI 사이의 계약서입니다. 사용자가 수정할 수 있고, AI는 이 값을 기준으로 문서를 처리합니다.

### Wiki-links + MOC — 양쪽 모두를 위한 네비게이션

MOC(Map of Content) 파일은 사람에게는 목차, AI에게는 지식 그래프의 **진입점(Entry Point)**입니다.<br>
DotBrain이 생성하는 [[위키링크]] 구조는 AI 에이전트가 로컬 파일 시스템을 효과적으로 탐색할 수 있게 합니다.

### Classification, not Creation

DotBrain은 PARA 체계 안에서 파일을 분류할 뿐, 임의로 체계를 바꾸지 않습니다. 휴먼 리더블한 문서 체계를 유지하며 AI 최적화를 수행합니다.

### AI Companion Files 

볼트에 `CLAUDE.md`, `AGENTS.md`, `.cursorrules`를 자동 생성하여 AI 도구가 볼트 구조를 즉시 이해할 수 있게 합니다.<br>
마커 기반 업데이트로 사용자 커스텀 내용은 보존됩니다

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
pkill -f DotBrain 2>/dev/null; \
rm -f ~/Library/LaunchAgents/com.dotbrain.app.plist; \
rm -rf ~/Applications/DotBrain.app; \
echo "제거 완료"
```

</details>

---

## 💬 DotBrain을 소개합니다

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
