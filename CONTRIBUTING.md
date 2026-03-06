[한국어](CONTRIBUTING.md) | [English](CONTRIBUTING.en.md)

# Contributing to DotBrain

## 개발 환경

- macOS 13.0+
- Swift 5.9+
- 의존성: ZIPFoundation (Package.swift에서 자동 관리)

```bash
git clone https://github.com/DinN0000/DotBrain.git
cd DotBrain
swift build
```

## 브랜치 규칙

- `main` — 안정 릴리즈
- `feature/*` — 기능 개발, 완료 후 main에 머지
- 머지 후 feature 브랜치 삭제 (로컬 + 리모트)

## 커밋 메시지

[Conventional Commits](https://www.conventionalcommits.org/) 형식, 영어:

```
feat: add vault search functionality
fix: resolve folder nesting bug in classifier
perf: parallelize file extraction with TaskGroup
docs: update architecture design document
refactor: consolidate dashboard views
style: systematize color scheme
chore: update .gitignore
```

## 코드 스타일

- **Zero warnings** — 커밋 전 `swift build`에서 경고 없어야 함
- 불필요한 주석, docstring 추가 금지
- 요청한 것만 수정 — 주변 코드 리팩토링 금지

> 상세한 코드 스타일 및 보안 규칙은 [CLAUDE.md](CLAUDE.md) 참조

## PR 프로세스

1. feature 브랜치에서 작업
2. `swift build` 성공 확인
3. PR 생성 (템플릿 따르기)
4. 리뷰 후 main에 머지
