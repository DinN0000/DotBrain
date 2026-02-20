# Security and Concurrency

보안 패턴, 동시성 모델, 에러 핸들링. 코드 변경 시 반드시 준수해야 할 불변 규칙(invariants).

## Path Traversal Defense

### isPathSafe()

`Sources/Services/FileSystem/PKMPathManager.swift`

```swift
func isPathSafe(_ path: String) -> Bool {
    let resolvedRoot = URL(fileURLWithPath: root)
        .standardizedFileURL.resolvingSymlinksInPath().path
    let resolvedPath = URL(fileURLWithPath: path)
        .standardizedFileURL.resolvingSymlinksInPath().path
    return isPathInsideResolvedRoot(resolvedPath, resolvedRoot: resolvedRoot)
}
```

**규칙**: 심볼릭 링크를 먼저 해석한 후 `hasPrefix`로 비교. 슬래시 정규화 포함.

**호출 위치**: `FileMover.moveFile()`, `FileMover.moveFolder()`, `FolderReorganizer.process()`, `ProjectManager.createProject()`, `PARAMover.moveFolder()`, `ContentHashCache.checkFile()`, `ContentHashCache.checkFolder()`, `VaultReorganizer.collectFiles()`

### sanitizeFolderName()

`Sources/Services/FileSystem/PKMPathManager.swift`

| 제약 | 값 |
|------|---|
| 최대 경로 깊이 | 3 |
| 컴포넌트 최대 길이 | 255자 |
| 차단 패턴 | `..`, `.`, null byte (`\0`) |
| PARA 중복 제거 | `"2_Area/subfolder"` → `"subfolder"` |

`sanitizeTargetFolder()`는 추가로 PARA 카테고리 접두사 중복을 제거하여 `"2_Area/2_Area/DevOps"` 같은 공격을 방지.

### InboxScanner 심볼릭 링크 검증

`Sources/Services/FileSystem/InboxScanner.swift`

심볼릭 링크 파일은 타겟이 pkmRoot 내부인지 검증 후에만 처리 대상에 포함.

## YAML Injection Prevention

### escapeYAML()

`Sources/Models/Frontmatter.swift`

**이스케이프 대상**: `:`, `#`, `"`, `'`, `\n`, `\r`, 선행/후행 공백, `[`, `{`, YAML 예약어(`true`, `false`, `null`, `yes`, `no`)

**처리**: 대상 감지 시 `\` 이스케이프 후 더블 쿼트로 감싸기.

### Tags 더블 쿼트 규칙

```yaml
tags: ["tag1", "tag2"]   # 항상 이 형식
```

태그 값 내부의 `\`와 `"`를 이스케이프한 후 각 태그를 더블 쿼트로 감싼다. `stringify()` 메서드에서 모든 필드에 `escapeYAML()` 적용.

## API Key Security

`Sources/Services/KeychainService.swift`

### Encryption Stack

```
Hardware UUID (IOKit)
        │
        ▼
HKDF<SHA256>.deriveKey(
    inputKeyMaterial: UUID + salt,
    salt: "dotbrain-keys-v2",
    info: "dotbrain-encryption",
    outputByteCount: 32
)
        │
        ▼
AES-GCM.seal(keyData, using: derivedKey)
        │
        ▼
~/.local/share/com.hwaa.dotbrain/keys.enc  (chmod 0o600)
```

| 레이어 | 기술 |
|--------|------|
| 키 도출 | HKDF<SHA256>, 하드웨어 UUID 바인딩 |
| 암호화 | AES-GCM (authenticated encryption) |
| 파일 권한 | `0o600` (owner read/write only) |
| 저장 형식 | JSON dict → AES-GCM sealed → 바이너리 파일 |
| 원자적 쓰기 | `.atomic` 옵션으로 부분 저장 방지 |

### V1 → V2 Migration

V1 (SHA256 hash) → V2 (HKDF-SHA256) 자동 마이그레이션. V1 키로 복호화 시도 후 V2로 재암호화. macOS Keychain에서의 레거시 마이그레이션도 지원.

## Actor Isolation

### Actor 목록

| Actor | 파일 | 보호 대상 |
|-------|------|-----------|
| `AIService` | `Sources/Services/AIService.swift` | 프로바이더 라우팅, 재시도 상태 |
| `Classifier` | `Sources/Services/Claude/Classifier.swift` | 2단계 분류 상태 |
| `RateLimiter` | `Sources/Services/RateLimiter.swift` | 프로바이더별 rate limit 상태 |
| `ClaudeAPIClient` | `Sources/Services/Claude/ClaudeAPIClient.swift` | URLSession, API 통신 |
| `GeminiAPIClient` | `Sources/Services/Gemini/GeminiAPIClient.swift` | URLSession, API 통신 |
| `ContentHashCache` | `Sources/Services/ContentHashCache.swift` | SHA256 해시 캐시 (JSON 파일 I/O) |
| `APIUsageLogger` | `Sources/Services/APIUsageLogger.swift` | 토큰 사용량 로그 (JSON 파일 I/O) |

### RateLimiter 상세

적응형 rate limiting. 프로바이더별 독립 상태 관리.

| 프로바이더 | 기본 간격 | 최소 간격 (가속 후) | RPM |
|-----------|----------|-------------------|-----|
| Gemini | 4200ms | 2100ms | ~14–28 |
| Claude | 500ms | 250ms | ~120–240 |

- **성공 시**: 연속 3회 성공마다 간격 5% 감소 (최소 간격까지)
- **429 에러 시**: 간격 2배 + 지수 백오프 cooldown (최대 60초)
- **5xx 에러 시**: 간격 1.5배 + 5초 cooldown

### StatisticsActor

`Sources/Services/StatisticsService.swift` 내부.

```swift
private actor StatisticsActor {
    // UserDefaults 뮤테이션을 직렬화
    func addCost(_ cost: Double) { ... }
    func incrementDuplicates() { ... }
    func recordActivity(_ entry: ActivityEntry) { ... }
}
```

## @MainActor Boundary Rules

### @MainActor 클래스

| 클래스 | 파일 |
|--------|------|
| `AppState` | `Sources/App/AppState.swift` |
| `AppDelegate` | `Sources/App/AppDelegate.swift` |
| `InboxWatchdog` | `Sources/Services/FileSystem/InboxWatchdog.swift` |

### 규칙

1. **UI 상태 변경은 반드시 @MainActor에서**: `@Published` 속성 수정은 MainActor 컨텍스트에서만
2. **Task.detached 내부에서 UI 업데이트**: `await MainActor.run { ... }` 사용
3. **콜백에서 MainActor 전환**: `Task { @MainActor in ... }` 패턴

```swift
// 올바른 패턴: Task.detached + MainActor.run 브릿징
Task.detached(priority: .utility) {
    let result = heavyWork()
    await MainActor.run {
        self.publishedProperty = result
    }
}
```

## Task.detached Usage Rules

**항상 `Task.detached(priority:)`를 사용** — `DispatchQueue.global()` 금지.

| priority | 사용처 |
|----------|--------|
| `.utility` | 일회성 백그라운드 작업 (에셋 마이그레이션, 볼트 감사) |
| 미지정 (기본) | 일반 파이프라인 작업 |

**패턴**: detached task 내부에서 UI 업데이트 시 반드시 `await MainActor.run` 사용.

**InboxWatchdog 예외**: `DispatchSource.makeFileSystemObjectSource`는 커널 레벨 FS 이벤트 API라 GCD가 유일한 선택. 디바운스/재시도는 Task로 브릿징.

## TaskGroup Concurrency Patterns

### 동시성 한도 테이블

| 작업 | 최대 동시 | 배치 크기 | 파일 |
|------|----------|----------|------|
| 콘텐츠 추출 | 5 | 1 파일 | `InboxProcessor.swift`, `FolderReorganizer.swift`, `VaultReorganizer.swift` |
| Stage 1 분류 (Haiku/Flash) | 3 | 5 파일/배치 | `Classifier.swift` |
| Stage 2 분류 (Sonnet/Pro) | 3 | 1 파일 | `Classifier.swift` |
| AI 링크 필터링 | 3 | 5 노트/배치 | `SemanticLinker.swift` |
| 노트 보강 | 3 | 1 파일 | `NoteEnricher.swift` |

### 패턴: 수동 동시성 제한

```swift
await withTaskGroup(of: Result.self) { group in
    var activeTasks = 0
    let maxConcurrent = 5

    for item in items {
        if activeTasks >= maxConcurrent {
            if let result = await group.next() {
                collected.append(result)
            }
            activeTasks -= 1
        }
        group.addTask { ... }
        activeTasks += 1
    }
    for await result in group {
        collected.append(result)
    }
}
```

## Error Handling Patterns

### AI Error Classification

`Sources/Services/AIService.swift`

| 분류 | 조건 | 동작 |
|------|------|------|
| Rate limit (429) | `httpError(status: 429)` or `apiError(status: 429, ...)` | 재시도 + 적응형 백오프 |
| Server error (5xx) | `httpError(status: 500–599)` | 재시도 + 중간 백오프 |
| Retryable | 429, 5xx, URLError 일부 | 최대 3회 재시도, 120초 deadline |
| Non-retryable | 401, 403, 잘못된 요청 | 즉시 실패 |
| Fallback | 기본 프로바이더 전체 실패 | 대체 프로바이더로 전환 |

### Error Enums

| Enum | 파일 | 주요 케이스 |
|------|------|------------|
| `ClaudeAPIError` | `Sources/Services/Claude/ClaudeAPIClient.swift` | noAPIKey, httpError(status), apiError(status, message), emptyResponse |
| `GeminiAPIError` | `Sources/Services/Gemini/GeminiAPIClient.swift` | noAPIKey, httpError(status), apiError(status, message) |
| `AIServiceError` | `Sources/Services/AIService.swift` | timeout |
| `ProjectError` | `Sources/Services/ProjectManager.swift` | alreadyExists, notFound |
| `EnrichError` | `Sources/Services/NoteEnricher.swift` | cannotRead, aiParseFailed |
| `PARAMoveError` | `Sources/Services/PARAMover.swift` | notFound, alreadyExists |

### User-Friendly Error Messages

`Sources/Pipeline/InboxProcessor.swift` — `friendlyErrorMessage()` static method.

| 기술 에러 | 사용자 메시지 (한국어) |
|-----------|---------------------|
| API key error | "API 키를 확인해주세요" |
| Rate limit (429) | "API 요청 한도 초과" |
| Network error | "인터넷 연결을 확인해주세요" |
| Permission error | "파일 접근 권한이 필요합니다" |
| CancellationError | "작업이 취소되었습니다" |
| Timeout | "요청 시간이 초과되었습니다" |

### Cancellation Handling

```swift
// Pattern 1: await 후 취소 확인
let results = try await processor.process()
guard !Task.isCancelled else { return }

// Pattern 2: 루프 내 취소 확인
for file in files {
    if Task.isCancelled { throw CancellationError() }
    // process file...
}

// Pattern 3: 취소 시 에러 UI 억제
} catch {
    if !Task.isCancelled {
        processedResults = [errorResult]
    }
}
```

## Streaming File I/O Rules

**규칙**: 대용량 파일을 전체 로드하지 않는다. `FileHandle`로 1MB 청크 단위 읽기.

### Smart Extraction Budget

`Sources/Services/Extraction/FileContentExtractor.swift`

마크다운 파일에서 AI 분류용 텍스트를 추출할 때 5000자 예산을 배분:

| 파트 | 비율 | 내용 |
|------|------|------|
| Frontmatter | ~20% | 기존 메타데이터 |
| Intro | ~30% | 본문 첫 1500자 |
| Headings | ~30% | 모든 `##` 제목 목록 |
| Tail | ~20% | 마지막 500자 (결론, 참고문헌) |

### Streaming Hash (중복 감지)

`Sources/Services/FileSystem/FileMover.swift`

```swift
func streamingHash(at path: String) -> SHA256Digest? {
    guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
    defer { handle.closeFile() }
    var hasher = SHA256()
    while true {
        let chunk = handle.readData(ofLength: 1024 * 1024)  // 1MB
        if chunk.isEmpty { break }
        hasher.update(data: chunk)
    }
    return hasher.finalize()
}
```

| 파일 크기 | 해시 방법 |
|-----------|----------|
| 텍스트 파일 | body SHA256 (frontmatter 제외) |
| 바이너리 <= 500MB | 스트리밍 SHA256 (1MB 청크) |
| 바이너리 > 500MB | 메타데이터 비교 (크기 + 수정일) |

## Cross-References

- **Actor 목록과 서비스 API**: [services.md](services.md)
- **TaskGroup 사용 파이프라인**: [pipelines.md](pipelines.md)
- **Frontmatter 스키마**: [models-and-data.md](models-and-data.md)
- **전체 아키텍처**: [architecture.md](architecture.md)
