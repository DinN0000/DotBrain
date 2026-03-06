<p align="right"><a href="README.md">한국어</a></p>

<p align="center">
  <img src="Resources/app-icon.png" width="128" alt="DotBrain Icon">
</p>

<h1 align="center">DotBrain</h1>

<p align="center">
  <strong>Built for Humans. Optimized for AI.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Swift-5.9-F05138?logo=swift&logoColor=white" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/macOS-13%2B-000000?logo=apple&logoColor=white" alt="macOS 13+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/DinN0000/DotBrain" alt="License"></a>
  <a href="https://github.com/DinN0000/DotBrain/releases/latest"><img src="https://img.shields.io/github/v/release/DinN0000/DotBrain" alt="Latest Release"></a>
</p>

[한국어](README.md) | **English**

DotBrain systematically organizes your local documents using the PARA methodology.<br>
This structure becomes an intuitive knowledge system for humans,

and provides understandable Context for AI.<br>
That Context serves as AI's exploration foundation, enabling it to understand and reason more deeply about your knowledge.

```
·‿·  →  ·_·!  →  ·_·…  →  ^‿^

```

---

## 🧐 What is DotBrain?

The bottleneck in knowledge management isn't accumulation — it's **utilization**.<br>
Information piles up easily,<br>
but organizing it for easy retrieval and connecting context is hard.

What's even harder is<br>
structuring that knowledge into a form AI can understand and leverage.

**The Problem: Human vs. AI**
- **The PARA Dilemma (Human Overhead):** The PARA methodology works brilliantly for human cognition, but the maintenance cost of manually sorting everything each time is high. Eventually, organizing falls behind and files just pile up in the inbox.
- **AI's Discord (Context Gap):** Disorganized documents make it difficult for even AI to grasp context. Simply storing files becomes nothing more than a useless data dump for both humans and AI.

**The Solution: DotBrain**
DotBrain delegates this 'organizing bottleneck' to AI.
- **Zero-Friction Sort:** Drop files into the inbox and AI reads the content, automatically moving them according to the PARA framework.
- **Semantic Structure:** Automatically generates Obsidian-compatible frontmatter and wiki-links to connect context between documents.
- **Self-Healing:** Flattens nested folder structures, repairs broken links and missing frontmatter, and detects duplicate files via SHA256 hashing for merging.
- **Reliability:** Supports both Claude and Gemini simultaneously, with an automatic fallback safety net — if one fails, the other takes over.

---

## 🚀 Quick Start
Install with a single line in your terminal.
```bash
npx dotbrain
```

When `·‿·` appears in your menu bar, installation is complete. Click the icon to begin onboarding.

> 📖 For detailed usage instructions, see the **[Service Manual (MANUAL.md)](MANUAL.md)**.

> **Requirements:** macOS 13 (Ventura) or later / Node.js 18+ (when using npx) / Claude subscription (Pro/Max) + Claude CLI as default. [Claude API key](https://console.anthropic.com/settings/keys) or [Gemini API key](https://aistudio.google.com/apikey) also supported.

<details>
<summary><b>Build from source</b></summary>

```bash
git clone https://github.com/DinN0000/DotBrain.git ~/Developer/DotBrain
cd ~/Developer/DotBrain
swift build -c release
# Binary: .build/release/DotBrain
```
</details>

---

## ⚙️ How it Works

### Inbox Processing

Drop files into the inbox and they are processed automatically:

```
Add file to _Inbox/ (drag & drop)
    ↓
Content extraction (text/PDF/image/PPTX/XLSX/DOCX)
    ↓
Two-stage AI classification
    ├── Stage 1: Fast (Haiku/Flash) — batch classification
    └── Stage 2: Precise (Sonnet/Pro) — only for low-confidence files
    ↓
File move + frontmatter injection + related note linking + MOC update
    ↓
Classification complete
```

### AI Classification Strategy

| Provider | Stage 1 (Fast) | Stage 2 (Precise) | Cost |
|----------|----------------|-------------------|------|
| **Claude CLI (recommended)** | Haiku | Sonnet | Uses subscription tokens |
| Claude API | Haiku 4.5 | Sonnet 4.5 | ~$0.002/file |
| Gemini API | Flash 2.5 | Pro 2.5 | Possible within free tier |

Most files finish at Stage 1. Claude CLI uses subscription tokens, so there is no additional API cost.

### Folder Reorganization

AI re-organizes existing PARA folders:

```
Select folder
    ↓
Flatten — move content from nested subfolders to top level (SHA256 deduplication)
    ↓
AI reclassification
    ├── Correct location → update frontmatter
    └── Wrong location → automatically move to correct folder
```

### Vault Management

- **PARA Management** — move folders between categories, create projects, auto-organize per folder
- **Full Reorganization** — AI scans the entire vault and suggests misclassification moves (executed after user approval)
- **Vault Audit** — automatically fixes broken links and missing frontmatter

### Frontmatter Standardization

DotBrain applies a standard specification that both humans and AI can understand to every note.

```yaml
---
para: project
tags: [defi, ethereum, blockchain]
created: 2026-02-11
status: active
summary: "DeFi system architecture project"
source: import
project: MyProject
---
```

| Field | Description |
|-------|-------------|
| `para` | PARA category (Project/Area/Resource/Archive) |
| `tags` | Auto-tagged based on file content |
| `created` | Original creation date (existing values preserved) |
| `status` | active / draft / completed / on-hold |
| `summary` | One-line summary of the file content |
| `source` | original / meeting / literature / import |
| `project` | Associated project name |
| `area` | Associated Area name |
| `projects` | List of associated projects (for documents within an Area) |
| `file` | Original filename (for non-text files) |

---

## 📂 Folder Structure
The PKM (Personal Knowledge Management) folder structure managed by DotBrain.

```
PKM Root/
├── _Inbox/                          ← Drop files here
├── _Assets/                         ← Central storage for binary files
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
└── 4_Archive/
    └── 2024-Q1/
        └── quarterly-report.md
```

## 🛠 Technical Details

### Supported File Formats

| Format | Extraction Method | Extracted Content |
|--------|-------------------|-------------------|
| `.md`, `.txt`, etc. | Direct read | Full text |
| `.pdf` | PDFKit | Text + page count/author/title |
| `.docx` | ZIPFoundation + XML | Body text + metadata |
| `.pptx` | ZIPFoundation + XML | Slide text |
| `.xlsx` | ZIPFoundation + XML | Cell data |
| `.jpg`, `.png`, `.heic`, etc. | ImageIO | EXIF (date taken, camera, GPS) |
| Folder | Internal file traversal | Aggregated content of contained files |

### Duplicate Detection

| Scenario | Detection Method | Action |
|----------|------------------|--------|
| Same content, different name | SHA256 body hash (excluding frontmatter) | Merge tags → delete |
| Same content binary | SHA256 hash (≤500MB) or size+modified date (>500MB) | Merge tags → delete |
| Same name, different content | Filename comparison | Prompt user for confirmation |
| Name conflict with index note | `foldername.md` comparison | Prompt user for confirmation |

### Tech Stack

- **Swift 5.9** + SwiftUI + Combine
- **macOS menu bar app** — `NSStatusItem` + `NSPopover`
- **AI** — Claude CLI (subscription, recommended) / Claude API / Gemini API — triple provider, automatic fallback
- **Dependencies** — ZIPFoundation (DOCX/PPTX/XLSX processing)
- **Security** — Claude CLI requires no API key (subscription auth). When using API keys, stored in AES-GCM encrypted files with device binding (hardware UUID + HKDF)
- **Reliability** — Exponential backoff retry, provider fallback, path traversal protection

---

## 🎨 Design Philosophy

### Making your context readable by AI

AI makes judgments based on the material it's given.
But in most cases, users have to manually select and hand over files.

- Passing individual files allows per-file analysis, but connecting context across documents is difficult
- Passing everything at once hits context limits
- The same background explanation must be repeated every conversation

For AI to leverage a user's entire knowledge, it needs a **structured knowledge base that AI can explore on its own**.

DotBrain receives files, classifies them, assigns tags, and generates relationships between documents.
When any AI tool opens this knowledge base, the structure alone enables it to navigate relevant context.

### Frontmatter — Metadata for both humans and AI

Every file receives YAML frontmatter.

```yaml
---
para: project
tags: [defi, ethereum, blockchain]
summary: "DeFi system architecture project"
---
```

For humans, it's metadata that's immediately visible in Obsidian and directly editable.
For AI, it's structured data where classification, search, and summary information can be extracted in a single parse.

**AI handles generation and management, while humans retain editing authority.**
Users are freed from the labor of manually filling in metadata, and AI gets consistently formatted data.

### Wiki-links + MOC — A table of contents for humans, an index for AI

Each folder gets an automatically generated MOC (Map of Content).
An MOC is an index note that lists all documents in a folder with `[[wiki-links]]` alongside **a summary of each document**.

```markdown
# MyProject

> System architecture project. Covers from architecture design to validation.

## Documents
- [[Architecture Design]] — Full system architecture design document
- [[Meeting Notes 0211]] — 2nd requirements meeting. API integration approach finalized
- [[Audit Report]] — Static analysis results and vulnerability remediation details
```

For humans, these links are a clickable table of contents, and the summaries are guides that convey content without opening each file.
For AI, these links are graph edges, and the summaries are context for determining exploration priority.
Which document to read first, which document is relevant to the current question — all of this can be determined from the MOC alone.

**The same structure works as navigation for humans and as an exploration graph for AI.**

### AI Companion Files — Making your vault AI-ready

DotBrain automatically generates AI companion files like `CLAUDE.md`, `AGENTS.md`, and `.cursorrules` in your vault.
With these files in place, AI tools like Claude Code or Cursor can immediately understand the folder structure, classification rules, and tag system when they open the vault.

Without reading the entire vault, a single companion file communicates **"this knowledge base is organized like this, and follows these rules."**

During updates, only the content between `<!-- DotBrain:start -->` / `<!-- DotBrain:end -->` markers is refreshed.
Any content users have added outside the markers is preserved.

### Humans define projects, AI handles classification

The PARA framework (Projects, Areas, Resources, Archive) provides the foundational structure for classification.
Within this structure, AI classifies files automatically.

What the user does is **define projects**.
"PoC-Alpha", "Research-Beta", "DotBrain" — only the user knows which projects are in progress.
Once projects are set, AI determines where each file belongs.

---

Once the knowledge base is structured, AI goes beyond simple Q&A.
It explores related materials on its own, discovers patterns in connections between documents, and reasons on top of the user's context.

DotBrain creates that starting point.

---

## ❓ Troubleshooting

<details>
<summary><b>"Unidentified developer" / "Damaged and can't be opened"</b></summary>

```bash
xattr -cr ~/Applications/DotBrain.app
```

Or: Go to **System Settings → Privacy & Security** → click "Open Anyway".
</details>

<details>
<summary><b>Folder access permission popup</b></summary>

On first launch, you must select **"Allow"** when prompted for PKM folder access permission.
</details>

<details>
<summary><b>Icon not visible in the menu bar</b></summary>

This may be due to insufficient menu bar space. Remove other icons by ⌘+dragging them away, or use Bartender/Ice to manage them.
</details>

<details>
<summary><b>Uninstall</b></summary>

```bash
npx dotbrain --uninstall
```

Or manually:
```bash
pkill -f DotBrain 2>/dev/null; \
launchctl bootout gui/$(id -u)/com.dotbrain.app 2>/dev/null; \
rm -f ~/Library/LaunchAgents/com.dotbrain.app.plist; \
rm -rf ~/Applications/DotBrain.app; \
echo "Uninstall complete"
```

</details>

---

## 💬 So, what is DotBrain?

> DotBrain is an AI-powered PKM app that runs in the macOS menu bar.
> Drop files into the inbox and AI analyzes the content, automatically classifying them into the PARA structure, writing frontmatter, linking related notes, and generating MOCs — all handled for you.
>
> **It eliminates the time spent organizing notes.** Deciding where to put things, adding tags, finding and linking related documents — AI does all of that, so users only need to write and read. Instead of a note app where things pile up and never get revisited, everything organizes itself so you actually come back and use it.
>
> And the real key is that **when AI reads a vault organized this way, its performance dramatically improves.** Thanks to structured frontmatter, MOCs, and related note links, AI grasps context accurately and finds the documents it needs quickly. The better your knowledge is organized, the smarter AI works — that's the feedback loop.
>
> It's Obsidian-compatible, and automatically embeds agents for Claude Code and Cursor, so a single command like "audit my vault" runs a full health check.

---

<p align="center">
Made by Hwaa
</p>
