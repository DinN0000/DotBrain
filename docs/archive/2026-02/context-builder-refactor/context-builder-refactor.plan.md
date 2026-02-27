# Plan: ProjectContextBuilder Index-First Refactor

## Feature Name
context-builder-refactor

## Problem Statement

ProjectContextBuilder의 5개 함수가 모두 디스크 직접 스캔으로 동작하여:
1. **속도 저하**: 분류 시 수십~수백 파일 I/O 발생 (볼트 커질수록 악화)
2. **태그 누락**: `buildTagVocabulary()`가 폴더당 5개만 샘플링하여 태그 90%+ 손실
3. **컨텍스트 부실**: `buildSubfolderContext()`가 폴더명만 제공, 설명 없음
4. **중복 코드**: `buildWeightedContext()` fallback이 다른 함수들과 데이터 중복
5. **죽은 코드**: `extractScope()`가 분류기에서 참조되지 않음
6. **잔존 버그**: 프로젝트 삭제 시 Area 인덱스 노트의 `projects` 필드 미정리

CLAUDE.md 규칙 "Index-first search patterns: load `.meta/note-index.json` first, fallback to directory scan only if needed" 위반.

## Scope

### In Scope
- `buildTagVocabulary()` → note-index.json 기반 전환
- `buildSubfolderContext()` → index.folders 정보로 보강 (폴더명 + tags + summary)
- `buildProjectContext()` → index 기반 전환 + `extractScope()` 삭제
- `buildWeightedContext()` → fallback 함수 3개 삭제 (buildProjectDocuments, buildFolderSummaries, buildArchiveSummary)
- `buildAreaContext()` → 프로젝트 삭제 시 Area `projects` 필드 정리 로직 추가
- Classifier 프롬프트 지시문 수정 (enriched subfolderContext 구조 반영)
- NoteIndexEntry에 `area` 필드 추가 (프로젝트 인덱스 노트에서 area 정보 필요)

### Out of Scope
- NoteIndexGenerator 자체의 성능 개선
- Classifier AI 프롬프트 전면 재설계
- SemanticLinker 로직 변경

## Requirements

### FR-01: buildTagVocabulary() Index 전환
- note-index.json의 notes 전체에서 태그 집계
- index 없으면 기존 디스크 스캔 fallback
- top 50 제한 유지, 전체 노트 기반 빈도 집계

### FR-02: buildSubfolderContext() 보강
- 기존: `{"area":["Dev","Health"]}` (폴더명만)
- 변경: `{"area":[{"name":"Dev","tags":["swift","infra"],"summary":"...","noteCount":5},...]}`
- 폴더 목록은 디스크 스캔 유지 (빈 폴더 커버)
- index.folders에서 tags/summary 매칭하여 보강
- Classifier 프롬프트 지시문도 새 구조에 맞게 수정

### FR-03: buildProjectContext() Index 전환 + extractScope 삭제
- index.folders에서 프로젝트별 summary/tags 획득
- `extractScope()` 삭제 (분류기 미참조 확인됨)
- area 필드는 NoteIndexEntry에 추가하여 해결 (FR-06)
- index 없으면 기존 디스크 fallback

### FR-04: buildWeightedContext() Fallback 삭제
- 루트 인덱스 노트 body 읽기는 유지 (index에 body 없음)
- fallback 3개 함수 삭제: buildProjectDocuments, buildFolderSummaries, buildArchiveSummary
- 루트 인덱스 없으면 빈 문자열 반환 (다른 context 함수들이 이미 커버)

### FR-05: Area projects 필드 정리
- 프로젝트 삭제 시 (`removeProject`, `PARAMover` 등) 관련 Area 인덱스 노트의 `projects` 필드에서 해당 프로젝트명 제거
- VaultCheckPipeline에서 존재하지 않는 프로젝트 참조를 정리하는 로직 추가

### FR-06: NoteIndexEntry에 area 필드 추가
- NoteIndexEntry에 `area: String?` 필드 추가
- NoteIndexGenerator.scanFolder()에서 frontmatter.area 읽어 저장
- note-index.json version 유지 (하위 호환 — optional 필드)

## Implementation Order

1. **FR-06** NoteIndexEntry area 필드 추가 (다른 FR의 선행 조건)
2. **FR-01** buildTagVocabulary index 전환 (독립적, 가장 효과 큼)
3. **FR-03** buildProjectContext index 전환 + extractScope 삭제
4. **FR-02** buildSubfolderContext 보강 + Classifier 프롬프트 수정
5. **FR-04** buildWeightedContext fallback 삭제
6. **FR-05** Area projects 필드 정리

## Risk & Side Effects

| Risk | Severity | Mitigation |
|------|----------|------------|
| 첫 실행 시 index 없음 | Low | 모든 함수에 디스크 fallback 유지 |
| 프롬프트 변경으로 분류 품질 변동 | Medium | enriched subfolderContext가 기존 weighted fallback 정보를 대체하므로 개선 방향이지만, 실제 분류 결과 검증 필요 |
| note-index.json 스키마 변경 | Low | area는 optional 필드, 기존 index 파싱 시 nil로 처리되어 하위 호환 |
| buildWeightedContext fallback 삭제 시 개별 파일 수준 컨텍스트 손실 | Medium | enriched subfolderContext의 폴더 수준 tags/summary로 대체. 분류 품질 저하 확인되면 후속 작업으로 index.notes 기반 파일 수준 보강 검토 |
| Area projects 정리 누락 경로 | Low | VaultCheck에서 주기적 정리하므로 즉시 반영 안 되어도 다음 점검 시 수정됨 |

## Success Criteria

- [ ] 분류 시 디스크 I/O: index 로드 1회 + 디스크 fallback 최소화
- [ ] buildTagVocabulary: 전체 노트 태그 반영 (prefix(5) 샘플링 제거)
- [ ] buildSubfolderContext: 폴더별 tags/summary 포함
- [ ] extractScope, fallback 3개 함수 삭제 → 코드 100줄+ 감소
- [ ] Area projects 정리 → 삭제된 프로젝트 잔존 방지
- [ ] swift build 경고 0개
- [ ] 기존 분류 동작 유지 (regression 없음)
