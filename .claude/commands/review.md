# Code Review

현재 브랜치의 변경사항을 리뷰한다.

1. `git diff main...HEAD`로 전체 변경사항 확인
2. 아래 기준으로 리뷰:
   - 빌드 에러/경고 여부 (`swift build`)
   - 보안: path traversal, YAML injection, API 키 노출
   - 동시성: `@MainActor` 누락, data race 가능성
   - 에러 핸들링: catch 후 무시하는 곳
   - CLAUDE.md 규칙 위반 여부
3. 발견된 이슈를 심각도(Critical/High/Medium)별로 정리
4. 수정 제안 포함
