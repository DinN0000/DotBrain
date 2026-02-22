# Plan: activity-log-fix

> 볼트 점검 등 일부 기능에서 "최근 활동" 기록이 누락되는 문제 수정

## 1. Problem Statement

**현상**: 볼트 점검 실행 후 "15건 발견, 211개 메타데이터 보완, 폴더 요약 갱신 완료"가 표시되지만, "최근 활동" 섹션은 "아직 활동 기록이 없습니다"로 나타남.

**원인**: `DashboardView.runVaultCheck()`가 4단계(Audit, Repair, Enrich, MOC Regenerate)를 실행하면서 `StatisticsService.recordActivity()`를 **한 번도 호출하지 않음**.

비교:
| 기능 | recordActivity 호출 | 상태 |
|------|---------------------|------|
| InboxProcessor | 시작 + 파일별 + 에러 + 완료 (4곳) | OK |
| FolderReorganizer | 시작 + 파일별 + 에러 + 완료 (5곳) | OK |
| VaultReorganizer.execute() | 파일별 + 에러 (2곳) | OK |
| **runVaultCheck()** | **0곳** | BUG |

## 2. Scope

### FR-01: 볼트 점검 활동 기록 추가
- `runVaultCheck()` 시작 시 "볼트 점검" started 기록
- 완료 시 결과 요약 포함한 completed 기록
- 에러 발생 시 error 기록

### FR-02: VaultReorganizer.scan() 활동 기록 추가
- 현재 execute()만 기록하고 scan() 단계는 기록 없음
- scan 시작/완료도 기록 추가

### Non-Goals
- VaultAuditor/NoteEnricher 내부 per-file 기록 (과도한 로깅 방지)
- UI 변경 없음 (기존 "최근 활동" UI 그대로 사용)

## 3. Affected Files

| File | Change |
|------|--------|
| `Sources/UI/DashboardView.swift` | runVaultCheck()에 recordActivity 3곳 추가 |
| `Sources/Pipeline/VaultReorganizer.swift` | scan()에 recordActivity 2곳 추가 |

## 4. Acceptance Criteria

- [ ] 볼트 점검 완료 후 "최근 활동"에 "볼트 점검" 항목 표시
- [ ] 활동 상세에 "N건 발견, N개 보완" 등 결과 요약 포함
- [ ] 전체 재정리 스캔 단계도 활동 기록에 남음
- [ ] 빌드 0 warnings

## 5. Risk

- Low: 단순 함수 호출 추가, 기존 로직 변경 없음
- UserDefaults 기반이라 대량 기록 시 성능 고려 불필요 (100건 제한 이미 있음)
