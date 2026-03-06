[한국어](MANUAL.md) | **English**

# DotBrain Service Manual

> **Built for Humans. Optimized for AI.**
>
> Version: 2.15 | Last Updated: 2026-03-06

---

## Table of Contents

- [1. Introduction](#1-introduction)
- [2. Installation](#2-installation)
- [3. Initial Setup (Onboarding)](#3-initial-setup-onboarding)
- [4. AI Provider Settings](#4-ai-provider-settings)
- [5. Usage Guide](#5-usage-guide)
  - [5.1 Inbox Processing](#51-inbox-processing)
  - [5.2 Folder Reorganization](#52-folder-reorganization)
  - [5.3 PARA Management](#53-para-management)
  - [5.4 Full Vault Reorganization](#54-full-vault-reorganization)
  - [5.5 Vault Audit](#55-vault-audit)
  - [5.6 Semantic Linking](#56-semantic-linking)
  - [5.7 Search](#57-search)
  - [5.8 Folder Relationship Explorer](#58-folder-relationship-explorer)
  - [5.9 AI Statistics](#59-ai-statistics)
- [6. Screen Layout](#6-screen-layout)
- [7. Frontmatter Specification](#7-frontmatter-specification)
- [8. Folder Structure](#8-folder-structure)
- [9. AI Companion Files](#9-ai-companion-files)
- [10. Supported File Formats](#10-supported-file-formats)
- [11. Duplicate Detection](#11-duplicate-detection)
- [12. Settings](#12-settings)
- [13. Troubleshooting](#13-troubleshooting)
- [14. Developer Guide](#14-developer-guide)
  - [14.1 Architecture](#141-architecture)
  - [14.2 Build](#142-build)
  - [14.3 Code Placement Rules](#143-code-placement-rules)
  - [14.4 Pipeline Details](#144-pipeline-details)
  - [14.5 Service List](#145-service-list)
  - [14.6 Models](#146-models)
  - [14.7 Security](#147-security)
  - [14.8 Release](#148-release)

---

## 1. Introduction

DotBrain is an AI-powered PKM (Personal Knowledge Management) app that runs in the macOS menu bar.

**Key Features:**
- Drop files into the inbox and AI reads the content to automatically classify them into the PARA structure
- Frontmatter generation, related note linking, MOC (Map of Content) creation
- Vault health checks: fix broken links, fill in missing metadata, detect duplicates
- Obsidian compatible — wiki-link and frontmatter based

**PARA Methodology:**

| Category | Description | Folder |
|----------|-------------|--------|
| Project | Active work with a deadline | `1_Project/` |
| Area | Ongoing responsibilities to maintain | `2_Area/` |
| Resource | Reference and learning materials | `3_Resource/` |
| Archive | Completed or stored items | `4_Archive/` |

---

## 2. Installation

### npx (Recommended)

```bash
npx dotbrain
```

When `·‿·` appears in the menu bar, installation is complete.

**Requirements:** macOS 13 (Ventura) or later, Node.js 18+

### Build from Source

```bash
git clone https://github.com/DinN0000/DotBrain.git ~/Developer/DotBrain
cd ~/Developer/DotBrain
swift build -c release
# Binary: .build/release/DotBrain
```

### Uninstall

```bash
npx dotbrain --uninstall
```

Or manually:
```bash
pkill -f DotBrain 2>/dev/null
launchctl bootout gui/$(id -u)/com.dotbrain.app 2>/dev/null
rm -f ~/Library/LaunchAgents/com.dotbrain.app.plist
rm -rf ~/Applications/DotBrain.app
```

---

## 3. Initial Setup (Onboarding)

On first launch, a 6-step onboarding wizard will start.

### Step 0: Welcome

Shows a Before/After comparison of what DotBrain does. Click "Get Started."

### Step 1: Full Disk Access Permission

DotBrain requires **Full Disk Access** permission to access PKM folders.

1. Open **System Settings** > **Privacy & Security** > **Full Disk Access**
2. Toggle DotBrain on
3. When you return to the app, the status will update automatically

> You can skip this step, but without the permission, some folders may be inaccessible.

### Step 2: Select PKM Folder

Select the folder to use as your vault. PARA subfolders (`1_Project/`, `2_Area/`, `3_Resource/`, `4_Archive/`, `_Inbox/`) will be created automatically.

### Step 3: Register Areas + Projects

Register at least one Area (ongoing responsibility domain), then register your current active projects. Areas and projects are configured together on a single screen.

- **Area examples:** `DevOps`, `Finance`, `Health`, `Learning`
- **Project examples:** `PoC-Alpha`, `DotBrain`, `Q1-Report`
- Each project can be linked to an Area

### Step 4: Select AI Provider

Choose one of three AI providers:

| Provider | Setup | Cost |
|----------|-------|------|
| **Claude CLI** (Recommended) | Requires Claude app installation, no API key needed | Uses subscription tokens |
| Claude API | Enter API key (`sk-ant-...`) | ~$0.002/file |
| Gemini API | Enter API key (`AIza...`) | Free tier available |

### Step 5: Complete

Once setup is finished, you will be taken to the inbox screen. Try dropping a file in.

---

## 4. AI Provider Settings

### Claude CLI (Recommended)

The default provider for Claude subscription (Pro/Max) users.

- **Setup:** Install the Claude desktop app and the `claude` CLI becomes automatically available
- **Models:** Haiku (Fast) → Sonnet (Precise)
- **Cost:** Uses subscription tokens, no separate API cost
- **Installation check:** Shows "Installed" / "Not Found" in settings

If Claude CLI is not available, install the Claude app from [claude.com/download](https://claude.com/download).

### Claude API

Direct API key-based calls.

- **Get a key:** [console.anthropic.com/settings/keys](https://console.anthropic.com/settings/keys)
- **Models:** Haiku 4.5 (Fast) → Sonnet 4.5 (Precise)
- **Cost:** ~$0.002/file (most files finish at Stage 1)
- **Key format:** `sk-ant-` prefix

### Gemini API

Leverage Google AI's free tier.

- **Get a key:** [aistudio.google.com/apikey](https://aistudio.google.com/apikey)
- **Models:** Flash 2.5 (Fast) → Pro 2.5 (Precise)
- **Cost:** Free tier (15 req/min, 1500 req/day)
- **Key format:** `AIza` prefix

### Switching Providers

You can change providers at any time from the settings screen. API keys for each provider are stored independently, so you don't need to re-enter keys when switching.

### Automatic Fallback

If the active provider call fails, it automatically switches to another provider that has a configured key.

---

## 5. Usage Guide

### 5.1 Inbox Processing

**This is the core feature.** Drop files into the inbox and AI classifies them.

**How to use:**
1. Click DotBrain in the menu bar → Inbox screen
2. Drag and drop files or click "+ Select Files"
3. Click the "Organize" button

**Processing Pipeline (5 stages):**

```
Preparation (0-5%)      File scanning
    ↓
Analysis (5-30%)        Content extraction (text/PDF/image/document)
    ↓
AI Classification (30-70%) Stage 1: Fast batch classification (Haiku/Flash)
                           Stage 2: Precise classification (Sonnet/Pro) — low confidence files only
    ↓
Organization (70-95%)   File move + frontmatter injection
    ↓
Finalization (95-100%)  MOC update + semantic link generation
```

**2-Stage AI Classification:**
- **Stage 1 (Fast):** Batch classification using filename + 2000-char preview (5 files at a time). Most files finish here
- **Stage 2 (Precise):** Only files with confidence < 0.8 get full-content precise classification

**Cases requiring user confirmation:**
- Low confidence classification (< 0.5)
- When AI-suggested project doesn't exist
- When filename conflicts with an index note
- When a file with the same name but different content already exists

**Results screen:**
- Shows success/failure/duplicate status per file
- Conflicting files can be reviewed manually by the user

### 5.2 Folder Reorganization

AI re-organizes files within existing PARA folders.

**How to use:**
1. Dashboard → "Folder Management" → Select folder
2. Run "Organize"

**Processing Pipeline:**

```
Flatten — Move content from nested subfolders to top level
    ↓
Deduplicate — Detect duplicate files via SHA256 hash, merge tags then delete
    ↓
AI Reclassify
    ├── Correct location → Update frontmatter (tags, summary, etc.)
    └── Wrong location → Automatically move to correct folder
```

### 5.3 PARA Management

Manage the PARA structure directly from Dashboard → "Folder Management."

- **Create project:** Automatically creates a new project folder + index note
- **Rename:** Rename folder (also updates the project field in frontmatter)
- **Merge:** Combine contents of two folders into one
- **Delete:** Delete empty folders
- **Move category:** Move between PARA categories (e.g., Project → Archive)

Each folder displays file count, modified file count, and health status.

### 5.4 Full Vault Reorganization

AI scans all files in the vault to find incorrect classifications.

**How to use:**
1. Dashboard → "Vault Check" → Run "Full Reorganization"

**2-Stage Workflow:**

```
Scan phase — AI classifies all files and compares with current location
    ↓
User review — Shows list of files that need to be moved
    ↓
Execute — Only moves files approved by the user
```

> Scans up to 200 files at a time. AI does not create new project folders; it only moves to existing ones.

### 5.5 Vault Audit

Automatically checks and repairs vault integrity.

**5-Stage Pipeline:**

| Stage | Description |
|-------|-------------|
| Audit | Detect broken wiki-links, missing frontmatter, files without tags |
| Repair | Replace broken links with most similar note (Levenshtein distance), inject missing frontmatter |
| Enrich | AI fills empty metadata fields on changed files (tags, summary, classification) |
| Index Update | Incremental update of `.meta/note-index.json` |
| Semantic Link | Create wiki-links between related notes (links deleted by user are not regenerated) |

### 5.6 Semantic Linking

AI analyzes semantic relationships between notes and automatically generates `[[wiki-links]]`.

**Candidate Generation Criteria:**
- Shared tags (weight: 1 point per tag)
- Same project membership
- MOC membership
- Folder relations (boost pairs: +3 points, suppress pairs: -1 point)

**AI Filtering:**
- Evaluated by the criterion: "Would following this link give the user a new insight?"
- Relationship type classification: prerequisite, project, reference, related

**`## Related Notes` Section Format:**

```markdown
## Related Notes

### Prerequisite
- [[Basic Concepts]] — Content to read first to understand this document

### Related Project
- [[Project Plan]] — Planning document from the same project

### Reference
- [[API Reference]] — API documentation to reference during implementation

### See Also
- [[Similar Case Analysis]] — A document covering a similar topic from a different perspective
```

**Link Protection:**
- Links manually deleted by the user are recorded in `LinkFeedbackStore` and will not be regenerated
- `LinkStateDetector` compares previous/current link snapshots to detect deletions

### 5.7 Search

Search the entire vault from Dashboard → "Search."

- **Search targets:** Tags, keywords, file titles, summaries, body text
- **Result display:** PARA category color icons, related note suggestions
- **Match types:** tagMatch, bodyMatch, summaryMatch, titleMatch

### 5.8 Folder Relationship Explorer

Manage AI-discovered folder relationships from the bottom tab → "Folder Relations" on the dashboard.

- **Card UI:** AI-suggested folder pairs displayed as cards
- **Swipe:** Right (accept) / Left (reject) to approve or deny relationships
- **Effect:** Approved relationships get boosted weight in semantic linking; rejected relationships are suppressed

### 5.9 AI Statistics

Check usage from Dashboard → "AI Statistics."

- **API cost:** Cumulative usage cost
- **By task type:** Cost breakdown by task type (classification, reorganization, semantic link, summary, etc.)
- **Recent history:** API call history (timestamp, model, token count, cost)

---

## 6. Screen Layout

### Main Navigation (4 Bottom Tabs)

| Tab | Icon | Description |
|-----|------|-------------|
| Inbox | tray.and.arrow.down | File drop zone, file list, "Organize" button |
| Dashboard | square.grid.2x2 | Statistics, health alerts, activity log, feature shortcuts |
| Folder Relations | rectangle.2.swap | AI folder pair matching |
| Settings | gearshape | AI settings, PKM folder, app info |

### Screens Accessible from Dashboard

| Screen | Description |
|--------|-------------|
| Folder Management | PARA folder create/rename/merge/delete |
| Search | Tag/keyword/title-based vault search |
| Vault Check | Health check, reorganization, issue scan |
| AI Statistics | API costs, usage log |

### Menu Bar Expression

The menu bar icon changes its expression based on app state:

| Expression | State |
|------------|-------|
| `·‿·` | Default (idle) |
| `·_·!` | Notification available |
| `·_·…` | Processing |
| `^‿^` | Processing complete |

---

## 7. Frontmatter Specification

DotBrain applies YAML frontmatter to all notes.

```yaml
---
para: project
tags: ["defi", "ethereum", "blockchain"]
created: 2026-02-11
status: active
summary: "DeFi system building project"
source: import
project: MyProject
---
```

| Field | Description | Values |
|-------|-------------|--------|
| `para` | PARA category | project, area, resource, archive |
| `tags` | AI auto-tagging | String array |
| `created` | Original creation date (preserves existing value) | YYYY-MM-DD |
| `status` | Note status | active, draft, completed, on-hold |
| `summary` | One-line summary | String |
| `source` | Origin | original, meeting, literature, import |
| `project` | Associated project name | String |
| `area` | Associated Area name | String |
| `projects` | Associated project list (for Area documents) | String array |
| `file` | Original filename (non-text files) | String |

---

## 8. Folder Structure

```
PKM Root/
├── _Inbox/                          ← Drop files here
├── _Assets/                         ← Central binary file storage
│   ├── documents/                   ← PDF, DOCX, etc.
│   ├── images/                      ← Images
│   └── videos/                      ← Videos
├── 1_Project/
│   └── MyProject/
│       ├── MyProject.md             ← Index note (auto-generated)
│       └── plan.md
├── 2_Area/
│   └── DevOps/
│       └── monitoring-guide.md
├── 3_Resource/
│   └── Python/
│       └── asyncio-patterns.md
├── 4_Archive/
│   └── 2024-Q1/
│       └── quarterly-report.md
├── .meta/                           ← Metadata (hidden)
│   ├── note-index.json              ← Vault index
│   ├── folder-relations.json        ← Folder relations
│   └── .dotbrain-companion-version
└── .Templates/                      ← Note templates
```

### MOC (Map of Content)

An index note (MOC) is automatically generated for each project folder:

```markdown
# MyProject

> System building project

## Document List
- [[Architecture Design]] — System-wide architecture design document
- [[Meeting Notes 0211]] — 2nd requirements meeting. API integration approach finalized
- [[Audit Report]] — Static analysis results and vulnerability remediation details
```

For humans, it serves as a clickable table of contents; for AI, it serves as an index for determining navigation priority.

---

## 9. AI Companion Files

DotBrain automatically generates guide files for AI tools in the vault.

| File | Purpose |
|------|---------|
| `CLAUDE.md` | Guides Claude Code to understand the vault structure |
| `AGENTS.md` | Agent workflow definitions |
| `.cursorrules` | Cursor IDE rules |
| `.claude/agents/` | Task-specific agents (inbox processing, project management, search, etc.) |
| `.claude/skills/` | Automation skill definitions |

**Update mechanism:**
- Only content between `<!-- DotBrain:start -->` and `<!-- DotBrain:end -->` markers is updated
- User-added content outside the markers is preserved
- Automatically regenerated when the app version is upgraded

---

## 10. Supported File Formats

| Format | Extraction Method | Extracted Content |
|--------|-------------------|-------------------|
| `.md`, `.txt`, etc. | Direct read | Full text |
| `.pdf` | PDFKit | Text + page count/author/title |
| `.docx` | ZIPFoundation + XML | Body text + metadata |
| `.pptx` | ZIPFoundation + XML | Slide text |
| `.xlsx` | ZIPFoundation + XML | Cell data |
| `.jpg`, `.png`, `.heic`, etc. | ImageIO | EXIF (date taken, camera, GPS) |
| Folder | Internal file traversal | Combined content of contained files |

Binary files (PDF, images, etc.) are stored in `_Assets/`, and a markdown companion file containing a summary is created in the PARA folder.

---

## 11. Duplicate Detection

| Target | Detection Method | Handling |
|--------|------------------|----------|
| Text files (same content, different name) | SHA256 body hash (excluding frontmatter) | Merge tags → delete duplicate |
| Binary files (≤ 500MB) | SHA256 streaming hash | Merge tags → delete duplicate |
| Binary files (> 500MB) | File size + modification date comparison | Merge tags → delete duplicate |
| Same name, different content | Filename comparison | Ask user for confirmation |
| Name conflict with index note | `foldername.md` comparison | Ask user for confirmation |

---

## 12. Settings

Settings are accessed via the gear icon in the bottom tab.

### AI Settings
- **Provider selection:** Claude CLI / Claude API / Gemini (segment tab)
- **API key management:** Enter/change/delete keys per provider
- **Key storage:** Securely stored as AES-GCM encrypted file (hardware UUID + HKDF key derivation, device-bound)

### PKM Folder
- **Change path:** Re-select vault folder with the "Change" button
- **Initialize structure:** Shows a create button if PARA folders don't exist

### Permissions
- **Full Disk Access:** Permission status display + shortcut to System Settings

### App Management
- **Version:** Shows current app version
- **Check for updates:** Shows an update button when a new version is available
- **Restart onboarding:** Run the onboarding wizard from the beginning again

---

## 13. Troubleshooting

### "Unidentified Developer" / "Damaged and Can't Be Opened"

```bash
xattr -cr ~/Applications/DotBrain.app
```

Or: **System Settings** > **Privacy & Security** > Click "Open Anyway"

### Folder Access Permission Popup

On first launch, make sure to select **"Allow"** when prompted for PKM folder access permission.

### Menu Bar Icon Not Visible

The menu bar may be out of space. Remove other icons by `Cmd+dragging` them away, or use apps like Bartender/Ice to manage them.

### Claude CLI Not Found

Check if the Claude desktop app is installed:
```bash
which claude
```

If not installed, install it from [claude.com/download](https://claude.com/download) and restart the app.

### AI Classification Is Inaccurate

- **Correction memory:** When you correct a classification, it is recorded in `CorrectionMemory` and reflected in future classifications
- **Project registration:** Accurately registering projects in settings improves classification accuracy
- **Area registration:** The more specifically you register Areas, the better AI understands context

### Uninstall App

```bash
npx dotbrain --uninstall
```

---

## 14. Developer Guide

### 14.1 Architecture

```
Sources/
├── App/
│   ├── DotBrainApp.swift       ← Entry point (@main)
│   ├── AppDelegate.swift       ← NSStatusItem + NSPopover setup
│   ├── AppIconGenerator.swift  ← Dynamic menu bar icon generation
│   └── AppState.swift          ← Central state management (@MainActor, ObservableObject)
├── Pipeline/                   ← Multi-stage processing pipelines
│   ├── InboxProcessor.swift    ← Inbox → PARA classification
│   ├── FolderReorganizer.swift ← Single folder reorganization
│   ├── VaultReorganizer.swift  ← Full vault reorganization
│   ├── VaultCheckPipeline.swift← Vault audit + repair + enrichment
│   └── ProjectContextBuilder.swift ← Context generation for AI prompts
├── Services/                   ← Single-responsibility utilities
│   ├── AIService.swift         ← Claude/Gemini API abstraction, automatic fallback
│   ├── Claude/                 ← Claude providers
│   │   ├── Classifier.swift    ← 2-stage AI classification (Stage 1 batch + Stage 2 precise)
│   │   ├── ClaudeAPIClient.swift ← Claude API HTTP client
│   │   └── ClaudeCLIClient.swift ← Claude CLI process pool management
│   ├── Gemini/
│   │   └── GeminiAPIClient.swift ← Gemini API client
│   ├── SemanticLinker/         ← Semantic linking system (9 components)
│   ├── FileSystem/             ← File system utilities
│   │   ├── FileMover.swift     ← File move + conflict resolution + duplicate detection
│   │   ├── PKMPathManager.swift ← Path validation + PARA category detection
│   │   ├── FrontmatterWriter.swift ← Frontmatter + wiki-link writing
│   │   ├── InboxScanner.swift  ← Inbox file scanning
│   │   ├── InboxWatchdog.swift ← Inbox change monitoring (DispatchSource)
│   │   └── AssetMigrator.swift ← Asset structure migration
│   ├── Extraction/             ← Format-specific content extraction
│   │   ├── FileContentExtractor.swift ← Extraction router
│   │   ├── PDFExtractor.swift, DOCXExtractor.swift, ...
│   │   └── ImageExtractor.swift, BinaryExtractor.swift
│   └── ...
├── Models/                     ← Data models
│   ├── Frontmatter.swift
│   ├── ClassifyResult.swift
│   ├── PARACategory.swift
│   └── ...
└── UI/                         ← SwiftUI views
    ├── MenuBarPopover.swift
    ├── OnboardingView.swift
    ├── InboxStatusView.swift
    └── ...
```

**Layer Rules:**
- **UI** → Read AppState + call methods. Never call Services directly.
- **AppState** → `@Published` properties + pipeline wrappers. No business logic over 10 lines.
- **Pipeline** → Multi-stage processing (TaskGroup, for loops, 5+ stages). Must be a separate struct/class.
- **Services** → Single-responsibility utilities (actor or struct).

### 14.2 Build

```bash
# Regular build
swift build

# Release build
swift build -c release

# Clean build (required after UI changes)
swift package clean && swift build -c release
```

**Dependencies:** Only ZIPFoundation 0.9.19+ (ZIP file processing). Everything else is pure Swift Foundation + AppKit + SwiftUI.

**Binary replacement (during development):**
```bash
pkill -9 DotBrain
sleep 2
cp .build/release/DotBrain ~/Applications/DotBrain.app/Contents/MacOS/DotBrain
sleep 1
open ~/Applications/DotBrain.app
```

> After UI changes, you must run `swift package clean` followed by a clean build. The build cache may reuse stale objects.

### 14.3 Code Placement Rules

| Location | Criteria | Examples |
|----------|----------|----------|
| `Pipeline/` | Multi-stage processing (for loops, TaskGroup, 5+ stages) | InboxProcessor, VaultCheckPipeline |
| `Services/` | Single-responsibility utility (actor or struct) | AIService, FileMover, VaultSearcher |
| `AppState` | `@Published`, navigation, thin pipeline wrappers | startProcessing(), navigateBack() |
| `UI/` | SwiftUI views. Reference AppState only | InboxStatusView, DashboardView |

**Code Style:**
- Korean: UI strings. English: code and comments
- Use `Task.detached(priority:)` (no DispatchQueue.global, except DispatchSource)
- `@MainActor` + `await MainActor.run` — UI updates from detached tasks
- `TaskGroup` concurrency limits: max 3 for AI calls, max 5 for file extraction
- File I/O: 4KB for frontmatter extraction, 64KB for body search, 1MB streaming for large binaries

### 14.4 Pipeline Details

#### InboxProcessor

```
scan → extract (max 5 concurrent) → classify (2-stage AI) → move → semantic link
```

- Media files skip AI classification (default .resource classification)
- Project name fuzzy matching: AI output → actual folder name matching
- Deduplicate project name from tags (AI hallucination prevention)

#### FolderReorganizer

```
flatten (unnest) → deduplicate (SHA256) → classify → move/update
```

- `_Assets/` substructure is preserved
- Placeholder files (`_-` prefix, empty index notes) are deleted

#### VaultCheckPipeline

```
audit → repair → enrich (AI, max 3 concurrent) → index update → semantic link
```

- `LinkStateDetector`: Compares with previous snapshot to detect user-deleted links
- Archive category files are skipped during the Enrich stage
- Incremental processing: only rescan changed folders

#### ProjectContextBuilder

Generates context injected into AI prompts:
- Project list (name, summary, tags, Area connection)
- Area context (Area-Project mapping)
- Subfolder JSON (AI hallucination prevention — only allow existing folder names)
- Top 50 tags (consistency maintenance)
- Correction memory (user feedback patterns)

### 14.5 Service List

**Core AI:**
| Service | Role |
|---------|------|
| `AIService` | Claude/Gemini API abstraction, automatic fallback |
| `Classifier` | 2-stage AI classification (Stage 1 batch + Stage 2 precise) |
| `ClaudeAPIClient` | Claude API HTTP client (actor) |
| `ClaudeCLIClient` | Claude CLI process pool management (actor) |
| `GeminiAPIClient` | Gemini API client (actor) |
| `NoteEnricher` | AI supplementation of empty metadata fields |
| `RateLimiter` | Adaptive per-provider API call rate limiting (actor) |
| `APIUsageLogger` | API usage/cost logging (actor) |

**Semantic Linking:**
| Service | Role |
|---------|------|
| `SemanticLinker` | Main orchestrator |
| `TagNormalizer` | Tag consistency enforcement |
| `LinkCandidateGenerator` | Candidate scoring (tags, project, MOC, folder relations) |
| `LinkAIFilter` | AI-based link evaluation ("Would this provide new insight?") |
| `RelatedNotesWriter` | `## Related Notes` section writing |
| `LinkStateDetector` | User-deleted link detection |
| `LinkFeedbackStore` | Link deletion/boost history storage |
| `FolderRelationStore` | Folder pair relationship (boost/suppress) management |
| `FolderRelationAnalyzer` | Folder pair candidate suggestions |

**File Processing:**
| Service | Role |
|---------|------|
| `FileMover` | File move, conflict resolution, duplicate detection (SHA256) |
| `PKMPathManager` | Path validation, PARA category detection, folder name validation |
| `FileContentExtractor` | Format-specific content extraction router |
| `PDFExtractor` | PDF text + metadata extraction (PDFKit) |
| `DOCXExtractor` | DOCX body extraction (ZIPFoundation + XML) |
| `PPTXExtractor` | PPTX slide text extraction |
| `XLSXExtractor` | XLSX cell data extraction |
| `ImageExtractor` | Image EXIF metadata extraction (ImageIO) |
| `NoteIndexGenerator` | `.meta/note-index.json` incremental update |
| `VaultSearcher` | Vault full-text search (index-first + 64KB body fallback) |
| `VaultAuditor` | Vault issue detection (broken links, missing metadata) |
| `FolderHealthAnalyzer` | Folder health score (0-1.0) |
| `ContentHashCache` | Duplicate detection hash cache (actor) |
| `InboxScanner` | Inbox file scan + symbolic link validation |
| `InboxWatchdog` | Inbox file change monitoring (DispatchSource) |
| `FrontmatterWriter` | Frontmatter serialization + wiki-link generation |
| `AssetMigrator` | Asset structure migration (v2.1.0+) |

**Other:**
| Service | Role |
|---------|------|
| `StatisticsService` | Activity log, API cost tracking |
| `AICompanionService` | CLAUDE.md, AGENTS.md, .cursorrules, agent/skill generation |
| `CorrectionMemory` | User classification correction records (reflected in future classifications) |
| `ProjectAliasRegistry` | AI name suggestion → actual project fuzzy mapping |
| `ProjectRegistry` | Project/Area registry (configured during onboarding) |
| `ProjectManager` | Project CRUD (create, rename, wiki-link update) |
| `PARAMover` | File/folder move between PARA categories + frontmatter/MOC update |
| `KeychainService` | API key AES-GCM encrypted storage (hardware UUID + HKDF) |
| `ContextMap` / `ContextMapBuilder` | Vault context map construction |
| `NotificationService` | macOS notification delivery |
| `TemplateService` | Note template management |

### 14.6 Models

| Model | Role |
|-------|------|
| `Frontmatter` | YAML frontmatter parsing/serialization |
| `PARACategory` | PARA category enum (project/area/resource/archive) |
| `ClassifyResult` | AI classification result (para, tags, summary, confidence, etc.) |
| `ProcessingModels` | Processing phase (ProcessingPhase), result (ProcessedFileResult), pending confirmation (PendingConfirmation) |
| `PKMStatistics` | Dashboard statistics (file count, cost, activity log) |
| `SearchResult` | Search result (match type, relevance score) |
| `AIResponse` | AI API response wrapper (text + token usage) |
| `AIProvider` | AI provider enum (claudeCLI/claude/gemini) |
| `ExtractResult` | Binary file extraction result |

### 14.7 Security

- **Path traversal prevention:** `URL.resolvingSymlinksInPath()` followed by `hasPrefix` check
- **YAML injection prevention:** Tags always stored as double-quoted arrays `tags: ["tag1", "tag2"]`
- **Folder name restrictions:** `sanitizeFolderName()` — max 3 depth, 255 char limit, no `..`
- **API key storage:** Claude CLI requires no key. When using API keys, stored with AES-GCM encryption + hardware UUID + HKDF for device-bound storage
- **Index-first search:** Query `.meta/note-index.json` first to minimize unnecessary file I/O

### 14.8 Release

**Release Order (Mandatory):**

```
1. swift build -c release              ← Must be release build
2. scripts/build-dmg.sh                ← Generate DMG
3. gh release create vX.Y.Z            ← GitHub release (DMG + binary + icon + plist)
4. npm publish                         ← npm package publish
5. npx dotbrain                        ← Verify installation
```

**Version sync required:** `Resources/Info.plist`, `npm/package.json`, and git tag must all match.

**Release assets:**
- `DotBrain-{VERSION}.dmg` — Primary installation file
- `DotBrain` — Binary (backward compatibility)
- `AppIcon.icns` — App icon
- `Info.plist` — App metadata

---

<p align="center">
Made by Hwaa
</p>
