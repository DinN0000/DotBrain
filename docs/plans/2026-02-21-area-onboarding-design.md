# Area-Project 온보딩 설계

## 목표

온보딩에서 Area(도메인)를 먼저 등록하고 Project를 Area에 연결하여, AI 분류기가 첫 분류부터 Area-Project 계층 구조를 활용할 수 있게 한다.

## 온보딩 플로우 변경

```
기존 (5스텝): 환영 → 폴더 → 프로젝트 → AI키 → 완료
변경 (6스텝): 환영 → 폴더 → 도메인 등록 → 프로젝트 등록 → AI키 → 완료
```

### Step 2: 도메인 등록 (신규)

- 제목: "도메인(제품명)을 등록하세요"
- 설명: "지속적으로 관리하는 영역입니다. 프로젝트를 묶는 상위 카테고리 역할을 합니다."
- UI: 기존 projectStep과 동일 패턴 (TextField + 리스트 + 추가/삭제)
- 등록 시: `2_Area/{name}/` 폴더 + 인덱스 노트 생성
- 필수 아님: 0개로도 다음 단계 진행 가능 (Area 없는 Project 허용)

### Step 3: 프로젝트 등록 (기존 Step 2 확장)

- 기존 projectStep UI 유지
- Area 드롭다운(Picker) 추가: Step 2에서 등록한 Area 목록 + "없음"
- 등록 시:
  - `1_Project/{name}/` 폴더 + 인덱스 노트 생성
  - 인덱스 노트 frontmatter에 `area: "도메인명"` 기록
  - Area 인덱스 노트의 frontmatter `projects` 배열에 프로젝트명 추가
- 프로젝트 목록에 Area 뱃지 표시

### Step 4-5: 기존 Step 3-4와 동일

AI키 설정, 완료 화면 — 변경 없음.

## 메타데이터 저장

물리적 폴더 구조(1_Project/, 2_Area/)는 유지. frontmatter 메타데이터로 Area-Project 관계 저장.

### Area 인덱스 노트 예시

```yaml
# 2_Area/금융/금융.md
---
para: area
tags: ["금융", "fintech"]
summary: "금융 도메인 관리 영역"
projects: ["PoC-신한은행", "PoC-여신협회"]
---
```

### Project 인덱스 노트 예시

```yaml
# 1_Project/PoC-신한은행/PoC-신한은행.md
---
para: project
tags: ["PoC", "신한은행"]
summary: "신한은행 PoC 프로젝트"
area: "금융"
---
```

## AI Classifier 연동

### ProjectContextBuilder 확장

기존 `buildProjectContext()`가 프로젝트 목록을 생성. 여기에 Area 매핑 추가:

```
## Area(도메인) 목록
- 금융: PoC-신한은행, PoC-여신협회
- 인사: (프로젝트 없음)

## 활성 프로젝트 목록
- PoC-신한은행 (Area: 금융)
- PoC-여신협회 (Area: 금융)
```

### Classifier 프롬프트 변경

분류 규칙 테이블의 area 설명 강화:

| para | 조건 |
|------|------|
| project | 활성 프로젝트의 직접 작업 문서 (마감 있는 작업) |
| area | 등록된 도메인 전반의 관리/운영 문서. 특정 프로젝트에 속하지 않는 도메인 문서 |
| resource | 참고/학습/분석 자료 |
| archive | 완료/비활성 문서 |

### SemanticLinker 활용

같은 Area 내 문서끼리 연결 우선순위 높임. Area 인덱스 노트가 허브 역할.

## 기존 사용자 호환

- 이미 온보딩 완료한 사용자: 영향 없음. 설정에서 Area 추가 가능.
- Area 없이 만든 기존 Project: `area` 필드 없이 정상 동작.
- re-onboarding 시: 기존 Area/Project 자동 로드.

## 스코프 제한

- 온보딩 UI 변경 (OnboardingView.swift)
- FrontmatterWriter에 area 필드 지원 추가
- ProjectContextBuilder에 Area 컨텍스트 빌드 추가
- Classifier 프롬프트 Area 규칙 강화
- 설정에서 Area 관리 UI는 이 스코프 밖 (추후)
