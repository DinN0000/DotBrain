# DotBrain Fixes Design Document

> **Summary**: Critical/High 버그, 보안, 에러 처리, 코드 중복 수정의 구체적 코드 변경 설계
>
> **Project**: DotBrain
> **Version**: v1.5.5 → v1.6.0
> **Author**: hwai
> **Date**: 2026-02-15
> **Status**: Draft
> **Planning Doc**: [dotbrain-fixes.plan.md](../../01-plan/features/dotbrain-fixes.plan.md)

---

## 1. Overview

### 1.1 Design Goals

- Critical/High 이슈를 최소 변경으로 안전하게 수정
- 기존 동작을 깨뜨리지 않으면서 보안과 안정성 강화
- 코드 중복 제거로 유지보수성 향상

### 1.2 Design Principles

- **최소 변경**: 각 수정은 해당 파일만 건드리고, 부수 효과 최소화
- **하위 호환**: KDF 도입 시 기존 암호화 데이터 자동 마이그레이션
- **실패 가시성**: `try?` 무시 패턴을 에러 로깅 패턴으로 전환

### 1.3 Plan 대비 변경사항

| Plan ID | 변경 | 이유 |
|---------|------|------|
| CR-02 | **삭제** | Classifier 카운터는 코드 분석 결과 문제없음 확인 |
| CR-03 | **조정** | FileMover는 이미 async 컨텍스트. 대용량 파일 중복검사 우회가 실제 이슈 |

---

## 2. Phase 1: Critical 수정 (3건)

### 2.1 CR-01: RateLimiter `pow()` overflow 클램핑

**파일**: `Sources/Services/RateLimiter.swift` (112줄)
**위치**: Line 89

**현재 코드:**
```swift
let cooldown = Duration.seconds(min(pow(2.0, Double(ps.consecutiveFailures)), 60))
ps.backoffUntil = now + cooldown
```

**문제**: `consecutiveFailures`가 무한 증가 가능. `pow(2, 1024)` = `Double.infinity`

**수정:**
```swift
let capped = min(ps.consecutiveFailures, 6)  // max 64초 → min(64, 60) = 60초
let cooldown = Duration.seconds(min(pow(2.0, Double(capped)), 60))
ps.backoffUntil = now + cooldown
```

**영향 범위**: RateLimiter 내부만. 외부 API 동일.

---

### 2.2 CR-03: FileMover 대용량 파일 중복검사 우회

**파일**: `Sources/Services/FileSystem/FileMover.swift` (459줄)
**위치**: Lines 204-206

**현재 코드:**
```swift
let maxHashSize = 500 * 1024 * 1024  // 500MB
if fileSize <= maxHashSize,
   let sourceHash = streamingHash(at: filePath),
   // ... hash 비교 로직
```

**문제**: >500MB 파일은 중복검사 완전 스킵 → 동일 대용량 파일 중복 이동

**수정:**
```swift
let maxHashSize = 500 * 1024 * 1024  // 500MB
if fileSize <= maxHashSize,
   let sourceHash = streamingHash(at: filePath),
   let destHash = streamingHash(at: destPath),
   sourceHash == destHash {
    // 해시 기반 중복 감지
    ...
} else if fileSize > maxHashSize {
    // 대용량 파일: 크기 + 수정일 기반 비교
    let srcAttr = try? fm.attributesOfItem(atPath: filePath)
    let dstAttr = try? fm.attributesOfItem(atPath: destPath)
    let srcDate = srcAttr?[.modificationDate] as? Date
    let dstDate = dstAttr?[.modificationDate] as? Date
    let srcSize = srcAttr?[.size] as? UInt64
    let dstSize = dstAttr?[.size] as? UInt64
    if srcSize == dstSize, srcDate == dstDate {
        // 메타데이터 기반 중복 감지
        ...
    }
}
```

**영향 범위**: FileMover 내부. 결과 Status 값 동일 (`deduplicated`).

---

### 2.3 CR-04: Gemini API 키 URL 노출

**파일**: `Sources/Services/Gemini/GeminiAPIClient.swift` (185줄)
**위치**: Line 85

**현재 코드:**
```swift
let endpoint = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
```

**문제**: API 키가 URL에 포함되어 로그/프록시에 평문 노출

**조사 결과**: Google Gemini API는 `?key=` 쿼리 파라미터 방식을 공식적으로 사용. 헤더 기반(`x-goog-api-key`)도 지원.

**수정:**
```swift
let endpoint = "\(baseURL)/\(model):generateContent"
guard let url = URL(string: endpoint) else {
    throw GeminiAPIError.invalidURL
}
var urlRequest = URLRequest(url: url)
urlRequest.httpMethod = "POST"
urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
```

**영향 범위**: GeminiAPIClient 내부. API 동작 동일 (Google은 헤더 방식 지원).

---

## 3. Phase 2: High 수정 (5건)

### 3.1 HI-01: KeychainService KDF 도입

**파일**: `Sources/Services/KeychainService.swift` (199줄)
**위치**: Lines 60-68

**현재 코드:**
```swift
private static func encryptionKey() -> SymmetricKey? {
    guard let uuid = hardwareUUID() else { return nil }
    let material = uuid + salt
    let hash = SHA256.hash(data: Data(material.utf8))
    return SymmetricKey(data: hash)
}
```

**문제**: 단일 SHA256 패스, KDF 미사용

**수정:**
```swift
private static let kdfIterations = 100_000

private static func encryptionKey() -> SymmetricKey? {
    guard let uuid = hardwareUUID() else {
        print("[SecureStore] 하드웨어 UUID를 가져올 수 없음")
        return nil
    }
    let password = Data((uuid + salt).utf8)
    let saltData = Data("dotbrain-kdf-salt-v2".utf8)

    // HKDF (CryptoKit 기본 제공, PBKDF2보다 빠르고 목적에 적합)
    let derived = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: SymmetricKey(data: password),
        salt: saltData,
        info: Data("dotbrain-encryption".utf8),
        outputByteCount: 32
    )
    return derived
}
```

**마이그레이션**: 기존 v1 키로 복호화 시도 → 실패 시 새 v2 키로 재암호화
```swift
static func load(for key: String) -> String? {
    // v2 키로 시도
    if let value = decrypt(with: encryptionKeyV2()) { return value }
    // v1 키로 fallback → 성공 시 v2로 재암호화
    if let value = decrypt(with: encryptionKeyV1()) {
        save(value, for: key)  // v2로 재저장
        return value
    }
    return nil
}
```

**영향 범위**: KeychainService 내부 + 첫 실행 시 자동 마이그레이션.

---

### 3.2 HI-02: install.sh 체크섬 검증

**파일**: `install.sh`

**현재**: 다운로드 후 바로 설치, 무결성 미확인

**수정**: GitHub Release에 `checksums.txt` 에셋 추가 + install.sh에 검증 로직

```bash
# 체크섬 파일 다운로드
CHECKSUM_URL="https://github.com/DinN0000/DotBrain/releases/download/${TAG}/checksums.txt"
if curl -sLf "$CHECKSUM_URL" -o /tmp/dotbrain-checksums.txt 2>/dev/null; then
    EXPECTED=$(grep "DotBrain$" /tmp/dotbrain-checksums.txt | awk '{print $1}')
    ACTUAL=$(shasum -a 256 /tmp/DotBrain | awk '{print $1}')
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        echo "체크섬 불일치! 설치 중단."
        exit 1
    fi
    echo "체크섬 확인 ✓"
fi
# 체크섬 파일 없으면 (이전 릴리즈) 경고만 출력하고 계속
```

**릴리즈 워크플로우**: `shasum -a 256 /tmp/DotBrain > checksums.txt` → Release 에셋 추가

---

### 3.3 HI-03: FolderReorganizer 에러 보고

**파일**: `Sources/Pipeline/FolderReorganizer.swift` (491줄)
**위치**: Lines 289, 291, 298, 307

**현재 코드:**
```swift
try? fm.moveItem(atPath: file.source, toPath: resolved)    // Line 289
try? fm.moveItem(atPath: file.source, toPath: destPath)    // Line 291
try? fm.removeItem(atPath: placeholder)                     // Line 298
try? fm.removeItem(atPath: dir)                             // Line 307
```

**수정:**
```swift
// Lines 289, 291: 이동 실패 시 에러 수집
var moveErrors: [String] = []

do {
    try fm.moveItem(atPath: file.source, toPath: resolved)
    movedCount += 1
} catch {
    moveErrors.append("\(file.fileName): \(error.localizedDescription)")
    print("[FolderReorganizer] 이동 실패: \(file.fileName) — \(error)")
}

// Lines 298, 307: 정리 실패는 로그만 (non-critical)
do {
    try fm.removeItem(atPath: placeholder)
} catch {
    print("[FolderReorganizer] 플레이스홀더 삭제 실패: \(error)")
}
```

**결과 반영**: `ProcessedFileResult.Status.error(String)`에 실패 파일 포함

---

### 3.4 HI-04: InboxWatchdog fd leak 방지

**파일**: `Sources/Services/FileSystem/InboxWatchdog.swift` (103줄)
**위치**: Lines 22-24, 36, 52-54

**현재 코드:**
```swift
deinit {
    stop()
}

func stop() {
    debounceWorkItem?.cancel()
    cancelRetry()
    source?.cancel()
    source = nil
}
```

**문제**: `deinit`에서 `source?.cancel()`은 비동기. cancel handler가 실행되기 전에 dealloc 가능.

**수정:**
```swift
func stop() {
    debounceWorkItem?.cancel()
    debounceWorkItem = nil
    cancelRetry()
    if let source = self.source {
        source.cancel()
        self.source = nil
    }
    print("[InboxWatchdog] 감시 중지")
}

// start() 내 setCancelHandler에서 fd close 보장
source.setCancelHandler { [fd] in
    close(fd)
    print("[InboxWatchdog] fd \(fd) closed")
}
```

**핵심**: `setCancelHandler`에서 `[fd]`를 캡처하면 source가 dealloc되어도 fd가 close됨. GCD가 cancel handler 실행을 보장.

---

### 3.5 HI-05: StatisticsService actor 전환

**파일**: `Sources/Services/StatisticsService.swift` (106줄)

**현재**: `class StatisticsService` with `static func` — race condition in read-modify-write

**수정**: `actor` 전환 + `shared` 싱글톤

```swift
actor StatisticsService {
    static let shared = StatisticsService()

    func recordActivity(type: String, detail: String, pkmRoot: String) {
        var history = Self.loadActivityHistory()
        let entry: [String: String] = [
            "type": type,
            "detail": detail,
            "date": ISO8601DateFormatter().string(from: Date())
        ]
        history.insert(entry, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        UserDefaults.standard.set(history, forKey: "pkmActivityHistory")
    }

    func addApiCost(_ cost: Double) {
        let current = UserDefaults.standard.double(forKey: "pkmApiCost")
        UserDefaults.standard.set(current + cost, forKey: "pkmApiCost")
    }

    func incrementDuplicates() {
        let current = UserDefaults.standard.integer(forKey: "pkmDuplicatesFound")
        UserDefaults.standard.set(current + 1, forKey: "pkmDuplicatesFound")
    }

    // 읽기 전용은 nonisolated 가능
    nonisolated func collectStatistics(pkmRoot: String) -> PKMStatistics { ... }
}
```

**호출부 변경**: `StatisticsService.recordActivity(...)` → `await StatisticsService.shared.recordActivity(...)`

**영향 파일**: InboxProcessor, FolderReorganizer, FileMover (호출부에 `await` 추가)

---

## 4. Phase 3: Refactoring (4건 우선)

### 4.1 RF-01: FileContentExtractor 공통 추출

**새 파일**: `Sources/Services/Extraction/FileContentExtractor.swift`

```swift
struct FileContentExtractor {
    static func extract(from filePath: String, maxLength: Int = 5000) -> String {
        if BinaryExtractor.isBinaryFile(filePath) {
            let result = BinaryExtractor.extract(at: filePath)
            let text = result.text ?? "[바이너리 파일: \(URL(fileURLWithPath: filePath).pathExtension)]"
            return String(text.prefix(maxLength))
        }

        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            return String(content.prefix(maxLength))
        }

        return "[읽기 실패: \(URL(fileURLWithPath: filePath).lastPathComponent)]"
    }
}
```

**변경 파일**:
- `InboxProcessor.swift` Line 275: `extractContent()` → `FileContentExtractor.extract(from:)` 호출 (폴더 처리는 유지)
- `FolderReorganizer.swift` Line 477: `extractContent()` → `FileContentExtractor.extract(from:)` 호출

---

### 4.2 RF-03: AIAPIError 통합

**새 파일**: `Sources/Models/AIAPIError.swift`

```swift
enum AIAPIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case httpError(statusCode: Int, body: String)
    case rateLimited
    case jsonParsingFailed(String)
    case emptyResponse
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "잘못된 URL"
        case .invalidResponse: return "잘못된 응답"
        case .httpError(let code, _): return "HTTP \(code)"
        case .rateLimited: return "Rate limited"
        case .jsonParsingFailed(let detail): return "JSON 파싱 실패: \(detail)"
        case .emptyResponse: return "빈 응답"
        case .networkError(let err): return "네트워크 에러: \(err.localizedDescription)"
        }
    }
}
```

**변경 파일**:
- `ClaudeAPIClient.swift`: 기존 `ClaudeAPIError` → `AIAPIError` 매핑
- `GeminiAPIClient.swift`: 기존 `GeminiAPIError` → `AIAPIError` 매핑
- `AIService.swift`: 에러 처리 통합

---

### 4.3 RF-02: JSON 파싱 유틸 통합

**새 파일**: `Sources/Services/AIResponseParser.swift`

```swift
struct AIResponseParser {
    /// AI 응답에서 JSON 블록 추출 (```json ... ``` 또는 raw JSON)
    static func extractJSON(from text: String) -> String? { ... }

    /// JSON 문자열 → ClassifyResult 배열 파싱
    static func parseClassifyResults(from json: String) throws -> [ClassifyResult] { ... }
}
```

**변경 파일**: ClaudeAPIClient, GeminiAPIClient에서 중복 JSON 추출 로직 제거

---

### 4.4 RF-06: categoryFromPath 통합

`PKMPathManager`에 공통 메서드 추가:

```swift
extension PKMPathManager {
    static func categoryFromPath(_ path: String, pkmRoot: String) -> PARACategory? {
        let relative = path.replacingOccurrences(of: pkmRoot + "/", with: "")
        if relative.hasPrefix("1_Project") { return .project }
        if relative.hasPrefix("2_Area") { return .area }
        if relative.hasPrefix("3_Resource") { return .resource }
        if relative.hasPrefix("4_Archive") { return .archive }
        return nil
    }
}
```

---

## 5. Phase 4: 문서 동기화

### 5.1 architecture.design.md 갱신

누락 항목 추가:

| 섹션 | 추가할 모듈 |
|------|------------|
| 컨텍스트 & 링킹 | ContextMapBuilder, ContextMap |
| 유틸리티 | VaultAuditor, VaultSearcher |
| 새 파일 (Phase 3) | FileContentExtractor, AIResponseParser, AIAPIError |
| UI | OnboardingView, SearchView, DashboardView 설명 보강 |

### 5.2 AICompanionService version 증가

`AICompanionService.swift`의 `version` 상수 +1 → 볼트 내 CLAUDE.md/AGENTS.md 자동 갱신 트리거

---

## 6. Implementation Order

```
Phase 1: Critical (워크트리: fix/dotbrain-fixes)
  1. RateLimiter.swift — pow 클램핑 (1줄 변경)
  2. GeminiAPIClient.swift — 헤더 기반 인증 (3줄 변경)
  3. FileMover.swift — 대용량 파일 메타데이터 비교 (~15줄 추가)
  → swift build 확인

Phase 2: High
  4. StatisticsService.swift — actor 전환 (~30줄 변경)
     + InboxProcessor, FolderReorganizer, FileMover 호출부 await 추가
  5. FolderReorganizer.swift — try? → do-catch (~20줄 변경)
  6. InboxWatchdog.swift — fd 캡처 패턴 (~5줄 변경)
  7. KeychainService.swift — HKDF + 마이그레이션 (~40줄 변경)
  → swift build 확인

Phase 3: Refactoring
  8. FileContentExtractor.swift 신규 + InboxProcessor/FolderReorganizer 수정
  9. AIAPIError.swift 신규 + Claude/Gemini 클라이언트 수정
  10. AIResponseParser.swift 신규 + 파싱 로직 통합
  11. PKMPathManager categoryFromPath 통합
  → swift build 확인

Phase 4: Docs
  12. architecture.design.md 갱신
  13. AICompanionService version 증가
  14. install.sh 체크섬 추가

→ git commit → PR → merge → release
```

---

## 7. Test Plan

| 항목 | 검증 방법 |
|------|-----------|
| RateLimiter overflow | `consecutiveFailures = 1000` 상태에서 cooldown 값 확인 |
| Gemini API 호출 | 실제 API 호출 성공 확인 (헤더 인증) |
| 대용량 파일 | >500MB 동일 파일 2개로 중복 감지 확인 |
| KDF 마이그레이션 | 기존 키 복호화 → 새 키 재암호화 확인 |
| StatisticsService | 동시 호출 시 카운터 정확성 확인 |
| FolderReorganizer | 잠긴 파일 이동 시 에러 메시지 포함 확인 |
| 빌드 | `swift build -c release --arch arm64 --arch x86_64` 성공 |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-15 | Initial draft — 소스 코드 분석 기반 | hwai |
