# DotBrain 서비스 매뉴얼

> **Built for Humans. Optimized for AI.**
>
> 버전: 2.11 | 최종 수정: 2026-02-25

---

## 목차

- [1. 소개](#1-소개)
- [2. 설치](#2-설치)
- [3. 초기 설정 (온보딩)](#3-초기-설정-온보딩)
- [4. AI 제공자 설정](#4-ai-제공자-설정)
- [5. 사용 가이드](#5-사용-가이드)
  - [5.1 인박스 처리](#51-인박스-처리)
  - [5.2 폴더 정리](#52-폴더-정리)
  - [5.3 PARA 관리](#53-para-관리)
  - [5.4 볼트 전체 재정리](#54-볼트-전체-재정리)
  - [5.5 볼트 감사](#55-볼트-감사)
  - [5.6 시맨틱 링킹](#56-시맨틱-링킹)
  - [5.7 검색](#57-검색)
  - [5.8 폴더 관계 탐색](#58-폴더-관계-탐색)
  - [5.9 AI 통계](#59-ai-통계)
- [6. 화면 구성](#6-화면-구성)
- [7. Frontmatter 규격](#7-frontmatter-규격)
- [8. 폴더 구조](#8-폴더-구조)
- [9. AI 컴패니언 파일](#9-ai-컴패니언-파일)
- [10. 지원 파일 형식](#10-지원-파일-형식)
- [11. 중복 감지](#11-중복-감지)
- [12. 설정](#12-설정)
- [13. 문제 해결](#13-문제-해결)
- [14. 개발자 가이드](#14-개발자-가이드)
  - [14.1 아키텍처](#141-아키텍처)
  - [14.2 빌드](#142-빌드)
  - [14.3 코드 배치 규칙](#143-코드-배치-규칙)
  - [14.4 파이프라인 상세](#144-파이프라인-상세)
  - [14.5 서비스 목록](#145-서비스-목록)
  - [14.6 모델](#146-모델)
  - [14.7 보안](#147-보안)
  - [14.8 릴리스](#148-릴리스)

---

## 1. 소개

DotBrain은 macOS 메뉴바에서 동작하는 AI 기반 PKM(Personal Knowledge Management) 앱입니다.

**핵심 기능:**
- 인박스에 파일을 넣으면 AI가 내용을 읽고 PARA 구조에 맞춰 자동 분류
- 프론트매터 작성, 관련 노트 연결, MOC(Map of Content) 생성
- 볼트 건강 검사: 깨진 링크 수정, 누락된 메타데이터 보충, 중복 감지
- Obsidian 호환 — 위키링크, 프론트매터 기반

**PARA 방법론:**

| 카테고리 | 설명 | 폴더 |
|---------|------|------|
| Project | 기한이 있는 진행 중인 작업 | `1_Project/` |
| Area | 지속적으로 관리하는 책임 영역 | `2_Area/` |
| Resource | 참고 자료, 학습 자료 | `3_Resource/` |
| Archive | 완료되거나 보관할 항목 | `4_Archive/` |

---

## 2. 설치

### npx (권장)

```bash
npx dotbrain
```

메뉴바에 `·‿·`가 나타나면 설치 완료입니다.

**요구 사항:** macOS 13 (Ventura) 이상, Node.js 18+

### 소스 빌드

```bash
git clone https://github.com/DinN0000/DotBrain.git ~/Developer/DotBrain
cd ~/Developer/DotBrain
swift build -c release
# 바이너리: .build/release/DotBrain
```

### 제거

```bash
npx dotbrain --uninstall
```

또는 수동으로:
```bash
pkill -f DotBrain 2>/dev/null
launchctl bootout gui/$(id -u)/com.dotbrain.app 2>/dev/null
rm -f ~/Library/LaunchAgents/com.dotbrain.app.plist
rm -rf ~/Applications/DotBrain.app
```

---

## 3. 초기 설정 (온보딩)

첫 실행 시 7단계 온보딩 마법사가 시작됩니다.

### Step 0: 환영

Before/After 비교로 DotBrain이 하는 일을 보여줍니다. "시작하기"를 클릭하세요.

### Step 1: 전체 디스크 접근 권한

DotBrain이 PKM 폴더에 접근하려면 **전체 디스크 접근** 권한이 필요합니다.

1. **시스템 설정** > **개인정보 보호 및 보안** > **전체 디스크 접근** 열기
2. DotBrain 토글 켜기
3. 앱으로 돌아오면 자동으로 상태가 업데이트됩니다

> 건너뛰기도 가능하지만, 권한 없이는 일부 폴더에 접근할 수 없습니다.

### Step 2: PKM 폴더 선택

볼트로 사용할 폴더를 선택합니다. PARA 하위 폴더(`1_Project/`, `2_Area/`, `3_Resource/`, `4_Archive/`, `_Inbox/`)가 자동 생성됩니다.

### Step 3: 영역(Area) 등록

지속적으로 관리하는 책임 영역을 1개 이상 등록합니다.

- 예: `DevOps`, `Finance`, `Health`, `Learning`
- 텍스트 입력 후 "+" 버튼으로 추가

### Step 4: 프로젝트 등록

현재 진행 중인 프로젝트를 1개 이상 등록합니다.

- 예: `PoC-Alpha`, `DotBrain`, `Q1-Report`
- 각 프로젝트를 Area에 연결할 수 있습니다

### Step 5: AI 제공자 선택

세 가지 AI 제공자 중 하나를 선택합니다:

| 제공자 | 설정 | 비용 |
|--------|------|------|
| **Claude CLI** (추천) | Claude 앱 설치 필요, API 키 불필요 | 구독 토큰 사용 |
| Claude API | API 키 입력 (`sk-ant-...`) | ~$0.002/파일 |
| Gemini API | API 키 입력 (`AIza...`) | 무료 티어 가능 |

### Step 6: 완료

설정이 끝나면 인박스 화면으로 이동합니다. 파일을 넣어보세요.

---

## 4. AI 제공자 설정

### Claude CLI (추천)

Claude 구독(Pro/Max) 사용자를 위한 기본 제공자입니다.

- **설정:** Claude 데스크톱 앱을 설치하면 `claude` CLI가 자동으로 사용 가능
- **모델:** Haiku (Fast) → Sonnet (Precise)
- **비용:** 구독 토큰 사용, 별도 API 비용 없음
- **설치 확인:** 설정에서 "설치됨" / "찾을 수 없음" 표시

Claude CLI가 없으면 [claude.com/download](https://claude.com/download)에서 Claude 앱을 설치하세요.

### Claude API

API 키 기반 직접 호출입니다.

- **키 발급:** [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
- **모델:** Haiku 4.5 (Fast) → Sonnet 4.5 (Precise)
- **비용:** ~$0.002/파일 (대부분 Stage 1에서 종료)
- **키 형식:** `sk-ant-` 접두사

### Gemini API

Google AI 무료 티어를 활용할 수 있습니다.

- **키 발급:** [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
- **모델:** Flash (Fast) → Pro (Precise)
- **비용:** 무료 티어 (15회/분, 1500회/일)
- **키 형식:** `AIza` 접두사

### 제공자 전환

설정 화면에서 언제든지 제공자를 변경할 수 있습니다. 각 제공자의 API 키는 독립적으로 저장되므로, 전환 시 키를 다시 입력할 필요가 없습니다.

### 자동 폴백

활성 제공자 호출이 실패하면, 키가 설정된 다른 제공자로 자동 전환됩니다.

---

## 5. 사용 가이드

### 5.1 인박스 처리

**가장 핵심적인 기능입니다.** 인박스에 파일을 넣으면 AI가 분류합니다.

**사용 방법:**
1. 메뉴바에서 DotBrain 클릭 → 인박스 화면
2. 파일을 드래그앤드롭하거나 "+ 파일 선택" 클릭
3. "정리하기" 버튼 클릭

**처리 과정 (5단계):**

```
준비 (0-5%)      파일 스캔
    ↓
분석 (5-30%)     내용 추출 (텍스트/PDF/이미지/문서)
    ↓
AI 분류 (30-70%) Stage 1: 빠른 배치 분류 (Haiku/Flash)
                  Stage 2: 정밀 분류 (Sonnet/Pro) — 신뢰도 낮은 파일만
    ↓
정리 (70-95%)    파일 이동 + 프론트매터 주입
    ↓
마무리 (95-100%) MOC 갱신 + 시맨틱 링크 생성
```

**2단계 AI 분류:**
- **Stage 1 (Fast):** 파일명 + 800자 미리보기로 배치 분류 (5개씩). 대부분 여기서 끝남
- **Stage 2 (Precise):** 신뢰도 < 0.8인 파일만 전체 내용(5000자)으로 정밀 분류

**사용자 확인이 필요한 경우:**
- 신뢰도가 낮은 분류 (< 0.5)
- AI가 제안한 프로젝트가 존재하지 않을 때
- 파일명이 인덱스 노트와 충돌할 때
- 같은 이름의 다른 내용 파일이 이미 있을 때

**결과 화면:**
- 파일별 성공/실패/중복 상태 표시
- 분쟁 파일은 사용자가 직접 확인 가능

### 5.2 폴더 정리

기존 PARA 폴더 안의 파일을 AI가 다시 정리합니다.

**사용 방법:**
1. 대시보드 → "폴더 관리" → 폴더 선택
2. "정리하기" 실행

**처리 과정:**

```
플랫화 — 중첩 하위 폴더에서 콘텐츠를 최상위로 이동
    ↓
중복 제거 — SHA256 해시로 중복 파일 감지, 태그 병합 후 삭제
    ↓
AI 재분류
    ├── 위치 맞음 → 프론트매터 갱신 (태그, 요약 등)
    └── 위치 틀림 → 올바른 폴더로 자동 이동
```

### 5.3 PARA 관리

대시보드 → "폴더 관리"에서 PARA 구조를 직접 관리합니다.

- **프로젝트 생성:** 새로운 프로젝트 폴더 + 인덱스 노트 자동 생성
- **이름 변경:** 폴더명 변경 (프론트매터의 project 필드도 함께 갱신)
- **병합:** 두 폴더의 내용을 하나로 합침
- **삭제:** 빈 폴더 삭제
- **카테고리 이동:** 프로젝트 → 아카이브 등 PARA 카테고리 간 이동

각 폴더에는 파일 수, 수정된 파일 수, 건강 상태가 표시됩니다.

### 5.4 볼트 전체 재정리

볼트의 모든 파일을 AI가 스캔하여 잘못된 분류를 찾아냅니다.

**사용 방법:**
1. 대시보드 → "볼트 점검" → "전체 재정리" 실행

**2단계 워크플로:**

```
스캔 단계 — 전체 파일을 AI가 분류하고 현재 위치와 비교
    ↓
사용자 검토 — 이동이 필요한 파일 목록을 보여줌
    ↓
실행 — 사용자가 승인한 파일만 이동
```

> 최대 200개 파일까지 한 번에 스캔합니다. AI가 새 프로젝트 폴더를 만들지는 않고, 기존 폴더로만 이동합니다.

### 5.5 볼트 감사

볼트의 무결성을 자동으로 점검하고 복구합니다.

**5단계 파이프라인:**

| 단계 | 내용 |
|------|------|
| 감사 (Audit) | 깨진 위키링크, 누락된 프론트매터, 태그 없는 파일 감지 |
| 수리 (Repair) | 깨진 링크 → 가장 유사한 노트로 교체 (레벤슈타인 거리), 누락된 프론트매터 주입 |
| 보강 (Enrich) | 변경된 파일의 빈 메타데이터 필드를 AI가 채움 (태그, 요약, 분류) |
| 인덱스 갱신 | `.meta/note-index.json` 증분 업데이트 |
| 시맨틱 링크 | 관련 노트 간 위키링크 생성 (사용자가 삭제한 링크는 재생성 안 함) |

### 5.6 시맨틱 링킹

AI가 노트 간의 의미적 관계를 분석하여 `[[위키링크]]`를 자동 생성합니다.

**후보 생성 기준:**
- 공유 태그 (가중치: 태그당 1점)
- 같은 프로젝트 소속
- MOC 멤버십
- 폴더 관계 (boost 쌍: +3점, suppress 쌍: -1점)

**AI 필터링:**
- "이 링크를 따라가면 사용자가 새로운 통찰을 얻을 수 있는가?" 기준으로 평가
- 관계 유형 분류: 선행 지식 (prerequisite), 관련 프로젝트 (project), 참고 자료 (reference), 함께 보기 (related)

**`## Related Notes` 섹션 형식:**

```markdown
## Related Notes

### 선행 지식
- [[기초 개념 정리]] — 이 문서를 이해하기 위해 먼저 읽어야 할 내용

### 관련 프로젝트
- [[프로젝트 계획서]] — 같은 프로젝트의 기획 문서

### 참고 자료
- [[API 레퍼런스]] — 구현 시 참고할 API 문서

### 함께 보기
- [[유사 사례 분석]] — 비슷한 주제를 다른 관점에서 다룬 문서
```

**링크 보호:**
- 사용자가 수동으로 삭제한 링크는 `LinkFeedbackStore`에 기록되어 재생성되지 않음
- `LinkStateDetector`가 이전/현재 링크 스냅샷을 비교하여 삭제를 감지

### 5.7 검색

대시보드 → "검색"에서 볼트 전체를 검색합니다.

- **검색 대상:** 태그, 키워드, 파일 제목, 요약, 본문
- **결과 표시:** PARA 카테고리별 색상 아이콘, 관련 노트 제안
- **매칭 유형:** tagMatch, bodyMatch, summaryMatch, titleMatch

### 5.8 폴더 관계 탐색

대시보드 하단 탭 → "폴더 관계"에서 AI가 발견한 폴더 간 관계를 관리합니다.

- **카드 UI:** AI가 제안한 폴더 쌍을 카드로 표시
- **스와이프:** 오른쪽(수락) / 왼쪽(거절)으로 관계를 승인하거나 거부
- **효과:** 승인된 관계는 시맨틱 링킹에서 가중치가 올라가고, 거절된 관계는 억제됨

### 5.9 AI 통계

대시보드 → "AI 통계"에서 사용량을 확인합니다.

- **API 비용:** 누적 사용 비용
- **작업별 분류:** 분류, 재정리, 시맨틱 링크, 요약 등 작업 유형별 비용
- **최근 기록:** API 호출 이력 (타임스탬프, 모델, 토큰 수, 비용)

---

## 6. 화면 구성

### 메인 네비게이션 (하단 탭 4개)

| 탭 | 아이콘 | 설명 |
|----|--------|------|
| 인박스 | tray.and.arrow.down | 파일 드롭존, 파일 목록, "정리하기" 버튼 |
| 대시보드 | square.grid.2x2 | 통계, 건강 알림, 활동 로그, 기능 바로가기 |
| 폴더 관계 | rectangle.2.swap | AI 폴더 쌍 매칭 |
| 설정 | gearshape | AI 설정, PKM 폴더, 앱 정보 |

### 대시보드에서 접근 가능한 화면

| 화면 | 설명 |
|------|------|
| 폴더 관리 | PARA 폴더 생성/이름 변경/병합/삭제 |
| 검색 | 태그/키워드/제목 기반 볼트 검색 |
| 볼트 점검 | 건강 검사, 재정리, 이슈 스캔 |
| AI 통계 | API 비용, 사용 로그 |

### 메뉴바 표정

메뉴바 아이콘은 앱 상태에 따라 표정이 바뀝니다:

| 표정 | 상태 |
|------|------|
| `·‿·` | 기본 (대기 중) |
| `·_·!` | 알림 있음 |
| `·_·…` | 처리 중 |
| `^‿^` | 처리 완료 |

---

## 7. Frontmatter 규격

DotBrain은 모든 노트에 YAML 프론트매터를 적용합니다.

```yaml
---
para: project
tags: ["defi", "ethereum", "blockchain"]
created: 2026-02-11
status: active
summary: "DeFi 시스템 구축 프로젝트"
source: import
project: DOJANG
---
```

| 필드 | 설명 | 값 |
|------|------|----|
| `para` | PARA 카테고리 | project, area, resource, archive |
| `tags` | AI 자동 태깅 | 문자열 배열 |
| `created` | 최초 생성일 (기존 값 보존) | YYYY-MM-DD |
| `status` | 노트 상태 | active, draft, completed, on-hold |
| `summary` | 한줄 요약 | 문자열 |
| `source` | 출처 | original, meeting, literature, import |
| `project` | 연관 프로젝트명 | 문자열 |
| `area` | 연관 Area 이름 | 문자열 |
| `projects` | 연관 프로젝트 목록 (Area 문서용) | 문자열 배열 |
| `file` | 원본 파일명 (비텍스트 파일) | 문자열 |

---

## 8. 폴더 구조

```
PKM Root/
├── _Inbox/                          ← 파일을 여기에 넣으세요
├── _Assets/                         ← 바이너리 파일 중앙 저장소
│   ├── documents/                   ← PDF, DOCX 등
│   ├── images/                      ← 이미지
│   └── videos/                      ← 동영상
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
├── 4_Archive/
│   └── 2024-Q1/
│       └── quarterly-report.md
├── .meta/                           ← 메타데이터 (숨김)
│   ├── note-index.json              ← 볼트 인덱스
│   ├── folder-relations.json        ← 폴더 관계
│   └── .dotbrain-companion-version
└── .Templates/                      ← 노트 템플릿
```

### MOC (Map of Content)

각 프로젝트 폴더에는 인덱스 노트(MOC)가 자동 생성됩니다:

```markdown
# DOJANG

> DeFi 시스템 구축 프로젝트

## 문서 목록
- [[DeFi 아키텍처 설계]] — L2 기반 DeFi 시스템의 전체 아키텍처 설계 문서
- [[파트너사 미팅 0211]] — 2차 요구사항 미팅. API 연동 방식 확정
- [[스마트컨트랙트 감사 리포트]] — Slither 정적 분석 결과 및 취약점 3건 조치 내역
```

사람에게는 클릭으로 이동하는 목차이고, AI에게는 탐색 우선순위를 판단하는 인덱스입니다.

---

## 9. AI 컴패니언 파일

DotBrain은 볼트에 AI 도구용 가이드 파일을 자동 생성합니다.

| 파일 | 용도 |
|------|------|
| `CLAUDE.md` | Claude Code가 볼트 구조를 이해하도록 안내 |
| `AGENTS.md` | 에이전트 워크플로 정의 |
| `.cursorrules` | Cursor IDE 규칙 |
| `.claude/agents/` | 작업별 에이전트 (인박스 처리, 프로젝트 관리, 검색 등) |
| `.claude/skills/` | 자동화 스킬 정의 |

**업데이트 방식:**
- `<!-- DotBrain:start -->` ~ `<!-- DotBrain:end -->` 마커 사이만 갱신
- 마커 바깥에 사용자가 추가한 내용은 보존됨
- 앱 버전이 올라가면 자동으로 재생성

---

## 10. 지원 파일 형식

| 형식 | 추출 방식 | 추출 내용 |
|------|-----------|-----------|
| `.md`, `.txt` 등 | 직접 읽기 | 전체 텍스트 |
| `.pdf` | PDFKit | 텍스트 + 페이지수/저자/제목 |
| `.docx` | ZIPFoundation + XML | 본문 텍스트 + 메타데이터 |
| `.pptx` | ZIPFoundation + XML | 슬라이드 텍스트 |
| `.xlsx` | ZIPFoundation + XML | 셀 데이터 |
| `.jpg`, `.png`, `.heic` 등 | ImageIO | EXIF (촬영일, 카메라, GPS) |
| 폴더 | 내부 파일 순회 | 포함 파일 내용 종합 |

바이너리 파일(PDF, 이미지 등)은 `_Assets/`에 저장되고, 요약이 담긴 마크다운 동반 파일이 PARA 폴더에 생성됩니다.

---

## 11. 중복 감지

| 대상 | 감지 방식 | 처리 |
|------|-----------|------|
| 텍스트 파일 (같은 내용, 다른 이름) | SHA256 본문 해시 (프론트매터 제외) | 태그 병합 → 중복 삭제 |
| 바이너리 파일 (≤ 500MB) | SHA256 스트리밍 해시 | 태그 병합 → 중복 삭제 |
| 바이너리 파일 (> 500MB) | 파일 크기 + 수정일 비교 | 태그 병합 → 중복 삭제 |
| 같은 이름, 다른 내용 | 파일명 비교 | 사용자에게 확인 |
| 인덱스 노트와 이름 충돌 | `폴더명.md` 비교 | 사용자에게 확인 |

---

## 12. 설정

설정은 하단 탭의 기어 아이콘에서 접근합니다.

### AI 설정
- **제공자 선택:** Claude CLI / Claude API / Gemini (세그먼트 탭)
- **API 키 관리:** 제공자별 키 입력/변경/삭제
- **키 저장:** macOS Keychain에 안전하게 저장

### PKM 폴더
- **경로 변경:** "변경" 버튼으로 볼트 폴더 재선택
- **구조 초기화:** PARA 폴더가 없으면 생성 버튼 표시

### 권한
- **전체 디스크 접근:** 권한 상태 표시 + 시스템 설정 바로가기

### 앱 관리
- **버전:** 현재 앱 버전 표시
- **업데이트 확인:** 새 버전이 있으면 업데이트 버튼 표시
- **온보딩 재시작:** 온보딩 마법사를 처음부터 다시 진행

---

## 13. 문제 해결

### "확인되지 않은 개발자" / "손상되어 열 수 없음"

```bash
xattr -cr ~/Applications/DotBrain.app
```

또는: **시스템 설정** > **개인정보 보호 및 보안** > "확인 없이 열기" 클릭

### 폴더 접근 권한 팝업

첫 실행 시 PKM 폴더 접근 권한 요청에 반드시 **"허용"**을 선택하세요.

### 메뉴바에 아이콘이 안 보임

메뉴바 공간 부족일 수 있습니다. 다른 아이콘을 `Cmd+드래그`로 제거하거나 Bartender/Ice 앱으로 정리하세요.

### Claude CLI를 찾을 수 없음

Claude 데스크톱 앱이 설치되어 있는지 확인하세요:
```bash
which claude
```

설치되어 있지 않다면 [claude.com/download](https://claude.com/download)에서 설치 후 앱을 재시작하세요.

### AI 분류가 부정확함

- **교정 메모리:** 사용자가 분류를 수정하면 `CorrectionMemory`에 기록되어 다음 분류부터 반영됩니다
- **프로젝트 등록:** 설정에서 프로젝트를 정확히 등록하면 분류 정확도가 올라갑니다
- **영역 등록:** Area를 구체적으로 등록할수록 AI가 맥락을 잘 이해합니다

### 앱 제거

```bash
npx dotbrain --uninstall
```

---

## 14. 개발자 가이드

### 14.1 아키텍처

```
Sources/
├── App/
│   ├── main.swift              ← 진입점
│   ├── AppDelegate.swift       ← NSStatusItem + NSPopover 설정
│   └── AppState.swift          ← 중앙 상태 관리 (@MainActor, ObservableObject)
├── Pipeline/                   ← 다단계 처리 파이프라인
│   ├── InboxProcessor.swift    ← 인박스 → PARA 분류
│   ├── FolderReorganizer.swift ← 단일 폴더 재정리
│   ├── VaultReorganizer.swift  ← 전체 볼트 재정리
│   ├── VaultCheckPipeline.swift← 볼트 감사 + 수리 + 보강
│   └── ProjectContextBuilder.swift ← AI 프롬프트용 컨텍스트 생성
├── Services/                   ← 단일 책임 유틸리티
│   ├── Claude/Classifier.swift ← 2단계 AI 분류
│   ├── AIService.swift         ← Claude/Gemini API 추상화
│   ├── SemanticLinker/         ← 시맨틱 링킹 시스템
│   ├── FileSystem/FileMover.swift ← 파일 이동 + 충돌 해결
│   └── ...
├── Models/                     ← 데이터 모델
│   ├── Frontmatter.swift
│   ├── ClassifyResult.swift
│   ├── PARACategory.swift
│   └── ...
└── UI/                         ← SwiftUI 뷰
    ├── MenuBarPopover.swift
    ├── OnboardingView.swift
    ├── InboxStatusView.swift
    └── ...
```

**레이어 규칙:**
- **UI** → AppState 읽기 + 메서드 호출. 서비스 직접 호출 금지.
- **AppState** → `@Published` 프로퍼티 + 파이프라인 래퍼. 10줄 이상 비즈니스 로직 금지.
- **Pipeline** → 다단계 처리 (TaskGroup, for 루프, 5+ 단계). 반드시 별도 struct/class.
- **Services** → 단일 책임 유틸리티 (actor 또는 struct).

### 14.2 빌드

```bash
# 일반 빌드
swift build

# 릴리스 빌드
swift build -c release

# 클린 빌드 (UI 변경 후 필수)
swift package clean && swift build -c release
```

**의존성:** ZIPFoundation 0.9.19+ (ZIP 파일 처리)만 사용. 나머지는 순수 Swift Foundation + AppKit + SwiftUI.

**바이너리 교체 (개발 중):**
```bash
pkill -9 DotBrain
sleep 2
cp .build/release/DotBrain ~/Applications/DotBrain.app/Contents/MacOS/DotBrain
sleep 1
open ~/Applications/DotBrain.app
```

> UI 변경 후에는 반드시 `swift package clean` 후 클린 빌드해야 합니다. 빌드 캐시가 오래된 오브젝트를 재사용할 수 있습니다.

### 14.3 코드 배치 규칙

| 위치 | 기준 | 예시 |
|------|------|------|
| `Pipeline/` | 다단계 처리 (for 루프, TaskGroup, 5+ 단계) | InboxProcessor, VaultCheckPipeline |
| `Services/` | 단일 책임 유틸리티 (actor 또는 struct) | AIService, FileMover, VaultSearcher |
| `AppState` | `@Published`, 네비게이션, 얇은 파이프라인 래퍼 | startProcessing(), navigateBack() |
| `UI/` | SwiftUI 뷰. AppState만 참조 | InboxStatusView, DashboardView |

**코드 스타일:**
- 한국어: UI 문자열. 영어: 코드와 주석
- `Task.detached(priority:)` 사용 (DispatchQueue.global 금지, DispatchSource 예외)
- `@MainActor` + `await MainActor.run` — 디태치드 태스크에서 UI 업데이트
- `TaskGroup` 동시성 제한: AI 호출 최대 3개, 파일 추출 최대 5개
- 파일 I/O: 프론트매터 추출 4KB, 본문 검색 64KB, 대형 바이너리 1MB 스트리밍

### 14.4 파이프라인 상세

#### InboxProcessor

```
scan → extract (max 5 concurrent) → classify (2-stage AI) → move → semantic link
```

- 미디어 파일은 AI 분류 건너뜀 (기본 .resource 분류)
- 프로젝트명 퍼지 매칭: AI 출력 → 실제 폴더명 매칭
- 태그에서 프로젝트명 중복 제거 (AI 환각 방지)

#### FolderReorganizer

```
flatten (중첩 해제) → deduplicate (SHA256) → classify → move/update
```

- `_Assets/` 하위 구조는 보존
- 플레이스홀더 파일 (`_-` 접두사, 빈 인덱스 노트) 삭제

#### VaultCheckPipeline

```
audit → repair → enrich (AI, max 3 concurrent) → index update → semantic link
```

- `LinkStateDetector`: 이전 스냅샷과 비교하여 사용자가 삭제한 링크 감지
- Archive 카테고리 파일은 보강(Enrich) 단계에서 건너뜀
- 증분 처리: 변경된 폴더만 재스캔

#### ProjectContextBuilder

AI 프롬프트에 주입하는 컨텍스트를 생성합니다:
- 프로젝트 목록 (이름, 요약, 태그, Area 연결)
- 하위 폴더 JSON (AI 환각 방지 — 존재하는 폴더명만 허용)
- 상위 50개 태그 (일관성 유지)
- 교정 메모리 (사용자 피드백 패턴)

### 14.5 서비스 목록

**핵심 AI:**
| 서비스 | 역할 |
|--------|------|
| `AIService` | Claude/Gemini API 추상화, 속도 제한 |
| `Classifier` | 2단계 AI 분류 (Stage 1 배치 + Stage 2 정밀) |
| `NoteEnricher` | 빈 메타데이터 필드 AI 보충 |

**시맨틱 링킹:**
| 서비스 | 역할 |
|--------|------|
| `SemanticLinker` | 메인 오케스트레이터 |
| `TagNormalizer` | 태그 일관성 보장 |
| `LinkCandidateGenerator` | 후보 점수 계산 (태그, 프로젝트, MOC, 폴더 관계) |
| `LinkAIFilter` | AI 기반 링크 평가 ("새 통찰을 얻을 수 있는가?") |
| `RelatedNotesWriter` | `## Related Notes` 섹션 작성 |
| `LinkStateDetector` | 사용자 삭제 링크 감지 |
| `LinkFeedbackStore` | 링크 삭제/부스트 이력 저장 |
| `FolderRelationStore` | 폴더 쌍 관계 (boost/suppress) 관리 |
| `FolderRelationAnalyzer` | 폴더 쌍 후보 제안 |

**파일 처리:**
| 서비스 | 역할 |
|--------|------|
| `FileMover` | 파일 이동, 충돌 해결, 중복 감지 |
| `PKMPathManager` | 경로 검증, PARA 카테고리 감지 |
| `FileContentExtractor` | 형식별 내용 추출 |
| `NoteIndexGenerator` | `.meta/note-index.json` 증분 업데이트 |
| `VaultSearcher` | 볼트 전문 검색 |
| `VaultAuditor` | 볼트 이슈 감지 (깨진 링크, 누락 메타) |
| `FolderHealthAnalyzer` | 폴더 건강 점수 (0-1.0) |
| `ContentHashCache` | 중복 감지 해시 캐시 |

**기타:**
| 서비스 | 역할 |
|--------|------|
| `StatisticsService` | 활동 로그, API 비용 추적 |
| `AICompanionService` | CLAUDE.md, AGENTS.md 등 생성 |
| `CorrectionMemory` | 사용자 분류 교정 기록 |
| `ProjectAliasRegistry` | AI 이름 제안 → 실제 프로젝트 매핑 |
| `KeychainService` | API 키 안전 저장 |
| `RateLimiter` | API 호출 속도 제한 |

### 14.6 모델

| 모델 | 역할 |
|------|------|
| `Frontmatter` | YAML 프론트매터 파싱/직렬화 |
| `PARACategory` | PARA 카테고리 enum (project/area/resource/archive) |
| `ClassifyResult` | AI 분류 결과 (para, tags, summary, confidence 등) |
| `ProcessingModels` | 처리 단계(ProcessingPhase), 결과(ProcessedFileResult), 확인 대기(PendingConfirmation) |
| `PKMStatistics` | 대시보드 통계 (파일 수, 비용, 활동 로그) |
| `SearchResult` | 검색 결과 (매칭 유형, 관련도 점수) |
| `AIResponse` | AI API 응답 래퍼 (텍스트 + 토큰 사용량) |
| `AIProvider` | AI 제공자 enum (claudeCLI/claude/gemini) |
| `ExtractResult` | 바이너리 파일 추출 결과 |

### 14.7 보안

- **경로 탐색 방지:** `URL.resolvingSymlinksInPath()` 후 `hasPrefix` 검사
- **YAML 인젝션 방지:** 태그를 항상 쌍따옴표 배열로 저장 `tags: ["tag1", "tag2"]`
- **폴더명 제한:** `sanitizeFolderName()` — 최대 3 깊이, 255자 제한, `..` 금지
- **API 키 저장:** Claude CLI는 키 불필요. API 키 사용 시 AES-GCM 암호화 + 하드웨어 UUID + HKDF로 기기 종속 저장
- **인덱스 우선 검색:** `.meta/note-index.json`을 먼저 조회하여 불필요한 파일 I/O 최소화

### 14.8 릴리스

**릴리스 순서 (필수):**

```
1. swift build -c release              ← 반드시 release 빌드
2. scripts/build-dmg.sh                ← DMG 생성
3. gh release create vX.Y.Z            ← GitHub 릴리스 (DMG + 바이너리 + 아이콘 + plist)
4. npm publish                         ← npm 패키지 배포
5. npx dotbrain                        ← 설치 확인
```

**버전 동기화 필수:** `Resources/Info.plist`, `npm/package.json`, git 태그가 모두 일치해야 합니다.

**배포 파일:**
- `DotBrain-{VERSION}.dmg` — 기본 설치 파일
- `DotBrain` — 바이너리 (하위 호환)
- `AppIcon.icns` — 앱 아이콘
- `Info.plist` — 앱 메타데이터

---

<p align="center">
Made by Hwaa
</p>
