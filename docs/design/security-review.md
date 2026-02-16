# DotBrain Security Review

> 2026-02-15 | Security Architect Review
> Scope: Full codebase security audit (v1.5.7 기준, 주요 이슈 수정 완료)

---

## 요약

| 구분 | 점수 |
|------|------|
| **전체 보안 점수** | **82/100** |
| Critical | 1건 |
| High | 2건 |
| Medium | 3건 |
| Low | 2건 |

DotBrain은 단일 사용자 로컬 macOS 앱으로서 서버 사이드 공격 벡터가 없는 점을 감안하면,
전반적으로 **양호한 보안 수준**입니다. 특히 path traversal 방어와 암호화 파일 퍼미션 설정이 잘 되어 있습니다.
다만 Gemini API 키의 URL 노출, AES-GCM 키 파생의 엔트로피 제한,
그리고 심볼릭 링크 TOCTOU 경합 조건 등은 실질적인 개선이 필요합니다.

---

## 1. API Key Storage (KeychainService.swift)

### 1.1 AES-GCM + Hardware UUID 방식 평가

**파일**: `/Users/hwai/Developer/DotBrain/Sources/Services/KeychainService.swift`

**현재 구현**:
```swift
private static func encryptionKey() -> SymmetricKey? {
    guard let uuid = hardwareUUID() else { return nil }
    let material = uuid + salt  // "UUID" + "dotbrain-key-salt-v1"
    let hash = SHA256.hash(data: Data(material.utf8))
    return SymmetricKey(data: hash)
}
```

**장점**:
- AES-256-GCM은 현대 대칭 암호 표준 (NIST 승인)
- 파일 퍼미션 0o600 설정으로 소유자만 읽기/쓰기 가능 (97-99행)
- Atomic write로 쓰기 중 손상 방지 (94행)
- 마이그레이션 후 레거시 키체인 항목 삭제 (165-166행)

**문제점**:

#### [HIGH] SEC-001: 키 파생에 KDF 미사용

| 항목 | 내용 |
|------|------|
| 심각도 | High |
| OWASP | A02 (Cryptographic Failures) |
| 위치 | `KeychainService.swift:60-68` |

하드웨어 UUID는 약 128비트 엔트로피를 제공하고 고정 salt와 단순 SHA256 해싱만 적용됩니다.
이것은 키체인(macOS Keychain)을 대체하기에는 약한 구조입니다.

**실질적 위험도**: 중간. 하드웨어 UUID는 추측이 어렵지만,
`ioreg -d2 -c IOPlatformExpertDevice` 명령으로 같은 기기에서 쉽게 조회 가능합니다.
같은 기기에 접근할 수 있는 다른 앱/프로세스가 동일한 키를 재파생할 수 있습니다.

**권장 조치**:
```swift
// HKDF 적용 (CryptoKit 내장)
private static func encryptionKey() -> SymmetricKey? {
    guard let uuid = hardwareUUID() else { return nil }
    let inputKey = SymmetricKey(data: Data(uuid.utf8))
    let derived = HKDF<SHA256>.deriveKey(
        inputKeyMaterial: inputKey,
        salt: Data("dotbrain-key-salt-v2".utf8),
        info: Data("com.hwaa.dotbrain.api-keys".utf8),
        outputByteCount: 32
    )
    return derived
}
```

또는 더 강력하게 macOS Keychain을 주 저장소로 유지하되, Sandboxed 환경에서의 접근 문제만 별도 처리하는 방안을 고려할 수 있습니다.

---

## 2. Network Security

### 2.1 Claude API - 양호

**파일**: `/Users/hwai/Developer/DotBrain/Sources/Services/Claude/ClaudeAPIClient.swift`

```swift
private let baseURL = "https://api.anthropic.com/v1/messages"
// API 키는 헤더로 전송 (x-api-key)
urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
```

- HTTPS 하드코딩 확인
- API 키가 HTTP 헤더로 전송 (URL 파라미터 아님) -- 양호
- `install.sh`의 ATS 설정에서 `NSAllowsArbitraryLoads: false` 확인 -- 양호

### 2.2 Gemini API - 치명적 문제

**파일**: `/Users/hwai/Developer/DotBrain/Sources/Services/Gemini/GeminiAPIClient.swift`

#### [CRITICAL] SEC-002: API 키가 URL Query Parameter에 노출

| 항목 | 내용 |
|------|------|
| 심각도 | **Critical** |
| OWASP | A02 (Cryptographic Failures) |
| 위치 | `GeminiAPIClient.swift:85` |

```swift
let endpoint = "\(baseURL)/\(model):generateContent?key=\(apiKey)"
```

**문제**:
- API 키가 URL에 포함되어 다음 위치에 노출될 수 있음:
  - macOS 시스템 로그 (`Console.app`, `log show`)
  - URLSession 디버그 로그
  - 프록시/VPN 로그 (HTTPS 터널링 전 URL은 로컬 프록시에서 볼 수 있음)
  - 크래시 리포트의 URL 스택 트레이스

**사실**: 이것은 Google의 Gemini API 공식 인증 방식입니다 (API key in query parameter).
Google 자체가 이 패턴을 사용하므로 프로토콜 수준에서 변경이 어렵습니다.

**위험 완화**:
- HTTPS로 전송되므로 네트워크 도청 자체는 방어됨
- 로컬 앱이므로 브라우저 히스토리/서버 로그 누출 시나리오는 해당 없음

**권장 조치** (가능한 범위):
```swift
// 1. 에러 로깅에서 URL 마스킹
print("[GeminiAPI] HTTP \(httpResponse.statusCode): \(preview)")
// 위 코드에서 URL을 절대 로그하지 말 것 (현재도 URL은 로그 안 하고 있음 - 양호)

// 2. Google OAuth2 방식으로 전환 가능하면 전환
// (개인용 로컬 앱에서는 과도한 복잡성)
```

**현재 판단**: Google API의 공식 인증 방식을 따르고 있고, 로컬 앱이므로 실질적 위험은 Medium에 가깝습니다.
다만 구조적으로 API 키가 URL에 포함되는 것 자체는 보안 안티패턴이므로 Critical로 분류합니다.

---

## 3. Path Traversal (PKMPathManager.swift)

**파일**: `/Users/hwai/Developer/DotBrain/Sources/Services/FileSystem/PKMPathManager.swift`

### 3.1 방어 메커니즘 분석

```swift
private func sanitizeFolderName(_ name: String) -> String {
    let components = name.components(separatedBy: "/")
    let safe = components.filter { $0 != ".." && $0 != "." && !$0.isEmpty }
    let limited = Array(safe.prefix(3))
    return limited.map { component in
        let cleaned = component.replacingOccurrences(of: "\0", with: "")
        return String(cleaned.prefix(255))
    }.joined(separator: "/")
}
```

**추가 방어 (이중 검증)**:
```swift
let resolvedBase = URL(fileURLWithPath: base).standardizedFileURL.resolvingSymlinksInPath().path
let resolvedTarget = URL(fileURLWithPath: targetPath).standardizedFileURL.resolvingSymlinksInPath().path
guard resolvedTarget.hasPrefix(resolvedBase) else { return base }
```

**평가**: **양호**. 이중 방어 구조가 적용되어 있습니다:
1. 입력 단계: `..`, `.`, null byte 제거
2. 검증 단계: 심볼릭 링크 해석 후 경로 비교

**`ProjectManager.swift`에도 동일한 `sanitizeName`이 있음**: 172-181행. 일관성 유지됨.

### 3.2 InboxScanner의 심볼릭 링크 방어

**파일**: `/Users/hwai/Developer/DotBrain/Sources/Services/FileSystem/InboxScanner.swift`

```swift
if isSymbolicLink(fullPath, fileManager: fm) {
    guard let resolved = try? fm.destinationOfSymbolicLink(atPath: fullPath),
          resolved.hasPrefix(pkmRoot) else {
        return nil
    }
}
```

#### [MEDIUM] SEC-003: TOCTOU Race Condition (Symlink)

| 항목 | 내용 |
|------|------|
| 심각도 | Medium |
| OWASP | A01 (Broken Access Control) |
| 위치 | `InboxScanner.swift:74-79` |

심볼릭 링크를 검사한 후 실제 파일을 처리하는 사이에 링크 대상이 변경될 수 있습니다
(Time-of-Check to Time-of-Use). 다만 로컬 단일 사용자 앱에서 이를 악용하려면
같은 기기에서 동시에 심볼릭 링크를 조작해야 하므로, 실질적 위험은 낮습니다.

**권장 조치**: 파일 처리 시점에 `O_NOFOLLOW` 플래그로 파일을 열거나,
처리 직전에 재검증하는 방어층 추가.

---

## 4. Input Validation & AI API Communication

### 4.1 파일 내용 -> AI API 전송

**파일들**: `NoteEnricher.swift`, `ContextLinker.swift`, `Classifier.swift`

```swift
// NoteEnricher.swift:29
let preview = String(body.prefix(maxContentLength))  // 5000자 제한

// FolderReorganizer.swift:483
return String(content.prefix(5000))  // 5000자 제한
```

**평가**: **양호**.
- 파일 내용을 AI API에 보내기 전 5000자로 절단
- AI API는 사용자 소유 데이터를 처리하므로, XSS/Injection 맥락이 아님
- AI 응답은 로컬 마크다운 파일에만 기록 (브라우저 렌더링 없음)

#### [LOW] SEC-004: AI 응답의 파일시스템 경로 주입 가능성

| 항목 | 내용 |
|------|------|
| 심각도 | Low |
| OWASP | A03 (Injection) |
| 위치 | 간접적 - AI 분류 결과가 폴더명으로 사용 |

AI가 반환하는 `targetFolder`나 `project` 이름이 `sanitizeFolderName()`과
`resolvedTarget.hasPrefix(resolvedBase)` 검증을 거치므로 실질적 위험은 차단됩니다.
현재 방어가 적절합니다.

---

## 5. File Permissions

### 5.1 암호화 키 파일

```swift
// KeychainService.swift:96-99
try FileManager.default.setAttributes(
    [.posixPermissions: 0o600],
    ofItemAtPath: storageURL.path
)
```

**평가**: **양호**. 소유자 전용 읽기/쓰기 (600).

### 5.2 일반 파일 쓰기

#### [MEDIUM] SEC-005: 생성되는 마크다운 파일에 퍼미션 미설정

| 항목 | 내용 |
|------|------|
| 심각도 | Medium |
| OWASP | A05 (Security Misconfiguration) |
| 위치 | 프로젝트 전반 (모든 `.write(toFile:)` 호출) |

마크다운 파일, 인덱스 노트, 템플릿 등을 생성할 때 별도 퍼미션 설정이 없습니다.
macOS 기본값(umask에 따라 보통 644)이 적용됩니다.

**실질적 위험**: 낮음. PKM 볼트의 마크다운 파일은 민감 데이터가 아닌 경우가 많고,
macOS의 기본 umask(022)로 생성되는 644 퍼미션은 로컬 단일 사용자 환경에서 적절합니다.
Obsidian 등 다른 앱에서도 읽어야 하므로 과도한 제한은 오히려 문제가 됩니다.

**판단**: 현재 상태 유지. API 키 파일에만 600 퍼미션이 적용된 것이 올바른 접근입니다.

---

## 6. install.sh 보안

**파일**: `/Users/hwai/Developer/DotBrain/install.sh`

#### [HIGH] SEC-006: curl | bash 패턴의 고유 위험

| 항목 | 내용 |
|------|------|
| 심각도 | High |
| OWASP | A08 (Software and Data Integrity Failures) |
| 위치 | `install.sh` (배포 방식) |

```bash
curl -sL https://raw.githubusercontent.com/DinN0000/DotBrain/main/install.sh | bash
```

**문제점**:
1. **바이너리 무결성 검증 없음**: 다운로드된 바이너리의 체크섬/서명 검증 없음
2. **Gatekeeper 우회**: `xattr -cr "$APP_PATH"` (121행)으로 quarantine 속성 제거
3. **GitHub API MITM**: 릴리즈 URL을 GitHub API JSON에서 추출 (grep + sed) --
   JSON 파싱이 아닌 텍스트 패턴 매칭이라 조작 가능성 있음

**권장 조치**:
```bash
# 릴리즈에 SHA256 체크섬 파일 포함
echo "다운로드 검증 중..."
EXPECTED_HASH=$(curl -sL "$HASH_URL")
ACTUAL_HASH=$(shasum -a 256 "$TMP_DIR/$APP_NAME" | awk '{print $1}')
if [ "$EXPECTED_HASH" != "$ACTUAL_HASH" ]; then
    echo "오류: 체크섬 불일치 — 다운로드가 변조되었을 수 있습니다."
    exit 1
fi
```

**현재 맥락**: 개인 프로젝트이고 GitHub HTTPS를 통해 배포되므로
실질적 공격 확률은 낮습니다. 다만 사용자 신뢰도를 높이기 위해 체크섬 검증 추가를 권장합니다.

---

## 7. ATS (App Transport Security) 설정

**파일**: `/Users/hwai/Developer/DotBrain/install.sh` (Info.plist 섹션)

```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <false/>
    <key>NSExceptionDomains</key>
    <dict>
        <key>api.anthropic.com</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <false/>
        </dict>
    </dict>
</dict>
```

#### [MEDIUM] SEC-007: Gemini API 도메인이 ATS 예외에 누락

| 항목 | 내용 |
|------|------|
| 심각도 | Medium |
| OWASP | A05 (Security Misconfiguration) |
| 위치 | `install.sh:101-116` (Info.plist 생성 부분) |

`generativelanguage.googleapis.com`이 ATS 예외 도메인에 등록되지 않았습니다.
`NSAllowsArbitraryLoads: false`이므로 ATS가 기본적으로 HTTPS를 강제하지만,
Anthropic만 명시적으로 선언된 상태입니다.

**실질적 영향**: macOS에서 HTTPS URL에 대한 URLSession 호출은 ATS 기본 정책으로도
정상 동작합니다. 기능적 문제는 없지만 명시적 선언이 바람직합니다.

**권장 조치**: `generativelanguage.googleapis.com`도 동일한 예외 설정 추가.

---

## 8. 추가 발견사항

### 8.1 Rate Limiter - 양호

**파일**: `/Users/hwai/Developer/DotBrain/Sources/Services/RateLimiter.swift`

- Provider별 적응형 스로틀링 구현
- 429 응답 시 지수 백오프 (최대 60초)
- 서버 에러 시 1.5배 백오프
- 연속 성공 시 점진적 가속 (최소 바닥값 존재)

API 과다 호출에 의한 계정 제한/비용 폭발 방어가 적절히 구현되어 있습니다.

### 8.2 에러 메시지 - 양호

에러 메시지에 내부 구현 상세 (스택 트레이스, 파일 경로 등)가 과도하게 노출되지 않습니다.
`InboxProcessor.friendlyErrorMessage()`로 사용자 친화적 메시지 변환이 적용되어 있습니다.

### 8.3 메모리 내 API 키 노출

#### [LOW] SEC-008: API 키가 Swift String으로 메모리에 존재

| 항목 | 내용 |
|------|------|
| 심각도 | Low |
| OWASP | A02 (Cryptographic Failures) |
| 위치 | `APIKeyInputView.swift:120`, `ClaudeAPIClient.swift:67` |

```swift
// APIKeyInputView.swift:120 - "눈" 토글 시 평문 키를 @State에 로드
if let key = provider == .claude ? KeychainService.getAPIKey() : KeychainService.getGeminiAPIKey() {
    keyInput.wrappedValue = key
}
```

API 키가 Swift String 객체로 메모리에 로드되며, ARC에 의한 해제 후에도
물리 메모리에 잔존할 수 있습니다.

**실질적 위험**: 매우 낮음. 메모리 덤프 공격은 이미 기기에 루트 접근이 필요하며,
그 경우 더 직접적인 공격 경로가 존재합니다. Swift에서 안전한 메모리 와이핑은
언어 수준에서 지원하지 않아 대응이 어렵습니다.

---

## 우선순위별 액션 플랜

### 즉시 (다음 릴리즈 전)

| ID | 조치 | 난이도 |
|----|------|--------|
| SEC-002 | Gemini API 키 URL 노출 인지 (Google API 제약) -- 최소한 디버그 로깅에서 URL 포함 여부 재확인 | 낮음 |
| SEC-006 | install.sh에 SHA256 체크섬 검증 추가 | 낮음 |

### 다음 스프린트

| ID | 조치 | 난이도 |
|----|------|--------|
| SEC-001 | SHA256 -> HKDF 키 파생 전환 (마이그레이션 로직 필요) | 중간 |
| SEC-007 | ATS 예외 도메인에 googleapis.com 추가 | 낮음 |

### 백로그

| ID | 조치 | 난이도 |
|----|------|--------|
| SEC-003 | Symlink TOCTOU 재검증 레이어 추가 | 중간 |
| SEC-004 | AI 응답 folder명 추가 검증 (현재도 방어됨, 강화 목적) | 낮음 |
| SEC-005 | 현재 상태 유지 (변경 불필요) | - |
| SEC-008 | 현재 상태 유지 (Swift 언어 제약) | - |

---

## 긍정적 보안 설계 요소

DotBrain 코드베이스에서 보안적으로 잘 설계된 부분:

1. **Path Traversal 이중 방어**: sanitize + resolve + hasPrefix 패턴
2. **암호화 파일 퍼미션 0o600**: API 키 저장 파일에 적절한 접근 제어
3. **Atomic Write**: 모든 파일 쓰기에 `atomically: true` 적용
4. **ATS 기본 차단**: `NSAllowsArbitraryLoads: false`
5. **Keychain 마이그레이션 후 삭제**: 레거시 항목 정리
6. **대용량 파일 경고**: 100MB 이상 파일 로깅
7. **Streaming Hash**: 대용량 바이너리 파일의 메모리 효율적 해시
8. **심볼릭 링크 검사**: InboxScanner에서 pkmRoot 외부 링크 차단
9. **코드 프로젝트 자동 건너뜀**: 소스코드 파일을 AI에 전송하지 않음
10. **Rate Limiter**: API 과다 호출 방어 및 비용 보호

---

*Security Architect Review by bkit-security-architect*
*Model: claude-opus-4-6 | Date: 2026-02-15*
