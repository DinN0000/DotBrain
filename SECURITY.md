[한국어](SECURITY.md) | [English](SECURITY.en.md)

# Security Policy

## 지원 버전

| 버전 | 지원 |
|------|------|
| 최신 릴리즈 | 지원 |
| 이전 버전 | 미지원 |

## 취약점 신고

보안 취약점을 발견하면 **공개 이슈로 등록하지 마시고** 아래 방법으로 신고해주세요:

1. GitHub Security Advisory: [Report a vulnerability](https://github.com/DinN0000/DotBrain/security/advisories/new)
2. 또는 비공개 이메일로 연락

### 신고 시 포함할 내용

- 취약점 유형 (예: path traversal, injection)
- 재현 단계
- 영향 범위
- 가능하면 수정 제안

### 대응 절차

1. 신고 접수 후 72시간 내 확인
2. 심각도 평가 후 수정 일정 공유
3. 수정 완료 후 릴리즈 및 크레딧 부여

## 보안 설계

### API 키 저장
- AES-GCM 암호화 파일, 하드웨어 UUID + HKDF 기반 키 유도 (기기 종속)
- 저장 파일 퍼미션: `0o600` (소유자만 읽기/쓰기)
- 레거시 macOS Keychain에서 암호화 파일로 자동 마이그레이션 (V1 SHA256 → V2 HKDF)
- Claude CLI 사용 시 API 키 불필요 (구독 인증)

### 네트워크
- HTTPS only (NSAppTransportSecurity)
- API 키는 HTTP 헤더로만 전달 (URL 파라미터 미사용)

### 파일 시스템
- 경로 탐색 방지: `URL.resolvingSymlinksInPath()` 후 `hasPrefix` 검사
- 폴더명 검증: `sanitizeFolderName()` — 최대 3 depth, 255자 제한, `..` 금지, null byte 제거
- 위키링크 인젝션 방지: `sanitizeWikilink()` — `[[`, `]]`, `/`, `\\`, `..` 제거

### 데이터 보호
- YAML: 태그를 항상 이중 인용부호 배열로 저장 (`tags: ["tag1", "tag2"]`)
- 파일 삭제: `trashItem` 사용 (복구 가능한 삭제)
- 파일 쓰기: `atomically: true` 옵션으로 원자적 쓰기
