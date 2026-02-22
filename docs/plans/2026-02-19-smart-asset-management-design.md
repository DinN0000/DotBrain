# Smart Hybrid Asset Management

## Problem

Current binary file handling has structural issues:

1. **Scattered `_Assets/` directories** — each PARA folder creates its own `_Assets/`, leading to 8+ directories
2. **Companion .md for everything** — images get `.png.md` files with only EXIF data (useless)
3. **Path mismatches** — companion .md and actual asset can end up in different PARA categories after reorganization
4. **URL-encoded filenames** — `%EC%8A%AC...` files are hard to manage

## Design

### New Directory Structure

```
DotBrain/
  _Assets/                              # Single centralized location at vault root
    documents/                          # PDF, DOCX, PPTX, XLSX
      Presentation_Second_Meeting.pdf
      PRD_전체.pdf
    images/                             # JPG, PNG, GIF, HEIC, WEBP, BMP
      레이크팰리스.jpg
      슬라이드13.png
  1_Project/
    PoC-신한은행/
      Presentation_Second_Meeting.pdf.md    # Companion with AI summary
  2_Area/
    ...
```

### File Type Routing Rules

| File Type | Storage | Companion .md | Reason |
|-----------|---------|--------------|--------|
| PDF, DOCX, PPTX, XLSX | `_Assets/documents/` | Yes (in PARA folder) | Text extractable, AI summary valuable |
| JPG, PNG, GIF, BMP, WEBP, HEIC | `_Assets/images/` | No | EXIF-only extraction, individual .md is noise |

### Companion .md Format (documents only)

```markdown
---
dotbrain: true
type: document-companion
source_file: "_Assets/documents/filename.pdf"
format: pdf
size_kb: 2340
tags: ["tag1", "tag2"]
para: project
created: 2026-02-19
---

# Document Title

AI-generated summary of extracted text...

## Source
![[_Assets/documents/filename.pdf]]

## Related Notes
- [[ProjectFolder]]
```

### Image Reference Pattern

Images embedded directly in notes without companion .md:
```markdown
![[_Assets/images/photo.jpg]]
```

## Components to Modify

### 1. PKMPathManager
- Add `centralAssetsPath` computed property → `pkmRoot/_Assets/`
- Add `documentsPath` → `_Assets/documents/`
- Add `imagesPath` → `_Assets/images/`
- Ensure directories created during vault initialization

### 2. FileMover
- Route binary files to centralized `_Assets/documents/` or `_Assets/images/` based on extension
- Skip companion .md generation for image files
- Update companion .md `source_file` frontmatter to use centralized path
- Duplicate detection: hash against centralized `_Assets/` (not per-folder)

### 3. InboxProcessor
- When file is image type: classify → move to `_Assets/images/` → no companion .md
- When file is document type: classify → move to `_Assets/documents/` → generate companion .md in PARA folder
- Image files still classified by AI (using EXIF + filename) for folder context, but result used only for related-note linking

### 4. FolderReorganizer
- During reorganization, binary files in `_Assets/documents/` stay put — only companion .md moves
- Update companion .md `source_file` path if PARA category changes
- Skip image files entirely (no companion to reorganize)

### 5. InboxScanner
- No change to file type detection — same extensions supported
- `_Assets/` at vault root added to scan exclusion list

### 6. VaultSearcher
- Continue excluding `_Assets/` from search (already does this)
- Companion .md files are searchable (they're in PARA folders)

## Migration Strategy

For existing vaults transitioning to new structure:

1. **Collect** — find all `*/folder/_Assets/*.pdf|docx|pptx|xlsx` → move to `_Assets/documents/`
2. **Collect** — find all `*/folder/_Assets/*.png|jpg|gif|...` → move to `_Assets/images/`
3. **Delete** — remove orphaned image companion files (`*.png.md`, `*.jpg.md`, etc.)
4. **Update** — rewrite `source_file` in document companion .md frontmatter
5. **Cleanup** — remove empty `*/folder/_Assets/` directories
6. **Verify** — check no broken wikilinks remain

Migration triggered as one-time operation via vault health check or manual command.

## Edge Cases

- **Filename collision in centralized _Assets/** — append UUID suffix if same filename exists from different source folders
- **Large files (>500MB)** — same size+date dedup strategy (no full hash)
- **Companion .md orphaned after asset deletion** — vault health check flags these
- **Mixed folder with both images and documents** — each type routes independently
