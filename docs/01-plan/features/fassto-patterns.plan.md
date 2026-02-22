# fassto-patterns Planning Document

> **Summary**: fassto_akb 볼트 분석에서 도출된 9개 패턴을 DotBrain에 단계적으로 도입 (패턴 #2 보류)
>
> **Project**: DotBrain
> **Version**: 2.2.0 ~ 2.5.0
> **Author**: hwaa
> **Date**: 2026-02-20
> **Status**: Phase A #3 CommonKB KEEP, #7 source_ref CLOSED, Phase B~E CLOSED (2026-02-22)

---

## 1. Overview

### 1.1 Purpose

fassto_akb Obsidian 볼트(291 마크다운, 84 디렉토리)의 구조적 강점을 DotBrain에 도입한다.
9개 에이전트 팀 비교 분석 + Tier별 영향 분석 결과를 바탕으로, 각 패턴의 사이드이펙트를 사전에 해결하는 방향으로 구현한다.

### 1.2 Background

fassto_akb는 물류 제품(파스토 2.0) 기획 볼트로, DotBrain과 다른 접근법을 사용한다:
- zero frontmatter, zero tags, 100% wiki-link 기반 탐색
- 5-file feature template (index + 기획 + 기능명세 + 데이터명세 + 개발지침)
- 도메인 격리 + 엔트리 문서 backlink 패턴
- `[name].md` bracket index naming

비교 분석에서 10개 도입 후보 패턴이 식별되었고, 코드 레벨 영향 분석 결과 1개(#2 Bracket Index)는 비용이 이점을 압도하여 보류로 확정되었다.

### 1.3 제외 패턴

| # | 패턴 | 보류 사유 |
|---|------|----------|
| 2 | Bracket Index `[name].md` | 8+ 파일 동시 수정, Obsidian `[[[name]]]` 파싱 불확실, shell glob 충돌, `ContextMapBuilder.parseMOC()` 파손, `FolderHealthAnalyzer` 전면 오탐, `FileMover.ensureIndexNote()` 이중 생성 |

---

## 2. Release Roadmap

```
v2.2.0  [Phase A] #3 Common KB + #7 source_ref       (안전, 기존 영향 zero)
v2.3.0  [Phase B] #1 엔트리 백링크 + #9 링크 격리     (SemanticLinker 집중 개선)
v2.4.0  [Phase C] #4 환각 방지 + #5 5-File Template   (AI 품질 + 프로젝트 scaffold)
v2.5.0  [Phase D] #10 doctype + #8 하위 카테고리       (메타데이터 확장 + 구조 심화)
v2.6.0  [Phase E] #6 Zero Orphans                      (모든 선행 패턴 안정화 후)
```

---

## 3. Phase A — v2.2.0: Common KB + Source Ref

### 3.1 패턴 #3: Common Knowledge Base

**목표**: 사용자가 `3_Resource/_CommonKB/`에 도메인 용어집, 분류 힌트를 넣으면 AI 분류 컨텍스트에 자동 반영

**수정 대상**:

| File | Change |
|------|--------|
| `ProjectContextBuilder.swift` | `buildCommonContext()` 메서드 추가 |
| `InboxProcessor.swift` (40~44행) | commonContext를 classifier 프롬프트에 주입 |
| `VaultReorganizer.swift` (88행) | 동일 주입 |
| `FolderReorganizer.swift` (80행) | 동일 주입 |
| `PKMPathManager.swift` | `commonKBPath` computed property 추가 |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| `_` 접두사 스킵 로직 (8곳)이 `_CommonKB/`를 무시 | `buildCommonContext()`에서 `_CommonKB/` 경로를 직접 읽기. 기존 8곳의 `!hasPrefix("_")` 로직은 그대로 유지 — MOC 생성, 시맨틱 링크, 재분류에서 `_CommonKB/`가 제외되는 건 올바른 동작 |
| 토큰 폭발 (사용자가 큰 문서를 넣는 경우) | `buildCommonContext()`에서 각 `.md` 파일의 첫 500자만 추출, 전체 합계 2000자 cap. 넘으면 파일 생성일 기준 최신 순으로 잘림 |
| `existingSubfolders()`에 `_CommonKB` 미포함 | 의도된 동작. AI가 파일을 `_CommonKB`로 분류하면 안 됨. 추가 조치 불필요 |
| `_CommonKB/` 디렉토리 미존재 시 | `guard fm.fileExists(atPath: commonKBPath) else { return "" }` — 옵트인 방식 유지 |

**구현 순서**:
1. `PKMPathManager`에 `commonKBPath` 추가
2. `ProjectContextBuilder.buildCommonContext()` 구현 (500자/파일, 2000자 총합 cap)
3. `InboxProcessor`, `VaultReorganizer`, `FolderReorganizer`에서 `buildCommonContext()` 호출 추가
4. `initializeStructure()`에 `_CommonKB/` 생성은 포함하지 않음 (사용자가 직접 만들어야 활성화)

### 3.2 패턴 #7: Source Reference Field

**목표**: `Frontmatter`에 `sourceRef: String?` 필드를 추가하여 원본 파일 + 페이지 정보 추적

**수정 대상**:

| File | Change |
|------|--------|
| `Frontmatter.swift` | `var sourceRef: String?` 추가, `applyScalar`에 `case "source_ref"`, `stringify()`에 출력 |
| `FrontmatterWriter.swift` | `createCompanionMarkdown()`에서 `source_ref` 설정, `injectFrontmatter()`에 파라미터 추가 |
| `PDFExtractor.swift` | 페이지 수 정보를 `ExtractResult`에 포함 (점진적 — v2.2에서는 총 페이지 수만) |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| 기존 노트에 `source_ref` 없음 | optional 필드이므로 nil 처리. 마이그레이션 불필요 |
| `VaultAuditor`가 `source_ref` broken reference를 검사하지 않음 | v2.2에서는 검사하지 않음. v2.5 `VaultAuditor` 확장 시 추가 검토 |
| `injectFrontmatter()` 호출부 전체 수정 | `sourceRef` 파라미터를 `String? = nil`로 추가하여 기존 호출부 변경 없이 도입 |
| `PDFExtractor` 대폭 수정 | v2.2에서는 `"filename.pdf (N pages)"` 형태만. 페이지별 텍스트 매핑은 v2.5 이후 |

**구현 순서**:
1. `Frontmatter` struct에 `sourceRef` 추가 + parse/stringify
2. `FrontmatterWriter.injectFrontmatter()`에 `sourceRef: String? = nil` 파라미터 추가
3. `FrontmatterWriter.createCompanionMarkdown()`에서 `source_ref` 자동 설정
4. `PDFExtractor`에서 페이지 수만 `ExtractResult.metadata`에 추가

---

## 4. Phase B — v2.3.0: Entry Backlink + Cross-Category Link Isolation

### 4.1 패턴 #1: Entry Document Backlink

**목표**: 모든 노트의 `## Related Notes`에 소속 폴더의 MOC 파일로의 백링크를 자동 포함

**수정 대상**:

| File | Change |
|------|--------|
| `RelatedNotesWriter.swift` | MOC 백링크 전용 슬롯 추가 (prefix(5) -> MOC 1 + AI 4) |
| `SemanticLinker.swift` (43, 116, 225, 310행) | `writeRelatedNotes()` 호출 시 폴더 정보 전달 |
| `SemanticLinker.swift` (461행) | `buildNoteIndex()`의 MOC 스킵 로직에서 `noteNames` Set에 MOC도 포함 (백링크 검증용) |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| 5개 슬롯 중 1개를 MOC가 점유 | `RelatedNotesWriter`에 MOC 슬롯 분리: `mocEntry` (1개, 고정) + `aiEntries` (최대 4개). `prefix(5)` 대신 `[mocEntry] + Array(aiEntries.prefix(4))` |
| `writeRelatedNotes()` 시그니처에 폴더 정보 없음 | 새 파라미터 `mocFileName: String? = nil` 추가. nil이면 기존 동작 유지 (하위 호환) |
| `noteNames` 검증에서 MOC 탈락 (`buildNoteIndex()`가 MOC 스킵) | MOC 파일명은 `noteNames` 검증을 bypass. `RelatedNotesWriter`에서 `mocFileName`은 `noteNames.contains()` 체크 없이 직접 삽입 |
| 역방향 링크 무한 루프 (MOC에 `## Related Notes` 추가됨) | `SemanticLinker`의 reverse link 생성 로직에서 MOC 파일은 reverse link 대상에서 제외: `guard !targetFile.hasSuffix("\(folderName).md")` |
| `ContextMapBuilder.parseMOC()`에 `## Related Notes` 헤더 간섭 | `parseMOC()`는 `## 포함된 노트` 또는 `## 문서 목록` 헤더만 파싱하므로 `## Related Notes`에는 영향 없음. 조치 불필요 |
| 기존 볼트 재처리 시 6개 링크 문제 | 기존 5개 AI 링크가 있는 노트에 MOC를 추가하면 5번째 AI 링크가 밀려남. 허용: MOC 1 + AI 4 = 5로 기존 제한 내 유지. 기존 노트의 `## Related Notes`는 다음 SemanticLinker 실행 시 자연스럽게 재구성 |
| `## Related Notes`의 relation 그룹화 | MOC 백링크 전용 relation type `"folder"` 추가. `relationOrder`에 `"folder"`를 맨 앞에 추가. 라벨: `"### 상위 문서"` |

### 4.2 패턴 #9: Cross-Category Link Isolation

**목표**: `LinkCandidateGenerator`에 PARA 카테고리 간 패널티를 적용하여 Archive/Resource의 noise link 억제

**수정 대상**:

| File | Change |
|------|--------|
| `LinkCandidateGenerator.swift` (46행 이후) | PARA 기반 penalty 로직 추가 |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| 유용한 cross-category 연결 손실 | hard block이 아닌 soft penalty 방식 채택. 패널티 매트릭스: `Project<->Area: 0`, `Project<->Resource: -0.5`, `Project<->Archive: -1.5`, `Area<->Resource: -0.3`, `Area<->Archive: -1.0`, `Resource<->Archive: -0.5`. score가 0 이하면 기존 guard에서 제거됨 |
| 기존 cross-category 링크 불일치 | 소급 제거하지 않음. 기존 `## Related Notes`에 이미 작성된 링크는 자연스럽게 유지. 새 SemanticLinker 실행부터 규칙 적용 |
| `PARAMover`로 카테고리 변경 시 기존 링크 위반 | v2.3에서는 조치하지 않음 (기존 링크 유지). v2.5에서 `PARAMover` 후 `SemanticLinker` 재실행 트리거를 추가할 수 있음 |
| 16개 카테고리 쌍 규칙 관리 | `paraPenalty(from:to:)` 함수 하나로 매트릭스 관리. 설정 UI 없이 코드 상수로 시작. 향후 필요 시 `AppState`의 설정으로 이동 가능 |

**구현 순서** (Phase B 전체):
1. `LinkCandidateGenerator`에 `paraPenalty(from:to:)` 추가 + score 계산에 반영 (#9)
2. `RelatedNotesWriter`에 MOC 슬롯 분리 로직 구현 (#1)
3. `SemanticLinker`의 `writeRelatedNotes()` 호출부 4곳에 `mocFileName` 전달 (#1)
4. reverse link 생성 시 MOC 파일 제외 조건 추가 (#1)
5. `relationOrder`에 `"folder"` 추가 + `"### 상위 문서"` 라벨 (#1)

---

## 5. Phase C — v2.4.0: No-Hallucination + 5-File Template

### 5.1 패턴 #4: AI Provenance Tracking (환각 방지)

**목표**: AI가 생성한 메타데이터에 `ai-generated` 마킹 + 프롬프트에 원문 인용 지시 추가

**수정 대상**:

| File | Change |
|------|--------|
| `Frontmatter.swift` | `var aiGenerated: Bool?` 추가, parse/stringify |
| `NoteEnricher.swift` (39~55행) | 프롬프트에 "원문에서 근거를 인용" 지시 추가. `updated.aiGenerated = true` 설정 |
| `FrontmatterWriter.swift` | `injectFrontmatter()`에 `aiGenerated: Bool? = nil` 파라미터 |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| AI 비용 증가 (응답 길이 2-3배) | **인용구 포함을 강제하지 않음**. 프롬프트에 `"가능한 경우 원문에서 근거를 인용"` (soft 지시). `maxTokens: 512` 유지. 응답이 잘려도 JSON 구조는 앞부분에 위치하므로 파싱 가능 |
| 파싱 복잡도 증가 | 중첩 JSON(`citations` 배열)을 추가하지 않음. `ai-generated: true/false`만 flat field로 추가. 기존 `extractJSON()` 변경 불필요 |
| strict mode fallback | fallback 없음. `ai-generated` 마킹은 항상 적용 (AI가 enrichment를 수행하면 무조건 `true`). 인용구 없어도 enrichment 자체는 진행 |
| 기존 볼트에 `ai-generated` 없음 | optional 필드이므로 nil = "알 수 없음" 상태. `Frontmatter.parse()`에서 키 없으면 nil 반환. 소급 적용 불필요 |
| 사용자가 AI 태그를 수동 수정한 혼합 상태 | `ai-generated`는 "이 노트가 AI enrichment를 받았는가"의 노트 단위 마킹. 필드 단위 추적은 과도한 복잡성이므로 v2.4에서는 하지 않음 |

### 5.2 패턴 #5: 5-File Project Template

**목표**: 프로젝트 생성 시 index + 4개 구조 파일 자동 생성

**템플릿 구성**:
```
ProjectName/
  ProjectName.md          (기존 index — 목적, 현재 상태)
  1-목표와범위.md          (프로젝트 목표, 범위 정의, 성공 기준)
  2-작업현황.md            (진행 중/완료/대기 작업 목록)
  3-참고자료.md            (관련 링크, 문서, 레퍼런스)
  4-회고.md               (교훈, 개선점, 후속 조치)
```

**수정 대상**:

| File | Change |
|------|--------|
| `ProjectManager.swift` (13~41행) | `createProject()`에 4개 추가 파일 생성 로직 |
| `TemplateService.swift` | 4개 새 템플릿 상수 |
| `NoteEnricher.swift` | 빈 템플릿 파일 enrichment 방지 로직 |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| 빈 파일을 `NoteEnricher`가 enrichment 대상으로 인식 | 템플릿 파일의 frontmatter에 `status: draft` 설정. `NoteEnricher.enrichNote()`에 guard 추가: `guard existing.status != .draft \|\| !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty` — draft이면서 본문이 비어있으면 enrichment 스킵 |
| 기존 프로젝트와 불일치 | 기존 프로젝트에 소급 적용하지 않음. 새로 생성되는 프로젝트부터만 적용. `FolderHealthAnalyzer`의 건강도 검사에 "템플릿 파일 누락" 이슈를 추가하되, severity를 `info`(최저)로 설정하여 기존 프로젝트가 warning을 받지 않도록 함 |
| 소규모 프로젝트에 불필요한 파일 | `ProjectManager.createProject()`에 `template: ProjectTemplate = .standard` 파라미터 추가. `.minimal`은 index만, `.standard`는 5파일. UI에서 선택 가능. 기본값은 `.standard` |
| `completeProject()` 호출 시 빈 템플릿이 Archive로 이동 | 허용. Archive에 빈 파일이 있어도 실질적 문제 없음. `completeProject()`의 `updateAllNotes(in:status:para:)`가 모든 파일의 status를 completed로 변경하는 것은 정상 동작 |
| 한국어 파일명 인코딩 문제 | 파일명을 영어-한국어 혼합으로 유지: `1-goals.md`, `2-tasks.md`, `3-references.md`, `4-retrospective.md`. 본문 제목만 한국어: `# 목표와 범위` |
| `MOCGenerator`가 빈 summary로 AI 요약 트리거 | `MOCGenerator.generateMOC()`에서 `extractContext()`가 빈 본문이면 빈 context 반환 — 기존 동작으로 문제 없음. MOC에는 `[[1-goals]]` 등 wikilink만 나열되므로 AI 호출 없음 |

---

## 6. Phase D — v2.5.0: Doctype + Sub-Category

### 6.1 패턴 #10: Document Type Field

**목표**: `Frontmatter`에 `doctype` 필드를 추가하여 문서의 역할(overview, spec, guide 등)을 추적

**doctype 값 (5개, 시작은 간소하게)**:
```
overview    — 개요/소개 문서
spec        — 명세/기획 문서
guide       — 가이드/절차 문서
meeting     — 회의록/논의 기록
note        — 일반 노트 (default)
```

**수정 대상**:

| File | Change |
|------|--------|
| `Frontmatter.swift` | `enum DocType` + `var doctype: DocType?`, parse/stringify |
| `ClassifyResult.swift` | `var doctype: DocType?` 추가 |
| `Classifier.swift` | Stage1/Stage2 프롬프트에 doctype 분류 규칙 추가 |
| `FrontmatterWriter.swift` | `injectFrontmatter()`에 `doctype` 파라미터 추가 |
| `MOCGenerator.swift` | doctype별 그룹화 (선택적) |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| Frontmatter 파서 전파 체인 | `doctype` 파라미터를 모든 팩토리/머지 메서드에 `DocType? = nil`로 추가하여 기존 호출부 변경 없음. `stringify()`에서 nil이면 출력 생략 |
| AI 분류 정확도 모호성 | doctype을 7개에서 5개로 축소 (overview/spec/guide/meeting/note). fassto의 7개에서 `spec-feature`와 `spec-data`를 `spec`으로 통합, `dev-guide`를 `guide`로 일반화 |
| 기존 볼트의 doctype 부재 | optional 필드 nil 허용. `VaultAuditor`의 gap analysis에 `missingDoctype`은 추가하되, severity를 `info`로 설정. 대규모 재처리는 `FolderReorganizer` 실행 시 사이드킥으로 doctype도 판별하는 옵션 추가 |
| 바이너리 companion markdown의 doctype | `FrontmatterWriter.createCompanionMarkdown()`에서 바이너리 원본의 확장자 기반 추론: PDF/DOCX -> `note` (default), 사용자가 수동으로 변경 가능 |
| `MOCGenerator` doctype 그룹화 시 빈 그룹 처리 | 그룹에 문서가 0개이면 해당 섹션을 생략. `## 문서 목록` 다음에 doctype별 `### Overview`, `### Specs` 등을 추가하되, 문서가 있는 그룹만 표시 |

### 6.2 패턴 #8: Sub-Category Layer

**목표**: Area/Resource 하위에 2단계 카테고리를 허용하여 폴더 비대화 해결

**수정 대상**:

| File | Change |
|------|--------|
| `ClassifyResult.swift` | `var subCategory: String?` 추가 |
| `Classifier.swift` | Stage1/Stage2에 `subCategory` 필드 추가 + 프롬프트에 기존 하위 폴더 정보 주입 |
| `PKMPathManager.swift` (28~34행) | `sanitizeFolderName()` depth 3 -> 4 변경 + 보안 강화 |
| `PKMPathManager.swift` | `targetDirectory()`에 subCategory 경로 조합 로직 |
| `ProjectContextBuilder.swift` | `buildSubfolderContext()` 2단계 스캔 |
| `ContextMapBuilder.swift` | 재귀 스캔 로직 추가 |
| `MOCGenerator.swift` | 중간 MOC 생성 (하위 카테고리 폴더용) |
| `SemanticLinker.swift` | `buildNoteIndex()` 2단계 폴더 인식 |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| `sanitizeFolderName()` depth 3 제한 충돌 | depth 제한을 3 -> 4로 변경. 보안 강화 조치 동반: (1) 절대 경로 길이 1024자 제한 추가, (2) 각 component에 대해 `isPathSafe()` 호출하여 symlink traversal 차단, (3) component당 `..` 필터는 기존 유지 |
| AI가 `targetFolder`와 `subCategory`에 동일 이름 반환 | `sanitizeSubCategory(targetFolder:subCategory:)` 함수 추가: `subCategory`가 `targetFolder`과 같거나, PARA 카테고리명과 같으면 nil로 치환 |
| `existingSubfolders()`가 1단계만 반환 | `existingSubfolders(includeNested: Bool = false)` 파라미터 추가. `includeNested: true`이면 2단계까지 `["area/DevOps": ["인프라", "CI-CD"]]` 형태로 반환. Classifier 프롬프트에 이 정보를 주입하여 기존 하위 카테고리 인식 가능 |
| `ContextMapBuilder`가 2단계 미인식 | `build()`에서 각 PARA 폴더 아래 재귀 enumerator 사용. depth 2까지만 스캔 (무한 재귀 방지). 하위 카테고리 폴더의 MOC도 `parseMOC()`로 파싱 |
| 기존 볼트의 flat 구조 | `subCategory`가 nil이면 기존 동작 유지. `targetDirectory()`에서 `subCategory == nil \|\| subCategory.isEmpty` 분기 필수. 기존 볼트에 소급 적용하지 않음 — 사용자가 수동으로 하위 폴더를 만들면 `FolderReorganizer`가 인식 |
| `FolderReorganizer` flatten 로직 방향 불일치 | `FolderReorganizer`에 `nestFolder(folder:into:)` 메서드 추가 (flatten의 역방향). v2.5에서는 수동 트리거만 제공 |
| `MOCGenerator` 중간 MOC 생성 | 하위 카테고리 폴더에도 `generateMOC()`를 호출하되, 상위 MOC의 `## 문서 목록`에는 하위 MOC를 `[[하위카테고리]]` wikilink로 포함. 하위 MOC의 `## 문서 목록`에는 해당 폴더의 문서만 나열 |

---

## 7. Phase E — v2.6.0: Zero Orphans

### 7.1 패턴 #6: Link Density Guarantee

**목표**: 모든 노트가 최소 1개의 wikilink를 보유하도록 보장

**전제 조건**: Phase A~D의 모든 패턴이 안정화되어야 함
- #1 (엔트리 백링크)가 있으면 대부분의 노트가 MOC 링크를 이미 보유
- #9 (링크 격리)가 있으면 noise link 없이 품질 유지 가능
- #4 (환각 방지)가 있으면 태그 품질이 보장되어 `score > 0` 후보 증가

**수정 대상**:

| File | Change |
|------|--------|
| `VaultAuditor.swift` | `audit()`에 orphan 검사 추가 (wikilink 0개 파일 수집) |
| `SemanticLinker.swift` | `linkOrphans(threshold:)` 메서드 추가 |
| `LinkCandidateGenerator.swift` (68행) | orphan 모드에서 `score > 0` -> `score >= 0` 완화 (MOC fallback) |
| `Frontmatter.swift` | `var noLink: Bool?` 옵트아웃 필드 추가 |

**사이드이펙트 해결**:

| 사이드이펙트 | 해결 방안 |
|-------------|----------|
| AI 비용 폭발 | **3단계 fallback 전략**: (1) 기존 score 기준으로 후보 생성 시도, (2) 후보 0개이면 같은 폴더 MOC로 fallback (AI 호출 없음), (3) MOC도 없으면 같은 PARA 카테고리의 최근 노트 1개와 연결 (AI context 생성만). 단계 (1)에서 해결되면 (2)(3) 불필요 |
| 무한 루프 위험 | `linkOrphans()`에 실행 횟수 카운터 추가. 1회 실행만 허용 (한 번의 orphan sweep). 재귀적 호출 불가 구조. `processOrphans()` -> `writeRelatedNotes()` -> 끝. reverse link 생성으로 인한 다른 노트 변경은 orphan 검사를 다시 트리거하지 않음 |
| 강제 링크의 품질 저하 | `score >= 0` 완화는 orphan 모드에서만 활성화. 일반 `linkAll()` 경로에서는 기존 `score > 0` 유지. orphan 모드에서도 MOC fallback을 우선하므로 무의미한 노트간 연결은 최소화 |
| 의도적 orphan 보존 | frontmatter에 `no-link: true` 옵트아웃. `VaultAuditor.audit()`에서 `noLink == true`인 파일은 orphan 카운트에서 제외. `linkOrphans()`에서도 스킵 |
| 대규모 vault 초기 적용 시 비용 | `linkOrphans(maxFiles: 20)` 배치 제한. 한 번에 최대 20개 orphan만 처리. 다음 `linkAll()` 실행에서 추가 20개 처리. 점진적 해소 |

---

## 8. Cross-Cutting Concerns

### 8.1 Frontmatter 확장 순서

Phase별 `Frontmatter` struct 변경을 정리:

| Phase | 추가 필드 | 타입 | 기본값 |
|-------|----------|------|--------|
| A (v2.2) | `sourceRef` | `String?` | nil |
| C (v2.4) | `aiGenerated` | `Bool?` | nil |
| D (v2.5) | `doctype` | `DocType?` | nil |
| E (v2.6) | `noLink` | `Bool?` | nil |

모든 필드는 optional이므로 기존 볼트에 영향 없음. `applyScalar()`의 switch에 case 추가, `stringify()`에 nil 체크 후 출력.

### 8.2 보안 변경 사항

| Phase | 변경 | 보안 검증 |
|-------|------|----------|
| D (v2.5) | `sanitizeFolderName()` depth 3->4 | 절대 경로 1024자 제한, symlink 해소 후 `isPathSafe()` 재검증, 각 component에 `..` 필터 유지 |

### 8.3 AI 비용 영향 추정 (100파일 인박스 처리 기준)

| Phase | 추가 비용 | 사유 |
|-------|----------|------|
| A (v2.2) | +$0.00 | `_CommonKB/` 컨텍스트는 기존 프롬프트에 추가되므로 input token만 소폭 증가 |
| B (v2.3) | -$0.01 | #9 cross-category 패널티로 AI filter 호출 감소 |
| C (v2.4) | +$0.00 | `maxTokens` 미변경, `ai-generated` 마킹은 파싱 단계에서 처리 |
| D (v2.5) | +$0.005 | doctype 분류 토큰 ~200개 추가, subCategory 프롬프트 확장 |
| E (v2.6) | +$0.01~0.05 | orphan 수에 비례. 배치 제한(20개)으로 상한 있음 |

---

## 9. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| Phase B에서 `RelatedNotesWriter` 변경이 기존 링크 파괴 | High | Low | MOC 슬롯 분리는 기존 `mergedEntries` 앞에 삽입. 기존 AI 링크 4개까지 유지. 5번째 AI 링크만 밀려남 |
| Phase D에서 path depth 변경이 보안 취약점 생성 | High | Low | 절대 경로 길이 제한 + symlink 해소 + `isPathSafe()` 이중 검증 |
| Phase E의 orphan sweep이 AI 비용 초과 | Medium | Medium | 배치 제한 20개 + 3단계 fallback (MOC 우선, AI 최후 수단) |
| 5개 Phase에 걸친 `Frontmatter` 필드 추가가 YAML 비대화 유발 | Low | Medium | 모든 신규 필드는 optional, nil이면 YAML에 미출력. 실제 추가되는 바이트는 미미 |
| 패턴 간 의존성으로 인한 Phase 순서 변경 불가 | Medium | Low | Phase A, B는 독립적. Phase C는 B의 relation type 추가에 의존하지 않음. Phase D는 C의 `ai-generated` 없어도 동작. Phase E만 A~D 전제 |

---

## 10. Success Criteria

### 10.1 Phase별 Definition of Done

| Phase | Criteria |
|-------|----------|
| A (v2.2) | `_CommonKB/` 컨텍스트가 분류 프롬프트에 포함됨. `source_ref` 필드가 companion markdown에 자동 설정됨. 기존 빌드 통과. |
| B (v2.3) | 모든 노트의 `## Related Notes`에 MOC 백링크 존재. Archive->Project 링크의 후보 점수가 기존 대비 감소. |
| C (v2.4) | AI enrichment된 노트에 `ai-generated: true` 마킹. 새 프로젝트 생성 시 5개 파일 존재. 빈 템플릿 파일이 enrichment 대상에서 제외. |
| D (v2.5) | Classifier가 doctype을 반환. 하위 카테고리 폴더에 MOC 자동 생성. `sanitizeFolderName()` depth 4에서 보안 테스트 통과. |
| E (v2.6) | `VaultAuditor`가 orphan 수를 보고. orphan 중 `no-link: true` 제외. 1회 sweep 후 orphan 수 감소. |

---

## 11. Next Steps

1. [ ] Phase A Design 문서 작성 (`fassto-patterns-phase-a.design.md`)
2. [ ] Phase A 구현
3. [ ] Phase A 빌드 검증 + Gap Analysis
4. [ ] Phase B~E는 이전 Phase 완료 후 순차 진행

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-20 | Initial draft — 9개 패턴, 5 Phase 로드맵, 사이드이펙트 해결 전략 | hwaa |
