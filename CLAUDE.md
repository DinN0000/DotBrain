# DotBrain

## Build
- `swift build` — build the project (macOS menubar app, Swift 5.9+)
- Zero warnings policy — fix all warnings before committing

## Architecture
- PARA-based PKM organizer: `_Inbox/` → AI classifies → `1_Project/`, `2_Area/`, `3_Resource/`, `4_Archive/`
- `AppState` (singleton) — central state, `@MainActor`, `ObservableObject`
- `Sources/Pipeline/` — InboxProcessor, FolderReorganizer, ProjectContextBuilder
- `Sources/Services/` — AIService, FileMover, PKMPathManager, VaultSearcher, MOCGenerator, StatisticsService
- `Sources/UI/` — SwiftUI views (menubar popover)
- `Sources/Models/` — Frontmatter, ClassifyResult, PARACategory

## Code Style
- Korean for UI strings, English for comments and code
- No emojis in code
- `Task.detached(priority:)` for background work, never `DispatchQueue.global`
- `@MainActor` + `await MainActor.run` for UI updates from detached tasks
- `TaskGroup` with concurrency limit (max 3) for batch AI calls
- Streaming file I/O (1MB chunks via FileHandle) for large files, never load entire file

## Security
- Path traversal: always canonicalize with `URL.resolvingSymlinksInPath()` before `hasPrefix` checks
- YAML injection: always double-quote tags in frontmatter `tags: ["tag1", "tag2"]`
- Folder names: sanitize via `sanitizeFolderName()` — max 3 depth, 255 char limit, no `..`

## Key Patterns
- AI companion files use marker-based updates (`<!-- DotBrain:start/end -->`) to preserve user content
- `StatisticsService` calls (addApiCost, incrementDuplicates, recordActivity) must be wired manually at each call site
- Wiki-links `[[note]]` in `## Related Notes` sections enable cross-note navigation for both humans and AI
- MOC files (`folderName.md`) auto-generated as folder-level table of contents

## Release Workflow
- GitHub: `DinN0000/DotBrain`
- Release assets: `DotBrain` (universal binary) + `AppIcon.icns` — naming must be exact
- Use `/release` command for guided release process
- `AICompanionService.swift` version must be bumped when behavior changes (triggers vault auto-update)

## Branch Rules
- `main` — stable, release-ready
- `feature/*` — feature work, merge into main when done
- Never switch branches on active working repo — use `/tmp/` temporary clones for cross-branch operations
- Delete feature branches after merge (local + remote)

## Custom Commands
- `/review` — code review against CLAUDE.md rules
- `/check` — quick project status (build, git, release)
- `/release` — guided release workflow
- `/status` — DotBrain app status
