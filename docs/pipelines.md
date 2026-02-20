# Pipelines

처리 파이프라인 상세. "이 앱이 어떻게 동작하는가?"

## Inbox Processing Pipeline

`Sources/Pipeline/InboxProcessor.swift` — 사용자가 "정리하기" 클릭 시 실행.

### 6단계 처리 흐름

```
_Inbox/ 파일
    │
    ▼
1. Prepare ── InboxScanner.scan()
    │           시스템 파일, 코드 파일 필터링
    │           심볼릭 링크 검증
    ▼
2. Extract ── FileContentExtractor (병렬, max 5)
    │           마크다운: Smart Extraction (5000자 예산)
    │           바이너리: BinaryExtractor 디스패치
    │           폴더: 하위 파일 목록 추출
    ▼
3. Classify ── Classifier 2단계 AI 분류
    │           ProjectContextBuilder로 볼트 컨텍스트 구성
    │           + buildTagVocabulary()로 상위 50 태그 어휘 주입
    │           Stage 1: Haiku/Flash 배치 (5파일/요청, 3병렬)
    │           Stage 2: Sonnet/Pro 정밀 (confidence < 0.8만, 3병렬)
    ▼
4. Process ── 충돌 감지 → FileMover.moveFile()/moveFolder()
    │           충돌 없으면 자동 이동
    │           충돌 있으면 PendingConfirmation 생성
    ▼
5. Link ── SemanticLinker.linkNotes() (이동 완료된 파일만)
    ▼
6. Finish ── MOCGenerator.updateMOCsForFolders()
              NotificationService 알림
```

### 2단계 AI 분류 상세

`Sources/Services/Claude/Classifier.swift`

**Stage 1 (Haiku/Flash — 빠른 배치)**:
- 최대 5개 파일을 하나의 AI 요청으로 전송
- 최대 3개 배치 동시 실행
- `extractPreview()` (800자)로 압축된 프리뷰 사용
- 출력: `Stage1Item` (fileName, para, tags, summary, confidence, project, targetFolder)

**Stage 2 (Sonnet/Pro — 정밀)**:
- Stage 1에서 `confidence < 0.8`인 파일만 대상
- 파일당 1개 요청, 최대 3개 동시 실행
- `extract()` (5000자)로 상세 콘텐츠 사용
- 프로젝트 컨텍스트 + 서브폴더 컨텍스트 포함
- 출력: `Stage2Item` (para, tags, summary, targetFolder, project, confidence)

**Project Name Resolution**:
- `fuzzyMatchProject()` — AI가 제안한 프로젝트명을 실제 폴더명과 매칭
- 대소문자 무시 비교, prefix 매칭
- 매칭 실패 시 `suggestedProject`에 원본값 보존 → `unmatchedProject` 충돌 생성

### 충돌 감지 4유형

| 유형 | 조건 | 사용자 행동 |
|------|------|------------|
| `lowConfidence` | `confidence < 0.5` | PARA 카테고리 선택 |
| `indexNoteConflict` | 파일명 == `folderName.md` | 덮어쓰기 또는 건너뛰기 |
| `nameConflict` | 대상에 동일 파일명 존재 (내용 다름) | 이동 또는 건너뛰기 |
| `unmatchedProject` | `para == .project`이지만 매칭 프로젝트 없음 | 새 프로젝트 생성 또는 다른 카테고리 선택 |

**동일 파일명 + 동일 내용** = 자동 중복 제거 (`deduplicated` 상태), 태그 병합.

### 에지 케이스

- **바이너리 파일**: `_Assets/{documents,images}/`로 이동, 컴패니언 마크다운 생성
- **폴더**: `FileMover.moveFolder()`로 전체 이동, wikilink 집약된 인덱스 노트 생성
- **이미지**: `ImageExtractor`로 EXIF 메타데이터 추출
- **코드 프로젝트**: `.git`, `Package.swift` 등 감지 시 인박스에서 제외
- **대용량 파일 (>100MB)**: 경고 로그, 스트리밍 I/O로 처리

### Return Type

```swift
struct Result {
    var processed: [ProcessedFileResult]
    var needsConfirmation: [PendingConfirmation]
    var affectedFolders: Set<String>
    var total: Int
    var failed: Int
}
```

## Folder Reorganization Pipeline

`Sources/Pipeline/FolderReorganizer.swift` — 기존 PARA 하위 폴더 재정리.

### 5단계 처리 흐름

```
PARA 하위 폴더 (예: 2_Area/DevOps/)
    │
    ▼
1. Flatten ── 중첩된 하위 디렉토리를 최상위로 플래튼
    │           플레이스홀더/인덱스 파일 삭제
    │           빈 디렉토리 제거, _Assets/ 보존
    ▼
2. Dedup ── SHA256 해시로 중복 감지
    │          텍스트: body 해시 (frontmatter 제외)
    │          바이너리: 스트리밍 해시 (1MB 청크)
    │          중복: 휴지통 이동, 태그 병합
    ▼
3. Classify ── 2단계 AI 분류 (InboxProcessor와 동일)
    │
    ▼
4. Compare ── 현재 위치 vs AI 추천 위치
    │           같은 위치: frontmatter 업데이트 + Related Notes 추가
    │           다른 위치: FileMover로 이동 (relocated 상태)
    ▼
5. Finish ── MOC 재생성 (소스 + 타겟 폴더)
```

### Flatten 상세

- 중첩 구조 (`folder/subfolder/file.md`) → 최상위 (`folder/file.md`)
- 인덱스 노트 (`folderName.md`, `_`로 시작하는 파일) 삭제
- 이름 충돌 시 `_2`, `_3` 접미사 추가
- `_Assets/` 서브트리는 이동하지 않음

### Compare 로직

```
현재 위치 == AI 추천 위치?
├── Yes → Frontmatter를 DotBrain 형식으로 업데이트
│         created 날짜 보존
│         ## Related Notes 섹션 추가/업데이트
│         결과: .success
│
└── No  → FileMover.moveFile()로 이동
          결과: .relocated(from: "2_Area/DevOps")
```

## Vault Reorganization Pipeline

`Sources/Pipeline/VaultReorganizer.swift` — 볼트 전체 대상 AI 재분류.

### Phase 1: Scan

```
PARA 폴더 전체 (또는 특정 카테고리)
    │
    ▼
1. Collect ── collectFiles() (max 200 파일)
    │           숨김/언더스코어 파일 제외
    │           인덱스 노트 제외
    ▼
2. Context ── ProjectContextBuilder
    ▼
3. Extract ── 병렬 추출 (max 5)
    ▼
4. Classify ── 2단계 AI 분류
    ▼
5. Compare ── 현재 위치 vs 추천 위치
              needsMove인 파일만 FileAnalysis로 반환
              새 프로젝트 폴더 생성이 필요한 이동은 제외
```

### Phase 2: Execute

```
FileAnalysis 목록 (사용자가 선택한 것만)
    │
    ▼
1. Move ── FileMover.moveFile() (isSelected == true만)
    ▼
2. MOC ── 소스 폴더 + 타겟 폴더 MOC 업데이트
    ▼
3. Link ── SemanticLinker.linkNotes()로 이동된 파일 재연결
```

### FileAnalysis

```swift
struct FileAnalysis: Identifiable {
    let filePath: String
    let fileName: String
    let currentCategory: PARACategory
    let currentFolder: String
    var recommended: ClassifyResult
    var isSelected: Bool         // 사용자 선택
    var needsMove: Bool          // 현재 != 추천
}
```

## Vault Audit Pipeline

`Sources/Services/VaultAuditor.swift` — 볼트 점검 및 자동 수리.

### Audit (감사)

```
모든 PARA 폴더의 .md 파일
    │
    ▼
1. Enumerate ── 재귀적으로 모든 마크다운 파일 수집
    ▼
2. Parse ── Frontmatter 파싱 + [[wikilink]] 추출
    ▼
3. Detect ── 4가지 이슈 감지:
              - Broken Links: [[target]]의 target이 볼트에 없음
              - Missing Frontmatter: para/tags/created/status 모두 없음
              - Untagged Files: tags가 비어있음
              - Missing PARA: para 필드 없음
    ▼
4. Suggest ── 깨진 링크에 대해 유사 노트 제안
              (대소문자 무시, 부분 문자열, Levenshtein, 단어 겹침)
```

### Repair (수리)

```
AuditReport
    │
    ▼
1. Fix Links ── 수정 가능: [[broken]] → [[suggestion]]
                수정 불가: [[broken]] → broken (구문 제거)
                          [[broken|display]] → display
    ▼
2. Inject Frontmatter ── 최소 frontmatter 추가
                         (para + empty tags + created + status=active)
    ▼
3. Fix PARA ── 경로에서 카테고리 추론
               PARACategory.fromPath()로 para 필드 설정
```

### Levenshtein Distance

`maxDistance = max(3, targetLength / 3)`. 이 범위 내의 가장 가까운 노트를 제안.

## Semantic Linking Pipeline

`Sources/Services/SemanticLinker/SemanticLinker.swift` — 노트 간 의미적 연결.

### linkAll() — 전체 볼트

```
전체 볼트
    │
    ▼
1. Tag Normalize ── TagNormalizer.normalize()
    │                프로젝트 폴더명 → 태그 추가
    │                project 필드값 → 태그 추가
    ▼
2. Index ── buildNoteIndex()
    │         모든 PARA .md 파일 인덱싱
    │         NoteInfo: name, tags, summary, project, folderName, para, existingRelated
    ▼
3. PARA 분기 ── 카테고리별 연결 전략 분기
    │
    ├── Project/Area ── processAutoLinks()
    │   │                같은 폴더 sibling 자동 연결 (AI 필터 없이)
    │   │                generateContextOnly()로 맥락 설명만 AI 생성
    │   │                + processAIFilteredLinks() (다른 폴더 후보)
    │   │                  excludeSameFolder=true, folderBonus=1.0
    │   │
    │   └── Resource/Archive ── processAIFilteredLinks()
    │                           folderBonus=2.5 (같은 폴더 가산점 상향)
    │                           excludeSameFolder=false
    ▼
4. AI Filter ── LinkAIFilter.filterBatch()
    │             배치: 5 노트/요청, 3 병렬
    │             노트당 최대 5개 링크 선택
    │             Context 형식: "~하려면", "~할 때", "~와 비교할 때" (15자)
    ▼
5. Write ── RelatedNotesWriter.writeRelatedNotes()
    │          ## Related Notes 섹션 파싱
    │          기존 + 신규 병합 (최대 5개)
    │          형식: - [[NoteName]] -- context
    ▼
6. Reverse ── 역방향 링크 생성
               대상 노트에 "SourceName에서 참조" 역링크 추가
```

### linkNotes(filePaths:) — 대상 파일만

`linkAll()`과 유사하지만:
- 태그 정규화 생략
- 지정된 파일만 후보 생성 및 필터링
- InboxProcessor.finish 단계에서 호출

### Wikilink Sanitization

`RelatedNotesWriter`에서 wikilink 작성 시:
- `[[`, `]]` 제거
- `/`, `\` 제거
- `..` 제거
- 노트 이름이 실제 볼트에 존재하는지 검증

### LinkResult

```swift
struct LinkResult {
    var tagsNormalized: TagNormalizer.Result  // filesModified, tagsAdded
    var notesLinked: Int                      // 1개 이상 링크가 추가된 노트 수
    var linksCreated: Int                     // 총 생성된 링크 수 (순방향 + 역방향)
}
```

## Pipeline Concurrency Summary

| 파이프라인 | 동기/비동기 | 병렬 추출 | 병렬 분류 | 취소 지원 |
|-----------|-----------|----------|----------|----------|
| InboxProcessor | async | max 5 | max 3 (배치) + max 3 (정밀) | Task.isCancelled |
| FolderReorganizer | async | max 5 | Classifier 재사용 | - |
| VaultReorganizer | async | max 5 | Classifier 재사용 | - |
| VaultAuditor | sync | - | - | - |
| SemanticLinker | async | - | max 3 (AI 필터) | - |

## ProjectContextBuilder

`Sources/Pipeline/ProjectContextBuilder.swift` — 모든 파이프라인이 공유하는 볼트 컨텍스트 빌더.

| 메서드 | 설명 |
|--------|------|
| `buildProjectContext()` | `1_Project/` 폴더 목록 + 요약/태그를 텍스트로 구성 |
| `buildSubfolderContext()` | Area/Resource/Archive 서브폴더를 JSON 형식으로 구성 (폴더명 할루시네이션 방지) |
| `extractProjectNames(from:)` | 프로젝트 컨텍스트에서 프로젝트명 추출 |
| `buildWeightedContext()` | 루트 MOC 파일 기반 가중 컨텍스트 구성 (카테고리별: Project 높음, Archive 낮음) |
| `buildTagVocabulary()` | 볼트 전체 상위 50개 태그를 빈도순 JSON 배열로 반환 |

**사용처**: InboxProcessor, FolderReorganizer, VaultReorganizer.

**최적화**: `buildWeightedContext()`는 루트 MOC 파일 우선 사용 (최대 4회 파일 읽기), MOC 없는 카테고리만 레거시 서브폴더 스캔으로 fallback.

## Cross-References

- **서비스 API 상세**: [services.md](services.md)
- **데이터 모델 (ClassifyResult, ProcessedFileResult 등)**: [models-and-data.md](models-and-data.md)
- **동시성 패턴 상세**: [security-and-concurrency.md](security-and-concurrency.md)
- **전체 아키텍처**: [architecture.md](architecture.md)
