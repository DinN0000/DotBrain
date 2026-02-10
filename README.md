# AI-PKM MenuBar

macOS 메뉴바 앱. 파일을 끌어다 놓으면 Claude AI가 PARA 구조로 자동 분류합니다.

```
·‿·  →  ·_·!  →  ·_·…  →  ^‿^
대기      파일있음    처리중     완료
```

## 왜 만들었나

Obsidian 같은 PKM 도구를 쓰다 보면, 파일이 쌓이기만 하고 정리가 안 됩니다.
PARA 방법론(Projects, Areas, Resources, Archive)은 좋은 체계인데, 매번 수동으로 분류하기는 번거롭습니다.

이 앱은 그 과정을 자동화합니다:
- **파일을 인박스에 넣으면** AI가 내용을 읽고 적절한 PARA 폴더로 이동
- **프론트매터**(tags, summary, para 등)를 자동 생성하여 Obsidian과 호환
- **중복 파일**을 감지하여 태그 병합 후 정리
- **기존 폴더 재정리**도 가능 — 잘못 분류된 파일을 찾아서 제안

## 동작 방식

### 1. 인박스 처리 파이프라인

```
_Inbox/에 파일 추가 (드래그앤드롭 / Cmd+V)
    ↓
InboxScanner — 파일 목록 수집
    ↓
ProjectContextBuilder — 기존 프로젝트/폴더 구조를 AI 컨텍스트로 변환
    ↓
내용 추출 — 텍스트 파일은 직접, PDF/이미지/PPTX/XLSX는 추출기 사용
    ↓
2단계 AI 분류
    ├── Stage 1: Haiku (빠르고 저렴) — 배치 분류, 신뢰도 산출
    └── Stage 2: Sonnet (정밀) — 신뢰도 < 0.8인 파일만 개별 재분류
    ↓
충돌 검사
    ├── 신뢰도 < 0.5 → 사용자에게 확인 요청
    ├── 인덱스 노트 이름 충돌 → 확인 요청
    └── 동명 파일 존재 → 확인 요청
    ↓
FileMover — 파일 이동 + 프론트매터 주입 + 중복 감지
    ├── 텍스트 파일: 본문 SHA256 비교 → 중복이면 태그 병합
    ├── 바이너리: _Assets/로 이동 + 동반 마크다운 생성
    └── 폴더: 통째로 이동 + [[위키링크]] 인덱스 노트 생성
    ↓
결과 화면 — 성공/건너뜀/삭제/중복/오류별 상태 표시
```

### 2. 폴더 재정리

기존 PARA 폴더의 파일을 다시 분류합니다:

```
폴더 선택 (예: 2_Area/DevOps)
    ↓
중복 제거 — 같은 폴더 내 동일 내용 파일 병합
    ↓
AI 재분류 — 현재 위치가 맞는지 판단
    ├── 위치 맞음 → 프론트매터만 업데이트 (tags, summary 등)
    └── 위치 틀림 → 사용자에게 이동 제안
```

### 3. AI 분류 전략

**Stage 1 (Haiku)** — 파일당 ~$0.002
- 파일명 + 200자 미리보기로 빠르게 분류
- 배치 처리 (10개씩)
- 신뢰도 0.0~1.0 산출

**Stage 2 (Sonnet)** — 파일당 ~$0.01
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

**인덱스 노트** — 각 서브폴더의 `폴더명.md`가 관리 문서 역할:
```yaml
---
para: area
tags: [devops, infrastructure]
created: 2025-02-11
status: active
summary: "DevOps 관련 운영 자료"
source: original
---
```

**바이너리 파일** — PDF, 이미지 등은 `_Assets/`에 저장되고 동반 마크다운이 생성:
```
_Assets/report.pdf          ← 원본
report.pdf.md               ← 추출된 텍스트 + 메타데이터
```

## 지원 파일 형식

| 형식 | 추출 방식 | 추출 내용 |
|------|-----------|-----------|
| `.md`, `.txt` 등 | 직접 읽기 | 전체 텍스트 (5000자) |
| `.pdf` | PDFKit | 텍스트 + 페이지수/저자/제목 |
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

## 설치 및 실행

```bash
# 빌드
swift build

# 실행
swift run AI-PKM-MenuBar

# 또는
.build/debug/AI-PKM-MenuBar
```

### 요구사항
- macOS 13+
- [Anthropic API 키](https://console.anthropic.com/settings/keys) (Claude 구독과 별도)

### 초기 설정
1. 앱 실행 → 온보딩 시작
2. API 키 입력
3. PKM 폴더 경로 선택 → PARA 구조 생성
4. (선택) 프로젝트 등록

## 기술 스택

- **Swift 5.9** + SwiftUI + Combine
- **macOS 메뉴바 앱** — `NSStatusItem` + `NSPopover`
- **AI** — Anthropic Claude API (Haiku 4.5 + Sonnet 4.5)
- **의존성** — ZIPFoundation (PPTX/XLSX 처리)
- **보안** — API 키는 macOS Keychain에 저장
- **상태관리** — `AppState` 싱글턴, `@Published` + `@EnvironmentObject`

## 비용

| 모델 | 용도 | 파일당 비용 |
|------|------|-------------|
| Haiku 4.5 | 1차 분류 (모든 파일) | ~$0.002 |
| Sonnet 4.5 | 2차 정밀 분류 (불확실한 파일만) | ~$0.01 |

대부분의 파일은 Haiku만으로 처리됩니다. 100개 파일 기준 약 $0.20~0.30.
