# Changelog

## v2.1.10 — 10-Agent Deep Review Round 3 (2026-02-19)
- 10개 전문 에이전트 심층 코드 리뷰 (동시성, 메모리, 에러경로, 경로안전, UI상태, 파일작업, CLAUDE.md 준수, 수치정확성, API계약, 데드코드)
- AppState: isProcessing defer 패턴으로 전환 (3개 메서드) — 취소 시 UI 멈춤 방지
- AppState: hasPrefix 경로 검증 트레일링 슬래시 추가 (경로 조작 방어)
- ResultsView: NSCursor.pop() 5개 컴포넌트 onDisappear 처리 (커서 스택 누수 방지)
- ResultsView: isConfirming 3곳 비동기 완료 후 리셋 (버튼 비활성 해제)
- VaultReorganizeView/DashboardView: 취소 시 상태 리셋 보장
- OnboardingView: isPathSafe 가드 + .. 필터 + 에러 로깅
- FolderReorganizer: isPathSafe 가드 + try? 3곳 do/catch+NSLog 전환
- VaultAuditor: try? 4곳 do/catch+NSLog + 정확한 카운트 로직
- PARAMover/ProjectManager: WikiLink 쓰기 실패 로깅 + 카운트 정확성
- 데드코드 제거: listFolders, listProjects, renameProject, companionMdPath
- 14개 파일, 25건 수정, 0 warnings

## v2.1.9 — 10-Agent Defensive Fixes (2026-02-19)
- 10개 병렬 에이전트 코드 리뷰 후 7건 방어적 수정 (비즈니스 로직 무변경)
- FileMover: source==dest 가드 추가 (재분류 시 데이터 손실 방지)
- DashboardView: Task.detached priority: .utility 추가
- PPTXExtractor: _metadataRegexCache var→let (data race 수정)
- FileContentExtractor: force-unwrap → guard let (크래시 방지)
- AppState: 배치 재정리 취소 가드 추가
- XLSXExtractor: 음수 인덱스 가드 추가
- VaultReorganizer: zip() 패턴으로 배열 범위 안전성 강화

## v2.1.8 — UI 폴리싱 (2026-02-19)
- 하단 탭바: 텍스트 라벨 제거, 아이콘만 표시 (18pt)
- 인박스 텍스트 이모티콘: 48pt로 확대, 중앙 플로팅 배치
- 인박스 통합 레이아웃: 빈/파일/드래그 세 상태에서 얼굴+콘텐츠 위치 고정
- 인박스 파일 리스트: 라운드 행 배경, 파일 사이즈 표시, 피드백 pill 스타일
- 인박스 드래그: 대시 테두리 + accent 배경 틴트
- 표정 변화: `·_·` (빈) → `·‿·` (파일) → `·o·` (드래그)

## v2.1.1 — 11-Agent Code Review Fixes (2026-02-19)
- 11개 병렬 에이전트 코드 리뷰 후 의도 기반 재검토, 15건 실제 버그 수정
- Data Safety: OnboardingView 프로젝트 삭제 시 trashItem 사용, AICompanionService marker 검색 범위 제한, PARAMover 에셋 이동 에러 핸들링
- Logic: RateLimiter backoff 초기화, Classifier Stage2 confidence fallback 0.0, AIService fallback 에러 로깅, ProjectManager isPathSafe 에러 타입 수정, FolderReorganizer 실패 카운트 전달, VaultReorganizer source MOC 갱신
- Security: PPTXExtractor ZIP 압축 해제 4MB 제한, KeychainService migrationDone NSLock 보호
- Convention: 코드 내 이모지 제거 (SF Symbols 전환), ContextLinker progress 이중 카운트 수정, flattenFolder _Assets/ 스킵

## v2.1.0 — 스마트 에셋 관리 (2026-02-19)
- 중앙 집중형 `_Assets/{documents,images}/` 구조로 전환
- 이미지 파일은 companion .md 생성 생략 (EXIF 데이터만으로는 노트 가치 없음)
- PKMPathManager: 확장자 기반 에셋 라우팅 (`assetsDirectory(for:)`)
- FileMover: 이미지는 `_Assets/images/`로, 문서는 `_Assets/documents/`로 분리
- FrontmatterWriter: 위키링크 `![[_Assets/documents/파일]]` 형식으로 변경
- AssetMigrator: 기존 볼트 자동 마이그레이션 (산재된 _Assets/ 통합, 이미지 companion 정리, 인덱스 노트 정리)
- PARAMover: 폴더 병합 시 에셋을 중앙으로 라우팅
- ProjectManager: 프로젝트별 _Assets/ 생성 제거

## v2.0.7 — PARA 색상 통일 (2026-02-19)
- PARACategory.color 중앙 프로퍼티 추가 (전체 앱 색상 한 곳에서 관리)
- Area 색상 불일치 수정 (PARAManageView .purple → .green 통일)
- Dashboard 상단 PARA 레이블 컴팩트 복원 (P A R A)
- SearchView, DashboardView 하드코딩 색상 → .color 참조로 전환

## v2.0.6 — 코드 품질 대폭 개선 (2026-02-19)
- 26개 파일 전면 리뷰 및 수정 (Critical 8, Important 14, Security 3, Bloat 6)
- print() → NSLog() 전환 (27개소), 사용자 에러 메시지 한국어 통일
- YAML injection 방지 (Frontmatter created 필드 이스케이프)
- sanitizeName 백슬래시 제거, 폴더 선택 심링크 해결
- RateLimiter actor 경합 조건 수정 (suspension 전 시간 기록)
- PARAManageView 에러/성공 색상 구분, InboxStatusView 캐시 갱신
- Gemini 온도 0.1로 조정 (JSON 출력 안정성)
- NoteEnricher 에러 로깅 추가, 데드 코드 정리
- removeItem → trashItem 전환 (데이터 안전)
- Classifier 이모지 → 텍스트 가중치 표기

## v2.0.5 — 인앱 업데이트 API 호출 제거 (2026-02-19)
- install.sh에 TAG 인자 전달 모드 추가 (API 호출 완전 생략)
- 앱에서 이미 알고 있는 버전 정보를 install.sh에 직접 전달
- 터미널 설치 시에만 API 호출 (기존 동작 유지)

## v2.0.4 — 인앱 업데이트 안정화 (2026-02-19)
- install.sh GitHub API 호출 3회 → 1회로 축소 (rate limit 방지)
- grep 파이프라인 pipefail 내성 강화
- 설정 액션 버튼 하단 배치, 업데이트 버튼에 대상 버전 표시

## v2.0.3 — 설정 액션 버튼 하단 배치 (2026-02-19)
- 헤더는 상태만 표시, 액션 버튼(전환/업데이트)은 섹션 하단으로 이동
- 업데이트 버튼에 대상 버전 표시 (예: "v2.0.3 업데이트")

## v2.0.2 — AI 설정 전환 버튼 헤더로 이동 (2026-02-19)
- "전환" 버튼을 헤더 우측으로 이동 (앱 정보의 "업데이트"와 동일 패턴)
- 키 관리 행에서 전환 버튼 분리, 3개 섹션 헤더 패턴 통일
- 키 없는 프로바이더 탭 시 "키 필요" 상태 표시

## v2.0.1 — 전환 버튼 같은 행으로 이동 (2026-02-19)
- "전환" 버튼을 API 키 변경/삭제와 같은 행 우측에 배치

## v2.0.0 — AI 설정 UX 개편 + 업데이트 안정화 (2026-02-19)
- 탭을 조회 전용으로 분리 (탭 전환 ≠ 프로바이더 변경)
- 활성 프로바이더에 초록 점 표시, 헤더에 "Claude 사용 중" 등 표시
- 명시적 "전환" 버튼으로 프로바이더 변경 (키 등록된 경우만)
- 모델/비용 정보가 보고 있는 프로바이더 기준으로 표시
- install.sh에서 launchctl bootout을 pkill 전에 실행 (이중 아이콘 방지)

## v1.9.9 — AI 설정 섹션 개선 (2026-02-19)
- 키 등록 시 인풋 숨기고 "API 키 변경" 버튼만 표시
- 헤더에 "키 등록됨" 상태 인라인 표시
- 모델 파이프라인 + 비용 정보 한 줄로 합침
- 다른 프로바이더 중복 상태 텍스트 제거

## v1.9.8 — 업데이트 버튼 간결화 (2026-02-19)
- 헤더에서 중복 버전명 제거, 업데이트 버튼 텍스트만 표시

## v1.9.7 — 업데이트 버튼 축소 + 재실행 보장 (2026-02-19)
- 업데이트 버튼을 헤더 인라인 mini 크기로 변경
- 업데이트 후 앱 자동 재실행 fallback 추가

## v1.9.6 — 설정 하단 레이아웃 정리 (2026-02-18)
- GitHub 버튼을 하단 footer로 이동 (도움말 옆)
- 앱 정보 섹션에 버전명 표시

## v1.9.5 — 설정 레이아웃 간결화 (2026-02-18)
- PKM 폴더 헤더에 PARA 상태 인라인 표시
- 앱 정보 헤더에 버전 + 업데이트 상태 인라인 표시

## v1.9.4 — 인앱 업데이트 후 자동 재실행 (2026-02-18)
- 업데이트 버튼 클릭 시 앱 종료 후 자동 재설치 + 재실행되도록 수정

## v1.9.3 — 도움말 인앱 표시 + 외부 링크 수정 (2026-02-18)
- 도움말을 인앱 팝오버로 변경 (사용법 + PARA 설명 + GitHub 링크)
- 외부 링크(GitHub 등) 클릭 시 팝오버에 씹히던 문제 수정

## v1.9.2 — 인앱 업데이트 수정 (2026-02-18)
- 설정 > 업데이트 버튼이 실제로 동작하도록 수정 (detach 실행 후 앱 종료)

## v1.9.1 — 검색 결과 PARA 아이콘 범례 (2026-02-18)
- 검색 결과 상단에 PARA 카테고리별 아이콘 범례 표시

## v1.9.0 — 인박스 비우기 (2026-02-18)
- 인박스 전체 비우기 버튼 추가 (휴지통으로 이동, 복구 가능)

## v1.8.9 — 인박스 파일 선택 + 온보딩 힌트 개선 (2026-02-18)
- 인박스에서 Finder 파일 선택으로 파일 추가 가능 (드래그 외 대안)
- 빈 인박스: "파일 선택" 버튼, 파일 있을 때: + 버튼
- 온보딩 프로젝트 등록 힌트 텍스트 명확화

## v1.8.8 — 볼트 변경 시 재온보딩 (2026-02-18)
- 새 폴더 선택 시 온보딩 플로우 자동 시작 (PARA 구조 설명 + 프로젝트 등록)
- 설정/인박스 양쪽에서 볼트 변경 시 동일하게 동작
- API 키 이미 설정된 경우 온보딩 3단계(API 키) 자동 건너뜀
- 재온보딩 시 완료 화면 텍스트 구분 ("볼트 설정 완료")
- 인박스 빈 상태/활성 상태 이모티콘 UI 개선

## v1.8.7 — 폴더 관리 안정성 + 보안 강화 (2026-02-18)
- 폴더 관리 화면 멈춤 근본 수정: Task.detached + TaskGroup 병렬 스캔 + 취소 지원
- 폴더 이름 변경 기능 추가 (프론트매터 + WikiLink 일괄 갱신)
- MOC 갱신을 백그라운드 스레드로 이동 (메인 스레드 차단 제거)
- 이름 변경/병합 후 카테고리 루트 MOC 자동 갱신
- WikiLink 완료 표시(markInVault) 노트 손상 버그 수정
- 병합 시 소스 폴더 완전 삭제 (인덱스 노트 잔존 해결)
- 이름 변경 시 인덱스 노트 처리 순서 수정 (enumerator 안정성)
- 재활성화 시 충돌 검사를 프론트매터 수정 전으로 이동
- 폴더 생성 입력값 검증 강화 (경로 탐색 방지)
- PARAMover/ProjectManager 전체 함수에 isPathSafe 검증 추가
- Finder 열기 시 resolvingSymlinksInPath 적용
- clearStatusAfterDelay 타이머 경쟁 조건 수정
- Frontmatter file.format YAML 인젝션 방어

## v1.8.6 — UX 개선 + Project Folder Protection (2026-02-18)
- 대시보드 섹션 라벨: "수제 도구" / "AI 관리" + 역할 설명 추가
- "전체 재정리" → "AI 재분류"로 기능명 변경
- 대시보드 카드 높이 축소
- 스캔 결과: 목적지 기준 그룹핑, AI 요약 표시, 출발/도착 풀 경로
- 폴더 건강도 "세분화 필요" 기준 20개 → 40개로 완화
- 재정리 시 새 프로젝트 폴더 자동 생성 방지
- 기존 프로젝트 매칭 시 targetFolder 보정 → 불필요한 이동 제안 제거
- 인박스에서 PKM 경로 클릭으로 볼트 폴더 변경 가능
- 폴더 관리: 모든 PARA 카테고리에서 폴더 생성 가능 (헤더 클릭)
- PARA 카테고리 헤더 hover 피드백 추가
- 폴더 관리 화면 반복 진입 시 로딩 멈춤 버그 수정
- 동작하지 않던 Cmd+V 붙여넣기 안내 및 코드 제거
- 메뉴바 아이콘 크기 안정화

## v1.8.5 — Vault Check Accuracy (2026-02-18)
- 볼트 점검 결과 상세 표시 (깨진 링크/프론트매터 누락/PARA 미분류 구분)
- enrichCount 실제 보완 건수만 집계 (전체 파일 수 → 변경된 파일만)
- 깨진 링크 자동 복구: suggestion 없는 링크는 일반 텍스트로 변환
- auditTotal에서 태그 누락 제외 (NoteEnricher가 처리하는 영역)

## v1.8.4 — Activity Log Fix (2026-02-18)
- 볼트 점검 완료 후 "최근 활동"에 기록되지 않던 버그 수정
- 전체 재정리 스캔 단계 활동 기록 추가
- MOCGenerator 디버그 로그 print() -> NSLog() 전환

## v1.8.3 — MOC Lifecycle (2026-02-18)
- VaultReorganizer 파일 이동 후 MOC 자동 갱신 추가
- 루트 MOC 태그 누락 진단 로그 추가 (generateCategoryRootMOC)
- 비용 추정 $0.005/파일로 전 파이프라인 통일

## v1.8.2 — Pipeline Optimization (2026-02-18)
- Area 옵션 분류 추가 (Project/Resource/Archive 외)
- Stage 1 전체 콘텐츠 기반 분류로 정확도 향상
- MOC 기반 컨텍스트 빌드 최적화

## v1.8.1 — 레포 루트 정리 (2026-02-18)
- CODE_REVIEW 파일 루트에서 제거
- docs/ 디렉토리 gitignore 처리 (GitHub 레포 페이지 정리)

## v1.8.0 — 품질 개선 + 보안 강화 + 성능 최적화 (2026-02-16)
- 스마트 콘텐츠 추출로 AI 분류 품질 향상 (FileContentExtractor 전면 개선)
- 경로 탐색 방지 강화 (canonicalize + hasPrefix), YAML 인젝션 방어
- 정규식 캐싱, actor 마이그레이션, 동시성 튜닝 (DOCXExtractor, XLSXExtractor, PPTXExtractor 등)
- SwiftUI 불필요 리렌더 방지, 애니메이션 메모리 릭 수정
- InboxWatchdog deinit actor isolation 에러 수정

## v1.7.8 — 문서 정비 + vault-audit 에이전트 (2026-02-16)
- 볼트 감사 에이전트 (vault-audit-agent) 추가
- 프론트매터 검증, MOC 무결성 검사 스킬 추가
- MIT 라이선스, CONTRIBUTING, SECURITY, Issue/PR 템플릿 추가
- README 배지, GitHub 설명/토픽 설정
- 아키텍처 문서 v1.7.7 기준 갱신, docs 구조 정리
- README API 키 저장 방식 설명 수정 (Keychain → AES-GCM)

## v1.7.7 — 성능 최적화 + UX 피드백 개선 (2026-02-15)
- 파일 추출 TaskGroup 동시성 최대 10개 제한 (메모리 폭증 방지)
- AI 재시도 120초 타임아웃 추가 (무한 대기 방지)
- confidence >= 0.9 파일은 ContextLinker 스킵 (불필요한 API 호출 제거)
- AI 분류 배치 진행 실시간 표시 ("배치 N/M 분류 중...")
- 볼트 점검 시 MOC 갱신 폴더 수 표시

## v1.7.6 — 색 체계 규칙화 (2026-02-15)
- PARA 색상(파랑/초록/주황/회색)은 stat 버튼에만 사용
- 카드/버튼/링크는 accentColor, 정보성 아이콘은 secondary로 통일
- 프로바이더별 브랜드 색 제거
- 활동 색상 단순화: 초록=성공, 빨강=오류, secondary=중립

## v1.7.5 — UI 색상 톤다운 (2026-02-15)
- 대시보드/설정 레인보우 색상 제거, 모노크롬 톤으로 통일
- 인터랙티브 요소만 시스템 accent 유지

## v1.7.4 — 업데이트 확인 인터랙션 개선 (2026-02-15)
- 업데이트 확인 버튼 회전 애니메이션 + 호버 하이라이트

## v1.7.3 — 업데이트 확인 + 버전 표시 수정 (2026-02-15)
- 설정에서 업데이트 확인/설치 기능 추가
- 설치 시 GitHub 태그에서 실제 버전을 Info.plist에 반영
- 대시보드 최근 활동 화면 전환 시 즉시 갱신

## v1.7.2 — 최근 활동 개선 (2026-02-15)
- 처리 시작/완료/에러 이벤트 기록 추가, 대상 경로 포함
- 활동 클릭 시 아코디언 상세 패널, 표시 항목 5→10개
- 액션별 아이콘/색상 세분화

## v1.7.1 — 처리 진행률 UX 개선 (2026-02-15)
- AI 분류 단계 "0/62" 멈춤 해결 — 단계별 진행 표시
- AI 분류: 펄스 애니메이션 + 배치 진행 텍스트
- 파일 정리: N/62 카운터 (실제 이동 단계에서만)
- 확신도 90% 이상 파일 컨텍스트 링킹 스킵

## v1.7.0 — 대시보드 + PARA 관리 통합 (2026-02-15)
- ProjectManageView + ReorganizeView → PARAManageView로 통합 (11→9 화면)
- 대시보드 4카드 → 3카드 (폴더 관리/검색/볼트 관리)
- PARA 숫자 탭 시 해당 카테고리로 이동, 건강 요약 표시
- 폴더 건강도 표시 (빨간점/주황점), 완료/재활성화, 삭제, 병합 기능

## v1.6.0 — UX 전면 개선 (2026-02-15)
- 온보딩 재설계 (4→5단계): Before/After 비교, PARA 일상 비유, 프로젝트 안내, API 연결, 빠른 시작
- 하단 3탭 네비게이션 + Breadcrumb
- 대시보드 허브화: 통계 요약 + 진입 카드
- 인박스 썸네일 + 예상 시간, 처리 중 파일 카운터, 결과 용어 사용자 친화적으로 변경

## v1.5.8 — UX 개선 (2026-02-15)
- 온보딩 5단계 리디자인 (전후 비교, PARA 설명, 프로젝트 가이드)
- Breadcrumb 네비게이션, 하단 3탭 간소화
- 처리 화면 파일 카운터 + 현재 파일명 표시

## v1.5.7 — 보안 강화 + 버그 수정 (2026-02-15)
- Gemini API 키 URL → 헤더 전송으로 변경
- HKDF 키 유도 도입 + 기존 키 자동 마이그레이션
- install.sh SHA256 체크섬 검증
- RateLimiter overflow, 대용량 파일 중복검사, StatisticsService 스레드 안전성 수정
- FileContentExtractor, PARACategory.fromPath() 공통 추출

## v1.5.6 — Settings UI Redesign (2026-02-15)
- 설정 화면 카드 기반 섹션으로 전면 개편
- AI 제공자 라디오 카드 선택, 앱 정보 섹션 추가
- 불필요한 "앱 종료" 버튼 제거

## v1.5.5 — AI Summary for Binary Files (2026-02-15)
- 바이너리 파일 처리 시 AI 요약 동반 노트 생성
- 원본 파일 링크 자동 삽입, 추출 텍스트 50,000자로 확장
- 동반 노트에도 관련 노트 위키링크 삽입

## v1.5.4 — PARA 이동 에이전트 (2026-02-14)
- AI 파일/폴더 이동 시 프론트매터, MOC, 카운트 자동 갱신하는 전용 에이전트
- CLAUDE.md에 7단계 이동 체크리스트 추가
- AICompanionService version 8 → 9

## v1.5.3 — 대시보드 인라인 피드백 (2026-02-14)
- 대시보드 기능 버튼 아래 진행 상황 + 결과 인라인 표시
- PARA 카테고리 루트 인덱스 노트 자동 생성

## v1.2.2 — 컴패니언 파일 v5 업데이트 (2026-02-14)
- AI 컴패니언 파일을 실제 앱 동작에 맞게 전면 업데이트
- 폴더 정리(Reorganize) 워크플로, 2단계 AI 분류, AI 시맨틱 링크, 볼트 감사 등 문서화
- 관련 노트 링크 규칙 수정 (태그 오버랩 → AI 시맨틱 분석)
- DOCX 지원 반영, 코드 파일 경고 수정

## v1.2.1 — 폴더 정리 자동 이동 (2026-02-14)
- 폴더 정리 시 잘못 분류된 파일을 사용자 확인 없이 자동 이동
- 결과 화면에 `원래 위치 → 새 위치` 보라색 표시
- 이동된 폴더의 MOC 자동 갱신

## v1.2.0 — 폴더 중첩 버그 수정 + 맥락 기반 관련 노트 링크 (2026-02-14)
- AI가 PARA 카테고리명을 경로에 포함시켜 중첩 폴더가 생성되던 버그 수정
- `stripParaPrefix()` 3단계 정제 로직 추가
- 태그 매칭 기반 관련 노트 → MOC 기반 VaultContextMap + AI 시맨틱 링크로 전환
- 다른 폴더/카테고리 간 크로스 링크 지원

## v1.1.5 — 온보딩 UX 전면 개선 (2026-02-14)
- 온보딩 5단계 → 4단계로 축소
- 폴더 생성 실패 에러 알림, 프로젝트 이름 유효성 검사
- PKM 폴더 삭제 감지 → 설정 화면 자동 이동
- InboxWatchdog 재시도 메커니즘 (최대 3회)
- 설정에 AI 제공자 전환 Picker, 도움말 버튼 추가

## v1.1.4 — 온보딩 전 폴더 생성 방지 + 메뉴바 아이콘 정렬 (2026-02-13)
- 온보딩 완료 전 `~/Documents/DotBrain/` 조기 생성 방지
- 메뉴바 아이콘 수직 정렬 수정

## v1.1.3 — API 키 마스킹 토글 수정 (2026-02-13)
- 눈 아이콘 토글 시 실제 키를 가져와 표시/숨김 정상 동작

## v1.1.2 — PKM 루트 경로 DotBrain 복원 (2026-02-13)
- v1.1.1에서 바이너리가 `PKM-DotBrain`으로 빌드되던 문제 수정

## v1.1.1 — PKM 루트 경로 분리 (2026-02-12)
- 기본 PKM 루트 경로를 소스 코드 디렉토리와 분리

## v1.1.0 — Code Quality & Reliability (2026-02-12)
- 검색, 프로젝트 관리 UI, 노트 AI 보완(NoteEnricher), 템플릿 시스템 추가
- AI 컴패니언 시스템 v4 (CLAUDE.md, AGENTS.md, .cursorrules + marker-based 안전 업데이트)
- replaceMarkerSection off-by-one 크래시 등 20+ 코드 품질 수정
- TaskGroup 병렬화, 스트리밍 SHA256 해싱 성능 개선

## v1.0.0 — 첫 릴리즈 (2026-02-11)
- PARA 기반 인박스 자동 분류
- Claude / Gemini 2단계 분류 파이프라인
- 폴더 재정리, SHA256 중복 감지
- 바이너리 자동 변환 (PDF/DOCX/PPTX/XLSX/이미지 → Markdown)
- 시맨틱 링크 & MOC 자동 생성
- Vault 감사, 온보딩 & PARA 폴더 자동 생성
