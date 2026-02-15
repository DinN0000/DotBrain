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

- API 키: AES-GCM 암호화 파일, 하드웨어 UUID + HKDF 기반 키 유도
- 네트워크: HTTPS only (NSAppTransportSecurity)
- 파일 경로: canonicalize 후 prefix 검사
- YAML: 이중 인용부호로 injection 방지
