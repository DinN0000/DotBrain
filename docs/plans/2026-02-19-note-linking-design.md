# Note Linking Redesign — MOC + Tag Hybrid

**Date**: 2026-02-19
**Status**: Approved

## Problem

1. 존재하지 않는 링크(broken links)가 생성되면 안 됨
2. 노트 간 연결이 PARA 기반 계층적 연결에만 집중되어 있어 빈약함
3. 73/130 (56%) 노트가 outgoing link 0개, 17개 orphan 노트 존재
4. ContextLinker가 inbox processing 시에만 작동하여 기존 노트 간 연결 불가

## Approved Approach: MOC + Tag Hybrid (Approach C)

태그 기반 후보 생성 + AI 필터링으로 풍부하고 정확한 노트 연결을 구축한다.

### Phase 1: Tag Normalization (전제 조건)

프로젝트 하위 노트에 프로젝트 폴더명 태그를 자동 부여하고, `project:` frontmatter 필드를 통해 PARA 카테고리를 넘어 태그를 전파한다.

**동작**:
- 프로젝트 폴더 하위 노트: 해당 프로젝트명이 tags에 없으면 추가
- `project: X` 필드가 있는 Area/Resource/Archive 노트: X가 tags에 없으면 추가
- 예: `project: SCOPE`인 Area 노트 → tags에 "SCOPE" 추가 → SCOPE 프로젝트의 1_Project 노트와 자동 연결

**목적**: 태그가 PARA 경계를 넘는 크로스-카테고리 연결의 핵심 축이 됨.

### Phase 2: Candidate Generation

태그 overlap + MOC co-membership + project field 공유로 후보를 생성한다.

**후보 점수 기준**:
| Signal | Weight | Description |
|--------|--------|-------------|
| Tag overlap ≥ 2 | 높음 | 공유 태그 수에 비례 |
| MOC co-membership | 중간 | 같은 MOC `## 문서 목록`에 등장 |
| Shared project field | 높음 | 동일 project 필드 값 |

**제약**:
- 후보는 실제 존재하는 노트 목록에서만 생성 (broken link 원천 차단)
- 이미 Related Notes에 있는 노트는 후보에서 제외
- 자기 자신 제외

### Phase 3: AI Filtering + Context Generation

후보가 있는 노트를 배치로 AI에 전달하여 실제 관련성을 판단하고 context 문구를 생성한다.

**동작**:
- 노트당 후보 목록 (이름 + summary + tags) 전달
- AI가 상위 5개 선택 + context 생성 (`"~하려면"`, `"~할 때"` 형식)
- Haiku 모델 사용 (비용 최소화)
- 배치 처리: 최대 3개 동시 API 호출

**비용**: ~$0.001/노트 (Haiku), 130개 노트 전체 스캔 시 ~$0.13

### Phase 4: Related Notes Recording

기존 Related Notes와 merge하여 기록한다.

**규칙**:
- 기존 수동 링크 보존 (덮어쓰지 않음)
- AI 생성 링크 추가/갱신
- 최대 5개 유지 (수동 우선)
- 역방향 링크도 자동 추가 (A→B이면 B→A도 추가)
- 파일 존재 여부 최종 확인 후 기록 (broken link 방지 이중 체크)

### Phase 5: Execution Triggers

| Trigger | Scope | Description |
|---------|-------|-------------|
| 볼트 점검 (Vault Audit) | 전체 볼트 | 모든 노트 대상 bulk 처리 |
| 인박스 처리 (Inbox Processing) | 새 노트 + 역연결 | 새 노트에 link 생성 + 기존 노트에 역연결 추가 |
| AI 재분류 (Reclassification) | 재분류 대상 | 이동된 노트의 link 갱신 |

## Broken Link Prevention

1. **후보 생성 단계**: vault 내 실제 .md 파일 목록에서만 후보 생성
2. **기록 단계**: `[[wikilink]]` 기록 직전에 파일 존재 여부 확인
3. **MOC 참조**: MOC에서 추출한 이름도 실제 파일 존재 여부 검증

## Architecture

```
SemanticLinker (new)
├── TagNormalizer          — Phase 1: 태그 정규화
├── LinkCandidateGenerator — Phase 2: 후보 생성
├── LinkAIFilter           — Phase 3: AI 필터링 + context
└── RelatedNotesWriter     — Phase 4: Related Notes 기록

Integration points:
├── VaultAuditor.audit()        — bulk linking
├── InboxProcessor.process()    — new note linking
└── VaultReorganizer.reorganize() — reclassification linking
```

## Non-Goals

- Graph visualization (Obsidian이 처리)
- 수동 링크 자동 삭제
- 이미지 동반 노트 간 연결 (이미지 제외)
