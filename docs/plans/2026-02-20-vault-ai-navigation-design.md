# Vault AI Navigation Design

## Summary

DotBrain의 볼트를 AI(Claude Code)가 효율적으로 탐색할 수 있도록 개선한다.
MOC 기반 구조적 링크를 제거하고, JSON 인덱스 + 의미있는 시맨틱 링크 조합으로 대체한다.

## Problem

1. Obsidian 그래프에서 3_Resource가 MOC의 `[[wiki-link]]` 목록으로 인해 허브처럼 폭발
2. Claude Code가 볼트 작업 시 노트 간 연결을 효율적으로 따라갈 수 없음
3. 의미없는 연결(태그 1개 겹침)이 과도하게 생성됨
4. MOC가 사람 탐색에도 AI 탐색에도 실질적 도움이 되지 않음

## Design

### 1. Note Index (`_meta/note-index.json`)

MOCGenerator를 대체하는 NoteIndexGenerator가 볼트 전체 메타데이터를 단일 JSON으로 생성.

```json
{
  "version": 1,
  "updated": "2026-02-20T14:30:00Z",
  "folders": {
    "SCOPE": {
      "path": "2_Area/SCOPE",
      "para": "area",
      "summary": "SCOPE 설계 원칙과 패턴 정리",
      "tags": ["architecture", "design-pattern"]
    }
  },
  "notes": {
    "SCOPE-Overview": {
      "path": "2_Area/SCOPE/SCOPE-Overview.md",
      "folder": "SCOPE",
      "para": "area",
      "tags": ["architecture", "overview"],
      "summary": "SCOPE 아키텍처 전체 구조",
      "project": null,
      "status": "active"
    }
  }
}
```

- Obsidian 그래프에 영향 없음 (JSON 파일)
- 생성 타이밍: InboxProcessor, FolderReorganizer, VaultReorganizer 처리 완료 후
- 갱신 방식: 변경된 노트/폴더만 업데이트 (incremental)

### 2. MOC 생성 중단

- MOCGenerator 제거, 모든 호출 지점(5곳)을 NoteIndexGenerator로 교체
- ContextMapBuilder가 MOC 대신 note-index.json에서 읽도록 변경
- LinkCandidateGenerator에 흐르는 데이터 형태(ContextMapEntry)는 동일
- 기존 볼트의 MOC 파일은 남겨두되 더 이상 갱신하지 않음
- AI 호출 절약: 폴더당 1회 MOC 요약 AI 호출 제거

### 3. Link Quality Improvement

원칙: 진짜 관련있으면 제한 없이 연결. 의미없는 연결만 줄이기.

| Item | Before | After |
|------|--------|-------|
| Tag overlap 1 | +0.5 (enters candidate pool) | Excluded (minimum 2 required) |
| Max links per note | 5 fixed | No limit (AI filter decides) |
| PARA direction bias | None | None (natural connections) |
| AI filter criteria | "practical context relevance" | Strengthened: "does following this link yield new insight?" |
| Reverse link context | "Referenced from X" | Relation-based meaningful description |
| Candidate threshold | score > 0 | score >= 3.0 |

### 4. CLAUDE.md Vault Navigation Rules

```markdown
## Vault Navigation
- Read _meta/note-index.json first for vault structure overview
- Use tags, summary, project from index to identify relevant notes
- Prioritize status: active notes
- Follow [[wiki-links]] in ## Related Notes for context expansion
- Relation type priority: prerequisite > project > reference > related
- Traversal depth: self-determined by task relevance (no fixed limit)
- Resolve note names to file paths via index (no grep needed)
```

## Code Changes

| File | Change |
|------|--------|
| `NoteIndexGenerator.swift` | NEW — index generation/update |
| `MOCGenerator.swift` | REMOVE |
| `ContextMapBuilder.swift` | Read from index instead of MOC files |
| `AppState.swift` | MOCGenerator -> NoteIndexGenerator |
| `InboxProcessor.swift` | MOCGenerator -> NoteIndexGenerator |
| `VaultReorganizer.swift` | MOCGenerator -> NoteIndexGenerator |
| `FolderReorganizer.swift` | MOCGenerator -> NoteIndexGenerator |
| `PARAManageView.swift` | MOCGenerator -> NoteIndexGenerator |
| `LinkCandidateGenerator.swift` | Remove single-tag candidates, raise threshold |
| `LinkAIFilter.swift` | Strengthen prompt, remove max limit |
| `SemanticLinker.swift` | Improve reverse link context |
| `CLAUDE.md` | Add Vault Navigation section |

## Impact on Existing Features

| Feature | Impact |
|---------|--------|
| Inbox classification | None (ProjectContextBuilder unchanged) |
| Semantic linking | Data source change only, logic identical |
| AI Companion | Comment updates only |
| Vault search | None (VaultSearcher unchanged) |
| UI (PARAManageView) | MOC generation -> index update |
| Obsidian graph | MOC hub noise removed, only meaningful connections shown |

## Design Decisions

1. **Index vs MCP server**: Index chosen for zero runtime dependency. MCP can be layered on later if needed.
2. **No link count limits**: Genuine connections should not be artificially constrained.
3. **No PARA direction bias**: Graph shape should emerge naturally from real relationships.
4. **Enriched index (not path-only)**: Including frontmatter fields (tags, summary, status, project) enables AI to make traversal decisions without opening files.
5. **MOC removal**: Index fully replaces MOC's role for both AI navigation and ContextMapBuilder input. MOC added graph noise without proportional value.
