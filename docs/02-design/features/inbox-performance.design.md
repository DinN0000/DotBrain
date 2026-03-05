# Inbox Performance Optimization Design Document

> **Summary**: 인박스 파이프라인의 API 호출 구조 최적화를 통한 속도·분류 품질 동시 개선
>
> **Project**: DotBrain
> **Version**: 2.14.2
> **Author**: hwaa
> **Date**: 2026-03-05
> **Status**: Draft
> **Planning Doc**: [inbox-performance.plan.md](../01-plan/features/inbox-performance.plan.md)

---

## 1. Overview

### 1.1 Design Goals

1. Stage 2 에스컬레이션율 68% → 30% 이하로 감소 (비용·속도 절감)
2. Prompt Caching 활성화로 반복 시스템 프롬프트 토큰 90% 절감
3. 기존 프론트매터가 있는 파일의 불필요한 AI 호출 제거
4. SemanticLinker maxTokens 버그 수정으로 안정성 확보

### 1.2 Design Principles

- **Opt-in 방식**: 모든 새 파라미터는 기본값 nil/기존값으로 하위 호환 유지
- **최소 변경**: 기존 파이프라인 흐름을 변경하지 않고 파라미터/필드 추가만으로 구현
- **프로바이더 투명성**: Claude 전용 기능(Prompt Caching)이 Gemini/CLI에 영향 없음

---

## 2. Architecture

### 2.1 현재 파이프라인 흐름 (변경 없음)

```
_Inbox/ 파일 스캔
    ↓
FileContentExtractor.extract() — 5000자 전체 콘텐츠
FileContentExtractor.extractPreview() — 800자 → [FR-01] 2000자
    ↓
InboxProcessor — [FR-03] 프론트매터 사전 분류 분기 추가
    ↓
Classifier.classifyBatchStage1() — Haiku 배치 (5개, 동시 3)
    ↓ confidence < 0.8
Classifier.classifyStage2() — Sonnet 정밀 분류
    ↓
FileMover — 파일 이동 + 프론트매터 삽입
    ↓
SemanticLinker → LinkAIFilter.filterBatch() — [FR-04] maxTokens 8192
```

### 2.2 변경 포인트 (API 호출 경로)

```
[FR-02] system message 전달 경로:

Classifier.classifyBatchStage1()
    ↓ systemMessage 파라미터
AIService.sendMessage()
    ↓ systemMessage 파라미터
AIService.sendWithRetry()
    ↓ systemMessage 파라미터
AIService.sendDirect()
    ├── ClaudeAPIClient.sendMessage() → system 필드로 분리 (캐싱 대상)
    ├── GeminiAPIClient.sendMessage() → systemMessage 무시
    └── ClaudeCLIClient.sendMessage() → userMessage 앞에 합침
```

### 2.3 Dependencies

| 변경 | 의존 대상 | 비고 |
|------|-----------|------|
| FR-01 (preview 2000자) | 없음 | 독립 변경 |
| FR-02 (Prompt Caching) | ClaudeAPIClient → AIService → Classifier | 순차 의존 |
| FR-03 (사전 분류) | 없음 | 독립 변경 |
| FR-04 (maxTokens) | 없음 | 독립 변경 |

---

## 3. Detailed Design

### 3.1 FR-01: extractPreview 2000자 확대

**목적**: Stage 1에서 AI가 더 많은 맥락을 확보하여 분류 확신도 향상 → Stage 2 에스컬레이션 감소

**변경 파일 및 코드**:

#### `FileContentExtractor.swift:37`

```swift
// Before
static func extractPreview(from filePath: String, content: String, maxLength: Int = 800) -> String {

// After
static func extractPreview(from filePath: String, content: String, maxLength: Int = 2000) -> String {
```

#### `ClassifyResult.swift:48`

```swift
// Before
/// Condensed structural preview (800 chars) for Stage 1 batch classification

// After
/// Condensed structural preview (2000 chars) for Stage 1 batch classification
```

#### `Classifier.swift:236`

```swift
// Before
// Use condensed preview (800 chars) instead of full content (5000 chars) for Stage 1 triage

// After
// Use condensed preview (2000 chars) instead of full content (5000 chars) for Stage 1 triage
```

**토큰 영향 분석**:
- 기존: 800자 × 5파일 ≈ 2,800 토큰 (입력)
- 변경: 2000자 × 5파일 ≈ 7,000 토큰 (입력)
- Haiku 200K 컨텍스트 대비 3.5% — 안전 범위
- 비용 증가: 배치당 ~$0.001 (무시 가능)

---

### 3.2 FR-02: Prompt Caching 활성화

**목적**: 동일 시스템 프롬프트를 Anthropic 서버에 캐시하여 반복 입력 토큰 90% 절감

**Anthropic Prompt Caching 동작 원리**:
- `system` 필드에 `cache_control: {"type": "ephemeral"}` 지정
- 첫 호출 시 캐시 생성 (cache_creation_input_tokens 발생)
- 이후 5분 내 동일 시스템 프롬프트 호출 시 캐시 히트 (cache_read_input_tokens)
- 캐시 히트 시 해당 토큰은 입력 비용의 10%만 과금

**변경 파일 및 코드**:

#### `ClaudeAPIClient.swift` — MessageRequest 구조 변경

```swift
// line 23-33: MessageRequest에 system 필드 추가
struct MessageRequest: Encodable {
    let model: String
    let max_tokens: Int
    let temperature: Double
    let messages: [Message]
    let system: [SystemBlock]?  // NEW: Prompt Caching용

    struct Message: Encodable {
        let role: String
        let content: String
    }

    struct SystemBlock: Encodable {
        let type: String           // "text"
        let text: String
        let cache_control: CacheControl?

        struct CacheControl: Encodable {
            let type: String       // "ephemeral"
        }
    }
}
```

#### `ClaudeAPIClient.swift` — sendMessage 시그니처 변경

```swift
// line 71: systemMessage 파라미터 추가
func sendMessage(
    model: String,
    maxTokens: Int,
    userMessage: String,
    systemMessage: String? = nil  // NEW: nil이면 기존 동작
) async throws -> (String, TokenUsage?) {
    // ...

    let systemBlocks: [MessageRequest.SystemBlock]? = systemMessage.map { msg in
        [MessageRequest.SystemBlock(
            type: "text",
            text: msg,
            cache_control: .init(type: "ephemeral")
        )]
    }

    let request = MessageRequest(
        model: model,
        max_tokens: maxTokens,
        temperature: 0.1,
        messages: [.init(role: "user", content: userMessage)],
        system: systemBlocks  // nil이면 JSON에 미포함 (Encodable optional)
    )
    // ...
}
```

#### `ClaudeAPIClient.swift:6` — API 버전 업그레이드

```swift
// Before
private let apiVersion = "2023-06-01"

// After
private let apiVersion = "2023-06-01"
// Prompt Caching은 2023-06-01에서도 지원됨 (beta 헤더 불필요, GA 기능)
// 별도 버전 변경 불필요 — system 필드 + cache_control만 추가하면 동작
```

> **참고**: Anthropic Prompt Caching은 `2023-06-01` API 버전에서 GA로 지원됨.
> `anthropic-beta: prompt-caching-2024-07-31` 헤더가 필요했던 것은 beta 기간 한정.
> 현재는 `system` 필드에 `cache_control`을 포함하면 자동 활성화.

#### `AIService.swift` — 파라미터 전달 체인

```swift
// sendMessage (line 64)
func sendMessage(
    model: String,
    maxTokens: Int,
    userMessage: String,
    systemMessage: String? = nil  // NEW
) async throws -> (String, TokenUsage?) {
    try await sendWithRetry(
        provider: currentProvider,
        model: model,
        maxTokens: maxTokens,
        userMessage: userMessage,
        systemMessage: systemMessage  // NEW
    )
}

// sendWithRetry (line 77)
private func sendWithRetry(
    provider: AIProvider,
    model: String,
    maxTokens: Int,
    userMessage: String,
    systemMessage: String? = nil  // NEW
) async throws -> (String, TokenUsage?) {
    // ... 기존 로직 동일, sendDirect 호출 시 systemMessage 전달 ...
    let result = try await sendDirect(
        provider: provider,
        model: model,
        maxTokens: maxTokens,
        userMessage: userMessage,
        systemMessage: systemMessage  // NEW
    )
    // ... fallback 시에도 systemMessage 전달 ...
}

// sendDirect (line 149)
private func sendDirect(
    provider: AIProvider,
    model: String,
    maxTokens: Int,
    userMessage: String,
    systemMessage: String? = nil  // NEW
) async throws -> (String, TokenUsage?) {
    switch provider {
    case .claude:
        return try await claudeClient.sendMessage(
            model: model,
            maxTokens: maxTokens,
            userMessage: userMessage,
            systemMessage: systemMessage  // NEW: Claude만 system 필드 활용
        )
    case .gemini:
        return try await geminiClient.sendMessage(
            model: model,
            maxTokens: maxTokens,
            userMessage: userMessage
            // Gemini: systemMessage 무시 (파라미터 추가하지 않음)
        )
    case .claudeCLI:
        // CLI: systemMessage를 userMessage 앞에 합침
        let combined = systemMessage.map { $0 + "\n\n" + userMessage } ?? userMessage
        return try await claudeCLIClient.sendMessage(
            model: model,
            maxTokens: maxTokens,
            userMessage: combined
        )
    }
}

// sendFastWithUsage, sendPreciseWithUsage — systemMessage 전달 추가
func sendFastWithUsage(maxTokens: Int = 4096, message: String, systemMessage: String? = nil) async throws -> AIResponse {
    let (text, usage) = try await sendMessage(model: fastModel, maxTokens: maxTokens, userMessage: message, systemMessage: systemMessage)
    return AIResponse(text: text, usage: usage)
}

func sendPreciseWithUsage(maxTokens: Int = 2048, message: String, systemMessage: String? = nil) async throws -> AIResponse {
    let (text, usage) = try await sendMessage(model: preciseModel, maxTokens: maxTokens, userMessage: message, systemMessage: systemMessage)
    return AIResponse(text: text, usage: usage)
}
```

#### Classifier에서의 활용 (선택적, Phase 2 후반)

Classifier의 `buildStage1Prompt`/`buildStage2Prompt`에서 시스템 프롬프트(분류 규칙, 프로젝트 컨텍스트 등)를 `systemMessage`로 분리하면 캐시 효과 극대화. 단, 이 분리는 프롬프트 동작 변경 위험이 있으므로 **FR-02 인프라 구현 완료 후** 별도 진행.

**캐시 효과 예측 (22개 파일 기준)**:
- Stage 1 배치 5회: 시스템 프롬프트 ~2000 토큰 × 5회 → 첫 1회만 full, 나머지 4회 캐시 (8000 토큰 절감)
- Stage 2 15회: 시스템 프롬프트 ~2000 토큰 × 15회 → 첫 1회만 full, 나머지 14회 캐시 (28000 토큰 절감)
- **총 ~36000 토큰 절감** (전체 입력의 약 40%)

---

### 3.3 FR-03: 프론트매터 기반 사전 분류

**목적**: `para:` 필드가 이미 있는 파일은 AI 분류를 건너뛰어 API 호출 수 절감

**변경 파일 및 코드**:

#### `InboxProcessor.swift:114-125`

```swift
// 기존 분기: mediaInputs / textInputs
// 추가 분기: preClassifiedInputs (para: 필드가 있는 파일)

var mediaInputs: [ClassifyInput] = []
var textInputs: [ClassifyInput] = []
var preClassifiedInputs: [(input: ClassifyInput, para: String)] = []  // NEW

for input in inputs {
    let ext = URL(fileURLWithPath: input.filePath).pathExtension.lowercased()
    if mediaExtensions.contains(ext) {
        mediaInputs.append(input)
    } else if let existingPara = extractParaFromContent(input.content) {
        // 기존 프론트매터에 para: 필드가 있으면 AI 분류 스킵
        preClassifiedInputs.append((input: input, para: existingPara))
    } else {
        textInputs.append(input)
    }
}
```

#### `InboxProcessor` — 헬퍼 메서드 추가

```swift
/// 콘텐츠에서 기존 para: 필드값 추출
private func extractParaFromContent(_ content: String) -> String? {
    // 프론트매터 내 para: 필드 탐색
    guard content.hasPrefix("---") else { return nil }
    let lines = content.components(separatedBy: "\n")
    var inFrontmatter = false
    for line in lines {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed == "---" {
            if inFrontmatter { break }  // 프론트매터 끝
            inFrontmatter = true
            continue
        }
        if inFrontmatter && trimmed.hasPrefix("para:") {
            let value = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            let validValues = ["project", "area", "resource", "archive"]
            if validValues.contains(value) {
                return value
            }
        }
    }
    return nil
}
```

#### 사전 분류된 파일의 처리

사전 분류된 파일은 `ClassifyResult`를 직접 생성하여 기존 이동·링크 파이프라인에 합류:

```swift
// preClassifiedInputs → ClassifyResult 변환 (AI 호출 없음)
let preClassifiedResults: [ClassifyResult] = preClassifiedInputs.map { item in
    ClassifyResult(
        fileName: item.input.fileName,
        category: item.para,
        confidence: 1.0,  // 사용자가 직접 지정한 값이므로 최고 확신도
        tags: [],         // 기존 태그는 프론트매터에서 유지됨
        summary: "",      // FileMover가 기존 프론트매터 유지
        subfolder: nil,
        stage: "pre-classified"
    )
}
```

---

### 3.4 FR-04: LinkAIFilter maxTokens 명시

**목적**: `filterBatch`에서 maxTokens 미지정으로 4096 기본값이 사용되는 잠재적 버그 수정

**변경 파일 및 코드**:

#### `LinkAIFilter.swift:55`

```swift
// Before
let response = try await aiService.sendFastWithUsage(message: prompt)

// After
let response = try await aiService.sendFastWithUsage(maxTokens: 8192, message: prompt)
```

**근거**:
- `filterBatch`는 최대 5개 노트 × 15개 후보를 동시 처리
- 각 노트당 최대 5개 링크 응답 시 JSON 출력이 4096 토큰을 초과할 수 있음
- 8192는 실제 출력(~2000-4000 토큰)의 안전 마진 확보
- Haiku 200K 컨텍스트 대비 4% — 안전 범위

---

## 4. Error Handling

### 4.1 FR-02 오류 시나리오

| 시나리오 | 발생 조건 | 처리 방법 |
|---------|----------|----------|
| system 필드 미지원 API 버전 | 발생 불가 (GA 기능) | - |
| systemMessage nil | 기본 동작 (user message만 전송) | 자동 fallback |
| 캐시 미스 | TTL 만료 또는 프롬프트 변경 | 정상 동작, 비용만 full |
| Gemini에 systemMessage 전달 | 코드상 전달 안 함 | 무시 |

### 4.2 FR-03 오류 시나리오

| 시나리오 | 발생 조건 | 처리 방법 |
|---------|----------|----------|
| para: 값이 유효하지 않음 | "project" 등 4개 외 값 | extractParaFromContent가 nil 반환 → AI 분류로 진행 |
| 프론트매터 파싱 실패 | 잘못된 YAML | nil 반환 → AI 분류로 진행 |

---

## 5. Test Plan

### 5.1 테스트 범위

| 유형 | 대상 | 검증 방법 |
|------|------|----------|
| 빌드 검증 | 전체 프로젝트 | `swift build` 성공 |
| 기능 검증 | 인박스 처리 | 5개 이상 파일 처리 |
| 캐시 검증 | Prompt Caching | api-usage.json의 cachedTokens > 0 |
| 사전 분류 | FR-03 | para: 필드 있는 파일이 AI 스킵 확인 |
| 호환성 | 프로바이더 | Gemini/CLI 전환 후 정상 동작 |

### 5.2 테스트 케이스

- [ ] Happy path: 22개 혼합 파일 인박스 처리 완료
- [ ] FR-01: 2000자 프리뷰로 Stage 2 에스컬레이션율 측정
- [ ] FR-02: api-usage.json에서 cachedTokens > 0 확인
- [ ] FR-03: `para: resource` 프론트매터 파일이 "pre-classified" stage로 처리됨
- [ ] FR-04: 다수 후보(10+) 노트의 semantic-link 정상 완료
- [ ] Edge case: 프론트매터 없는 파일만 있을 때 기존 동작 동일
- [ ] Edge case: systemMessage nil로 Gemini 프로바이더 정상 동작

---

## 6. Implementation Guide

### 6.1 변경 파일 목록

```
Sources/
├── Services/
│   ├── Extraction/
│   │   └── FileContentExtractor.swift    [FR-01] line 37: maxLength 800→2000
│   ├── Claude/
│   │   ├── ClaudeAPIClient.swift         [FR-02] MessageRequest + sendMessage 변경
│   │   └── Classifier.swift              [FR-01] line 236: 주석 갱신
│   ├── SemanticLinker/
│   │   └── LinkAIFilter.swift            [FR-04] line 55: maxTokens 8192
│   └── AIService.swift                   [FR-02] 파라미터 체인 추가
├── Models/
│   └── ClassifyResult.swift              [FR-01] line 48: 주석 갱신
└── Pipeline/
    └── InboxProcessor.swift              [FR-03] 사전 분류 분기
```

### 6.2 Implementation Order

```
Phase 1 (독립 변경, 병렬 가능):
  1. [FR-01] FileContentExtractor.swift:37 — maxLength 800→2000
  2. [FR-01] ClassifyResult.swift:48 — 주석 갱신
  3. [FR-01] Classifier.swift:236 — 주석 갱신
  4. [FR-04] LinkAIFilter.swift:55 — maxTokens: 8192
  5. [FR-03] InboxProcessor.swift — 사전 분류 분기 + 헬퍼

Phase 2 (의존 체인, 순차):
  6. [FR-02a] ClaudeAPIClient.swift — SystemBlock 구조체 + system 필드
  7. [FR-02b] ClaudeAPIClient.swift — sendMessage에 systemMessage 파라미터
  8. [FR-02c] AIService.swift — sendMessage/sendWithRetry/sendDirect 파라미터 전달
  9. [FR-02d] AIService.swift — sendFastWithUsage/sendPreciseWithUsage 파라미터 전달

Phase 2 후반 (선택적):
  10. Classifier — 프롬프트 system/user 분리 (캐시 효과 극대화)
```

---

## 7. Convention Reference

### 7.1 Swift 코딩 규칙 (기존 프로젝트 준수)

| 항목 | 규칙 |
|------|------|
| 동시성 | Actor 기반 (AIService, Classifier, ClaudeAPIClient) |
| Optional 파라미터 | 기본값 nil로 하위 호환 유지 |
| Encodable optional | nil이면 JSON에 자동 미포함 |
| 네이밍 | camelCase (Swift 표준) |
| 에러 처리 | 기존 ClaudeAPIError enum 활용 |

### 7.2 API 호환 규칙

| 프로바이더 | systemMessage 처리 |
|-----------|-------------------|
| Claude API | `system` 필드로 분리, `cache_control` 포함 |
| Gemini API | 파라미터 추가하지 않음 (무시) |
| Claude CLI | `userMessage` 앞에 합쳐서 전달 |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-03-05 | Initial draft — Plan 문서 기반 상세 설계 | hwaa |
