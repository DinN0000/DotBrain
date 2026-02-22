# Design: activity-log-fix

> 볼트 점검 / 전체 재정리 스캔에서 누락된 활동 기록 추가

## References
- Plan: `docs/01-plan/features/activity-log-fix.plan.md`

## FR-01: runVaultCheck() 활동 기록

### Changes: `Sources/UI/DashboardView.swift`

`runVaultCheck()` 내부 3곳에 `StatisticsService.recordActivity()` 추가:

1. **시작** (Task.detached 진입 직후):
```swift
StatisticsService.recordActivity(
    fileName: "볼트 점검",
    category: "system",
    action: "started",
    detail: "오류 검사 · 메타데이터 보완 · MOC 갱신"
)
```

2. **완료** (refreshStats() 직전):
```swift
StatisticsService.recordActivity(
    fileName: "볼트 점검",
    category: "system",
    action: "completed",
    detail: "\(auditTotal)건 발견, \(repairCount)건 복구, \(enrichCount)개 보완"
)
```

3. **에러** — 현재 try/catch가 없으므로 불필요. 각 단계가 내부에서 에러를 처리함.

### 위치
- started: line ~344 (`Task.detached {` 바로 다음)
- completed: line ~395 (`await MainActor.run {` 직전)

## FR-02: VaultReorganizer.scan() 활동 기록

### Changes: `Sources/Pipeline/VaultReorganizer.swift`

`scan()` 메서드에 시작/완료 기록 추가:

1. **시작** (scan 메서드 초입):
```swift
StatisticsService.recordActivity(
    fileName: "전체 재정리",
    category: "system",
    action: "started",
    detail: "AI 위치 재분류 스캔"
)
```

2. **완료** (return 직전):
```swift
StatisticsService.recordActivity(
    fileName: "전체 재정리",
    category: "system",
    action: "completed",
    detail: "\(plan.count)개 파일 스캔 완료"
)
```

## Implementation Order

1. DashboardView.swift — FR-01 (2곳)
2. VaultReorganizer.swift — FR-02 (2곳)
3. Build verification (0 warnings)
