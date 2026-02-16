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

macOS 메뉴바에서 동작하는 AI PKM 앱입니다.
파일을 인박스에 넣으면 AI가 내용을 분석해서 PARA 구조로 자동 분류하고, 프론트매터 작성, 관련 노트 연결, MOC 생성까지 해줍니다.

노트 정리하는 시간을 없애줍니다. 정리된 볼트는 AI가 읽을 때도 성능이 올라갑니다.

```
·‿·  →  ·_·!  →  ·_·…  →  ^‿^

```

---

## Quick Start

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

## How it Works

### 인박스 처리

인박스에 파일을 넣으면 자동으로 처리됩니다:

```
파일 추가 (드래그앤드롭 / Cmd+V)
    ↓
내용 추출 (텍스트/PDF/이미지/PPTX/XLSX/DOCX)
    ↓
2단계 AI 분류
    ├── Stage 1: Fast (Haiku/Flash) — 배치 분류
    └── Stage 2: Precise (Sonnet/Pro) — 신뢰도 낮은 파일만
    ↓
파일 이동 + 프론트매터 주입 + 관련 노트 연결 + MOC 갱신
```

대부분의 파일은 Stage 1에서 끝납니다. 100개 파일 기준 Claude ~$0.20, Gemini는 무료 티어 내 가능.

### 폴더 정리

기존 PARA 폴더를 AI가 다시 정리합니다:

```
폴더 선택
    ↓
플랫화 + SHA256 중복 제거
    ↓
AI 재분류
    ├── 위치 맞음 → 프론트매터 갱신
    └── 위치 틀림 → 올바른 폴더로 자동 이동
```

### 볼트 관리

- **PARA 관리** — 카테고리 간 폴더 이동, 프로젝트 생성, 폴더별 자동 정리
- **전체 재정리** — 볼트 전체를 AI가 스캔하여 잘못된 분류 교정
- **볼트 감사** — 깨진 링크, 누락된 프론트매터, 태그 불일치 자동 수정

---

## Folder Structure

```
PKM Root/
├── _Inbox/                    ← 여기에 파일을 넣으면
├── 1_Project/
│   └── MyProject/
│       ├── MyProject.md       ← 인덱스 노트 (자동 생성)
│       ├── plan.md
│       └── _Assets/
├── 2_Area/
│   └── DevOps/
├── 3_Resource/
│   └── Python/
└── 4_Archive/
    └── 2024-Q1/
```

---

## Technical Details

<details>
<summary><b>지원 파일 형식</b></summary>

| 형식 | 추출 방식 | 추출 내용 |
|------|-----------|-----------|
| `.md`, `.txt` 등 | 직접 읽기 | 전체 텍스트 |
| `.pdf` | PDFKit | 텍스트 + 메타데이터 |
| `.docx` | ZIPFoundation + XML | 본문 텍스트 |
| `.pptx` | ZIPFoundation + XML | 슬라이드 텍스트 |
| `.xlsx` | ZIPFoundation + XML | 셀 데이터 |
| `.jpg`, `.png`, `.heic` 등 | ImageIO | EXIF 정보 |

</details>

<details>
<summary><b>기술 스택</b></summary>

- **Swift 5.9** + SwiftUI + Combine
- **macOS 메뉴바 앱** — `NSStatusItem` + `NSPopover`
- **AI** — Claude (Haiku + Sonnet) / Gemini (Flash + Pro) — 이중 제공자, 자동 폴백
- **의존성** — ZIPFoundation (DOCX/PPTX/XLSX 처리)
- **보안** — API 키는 AES-GCM 암호화 파일로 기기 종속 저장 (하드웨어 UUID + HKDF)
- **안정성** — 지수 백오프 재시도, 제공자 폴백, 경로 탐색 보호

</details>

---

## Design Philosophy

> **"사람이 쓰기 좋은 것"과 "AI가 다루기 좋은 것"은 왜 항상 따로일까?**

DotBrain은 그 둘이 같은 것이 될 수 있도록 설계되었습니다.

- **Frontmatter as Contract** — YAML 프론트매터는 사람과 AI 사이의 계약서. 사용자가 수정할 수 있고, AI는 이 값을 기준으로 처리합니다.
- **Wiki-links + MOC** — MOC 파일은 사람에게는 목차, AI에게는 지식 그래프의 진입점입니다.
- **Classification, not Creation** — PARA 체계 안에서 파일을 분류할 뿐, 체계 자체를 바꾸지 않습니다.
- **AI Companion Files** — 볼트에 `CLAUDE.md`, `AGENTS.md`, `.cursorrules`를 자동 생성하여 AI 도구가 볼트 구조를 즉시 이해할 수 있게 합니다. 마커 기반 업데이트로 사용자 커스텀 내용은 보존됩니다.

---

## Troubleshooting

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

<p align="center">
  <a href="CHANGELOG.md">Changelog</a> · <a href="CONTRIBUTING.md">Contributing</a> · <a href="SECURITY.md">Security</a>
</p>

<p align="center">
Made by Hwaa
</p>
