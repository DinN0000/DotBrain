# DotBrain 코드 리뷰 리포트

**일시**: 2026-02-16
**대상**: Sources/ 전체 (59개 Swift 파일, 13,140줄)
**검토 영역**: Pipeline/App, Services, UI, 보안, Models/Extraction

---

## 요약

| 심각도 | 건수 | 주요 패턴 |
|--------|------|-----------|
| Critical | 8 | TaskGroup 동시성 한도 위반, 메모리 미스트리밍, DispatchQueue 사용 |
| High | 18 | 경로 정규화 누락, MainActor 패턴 위반, 에러 핸들링 부재 |
| Medium | 28 | 파일 전체 로드, YAML 파싱 엣지케이스, UI 리렌더 비효율 |
| Low | 12 | 스타일 위반, 하드코딩, 접근성 |

---

## Critical 이슈

### 1. TaskGroup 동시성 한도 위반 (CLAUDE.md: max 3)
현재 `maxConcurrent = 10`으로 설정되어 있어 API rate limiting과 비용 초과 위험이 있습니다.

- `InboxProcessor.swift:49-86`
- `FolderReorganizer.swift:76-111`
- `VaultReorganizer.swift:82-121`

**수정**: `maxConcurrent = 3`으로 변경

### 2. DispatchQueue 사용 (CLAUDE.md: Task.detached만 허용)
GCD 패턴이 Swift Concurrency와 혼용되어 있습니다.

- `InboxWatchdog.swift:45` — `DispatchQueue.global(qos: .utility)`
- `InboxWatchdog.swift:80-81` — `DispatchSource.makeTimerSource`
- `InboxWatchdog.swift:101` — `DispatchQueue.main.asyncAfter`
- `AppDelegate.swift:25-26` — `DispatchQueue.main.asyncAfter`
- `StatisticsService.swift:8` — `DispatchQueue(label:)` serial queue

**수정**: `Task.detached(priority:)` + `Task.sleep(for:)` + `await MainActor.run` 패턴으로 전환

### 3. 파일 전체 메모리 로드 (CLAUDE.md: 1MB 청크 스트리밍 필수)
`String(contentsOfFile:)` / `Data(contentsOf:)` 사용이 39곳 이상 발견됩니다.

주요 위치:
- `FileContentExtractor.swift:17` — 텍스트 파일 전체 로드
- `InboxProcessor.swift:356` — 폴더 콘텐츠 추출
- `VaultSearcher.swift:39` — 마크다운 검색
- `FolderReorganizer.swift:356, 452` — SHA256 해싱
- `BinaryExtractor.swift:55` — 바이너리 추출
- `ProjectManager.swift:144, 195, 259, 278`

**수정**: `FileHandle` + 1MB 청크 읽기 패턴 적용

---

## High 이슈

### 4. Task.detached 미사용
`AppState.swift`에서 `Task { await refreshInboxCount() }`가 MainActor에서 암시적으로 실행됩니다.

- `AppState.swift:268-270`
- `AppState.swift:634-636`

### 5. onProgress 콜백 MainActor 마샬링 부재
백그라운드 스레드에서 호출될 수 있는 콜백이 명시적으로 MainActor로 전달되지 않습니다.

- `InboxProcessor.swift:180-185`
- `FolderReorganizer.swift:142-157`
- `VaultReorganizer.swift:134-137`

### 6. 경로 정규화 누락 (보안)
`resolvingSymlinksInPath()` 없이 경로를 구성하여 심링크 공격 가능성이 있습니다.

- `ProjectContextBuilder.swift:31, 130, 148, 185, 196`
- `InboxProcessor.swift:344`
- `VaultReorganizer.swift:260`
- `AICompanionService.swift:58-90` — 파일 쓰기 시 정규화 없음
- `ProjectManager.swift:143` — `.appending("/\(entry).md")` 직접 사용

### 7. AI 응답 검증 부족
- `Classifier.swift:192-204` — 잘못된 PARA 값이 조용히 무시됨 (`.resource`로 기본 대체)
- `FrontmatterWriter.swift:43-47` — AI가 반환한 프로젝트명/노트명이 위키링크에 그대로 삽입

### 8. YAML 파서 엣지케이스
- `Frontmatter.swift:71-145` (`parseYamlSimple`)
  - 따옴표 안의 콜론 미처리 (`key: "value: with colon"`)
  - 이스케이프된 따옴표 미지원
  - 블록 스칼라 (`|`, `>`) 미지원
  - 멀티라인 문자열 미지원

### 9. UI 스레드 안전성
- `DashboardView.swift:206-210` — `refreshStats()` MainActor 격리 없음
- `PARAManageView.swift:106` — `DispatchQueue.main.asyncAfter` 사용
- `SettingsView.swift:414-451` — URLSession 타임아웃 미설정 (네트워크 행 시 UI 멈춤)
- `DashboardView.swift:315-326` — TaskGroup 없이 병렬 폴더 분석

---

## Medium 이슈

### 10. UI 리렌더 비효율
- `DashboardView.swift:33-44` — PARA 카운트를 body에서 매번 재계산
- `PARAManageView.swift:178-195` — `analyses.filter` 렌더마다 실행
- `ResultsView.swift:47-92` — successCount/errorCount 매번 재계산
- `SearchView.swift:97-109` — `inboxFiles` 렌더마다 FileManager 재조회

### 11. 애니메이션 메모리 릭 위험
- `SettingsView.swift:420` — `.repeatForever` 애니메이션 cancel 없음
- `ProcessingView.swift:86-91, 111-116` — 중복 pulsing 애니메이션
- `InboxStatusView.swift:56-58` — onDisappear에서 애니메이션 미정지

### 12. 파일 I/O 레이스 컨디션
- `FolderReorganizer.swift:470-484` — TOCTOU: 파일 읽기와 쓰기 사이 변경 가능

### 13. 정규식 매번 컴파일
- `DOCXExtractor.swift:54, 61`
- `XLSXExtractor.swift:85, 91, 129, 146, 153`
- `PPTXExtractor.swift:70`

정적 프로퍼티로 캐싱 필요

### 14. PARACategory.fromPath() 오탐
- `PARACategory.swift:49-55` — `path.contains("/1_Project/")` 사용으로 `/my1_Project_folder/` 같은 경로도 매칭

### 15. StatisticsService API 비용 추적 누락
- `AIService`에서 AI 호출 후 `StatisticsService.addApiCost()` 미연결

### 16. Extractor 빈 파일/실패 처리 불일치
- PDF/DOCX: `text: nil` 반환
- Binary: 빈 문자열 반환
- Image: `success: true`로 반환 (실패인데도)

---

## Low 이슈

### 17. 코드 내 이모지 사용 (CLAUDE.md 위반)
- `ProjectContextBuilder.swift:86, 92, 98, 104`
- `OnboardingView.swift:198-227`

### 18. 한국어 로그 메시지 (CLAUDE.md: 코드/주석은 영어)
- `AIService.swift:131`
- `Classifier.swift:437-438`

### 19. 하드코딩된 값
- `AIService.swift:88` — 120초 타임아웃
- `NoteEnricher.swift:7` — maxContentLength = 5000
- `GeminiAPIClient.swift:100` — temperature: 0.7

### 20. 접근성 부재
- `DashboardView.swift:150-177` — VoiceOver 라벨 없음
- `ResultsView.swift:254-410` — 라디오 버튼 접근성 미구현
- `PARAManageView.swift:261-315` — 키보드 단축키 없음

---

## 긍정적 사항

- KeychainService: AES-GCM + HKDF 기반 암호화, 파일 퍼미션 0o600 적용
- Frontmatter.stringify(): YAML 태그 double-quote + escape 올바르게 구현
- FileMover.swift: SHA256 해싱에 1MB 청크 스트리밍 올바르게 적용
- PKMPathManager.sanitizeFolderName(): `..`, `.` 필터링 + 경로 정규화 적용
- 위키링크 `[[note]]` 패턴 전체적으로 올바르게 사용

---

## 우선 수정 권장 순서

1. **TaskGroup max 3 적용** (3곳) — API 비용 직결
2. **DispatchQueue 제거** (5곳) — 동시성 모델 통일
3. **파일 스트리밍 I/O 적용** (39곳) — OOM 방지
4. **경로 정규화 일관 적용** (7곳) — 보안
5. **AI 응답 검증 강화** — 위키링크 인젝션 방지
6. **UI 리렌더 최적화** — 사용자 체감 성능
