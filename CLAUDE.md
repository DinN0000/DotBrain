# DotBrain

## Build
- `swift build` — build the project (macOS menubar app, Swift 5.9+)
- Zero warnings policy — fix all warnings before committing

## Architecture
- PARA-based PKM organizer: `_Inbox/` → AI classifies → `1_Project/`, `2_Area/`, `3_Resource/`, `4_Archive/`
- `AppState` (singleton) — central state, `@MainActor`, `ObservableObject`
- `Sources/Pipeline/` — InboxProcessor, FolderReorganizer, VaultReorganizer, VaultCheckPipeline, ProjectContextBuilder
- `Sources/Services/` — AIService, FileMover, PKMPathManager, VaultSearcher, NoteIndexGenerator, StatisticsService
- `Sources/Services/SemanticLinker/` — SemanticLinker, TagNormalizer, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter, FolderRelationStore, FolderRelationAnalyzer, LinkFeedbackStore, LinkStateDetector
- `Sources/UI/` — SwiftUI views (menubar popover)
- `Sources/Models/` — Frontmatter, ClassifyResult, PARACategory

## Code Placement Rules
- **Pipeline** (`Sources/Pipeline/`): multi-phase processing (for loops, TaskGroup, 5+ phases). Always a separate struct/class.
- **Services** (`Sources/Services/`): single-responsibility utilities (actor or struct)
- **AppState**: `@Published` properties, navigation methods, thin pipeline wrappers (guard + create pipeline + call). No TaskGroup, no 10+ line business logic. Simple iteration (for loops for UI state updates) is allowed.
- **UI Views**: read AppState, call AppState methods. Never call Services directly.

## Code Style
- Korean for UI strings, English for comments and code
- No emojis in code
- `Task.detached(priority:)` for background work, never `DispatchQueue.global` (exception: `DispatchSource` for file system events)
- `@MainActor` + `await MainActor.run` for UI updates from detached tasks
- `TaskGroup` with concurrency limit (max 3 for AI calls, max 5 for file extraction) for batch processing
- File I/O: 4KB partial reads (FileHandle) for frontmatter extraction (NoteIndexGenerator); 64KB for body search (VaultSearcher); 1MB streaming for large binaries
- Index-first search patterns: load `.meta/note-index.json` first, fallback to directory scan only if needed (zero file I/O when possible)

## Security
- Path traversal: always canonicalize with `URL.resolvingSymlinksInPath()` before `hasPrefix` checks
- YAML injection: always double-quote tags in frontmatter `tags: ["tag1", "tag2"]`
- Folder names: sanitize via `sanitizeFolderName()` — max 3 depth, 255 char limit, no `..`

## Key Patterns
- AI companion files use marker-based updates (`<!-- DotBrain:start/end -->`) to preserve user content
- `StatisticsService` calls (addApiCost, incrementDuplicates, recordActivity) must be wired manually at each call site
- Wiki-links `[[note]]` in `## Related Notes` sections enable cross-note navigation for both humans and AI
- `.meta/note-index.json` — vault metadata index for AI navigation (NoteIndexGenerator)
- `.meta/folder-relations.json` — folder pair relations (boost/suppress) managed by FolderRelationStore

## Vault Navigation (for Claude Code)
- Read `.meta/note-index.json` first for vault structure overview
- Use tags, summary, project fields from index to identify relevant notes
- Prioritize `status: active` notes when gathering context
- Follow `[[wiki-links]]` in `## Related Notes` for context expansion
- Relation type priority: prerequisite > project > reference > related
- Traversal depth: self-determined by task relevance (no fixed limit)
- Resolve note names to file paths via index (no grep needed)

## Release Workflow
- GitHub: `DinN0000/DotBrain`
- Release assets: `DotBrain-{VERSION}.dmg` (primary) + `DotBrain` (binary, backward compat) + `AppIcon.icns` + `Info.plist`
- Use `/release` command for guided release process
- **DMG build:** `scripts/build-dmg.sh` — reads version from Info.plist, assembles .app, creates DMG
- **npm install:** `npx dotbrain` — downloads DMG from GitHub Releases, installs to ~/Applications
- **npm uninstall:** `npx dotbrain --uninstall`
- **Version sync:** Info.plist, npm/package.json, git tag must all match
- **Every release:** bump `Resources/Info.plist` + `npm/package.json` version to match release tag
- **Deploy:** copy both binary and Info.plist → `cp Resources/Info.plist ~/Applications/DotBrain.app/Contents/Info.plist`
- `AICompanionService.swift` version must be bumped when behavior changes (triggers vault auto-update)

## Branch Rules
- `main` — stable, release-ready
- `feature/*` — feature work, merge into main when done
- Never switch branches on active working repo — use `/tmp/` temporary clones for cross-branch operations
- Delete feature branches after merge (local + remote)

## Documentation
- Architecture docs live in `docs/` — update when code changes affect:
  - Pipeline phase order or data flow → `docs/pipelines.md`
  - Service public API or integration points → `docs/services.md`
  - Model fields or new model types → `docs/models-and-data.md`
  - Security invariants or concurrency patterns → `docs/security-and-concurrency.md`
  - Layer boundaries or new modules → `docs/architecture.md`
- Doc updates go in the same commit as the code change
- Use Korean explanations + English technical terms
- New files: add to relevant section in docs
- Removed files: remove references from docs
- Design decisions: `docs/plans/YYYY-MM-DD-feature-name.md`

## Custom Commands
- `/review` — code review against CLAUDE.md rules
- `/check` — quick project status (build, git, release)
- `/release` — guided release workflow
- `/status` — DotBrain app status
- `/deploy` — build → install → run (clean build with `rm -rf .build`)
- `/wrap` — session wrap-up (4 parallel agents → consolidate → apply)
