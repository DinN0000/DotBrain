[한국어](CONTRIBUTING.md) | **English**

# Contributing to DotBrain

## Development Environment

- macOS 13.0+
- Swift 5.9+
- Dependencies: ZIPFoundation (automatically managed in Package.swift)

```bash
git clone https://github.com/DinN0000/DotBrain.git
cd DotBrain
swift build
```

## Branch Rules

- `main` — stable releases
- `feature/*` — feature development, merge into main when complete
- Delete feature branches after merge (local + remote)

## Commit Messages

[Conventional Commits](https://www.conventionalcommits.org/) format, in English:

```
feat: add vault search functionality
fix: resolve folder nesting bug in classifier
perf: parallelize file extraction with TaskGroup
docs: update architecture design document
refactor: consolidate dashboard views
style: systematize color scheme
chore: update .gitignore
```

## Code Style

- **Zero warnings** — `swift build` must produce no warnings before committing
- Do not add unnecessary comments or docstrings
- Only modify what was requested — do not refactor surrounding code

> See [CLAUDE.md](CLAUDE.md) for detailed code style and security rules

## PR Process

1. Work on a feature branch
2. Verify `swift build` succeeds
3. Create a PR (follow the template)
4. Merge into main after review
