# Services

서비스 레이어 레퍼런스. `Sources/Services/` — 39개 파일, 6개 하위 디렉토리.

## AI Services

### AIService

`Sources/Services/AIService.swift` — **actor**

프로바이더에 독립적인 AI 호출 인터페이스. 재시도, rate limiting, fallback을 관리.

| 메서드 | 설명 |
|--------|------|
| `sendMessage(model:maxTokens:userMessage:)` | 현재 프로바이더로 메시지 전송 |
| `sendFast(maxTokens:message:)` | 빠른 모델 사용 (Haiku / Flash) |
| `sendPrecise(maxTokens:message:)` | 정밀 모델 사용 (Sonnet / Pro) |

**재시도 로직**: 최대 3회, 120초 deadline. Rate limit(429) 및 서버 에러(5xx) 시 재시도. 전체 실패 시 대체 프로바이더 fallback.

**의존**: ClaudeAPIClient, GeminiAPIClient, RateLimiter

### Classifier

`Sources/Services/Claude/Classifier.swift` — **actor**

2단계 AI 분류기. `classifyFiles()` 메서드가 전체 흐름을 조율.

| 메서드 | 설명 |
|--------|------|
| `classifyFiles(_:projectContext:subfolderContext:projectNames:weightedContext:onProgress:)` | 파일 목록을 2단계로 분류 |

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
| `sendMessage(model:maxTokens:userMessage:)` | Claude API 호출 |

모델: `haikuModel = "claude-haiku-4-5-20251001"`, `sonnetModel = "claude-sonnet-4-5-20250929"`

### GeminiAPIClient

`Sources/Services/Gemini/GeminiAPIClient.swift` — **actor**

| 메서드 | 설명 |
|--------|------|
| `sendMessage(model:maxTokens:userMessage:)` | Gemini API 호출 |

모델: `flashModel = "gemini-2.5-flash"`, `proModel = "gemini-2.5-pro"`

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

**경로 속성**: `inboxPath`, `projectsPath`, `areaPath`, `resourcePath`, `archivePath`, `centralAssetsPath`, `documentsAssetsPath`, `imagesAssetsPath`

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

### MOCGenerator

`Sources/Services/MOCGenerator.swift` — **struct**

Map of Contents 생성. 폴더 수준의 자동 목차.

| 메서드 | 설명 |
|--------|------|
| `generateMOC(folderPath:folderName:para:)` | AI 요약으로 MOC 생성. 태그 클라우드 포함 |
| `generateCategoryRootMOC(basePath:para:)` | 카테고리 루트 인덱스 생성 (예: `1_Project.md`) |
| `updateMOCsForFolders(_:)` | 변경된 폴더들의 MOC 업데이트 + 상위 카테고리 |
| `regenerateAll()` | 전체 볼트 MOC 재생성 (max 3 병렬 AI) |

**MOC 구조**: frontmatter + `## 문서 목록` (wikilink + context) + `## 태그 클라우드` (top 10).

**의존**: AIService, StatisticsService, PKMPathManager

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

**버전**: `static let version = 11`. 동작 변경 시 증가 → 볼트 자동 업데이트 트리거.

**생성 파일**: CLAUDE.md, AGENTS.md, .cursorrules, 11개 에이전트 파일, 5+ 스킬 파일.

**업데이트 전략**: `<!-- DotBrain:start/end -->` 마커로 DotBrain 생성 영역만 교체. 사용자 수정 보존.

### ContextLinker

`Sources/Services/ContextLinker.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `findRelatedNotes(for:contextMap:onProgress:)` | AI로 관련 노트 검색 (배치 5, 병렬 3) |

**의존**: AIService, FileContentExtractor, StatisticsService

### ContextMapBuilder

`Sources/Services/ContextMapBuilder.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `build()` | 모든 MOC 파싱 → VaultContextMap (max 3 병렬) |

**의존**: PKMPathManager

## Semantic Linker Services

### SemanticLinker

`Sources/Services/SemanticLinker/SemanticLinker.swift` — **struct: Sendable**

> 상세: [pipelines.md](pipelines.md) — Semantic Linking Pipeline

| 메서드 | 설명 |
|--------|------|
| `linkAll(onProgress:)` | 전체 볼트 링킹 (6단계) |
| `linkNotes(filePaths:onProgress:)` | 특정 파일만 링킹 |

**의존**: TagNormalizer, ContextMapBuilder, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter, PKMPathManager

### TagNormalizer

`Sources/Services/SemanticLinker/TagNormalizer.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `normalize()` | 프로젝트 폴더명/project 필드값 → 태그에 추가 |

### LinkCandidateGenerator

`Sources/Services/SemanticLinker/LinkCandidateGenerator.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `generateCandidates(for:allNotes:mocEntries:maxCandidates:)` | 노트별 top 10 링크 후보 |

**스코어링**: 태그 겹침 >= 2 (+1.5/태그), 태그 겹침 == 1 (+0.5), 공유 MOC 폴더 (+1.0/폴더), 같은 프로젝트 (+2.0).

### LinkAIFilter

`Sources/Services/SemanticLinker/LinkAIFilter.swift` — **struct: Sendable**

| 메서드 | 설명 |
|--------|------|
| `filterBatch(notes:maxResultsPerNote:)` | 배치 AI 필터링 (노트당 max 5) |
| `filterSingle(...)` | 단일 노트 필터링 |

**Context 형식**: "~하려면", "~할 때", "~와 비교할 때" (15자 이내, 한국어).

**의존**: AIService, StatisticsService

### RelatedNotesWriter

`Sources/Services/SemanticLinker/RelatedNotesWriter.swift` — **struct**

| 메서드 | 설명 |
|--------|------|
| `writeRelatedNotes(filePath:newLinks:noteNames:)` | `## Related Notes` 섹션 파싱, 병합, 작성 (max 5) |

**Wikilink Sanitization**: `[[`, `]]`, `/`, `\`, `..` 제거. 노트 이름 존재 검증.

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

## Service Dependency Graph

```
AppState
├── InboxProcessor
│   ├── InboxScanner
│   ├── ProjectContextBuilder ← PKMPathManager
│   ├── Classifier ← AIService ← (ClaudeAPIClient, GeminiAPIClient, RateLimiter)
│   ├── FileMover ← (PKMPathManager, BinaryExtractor, FrontmatterWriter, AIService)
│   ├── MOCGenerator ← (AIService, PKMPathManager)
│   ├── SemanticLinker ← (TagNormalizer, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter)
│   ├── StatisticsService ← StatisticsActor
│   └── NotificationService
├── FolderReorganizer
│   ├── (InboxProcessor 서비스 공유)
│   └── ContextLinker ← (AIService, FileContentExtractor)
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
