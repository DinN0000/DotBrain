# Inbox Performance Optimization Planning Document

> **Summary**: DotBrain 인박스 처리 파이프라인의 속도 및 분류 정확도 개선
>
> **Project**: DotBrain
> **Version**: 2.14.2
> **Author**: hwaa
> **Date**: 2026-03-05
> **Status**: Draft

---

## 1. Overview

### 1.1 Purpose

인박스에 파일을 처음 넣을 때 분류 속도와 정확도가 기대에 미치지 못함. API 호출 구조 최적화를 통해 속도와 분류 품질을 동시에 개선한다.

### 1.2 Background

현재 파이프라인 분석 (22개 파일 기준, 2026-02-23 데이터):

| 단계 | 모델 | 호출 수 | 소요시간 | 비고 |
|------|------|---------|----------|------|
| classify-stage1 | Haiku | 22회 | ~30초 | 배치 5, 동시 3 |
| classify-stage2 | Sonnet | 15회 | ~25초 | **68% 에스컬레이션** |
| summary (바이너리) | Haiku | 22회 | ~3분 | 순차 처리 |
| semantic-link | Haiku | 13회 | ~20초 | 배치 5, 동시 3 |
| **총합** | | **72회** | **~5분** | |

**핵심 병목:**
1. Stage 1 프리뷰가 800자로 짧아 AI가 충분한 맥락 확보 불가 → Stage 2 에스컬레이션 68%
2. Prompt Caching 미사용 — 매 호출마다 동일한 시스템 프롬프트 재전송
3. Stage 2(Sonnet)는 Haiku 대비 3배 비용, 속도도 느림

### 1.3 Related Documents

- 소스코드: `/Users/hwaa/Developer/DotBrain/Sources/`
- API 사용 로그: `.dotbrain/api-usage.json`
- CLAUDE.md: 분류 규칙 및 PARA 방법론

---

## 2. Scope

### 2.1 In Scope

- [x] FR-01: Stage 1 프리뷰 길이 800자 → 2000자 확대
- [x] FR-02: Anthropic Prompt Caching 활성화 (API 구조 변경)
- [x] FR-03: 기존 프론트매터 기반 사전 분류 (AI 호출 스킵)
- [x] FR-04: SemanticLinker maxTokens 명시 (기존 버그 수정)

### 2.2 Out of Scope

- 파일명 기반 사전 분류 (오분류 위험 높음, 효과 불명확)
- SemanticLinker 배치 크기 증가 (후보 수 무제한 문제 선행 해결 필요)
- Summary(바이너리 동반노트) 병렬화 (중복 아님, 복잡도 대비 효과 낮음)
- RateLimiter 슬롯 수 변경 (현재 3슬롯이 429 방지에 적절)

---

## 3. Requirements

### 3.1 Functional Requirements

| ID | Requirement | Priority | Status |
|----|-------------|----------|--------|
| FR-01 | `extractPreview` 기본값을 800→2000으로 변경, 관련 주석 3곳 갱신 | High | Pending |
| FR-02 | `ClaudeAPIClient.MessageRequest`에 `system` 필드 추가, `sendMessage`에 `systemMessage` 파라미터 추가, API 버전 업그레이드 | High | Pending |
| FR-03 | `InboxProcessor`에서 기존 프론트매터에 `para:`가 있는 파일은 AI 분류 스킵 | Medium | Pending |
| FR-04 | `LinkAIFilter.filterBatch`에 `maxTokens: 8192` 명시 (현재 미지정으로 4096 기본값 사용 중) | High | Pending |

### 3.2 Non-Functional Requirements

| Category | Criteria | Measurement Method |
|----------|----------|-------------------|
| Performance | Stage 2 에스컬레이션율 68% → 30% 이하 | api-usage.json 분석 |
| Performance | 캐시 히트 시 반복 입력 토큰 90% 절감 | cachedTokens 필드 확인 |
| Compatibility | Gemini/ClaudeCLI 프로바이더 동작 변경 없음 | 프로바이더 전환 테스트 |
| Stability | 기존 분류 정확도 저하 없음 | 동일 파일셋으로 비교 테스트 |

---

## 4. Success Criteria

### 4.1 Definition of Done

- [ ] FR-01~FR-04 구현 완료
- [ ] 기존 인박스 처리 동작에 regression 없음
- [ ] Gemini/ClaudeCLI 프로바이더 호환성 확인
- [ ] api-usage.json에 cachedTokens > 0 확인 (Prompt Caching 작동)

### 4.2 Quality Criteria

- [ ] Swift 빌드 성공 (컴파일 에러 없음)
- [ ] 테스트 파일 5개 이상으로 인박스 처리 검증
- [ ] Stage 2 에스컬레이션율 측정 및 기록

---

## 5. Risks and Mitigation

| Risk | Impact | Likelihood | Mitigation |
|------|--------|------------|------------|
| API 버전 업그레이드 시 비호환 | High | Low | 최신 GA 버전 사용, 롤백 가능하도록 기존 버전 주석 보존 |
| system/user 프롬프트 분리 시 모델 동작 변경 | Medium | Low | Stage 1/2 confidence 점수 모니터링 |
| 프리뷰 2000자로 늘렸는데도 Stage 2 에스컬레이션 감소 미미 | Medium | Medium | 프롬프트 규칙 개선과 병행 가능 |
| filterBatch maxTokens 8192 설정 시 비용 증가 | Low | Low | 출력 토큰은 실제 필요한 만큼만 사용됨 |

---

## 6. Architecture Considerations

### 6.1 변경 대상 파일

| 파일 | 변경 내용 | 복잡도 |
|------|---------|--------|
| `FileContentExtractor.swift:37` | maxLength 기본값 800→2000 | Low |
| `ClassifyResult.swift:48` | 주석 갱신 | Low |
| `Classifier.swift:236` | 주석 갱신 | Low |
| `ClaudeAPIClient.swift` | MessageRequest에 system 필드, sendMessage 시그니처 변경, API 버전 | Medium |
| `AIService.swift` | sendMessage/sendWithRetry/sendDirect에 systemMessage 파라미터 전달 | Medium |
| `InboxProcessor.swift:113-125` | 프론트매터 사전 분류 분기 추가 | Medium |
| `LinkAIFilter.swift:55` | maxTokens: 8192 명시 | Low |

### 6.2 변경하지 않는 파일

| 파일 | 이유 |
|------|------|
| `RateLimiter.swift` | 현재 3슬롯/500ms가 429 방지에 적절 |
| `SemanticLinker.swift` | batchSize 5 유지 (후보 수 제한 없이 증가하면 위험) |
| `GeminiAPIClient.swift` | systemMessage 파라미터 무시, 인터페이스 불변 |
| `ClaudeCLIClient.swift` | systemMessage를 userMessage 앞에 합쳐서 전달 |
| `FileMover.swift` | summary 오퍼레이션은 바이너리 동반노트용으로 중복 아님 |
| `NoteEnricher.swift` | 프롬프트 분리는 Phase 2에서 진행 |

### 6.3 구현 순서 (의존성 기반)

```
Phase 1 (독립 변경, 병렬 가능):
  FR-01: extractPreview 2000자 ─┐
  FR-04: filterBatch maxTokens ──┤── 서로 의존성 없음
  FR-03: 프론트매터 사전 분류 ───┘

Phase 2 (의존 체인):
  FR-02a: ClaudeAPIClient MessageRequest 구조 변경
    ↓
  FR-02b: AIService 파라미터 전달
    ↓
  FR-02c: Classifier 프롬프트 system/user 분리 (선택적)
```

---

## 7. Convention Prerequisites

### 7.1 Swift 코딩 규칙 (기존 프로젝트 준수)

- Actor 기반 동시성 (AIService, Classifier, RateLimiter)
- Optional 파라미터에 기본값 nil 사용 (하위 호환)
- Encodable 구조체에서 optional 필드는 JSON에 자동 미포함

### 7.2 API 호환 규칙

- Anthropic API: `system` 필드가 nil이면 기존 동작 (user message만 전송)
- Gemini/CLI: systemMessage 파라미터 무시 또는 userMessage에 합침
- 모든 변경은 기본값으로 기존 동작 유지 (opt-in 방식)

---

## 8. Next Steps

1. [ ] Design 문서 작성 (`inbox-performance.design.md`)
2. [ ] Phase 1 변경 구현 (FR-01, FR-03, FR-04)
3. [ ] Phase 2 변경 구현 (FR-02)
4. [ ] 테스트 및 검증

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-03-05 | Initial draft — 5개 에이전트 동시 검토 결과 반영 | hwaa |
