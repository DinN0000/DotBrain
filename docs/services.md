# Services

서비스 레이어 레퍼런스. `Sources/Services/` — 45개 파일, 5개 하위 디렉토리.

## AI Services

### AIService

`Sources/Services/AIService.swift` — **actor**

프로바이더에 독립적인 AI 호출 인터페이스. 재시도, rate limiting, fallback을 관리.

| 메서드 | 설명 |
|--------|------|
| `sendMessage(model:maxTokens:userMessage:)` | 현재 프로바이더로 메시지 전송 |
| `sendFast(maxTokens:message:)` | 빠른 모델 사용 (Haiku / Flash) |
| `sendPrecise(maxTokens:message:)` | 정밀 모델 사용 (Sonnet / Pro) |
| `sendFastWithUsage(maxTokens:message:)` | 빠른 모델 + 토큰 사용량 반환 → `AIResponse` |
| `sendPreciseWithUsage(maxTokens:message:)` | 정밀 모델 + 토큰 사용량 반환 → `AIResponse` |

**WithUsage 변형**: `AIResponse` (text + TokenUsage?)를 반환. 실제 토큰 사용량을 추적하여 APIUsageLogger에 기록할 수 있도록 함. Classifier, NoteEnricher, LinkAIFilter, FileMover에서 사용.

**재시도 로직**: 최대 3회, 120초 deadline. Rate limit(429) 및 서버 에러(5xx) 시 재시도. 전체 실패 시 대체 프로바이더 fallback.

**의존**: ClaudeAPIClient, GeminiAPIClient, RateLimiter

### Classifier

`Sources/Services/Claude/Classifier.swift` — **actor**

2단계 AI 분류기. `classifyFiles()` 메서드가 전체 흐름을 조율.

| 메서드 | 설명 |
|--------|------|
| `classifyFiles(_:projectContext:subfolderContext:projectNames:weightedContext:areaContext:tagVocabulary:correctionContext:pkmRoot:onProgress:)` | 파일 목록을 2단계로 분류 |

**내부 흐름**:
1. `classifyBatchStage1()` — Haiku/Flash, 5파일/배치, 3병렬
2. `classifySingleStage2()` — Sonnet/Pro, confidence < 0.8만, 3병렬
3. `fuzzyMatchProject()` — AI 프로젝트명 → 실제 폴더 매칭
4. `parseJSONSafe()` — 마크다운 코드블록에서 JSON 추출

**의존**: AIService, StatisticsService

### RateLimiter

`Sources/Services/RateLimiter.swift` — **actor**, singleton(`shared`)

적응형 rate limiting. 프로바이더별 독립 상태.

| 메서드 | 설명 |
|--------|------|
| `acquire(for:)` | 요청 가능할 때까지 대기 |
| `recordSuccess(for:duration:)` | 성공 기록, 간격 감소 (3연속 성공 시 5%) |
| `recordFailure(for:isRateLimit:)` | 실패 기록, 429시 2배 + 지수 백오프, 5xx시 1.5배 |

### ClaudeAPIClient

`Sources/Services/Claude/ClaudeAPIClient.swift` — **actor**

| 메서드 | 설명 |
|--------|------|
| `sendMessage(model:maxTokens:userMessage:)` | Claude API 호출, `(String, TokenUsage?)` 반환 |

모델: `haikuModel = "claude-haiku-4-5-20251001"`, `sonnetModel = "claude-sonnet-4-5-20250929"`

내부 `Usage` struct로 Claude API 응답의 `usage` 필드를 디코딩하여 `TokenUsage`로 변환.

### GeminiAPIClient

`Sources/Services/Gemini/GeminiAPIClient.swift` — **actor**

| 메서드 | 설명 |
|--------|------|
| `sendMessage(model:maxTokens:userMessage:)` | Gemini API 호출, `(String, TokenUsage?)` 반환 |

모델: `flashModel = "gemini-2.5-flash"`, `proModel = "gemini-2.5-pro"`

내부 `UsageMetadata` struct로 Gemini API 응답의 `usageMetadata` 필드를 디코딩하여 `TokenUsage`로 변환. `cachedContentTokenCount`도 지원.

## File System Services

### FileMover

`Sources/Services/FileSystem/FileMover.swift` — **struct**

파일/폴더를 PARA 구조로 이동. 중복 감지, frontmatter 주입 포함.

| 메서드 | 설명 |
|--------|------|
| `moveFile(at:with:)` | 파일 이동 (마크다운 또는 바이너리) |
| `moveFolder(at:with:)` | 폴더 트리 이동, 인덱스 노트 생성 |

**중복 감지**: 텍스트=body SHA256, 바이너리<=500MB=스트리밍 SHA256, 바이너리>500MB=메타데이터 비교.
**충돌 해결**: `_2`, `_3`, UUID 접미사.
**바이너리**: `_Assets/{documents,images}/`로 이동 + 컴패니언 마크다운.

**의존**: PKMPathManager, BinaryExtractor, FrontmatterWriter, AIService, StatisticsService

### PKMPathManager

`Sources/Services/FileSystem/PKMPathManager.swift` — **struct**

PARA 경로 관리 및 보안 검증.

| 메서드 | 설명 |
|--------|------|
| `paraPath(for:)` | 카테고리별 기본 경로 |
| `targetDirectory(for:)` | 분류 결과 → 대상 폴더 (sanitization 포함) |
| `assetsDirectory(for:)` | 바이너리 파일 → documents/ 또는 images/ |
| `isPathSafe(_:)` | 경로 탐색 방어 (symlink 해석 + hasPrefix) |
| `isInitialized()` | PARA 구조 존재 확인 |
| `initializeStructure()` | 전체 PARA 폴더 + AI 컴패니언 파일 생성 |
| `existingSubfolders()` | Area/Resource/Archive 서브폴더 목록 |

**경로 속성**: `inboxPath`, `projectsPath`, `areaPath`, `resourcePath`, `archivePath`, `centralAssetsPath`, `documentsAssetsPath`, `imagesAssetsPath`, `videosAssetsPath`, `metaPath`, `noteIndexPath`

### InboxScanner

`Sources/Services/FileSystem/InboxScanner.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `scan()` | `_Inbox/` 파일 목록 수집 |
| `filesInDirectory(at:)` | 디렉토리 내 텍스트 파일 목록 |
| `static isCodeProject(at:fm:)` | 코드 프로젝트 감지 (.git, Package.swift 등) |

**필터링**: 시스템 파일 (.DS_Store 등), 코드 파일 (.swift, .py 등), 설정 파일 (.json, .yml 등) 제외. 심볼릭 링크 타겟 검증.

### InboxWatchdog

`Sources/Services/FileSystem/InboxWatchdog.swift` — **@MainActor final class**

| 메서드 | 설명 |
|--------|------|
| `start()` | DispatchSource로 파일시스템 감시 시작 |
| `stop()` | 감시 중단 |

디바운스 간격 2초. 폴더 미존재 시 최대 3회 재시도 (10초 간격).

### FrontmatterWriter

`Sources/Services/FileSystem/FrontmatterWriter.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `injectFrontmatter(into:para:tags:summary:source:project:file:relatedNotes:)` | Frontmatter 병합 + wikilink 추가 |
| `createCompanionMarkdown(for:classification:aiSummary:relatedNotes:)` | 바이너리 컴패니언 마크다운 생성 |
| `createIndexNote(folderName:para:description:)` | 폴더 인덱스 노트 템플릿 |

**병합 정책**: 기존 값 우선. AI 생성 값은 빈 필드만 채움.

### AssetMigrator

`Sources/Services/FileSystem/AssetMigrator.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `needsMigration(pkmRoot:)` | 분산된 `_Assets/` 감지 |
| `migrate(pkmRoot:)` | 중앙 집중화 (`_Assets/{documents,images}/`) |

마이그레이션: 분산 에셋 수집 → 중앙 이동 → 고아 컴패니언 삭제 → wikilink 업데이트 → 인덱스 노트 정리.

## Content Extraction Services

### FileContentExtractor

`Sources/Services/Extraction/FileContentExtractor.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `extract(from:maxLength:)` | AI 분류용 텍스트 추출 (기본 5000자) |
| `extractPreview(from:content:maxLength:)` | Stage 1 배치용 압축 프리뷰 (기본 800자) |

**마크다운 Smart Extraction**: frontmatter(20%) + intro(30%) + headings(30%) + tail(20%) 예산 배분. FileHandle 1MB 청크 스트리밍.

### BinaryExtractor

`Sources/Services/Extraction/BinaryExtractor.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `isBinaryFile(_:)` | 바이너리 확장자 확인 |
| `extract(at:)` | 포맷별 추출기 디스패치 |

### 개별 추출기

| 추출기 | 파일 | 대상 |
|--------|------|------|
| `PDFExtractor` | `Sources/Services/Extraction/PDFExtractor.swift` | PDF 텍스트 |
| `PPTXExtractor` | `Sources/Services/Extraction/PPTXExtractor.swift` | PowerPoint 슬라이드 |
| `XLSXExtractor` | `Sources/Services/Extraction/XLSXExtractor.swift` | Excel 시트 |
| `DOCXExtractor` | `Sources/Services/Extraction/DOCXExtractor.swift` | Word 문서 |
| `ImageExtractor` | `Sources/Services/Extraction/ImageExtractor.swift` | EXIF 메타데이터 + OCR |

모두 **enum** (static methods), `ExtractResult` 반환.

## Knowledge Management Services

### NoteIndexGenerator

`Sources/Services/NoteIndexGenerator.swift` — **struct: Sendable**

`.meta/note-index.json` 생성. 볼트 전체 노트/폴더를 단일 JSON 인덱스로 관리.

| 메서드 | 설명 |
|--------|------|
| `updateForFolders(_:)` | 변경된 폴더만 증분 업데이트 (기존 인덱스와 병합) |
| `regenerateAll()` | 전체 볼트 스캔 후 인덱스 완전 재생성 |

**인덱스 구조**: `NoteIndex` (version, updated, folders: `[String: FolderIndexEntry]`, notes: `[String: NoteIndexEntry]`). 각 노트는 path, folder, para, tags, summary, project, status를 포함.

**파일 I/O 최적화**: FileHandle 4KB partial read로 프론트매터만 추출 (MultiByteUTF-8 safe). 대용량 바이너리가 아닌 메타데이터 추출에 최적화.

**의존**: PKMPathManager (AI 호출 없음 — 프론트매터 파싱으로 구축)

### VaultAuditor

`Sources/Services/VaultAuditor.swift` — **struct**

> Pipeline으로도 사용됨. 상세: [pipelines.md](pipelines.md)

| 메서드 | 설명 |
|--------|------|
| `audit()` | 볼트 전체 스캔 → AuditReport |
| `repair(report:)` | 자동 수리 → RepairResult |

### VaultSearcher

`Sources/Services/VaultSearcher.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `search(query:)` | 다층 검색 (제목→태그→요약→본문), 최대 200결과 |

**검색 우선순위**: title(1.0) > summary(0.6) > tag(0.5–0.9) > body(0.3)

**검색 전략** (2단계): Phase 1: note-index.json에서 제목/태그/요약 매칭 (zero file I/O). Phase 2: 결과 < 10개일 때만 디렉토리 스캔 fallback으로 본문 검색. FileHandle 64KB partial read로 메모리 효율화.

### NoteEnricher

`Sources/Services/NoteEnricher.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `enrichNote(at:)` | 빈 frontmatter 필드를 AI로 채움 |
| `enrichFolder(at:)` | 폴더 내 모든 노트 보강 (max 3 병렬) |

**병합 정책**: 빈 필드만 채움. 기존 값은 변경하지 않음.

**의존**: AIService, FileContentExtractor, StatisticsService

### AICompanionService

`Sources/Services/AICompanionService.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `generateAll(pkmRoot:)` | 모든 AI 컴패니언 파일 생성 (첫 설정) |
| `updateIfNeeded(pkmRoot:)` | 버전 확인 후 필요 시 재생성 |

**버전**: `static let version = 13`. 동작 변경 시 증가 → 볼트 자동 업데이트 트리거.

**생성 파일**: CLAUDE.md, AGENTS.md, .cursorrules, 11개 에이전트 파일, 5+ 스킬 파일.

**업데이트 전략**: `<!-- DotBrain:start/end -->` 마커로 DotBrain 생성 영역만 교체. 사용자 수정 보존.

### ContextMapBuilder

`Sources/Services/ContextMapBuilder.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `build()` | `.meta/note-index.json` 읽기 → VaultContextMap |

**의존**: PKMPathManager

## Semantic Linker Services

### SemanticLinker

`Sources/Services/SemanticLinker/SemanticLinker.swift` — **struct: Sendable**

> 상세: [pipelines.md](pipelines.md) — Semantic Linking Pipeline

| 메서드 | 설명 |
|--------|------|
| `linkAll(changedFiles:prebuiltIndex:onProgress:)` | 전체 또는 증분 링킹 (6단계) |
| `linkNotes(filePaths:onProgress:)` | 특정 파일만 링킹 |

**성능 최적화**: buildNoteIndex()는 index-first 전략 사용 (note-index.json 로드 후 existingRelated만 파일 읽기, fallback은 전체 디렉토리 스캔). FolderRelationStore 호출 최소화: suppress/boost sets를 사전구축하여 LinkCandidateGenerator에 전달.

**의존**: TagNormalizer, ContextMapBuilder, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter, LinkFeedbackStore, FolderRelationStore, PKMPathManager

### TagNormalizer

`Sources/Services/SemanticLinker/TagNormalizer.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `normalize()` | 프로젝트 폴더명/project 필드값 → 태그에 추가 |

### LinkCandidateGenerator

`Sources/Services/SemanticLinker/LinkCandidateGenerator.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `generateCandidates(for:allNotes:mocEntries:folderBonus:excludeSameFolder:folderRelations:)` | 노트별 링크 후보 생성 (인위적 제한 없음) |
| `prepareIndex(allNotes:mocEntries:)` | 역인덱스 사전구축 (tagIndex, projectIndex, mocFolders) |
| `generateCandidates(for:allNotes:preparedIndex:...suppressSet:boostSet:)` | 인덱스 기반 후보 생성 (pre-computed suppress/boost sets) |

**스코어링**: 태그 겹침 >= 2 (+1.5/태그), 공유 인덱스 폴더 (+folderBonus/폴더), 같은 프로젝트 (+2.0). 최소 점수 >= 3.0. 단일 태그 겹침은 무시.

**성능 최적화**: `PreparedIndex` struct로 reverse indices (O(1) tag/project lookup) 사전구축. 오버로드된 generateCandidates()는 suppress/boost sets을 입력받아 FolderRelationStore 디스크 I/O 회피.

### LinkAIFilter

`Sources/Services/SemanticLinker/LinkAIFilter.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `filterBatch(notes:maxResultsPerNote:)` | 배치 AI 필터링 (노트당 기본 max 15, 인사이트 기준) |
| `filterSingle(...)` | 단일 노트 필터링 |

**Context 형식**: "~하려면", "~할 때", "~와 비교할 때" (15자 이내, 한국어).

**의존**: AIService, StatisticsService

### RelatedNotesWriter

`Sources/Services/SemanticLinker/RelatedNotesWriter.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `writeRelatedNotes(filePath:newLinks:noteNames:)` | `## Related Notes` 섹션 파싱, 병합, 작성 (인위적 제한 없음) |

**Wikilink Sanitization**: `[[`, `]]`, `/`, `\`, `..` 제거. 노트 이름 존재 검증.

### FolderRelationStore

`Sources/Services/SemanticLinker/FolderRelationStore.swift` — **struct: Sendable**

폴더 간 관계(boost/suppress) 저장소. `.meta/folder-relations.json`에 영속화.

| 메서드 | 설명 |
|--------|------|
| `load()` | JSON에서 전체 관계 로드 → `FolderRelations` |
| `save(_:)` | 관계를 JSON으로 저장 |
| `addRelation(_:)` | 관계 추가 (기존 동일 쌍은 교체) |
| `removeRelation(source:target:)` | 관계 제거 |
| `boostPairs()` | boost 타입 관계 목록 |
| `suppressPairs()` | suppress 타입 쌍 키 Set |
| `renamePath(from:to:)` | 폴더 경로 변경 시 관계 경로 업데이트 |
| `pruneStale(existingFolders:)` | 삭제된 폴더의 관계 정리 |

**양방향 매칭**: (A,B)와 (B,A)를 동일하게 취급. `pairKey()`로 정렬된 키 생성.

**모델**: `FolderRelation` (source, target, type, hint, relationType, origin, created), `FolderRelations` (version, updated, relations).

### FolderRelationAnalyzer

`Sources/Services/SemanticLinker/FolderRelationAnalyzer.swift` — **struct: Sendable**

AI를 이용한 폴더 쌍 관계 후보 생성. FolderRelationExplorer UI에서 사용.

| 메서드 | 설명 |
|--------|------|
| `generateCandidates(allNotes:existingRelations:)` | 폴더 쌍 후보 생성 (기존 관계 제외, AI 분석 포함) |

**스코어링**: 폴더 간 기존 링크 수 x3.0 + 공유 태그 수. 상위 20개 선택 후 AI 배치 분석.

**AI 분석**: hint("~할 때" 형식, 한국어 20자 이내), relationType(비교/대조|적용|확장|관련), confidence(0.0~1.0) 생성. confidence > 0.1만 반환.

**의존**: AIService, SemanticLinker (NoteInfo), StatisticsService

### LinkFeedbackStore

`Sources/Services/SemanticLinker/LinkFeedbackStore.swift` — **struct: Sendable**

사용자 링크 삭제 피드백 저장소. `.meta/link-feedback.json`에 영속화 (FIFO, 500 entries max).

| 메서드 | 설명 |
|--------|------|
| `load()` | JSON에서 피드백 로드 → `LinkFeedback` |
| `save(_:)` | 피드백을 JSON으로 저장 |
| `recordRemoval(sourceNote:targetNote:sourceFolder:targetFolder:)` | 링크 삭제 기록 추가 |
| `buildPromptContext()` | 폴더 쌍별 삭제 패턴 요약 → AI 프롬프트 컨텍스트 |

**모델**: `LinkFeedbackEntry` (date, sourceNote, targetNote, sourceFolder, targetFolder, action), `LinkFeedback` (version, entries).

### LinkStateDetector

`Sources/Services/SemanticLinker/LinkStateDetector.swift` — **struct: Sendable**

볼트체크 간 Related Notes 스냅샷을 비교하여 사용자 링크 삭제를 감지.

| 메서드 | 설명 |
|--------|------|
| `loadSnapshot()` | `.meta/link-snapshot.json`에서 이전 스냅샷 로드 |
| `saveSnapshot(_:)` | 현재 스냅샷 저장 |
| `buildCurrentSnapshot(allNotes:)` | 현재 볼트의 Related Notes 파싱 → `LinkSnapshot` |
| `detectRemovals(previous:current:noteInfoMap:)` | 이전 vs 현재 스냅샷 diff → 삭제된 링크 목록 |

**모델**: `LinkSnapshot` (noteLinks: `[String: [String]]`).

**의존**: LinkCandidateGenerator.NoteInfo

## Learning Services

### ProjectAliasRegistry

`Sources/Services/ProjectAliasRegistry.swift` — **struct** (static methods)

AI가 생성한 프로젝트 이름 변형을 실제 폴더명으로 매핑. `.meta/project-aliases.json`에 영속화.

| 메서드 | 설명 |
|--------|------|
| `resolve(_:pkmRoot:)` | AI 반환 프로젝트명 → 실제 폴더명 조회 (없으면 nil) |
| `register(aiName:actualName:pkmRoot:)` | 새 별칭 등록 (동일 이름이면 스킵) |

**사용처**: InboxProcessor (PendingConfirmation 처리 시 사용자가 수정한 프로젝트명 학습)

### CorrectionMemory

`Sources/Services/CorrectionMemory.swift` — **struct** (static methods)

사용자의 AI 분류 수정 이력을 기록하고, 반복 패턴을 few-shot 프롬프트로 구성. `.meta/correction-memory.json`에 영속화 (FIFO, 200 entries max).

| 메서드 | 설명 |
|--------|------|
| `record(_:pkmRoot:)` | CorrectionEntry 기록 (PARA/프로젝트 수정 이력) |
| `buildPromptContext(pkmRoot:)` | 수정 패턴 → AI 프롬프트 컨텍스트 (카테고리/태그/프로젝트 패턴) |

**모델**: `CorrectionEntry` (date, fileName, aiPara, userPara, aiProject, userProject, tags, action).

**사용처**: InboxProcessor의 Classify 단계에서 `correctionContext`로 주입

## Project / Folder Management

### ProjectManager

`Sources/Services/ProjectManager.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `createProject(name:summary:)` | 새 프로젝트 폴더 + 인덱스 노트 |
| `completeProject(name:)` | 프로젝트 아카이브 (4_Archive로 이동, status=completed) |

**의존**: PKMPathManager, FrontmatterWriter, StatisticsService

### PARAMover

`Sources/Services/PARAMover.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `moveFolder(name:from:to:)` | PARA 카테고리 간 폴더 이동, frontmatter 업데이트 |
| `deleteFolder(name:category:)` | macOS 휴지통으로 이동 |
| `mergeFolder(source:into:category:)` | 같은 카테고리 내 폴더 병합 |

아카이브 시 `status=completed`, 비아카이브 시 `status=active`.

### FolderHealthAnalyzer

`Sources/Services/FolderHealthAnalyzer.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `analyze(folderPath:folderName:category:)` | 폴더 건강 점수 (AI 호출 없음) |

**점수 요소**: 파일 수(>40 감점), missing frontmatter, 태그 다양성, 인덱스 노트 유무.
**점수 레벨**: >= 0.8 good, 0.5–0.8 attention, < 0.5 urgent.

## Utility Services

### StatisticsService

`Sources/Services/StatisticsService.swift` — **class** (내부에 **StatisticsActor** 사용)

| 메서드 | 설명 |
|--------|------|
| `collectStatistics()` | PARA 폴더 스캔 → PKMStatistics |
| `static recordActivity(fileName:category:action:detail:)` | 활동 기록 (스레드 안전) |
| `static addApiCost(_:)` | API 비용 누적 (스레드 안전) |
| `static incrementDuplicates()` | 중복 카운터 증가 (스레드 안전) |
| `static logTokenUsage(operation:model:usage:)` | 실제 토큰 기반 비용 계산 및 로깅 |

| 속성 | 설명 |
|------|------|
| `static sharedPkmRoot: String?` | AppState가 초기화 시 설정하는 PKM 루트 경로. APIUsageLogger가 `.dotbrain/` 경로를 결정하는 데 사용 |

**logTokenUsage**: `APIUsageLogger.calculateCost(model:usage:)`로 실제 비용을 계산한 후, `addApiCost()`로 UserDefaults에 누적하고 `APIUsageLogger.log()`로 상세 내역을 JSON에 기록. 기존 hardcoded `addApiCost()` 호출을 대체.

**저장**: UserDefaults (`pkmApiCost`, `pkmDuplicatesFound`, `pkmActivityHistory` — 최근 100건).
**동시성**: 내부 `StatisticsActor` (private actor)로 UserDefaults 뮤테이션 직렬화.

### KeychainService

`Sources/Services/KeychainService.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `saveAPIKey(_:)` / `getAPIKey()` / `deleteAPIKey()` | Claude 키 |
| `saveGeminiAPIKey(_:)` / `getGeminiAPIKey()` / `deleteGeminiAPIKey()` | Gemini 키 |

> 상세: [security-and-concurrency.md](security-and-concurrency.md) — AES-GCM + HKDF + 하드웨어 바인딩

### TemplateService

`Sources/Services/TemplateService.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `initializeTemplates(pkmRoot:)` | `.Templates/`에 기본 템플릿 생성 |

**기본 템플릿**: Note.md, Project.md, Asset.md. 플레이스홀더: `{{date}}`, `{{title}}`, `{{project_name}}`, `{{filename}}`, `{{format}}`, `{{size_kb}}`.

### NotificationService

`Sources/Services/NotificationService.swift` — **enum** (static methods)

| 메서드 | 설명 |
|--------|------|
| `sendProcessingComplete(classified:total:failed:)` | 처리 완료 알림 |
| `send(title:body:)` | 범용 알림 |

`NSSound.beep()` + NSLog. SPM 실행파일은 `.app` 번들이 아니라 `UNUserNotificationCenter` 사용 불가.

## Data / Cache Services

### ContentHashCache

`Sources/Services/ContentHashCache.swift` — **actor**

SHA256 기반 파일 변경 감지. 볼트 내 파일의 해시를 캐싱하여 변경/신규/미변경 상태를 판별.

| 메서드 | 설명 |
|--------|------|
| `load()` | `.dotbrain/content-hashes.json`에서 해시 캐시 로드 |
| `checkFile(_:)` | 단일 파일 상태 확인 → `FileStatus` |
| `checkFolder(_:)` | 폴더 내 모든 파일 상태 확인 → `[FileStatusEntry]` |
| `updateHash(_:)` | 단일 파일 해시 갱신 |
| `updateHashes(_:)` | 복수 파일 해시 일괄 갱신 |
| `save()` | 해시 캐시를 JSON으로 저장 |

**FileStatus**: `.unchanged` (해시 동일), `.modified` (해시 변경), `.new` (캐시에 없음).

**저장 경로**: `{pkmRoot}/.dotbrain/content-hashes.json`

**해시 알고리즘**: CryptoKit SHA256. 마크다운 파일의 전체 내용을 해싱.

**경로 보안**: `URL.resolvingSymlinksInPath()`로 canonicalize 후 `hasPrefix` 검사.

### APIUsageLogger

`Sources/Services/APIUsageLogger.swift` — **actor**

실제 토큰 사용량 기반 API 비용 추적. 모델별 가격표로 정확한 비용 계산.

| 메서드 | 설명 |
|--------|------|
| `log(operation:model:usage:)` | API 호출 내역 기록 (operation, model, tokens, cost) |
| `loadEntries()` | `.dotbrain/api-usage.json`에서 전체 내역 로드 |
| `costByOperation()` | operation별 누적 비용 집계 |
| `totalCost()` | 전체 누적 비용 |
| `recentEntries(limit:)` | 최근 N건의 API 호출 내역 |
| `static calculateCost(model:usage:)` | 모델 + TokenUsage로 비용 계산 (StatisticsService에서 호출) |

**모델 가격 (per 1M tokens)**:

| 모델 | Input | Output |
|------|-------|--------|
| Haiku | $0.80 | $4.00 |
| Sonnet | $3.00 | $15.00 |
| Flash | $0.15 | $0.60 |
| Pro | $1.25 | $5.00 |

**저장 경로**: `{pkmRoot}/.dotbrain/api-usage.json`

**저장 형식**: `[APIUsageEntry]` — id, timestamp, operation, model, inputTokens, outputTokens, cachedTokens, cost.

## Service Dependency Graph

```
AppState
├── InboxProcessor
│   ├── InboxScanner
│   ├── ProjectContextBuilder ← PKMPathManager
│   ├── Classifier ← AIService ← (ClaudeAPIClient, GeminiAPIClient, RateLimiter)
│   ├── FileMover ← (PKMPathManager, BinaryExtractor, FrontmatterWriter, AIService)
│   ├── NoteIndexGenerator ← PKMPathManager
│   ├── SemanticLinker ← (TagNormalizer, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter)
│   ├── StatisticsService ← StatisticsActor
│   └── NotificationService
├── FolderReorganizer
│   ├── (InboxProcessor 서비스 공유)
├── VaultReorganizer
│   └── (InboxProcessor 서비스 공유)
└── VaultAuditor
    └── (PKMPathManager, Frontmatter만 의존)
```

## Cross-References

- **파이프라인에서의 서비스 사용**: [pipelines.md](pipelines.md)
- **Actor 격리 및 동시성**: [security-and-concurrency.md](security-and-concurrency.md)
- **데이터 모델**: [models-and-data.md](models-and-data.md)
- **전체 아키텍처**: [architecture.md](architecture.md)
