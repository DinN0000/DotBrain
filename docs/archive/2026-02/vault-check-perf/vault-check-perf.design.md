# Design: vault-check-perf

> Plan 참조: `docs/01-plan/features/vault-check-perf.plan.md`

## 1. Architecture Overview

```
startVaultCheck() 현재 흐름:
  Audit → Repair → Enrich(순차) → MOC(전체) → SemanticLink(전체)

startVaultCheck() 변경 후 흐름:
  cache.load()
  → Audit(1회 스캔) → Repair → cache.updateHashes(수정된 파일)
  → Enrich(변경분만, 병렬) → cache.updateHashes(enriched 파일)
  → MOC(변경 폴더만)
  → SemanticLink(변경 노트만)
  → cache.save()
```

## 2. Phase 1: ContentHashCache 통합

### 2.1 ContentHashCache 배치 API 추가

**파일**: `Sources/Services/ContentHashCache.swift`

현재 `checkFile()`이 파일당 1회 actor 진입이므로, 배치 메서드를 추가하여 N개 파일을 1회 actor 진입으로 처리.

```swift
// 추가할 메서드
func checkFiles(_ filePaths: [String]) -> [String: FileStatus] {
    var results: [String: FileStatus] = [:]
    for path in filePaths {
        results[path] = checkFile(path)
    }
    return results
}

func updateHashesAndSave(_ filePaths: [String]) {
    for path in filePaths {
        updateHash(path)
    }
    save()
}
```

변경 없는 기존 API는 그대로 유지. Pipeline/UI에서 쓰는 `checkFile()`, `checkFolder()`에 영향 없음.

### 2.2 NoteEnricher에 캐시 연동

**파일**: `Sources/Services/NoteEnricher.swift`

`enrichFolder()` 호출 전에 상위(AppState)에서 변경된 파일만 필터링하므로, NoteEnricher 자체는 수정하지 않는다. 변경 파일만 enrichNote()에 전달되도록 AppState에서 제어.

### 2.3 MOCGenerator.regenerateAll()에 dirty folder 필터

**파일**: `Sources/Services/MOCGenerator.swift`

`regenerateAll()` 시그니처 변경:

```swift
// 현재
func regenerateAll() async

// 변경
func regenerateAll(dirtyFolders: Set<String>? = nil) async
```

- `dirtyFolders == nil` → 기존 동작 (전체 재생성). Pipeline에서의 호출 경로에 영향 없음.
- `dirtyFolders != nil` → 해당 폴더만 `generateMOC()` 호출, 나머지 스킵.
- 루트 카테고리 MOC는 dirtyFolders가 속한 카테고리만 재생성.

내부 변경:
```swift
func regenerateAll(dirtyFolders: Set<String>? = nil) async {
    // ... folderTasks 수집 ...

    // dirtyFolders가 지정되면 해당 폴더만 필터
    let tasksToRun: [(para: PARACategory, folderPath: String, folderName: String)]
    if let dirty = dirtyFolders {
        tasksToRun = folderTasks.filter { dirty.contains($0.folderPath) }
    } else {
        tasksToRun = folderTasks
    }

    // ... 이하 기존 TaskGroup 로직 동일 ...

    // 루트 MOC도 dirty 카테고리만
    let dirtyCategories: Set<String>
    if let dirty = dirtyFolders {
        dirtyCategories = Set(tasksToRun.map {
            ($0.folderPath as NSString).deletingLastPathComponent
        })
    } else {
        dirtyCategories = Set(categories.map { $0.1 })
    }

    for (para, basePath) in categories where dirtyCategories.contains(basePath) {
        try await generateCategoryRootMOC(basePath: basePath, para: para)
    }
}
```

### 2.4 SemanticLinker.linkAll()에 변경 노트 필터

**파일**: `Sources/Services/SemanticLinker/SemanticLinker.swift`

시그니처 변경:

```swift
// 현재
func linkAll(onProgress: ...) async -> LinkResult

// 변경
func linkAll(changedFiles: Set<String>? = nil, onProgress: ...) async -> LinkResult
```

- `changedFiles == nil` → 기존 동작 (전체 스캔). Pipeline 호출에 영향 없음.
- `changedFiles != nil` → 전체 인덱스는 빌드하되(후보 생성에 필요), **AI 필터링은 변경된 노트만** 대상.

내부 변경:
```swift
// buildNoteIndex()는 그대로 (전체 인덱스 필요)
let allNotes = buildNoteIndex()

// 후보 생성은 변경 노트 + 기존 Related Notes 대상
let targetNotes: [NoteInfo]
if let changed = changedFiles {
    let changedNames = Set(changed.map {
        (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
    })
    targetNotes = allNotes.filter { note in
        changedNames.contains(note.name) ||
        !note.existingRelated.isDisjoint(with: changedNames)
    }
} else {
    targetNotes = allNotes
}

// targetNotes에 대해서만 후보 생성 + AI 필터링
for note in targetNotes {
    let candidates = candidateGen.generateCandidates(for: note, allNotes: allNotes, ...)
    // ...
}
```

역방향 링크 누락 방지: `changedNames`에 속하는 노트 뿐 아니라, 해당 노트의 `existingRelated`에 있는 노트도 재처리 대상에 포함.

### 2.5 AppState.startVaultCheck() 오케스트레이션 변경

**파일**: `Sources/App/AppState.swift:213-305`

```swift
func startVaultCheck() {
    // ... 기존 guard, 상태 설정 ...

    backgroundTask = Task.detached(priority: .utility) {
        let cache = ContentHashCache(pkmRoot: root)
        await cache.load()

        // Phase 1: Audit (기존 동일)
        let auditor = VaultAuditor(pkmRoot: root)
        let report = auditor.audit()
        if Task.isCancelled { return }

        // Phase 2: Repair (기존 동일)
        var repairedFiles: [String] = []
        if report.totalIssues > 0 {
            let repair = auditor.repair(report: report)
            // repair가 수정한 파일 목록 수집
            repairedFiles = collectRepairedFiles(from: report, repair: repair)
            await cache.updateHashesAndSave(repairedFiles)
        }
        if Task.isCancelled { return }

        // 전체 .md 파일 해시 체크 (1회 배치)
        let pm = PKMPathManager(root: root)
        let allMdFiles = collectAllMdFiles(pm: pm)
        let fileStatuses = await cache.checkFiles(allMdFiles)
        let changedFiles = Set(fileStatuses.filter { $0.value != .unchanged }.map { $0.key })

        // Phase 3: Enrich (변경 파일만)
        let enricher = NoteEnricher(pkmRoot: root)
        var enrichedFiles: [String] = []
        let filesToEnrich = changedFiles.filter { path in
            // archive 제외
            !path.contains("/4_Archive/")
        }
        // 단일 TaskGroup(max 3)으로 병렬 실행
        await withTaskGroup(of: EnrichResult?.self) { group in
            var active = 0
            var index = 0
            let files = Array(filesToEnrich)
            while index < files.count || !group.isEmpty {
                while active < 3 && index < files.count {
                    let path = files[index]; index += 1; active += 1
                    group.addTask { try? await enricher.enrichNote(at: path) }
                }
                if let result = await group.next() {
                    active -= 1
                    if let r = result, r.fieldsUpdated > 0 {
                        enrichedFiles.append(r.filePath)
                    }
                }
            }
        }
        await cache.updateHashesAndSave(enrichedFiles)
        if Task.isCancelled { return }

        // Phase 4: MOC (변경 폴더만)
        let dirtyFolders = Set(
            (changedFiles.union(enrichedFiles)).map {
                ($0 as NSString).deletingLastPathComponent
            }
        )
        let generator = MOCGenerator(pkmRoot: root)
        await generator.regenerateAll(dirtyFolders: dirtyFolders)
        if Task.isCancelled { return }

        // Phase 5: SemanticLink (변경 노트만)
        let allChanged = changedFiles.union(Set(enrichedFiles))
        let linker = SemanticLinker(pkmRoot: root)
        let linkResult = await linker.linkAll(changedFiles: allChanged, onProgress: ...)

        // 최종 해시 저장
        await cache.updateHashesAndSave(Array(allChanged))

        // ... 기존 결과 보고 ...
    }
}
```

### 2.6 collectRepairedFiles 헬퍼

repair()가 현재 수정된 파일 목록을 명시적으로 반환하지 않으므로, AuditReport에서 추출:

```swift
private func collectRepairedFiles(from report: AuditReport, repair: RepairResult) -> [String] {
    var files = Set<String>()
    // 링크 수정된 파일
    for link in report.brokenLinks where link.suggestion != nil {
        files.insert(link.filePath)
    }
    // frontmatter 주입된 파일
    for path in report.missingFrontmatter {
        files.insert(path)
    }
    // PARA 수정된 파일
    for path in report.missingPARA {
        files.insert(path)
    }
    return Array(files)
}
```

### 2.7 collectAllMdFiles 헬퍼

VaultAuditor.allMarkdownFiles()와 동일한 로직이지만 private이므로, 별도 유틸리티로 추출하거나 AppState에 헬퍼로 추가:

```swift
private func collectAllMdFiles(pm: PKMPathManager) -> [String] {
    let fm = FileManager.default
    var results: [String] = []
    for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath, pm.archivePath] {
        guard let enumerator = fm.enumerator(atPath: basePath) else { continue }
        while let element = enumerator.nextObject() as? String {
            let name = (element as NSString).lastPathComponent
            if name.hasPrefix(".") || name.hasPrefix("_") {
                let full = (basePath as NSString).appendingPathComponent(element)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard name.hasSuffix(".md") else { continue }
            results.append((basePath as NSString).appendingPathComponent(element))
        }
    }
    return results
}
```

## 3. Phase 2: RateLimiter Concurrent Slot

### 3.1 ProviderState 변경

**파일**: `Sources/Services/RateLimiter.swift`

```swift
// 현재
private struct ProviderState {
    var minInterval: Duration
    var lastRequestTime: ContinuousClock.Instant?
    var consecutiveSuccesses: Int = 0
    var consecutiveFailures: Int = 0
    var backoffUntil: ContinuousClock.Instant?
}

// 변경
private struct ProviderState {
    var minInterval: Duration
    var slotCount: Int
    var slotNextAvailable: [ContinuousClock.Instant]  // slot별 다음 가용 시각
    var consecutiveSuccesses: Int = 0
    var consecutiveFailures: Int = 0
    var backoffUntil: ContinuousClock.Instant?
}
```

### 3.2 provider별 slot 수 기본값

```swift
private let defaultSlots: [AIProvider: Int] = [
    .claude: 3,   // 120 RPM 여유 → 3 concurrent 안전
    .gemini: 1,   // 무료 15 RPM → 직렬 유지 (기존 동작 보존)
]
```

### 3.3 acquire() 로직 변경

```swift
func acquire(for provider: AIProvider) async {
    var ps = getState(for: provider)
    let now = ContinuousClock.now

    // backoff 대기 (기존 동일)
    if let backoffUntil = ps.backoffUntil, now < backoffUntil {
        try? await Task.sleep(for: backoffUntil - now)
        ps.backoffUntil = nil
        state[provider] = ps
    }

    // 가장 빠른 slot 선택
    let earliestIndex = ps.slotNextAvailable.enumerated()
        .min(by: { $0.element < $1.element })!.offset
    let earliestTime = ps.slotNextAvailable[earliestIndex]

    let waitUntil = max(earliestTime, ContinuousClock.now)
    let sleepDuration = waitUntil - ContinuousClock.now

    // 해당 slot의 다음 가용 시간 예약 (sleep 전에)
    ps.slotNextAvailable[earliestIndex] = waitUntil + ps.minInterval
    state[provider] = ps

    // 대기
    if sleepDuration > .zero {
        try? await Task.sleep(for: sleepDuration)
    }
}
```

핵심: slot이 3개이면 3개 요청이 각각 다른 slot을 잡아 거의 동시에 발사. 각 slot의 다음 가용 시간은 `now + minInterval`로 설정되므로 minInterval 간격은 slot 단위로 유지.

### 3.4 recordFailure() 변경 — 전체 slot backoff

```swift
func recordFailure(for provider: AIProvider, isRateLimit: Bool) {
    var ps = getState(for: provider)
    ps.consecutiveSuccesses = 0
    ps.consecutiveFailures += 1

    if isRateLimit {
        ps.minInterval = min(ps.minInterval * 2, .seconds(30))
        let capped = min(ps.consecutiveFailures, 6)
        let cooldown = Duration.seconds(min(pow(2.0, Double(capped)), 60))
        let backoffEnd = ContinuousClock.now + cooldown
        ps.backoffUntil = backoffEnd
        // 모든 slot의 다음 가용 시간을 backoff 이후로 설정
        ps.slotNextAvailable = Array(repeating: backoffEnd, count: ps.slotCount)
    } else {
        ps.minInterval = min(ps.minInterval * 3 / 2, .seconds(15))
        ps.backoffUntil = ContinuousClock.now + .seconds(5)
    }
    state[provider] = ps
}
```

### 3.5 recordSuccess() 변경 — 회복 가속

```swift
func recordSuccess(for provider: AIProvider, duration: Duration) {
    var ps = getState(for: provider)
    ps.consecutiveFailures = 0
    ps.consecutiveSuccesses += 1
    ps.backoffUntil = nil

    // 회복: 15% 감소 / 2회 연속 성공마다 (기존: 5% / 3회)
    if ps.consecutiveSuccesses >= 2 {
        let floor = minFloor[provider] ?? .milliseconds(250)
        let reduced = ps.minInterval * 85 / 100
        ps.minInterval = max(reduced, floor)
        ps.consecutiveSuccesses = 0
    }
    state[provider] = ps
}
```

30초 → 4.2초 회복에 필요한 연속 성공 수:
- 기존 (5%/3회): ~55회 (18라운드)
- 변경 (15%/2회): ~24회 (12라운드)

### 3.6 getState() 초기화 변경

```swift
private func getState(for provider: AIProvider) -> ProviderState {
    if let existing = state[provider] { return existing }
    let interval = defaults[provider] ?? .seconds(1)
    let slots = defaultSlots[provider] ?? 1
    return ProviderState(
        minInterval: interval,
        slotCount: slots,
        slotNextAvailable: Array(repeating: .now, count: slots)
    )
}
```

## 4. Phase 3: VaultAuditor 중복 호출 제거

### 4.1 변경 내용

**파일**: `Sources/Services/VaultAuditor.swift`

```swift
// 현재 (라인 41-43)
func audit() -> AuditReport {
    let files = allMarkdownFiles()
    let noteNames = allNoteNames()  // 내부에서 allMarkdownFiles() 재호출

// 변경
func audit() -> AuditReport {
    let files = allMarkdownFiles()
    let noteNames = noteNames(from: files)  // files 재사용
```

```swift
// 현재 (라인 337-345)
private func allNoteNames() -> Set<String> {
    let files = allMarkdownFiles()
    // ...
}

// 변경
private func noteNames(from files: [String]) -> Set<String> {
    var names = Set<String>()
    for file in files {
        let basename = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
        names.insert(basename)
    }
    return names
}
```

### 4.2 영향 범위

- `allNoteNames()`는 `audit()` 내부에서만 호출됨 (private)
- 외부 API 변경 없음
- `allMarkdownFiles()`도 private, audit()에서만 사용

## 5. Phase 4: NoteEnricher 폴더간 병렬화

### 5.1 변경 내용

Phase 1의 AppState 오케스트레이션 변경(Section 2.5)에서 이미 반영됨:

```swift
// 현재: 폴더별 순차
for basePath in [pm.projectsPath, pm.areaPath, pm.resourcePath] {
    for folder in folders {
        let results = await enricher.enrichFolder(at: folderPath)  // 폴더 내부만 max 3
    }
}

// 변경: 전체 파일을 flat list → 단일 TaskGroup(max 3)
let filesToEnrich = changedFiles.filter { !$0.contains("/4_Archive/") }
await withTaskGroup(of: EnrichResult?.self) { group in
    // max 3 concurrent enrichNote() 호출
}
```

### 5.2 enrichFolder() 보존

`enrichFolder()` 메서드는 삭제하지 않는다. 현재는 startVaultCheck()에서만 호출되지만, 향후 개별 폴더 enrich 용도로 유지.

## 6. 파일별 변경 요약

| 파일 | 변경 내용 | 영향 범위 |
|------|----------|----------|
| `ContentHashCache.swift` | `checkFiles()`, `updateHashesAndSave()` 추가 | 추가만, 기존 API 유지 |
| `RateLimiter.swift` | ProviderState에 slot 배열, acquire/record 로직 변경 | **전역** (싱글턴) |
| `VaultAuditor.swift` | `allNoteNames()` → `noteNames(from:)` 변경 | 내부만 (private) |
| `MOCGenerator.swift` | `regenerateAll(dirtyFolders:)` 파라미터 추가 | 기존 호출은 nil 전달 |
| `SemanticLinker.swift` | `linkAll(changedFiles:)` 파라미터 추가 | 기존 호출은 nil 전달 |
| `AppState.swift` | `startVaultCheck()` 오케스트레이션 재작성 | startVaultCheck()만 |
| `NoteEnricher.swift` | **변경 없음** | - |

## 7. 구현 순서 (상세)

```
Step 1: ContentHashCache.checkFiles(), updateHashesAndSave() 추가
Step 2: VaultAuditor.noteNames(from:) 변경
Step 3: MOCGenerator.regenerateAll(dirtyFolders:) 파라미터 추가
Step 4: SemanticLinker.linkAll(changedFiles:) 파라미터 추가
Step 5: AppState.startVaultCheck() 오케스트레이션 재작성
Step 6: RateLimiter concurrent slot 변경
Step 7: swift build 0 warning 확인
```

Step 1-4는 기존 동작을 깨지 않는 추가/옵셔널 변경.
Step 5에서 모든 조각을 조립.
Step 6은 독립적이며 Step 5 전후 어디서든 가능.

## 8. 테스트 시나리오

| 시나리오 | 검증 항목 |
|----------|----------|
| 최초 전체 점검 (캐시 없음) | 기존과 동일한 결과물, 캐시 파일 생성됨 |
| 2회차 전체 점검 (변경 없음) | AI 호출 ~0, 10초 이내 완료 |
| 파일 1개 수정 후 전체 점검 | 해당 파일만 enrich + 해당 폴더 MOC만 재생성 + 해당 노트만 semantic link |
| repair()가 파일 수정한 경우 | 수정된 파일이 enrich 대상에 포함됨 |
| RateLimiter 429 발생 | 모든 slot backoff, 회복 후 정상 동작 |
| Claude → Gemini fallback | Gemini는 slot 1로 동작, 기존 rate 유지 |
