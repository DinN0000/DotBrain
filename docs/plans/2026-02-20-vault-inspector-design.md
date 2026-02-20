# Vault Inspector + AI Statistics 설계

2026-02-20

## 목표

기존 대시보드의 "볼트 점검"과 "AI 재분류" 기능을 **VaultInspectorView**로 통합하고, 실제 토큰 사용량 기반의 **AIStatisticsView**를 추가한다.

- `VaultReorganizeView` 제거 → `VaultInspectorView`로 대체
- hardcoded `addApiCost()` 호출 → 실제 토큰 기반 비용 추적으로 전환
- 대시보드 카드 레이아웃 유지: 수제 도구 2장 + AI 관리 2장

## Dashboard 카드 레이아웃

```
┌─────────────┐ ┌─────────────┐
│  PARA 관리   │ │   볼트 검색  │   ← 수제 도구 (기존 유지)
└─────────────┘ └─────────────┘
┌─────────────┐ ┌─────────────┐
│  볼트 점검   │ │  AI 통계    │   ← AI 관리 (신규 구성)
└─────────────┘ └─────────────┘
```

2+2 카드 구성을 유지. 기존 "AI 재분류" 카드는 "볼트 점검" 안에 흡수되고, "AI 통계" 카드가 새로 추가됨.

## VaultInspectorView

`Sources/UI/VaultInspectorView.swift`

### 화면 구성

3단계 계층 구조:

1. **Level 1 — 폴더 목록**: PARA 카테고리별 Level 1 폴더를 나열. ContentHashCache로 각 폴더의 변경 파일 수를 표시.
2. **Level 2 — 폴더 상세**: 선택된 폴더 내 파일 목록. FileStatus (unchanged/modified/new) 표시. FolderHealthAnalyzer 점수.
3. **재분류 실행**: VaultReorganizer를 `.folder(String)` scope로 호출하여 해당 폴더만 AI 재분류. 기존 VaultReorganizeView의 scan → select → execute 흐름을 그대로 유지.

### 기존 VaultReorganizeView와의 차이

| 항목 | VaultReorganizeView (제거) | VaultInspectorView (신규) |
|------|---------------------------|---------------------------|
| 진입점 | 대시보드에서 직접 진입 | 대시보드에서 직접 진입 |
| 범위 | 카테고리 전체 | 개별 폴더 단위 |
| 파일 변경 감지 | 없음 | ContentHashCache로 변경 상태 표시 |
| 볼트 점검 기능 | 별도 (DashboardView 내장) | 통합 |

## AIStatisticsView

`Sources/UI/AIStatisticsView.swift`

### 표시 내용

- **총 비용**: APIUsageLogger.totalCost()
- **Operation별 비용**: classify, enrich, moc, link-filter, move 등
- **최근 API 호출**: recentEntries(limit:)로 최근 N건 표시 (timestamp, operation, model, tokens, cost)

### 데이터 소스

APIUsageLogger actor에서 `.dotbrain/api-usage.json`을 읽어 표시. 기존 UserDefaults 기반의 `pkmApiCost` 누적값도 병행 표시.

## ContentHashCache

`Sources/Services/ContentHashCache.swift` — **actor**

### 설계 의도

볼트 내 파일의 SHA256 해시를 캐싱하여 마지막 점검 이후 변경된 파일을 빠르게 식별. VaultInspectorView에서 폴더별 변경 상태를 표시하는 데 사용.

### 저장

- 경로: `{pkmRoot}/.dotbrain/content-hashes.json`
- 형식: `[filePath: sha256Hash]` dictionary
- CryptoKit `SHA256` 사용

### FileStatus

- `.unchanged` — 캐시된 해시와 현재 해시 동일
- `.modified` — 캐시된 해시와 현재 해시 다름
- `.new` — 캐시에 해당 파일 없음

### 보안

경로 canonicalize (`URL.resolvingSymlinksInPath()`) 후 `hasPrefix` 검사로 path traversal 방지.

## APIUsageLogger

`Sources/Services/APIUsageLogger.swift` — **actor**

### 설계 의도

기존 hardcoded `StatisticsService.addApiCost(0.003)` 호출을 실제 토큰 기반 비용 계산으로 대체. 각 AI 호출에서 반환되는 `TokenUsage`를 사용하여 정확한 비용을 기록.

### 모델 가격표 (per 1M tokens)

| 모델 | Input | Output |
|------|-------|--------|
| Claude Haiku | $0.80 | $4.00 |
| Claude Sonnet | $3.00 | $15.00 |
| Gemini Flash | $0.15 | $0.60 |
| Gemini Pro | $1.25 | $5.00 |

### 비용 계산 흐름

```
AI 호출 (Classifier, NoteEnricher, MOCGenerator, LinkAIFilter, FileMover)
    │
    ▼
sendFastWithUsage() / sendPreciseWithUsage()
    │  → AIResponse { text, usage: TokenUsage? }
    ▼
StatisticsService.logTokenUsage(operation:model:usage:)
    │
    ├── APIUsageLogger.calculateCost(model:usage:) → 비용 계산
    ├── StatisticsService.addApiCost() → UserDefaults 누적
    └── APIUsageLogger.log() → .dotbrain/api-usage.json 기록
```

### 저장

- 경로: `{pkmRoot}/.dotbrain/api-usage.json`
- 형식: `[APIUsageEntry]` JSON 배열
- 각 entry: id, timestamp, operation, model, inputTokens, outputTokens, cachedTokens, cost

## 데이터 파일 요약

| 파일 | 용도 | 관리 서비스 |
|------|------|------------|
| `.dotbrain/content-hashes.json` | SHA256 파일 해시 캐시 | ContentHashCache |
| `.dotbrain/api-usage.json` | API 호출 내역 + 비용 | APIUsageLogger |

두 파일 모두 `.dotbrain/` 디렉토리에 저장. `.gitignore`에 이미 포함된 경로이므로 볼트 동기화에 영향 없음.
