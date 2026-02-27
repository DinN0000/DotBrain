# context-builder-refactor Design Document

> **Summary**: ProjectContextBuilder 5개 함수를 note-index.json 기반으로 전환하여 디스크 I/O 제거, 태그 누락 해소, 컨텍스트 품질 개선
>
> **Project**: DotBrain
> **Date**: 2026-02-27
> **Status**: Draft
> **Planning Doc**: [context-builder-refactor.plan.md](../../01-plan/features/context-builder-refactor.plan.md)

---

## 1. Overview

### 1.1 Design Goals

- ProjectContextBuilder의 모든 함수를 note-index.json 기반으로 전환 (CLAUDE.md 규칙 준수)
- 분류 시 디스크 I/O를 index 로드 1회로 최소화
- 태그 전수 집계로 buildTagVocabulary 품질 개선 (prefix(5) 샘플링 제거)
- 폴더별 tags/summary 제공으로 subfolderContext 보강
- 죽은 코드 100줄+ 삭제 (extractScope, fallback 3개 함수)
- 프로젝트 삭제/이동 시 Area projects 필드 정리

### 1.2 Design Principles

- Index-first, disk-fallback: index 없으면 기존 디스크 스캔으로 graceful degradation
- Classifier 프롬프트 호환: enriched 구조가 기존 프롬프트 지시문과 매끄럽게 연결
- 최소 변경: NoteIndex 스키마는 optional 필드 추가만 (하위 호환)
- 공유 로더: PKMPathManager에 loadNoteIndex() 추가하여 중복 제거

---

## 2. Architecture

### 2.1 변경 전 데이터 흐름

```
InboxProcessor.classifyFiles()
    |
    v
ProjectContextBuilder (5 functions, all disk scan)
    ├── buildProjectContext()      ← 디스크: 프로젝트 폴더 순회 + 인덱스 노트 읽기
    ├── buildAreaContext()         ← 디스크: Area 폴더 순회 + 인덱스 노트 읽기
    ├── buildSubfolderContext()    ← 디스크: PKMPathManager.existingSubfolders()
    ├── buildWeightedContext()     ← 디스크: 루트 인덱스 노트 + fallback 3개 함수
    └── buildTagVocabulary()      ← 디스크: 폴더당 5개 파일만 샘플링
    |
    v
Classifier.classifyFiles(projectContext:, subfolderContext:, weightedContext:, ...)
```

### 2.2 변경 후 데이터 흐름

```
InboxProcessor.classifyFiles()
    |
    v
PKMPathManager.loadNoteIndex()   ← 1회 로드 (shared)
    |
    v
ProjectContextBuilder(pkmRoot:, noteIndex:)  ← index 주입
    ├── buildProjectContext()      ← index.folders + index.notes (area 필드)
    ├── buildAreaContext()         ← index.notes에서 area별 프로젝트 집계
    ├── buildSubfolderContext()    ← 디스크(폴더 목록) + index.folders(tags/summary)
    ├── buildWeightedContext()     ← 루트 인덱스 노트 body만 (fallback 삭제)
    └── buildTagVocabulary()      ← index.notes 전체 태그 집계
    |
    v
Classifier.classifyFiles(...)    ← subfolderContext JSON 구조 변경 반영
```

### 2.3 Index 공유 로더

현재 4곳에서 독립적으로 note-index.json을 로드:
- VaultSearcher.loadNoteIndex()
- ContextMapBuilder.build()
- SemanticLinker.buildNoteIndexFromIndex()
- AppState.detectManualMoves()

PKMPathManager에 공유 로더 추가:

```swift
extension PKMPathManager {
    /// Load note-index.json, returning nil if missing or corrupt
    func loadNoteIndex() -> NoteIndex? {
        guard let data = FileManager.default.contents(atPath: noteIndexPath) else { return nil }
        return try? JSONDecoder().decode(NoteIndex.self, from: data)
    }
}
```

ProjectContextBuilder에서 호출자가 index를 주입하도록 변경:

```swift
struct ProjectContextBuilder {
    let pkmRoot: String
    let noteIndex: NoteIndex?  // NEW: 외부에서 주입

    private var pathManager: PKMPathManager { PKMPathManager(root: pkmRoot) }
}
```

기존 4곳의 독립 로더는 이번 스코프에서 변경하지 않음 (후속 작업).

---

## 3. Detailed Design

### 3.1 FR-06: NoteIndexEntry에 area 필드 추가

**변경 파일**: `Sources/Services/NoteIndexGenerator.swift`

현재 NoteIndexEntry:
```swift
struct NoteIndexEntry: Codable, Sendable {
    let path: String
    let folder: String
    let para: String
    let tags: [String]
    let summary: String
    let project: String?
    let status: String?
}
```

변경 후:
```swift
struct NoteIndexEntry: Codable, Sendable {
    let path: String
    let folder: String
    let para: String
    let tags: [String]
    let summary: String
    let project: String?
    let status: String?
    let area: String?  // NEW
}
```

`scanFolder()` 변경 (line 195):
```swift
let noteEntry = NoteIndexEntry(
    path: relNotePath,
    folder: relFolder,
    para: para.rawValue,
    tags: frontmatter.tags,
    summary: frontmatter.summary ?? "",
    project: frontmatter.project,
    status: frontmatter.status?.rawValue,
    area: frontmatter.area  // NEW
)
```

**하위 호환**: area는 optional이므로 기존 JSON 파싱 시 nil로 처리됨. version 변경 불필요.

---

### 3.2 FR-01: buildTagVocabulary() Index 전환

**변경 파일**: `Sources/Pipeline/ProjectContextBuilder.swift`

현재 문제:
- 폴더당 `prefix(5)` 파일만 샘플링 → 태그 90%+ 손실
- 전체 PARA 폴더 순회 → 수십~수백 파일 I/O

변경 후:
```swift
func buildTagVocabulary() -> String {
    // Index-first: 전체 노트 태그 집계
    if let index = noteIndex {
        var tagCounts: [String: Int] = [:]
        for (_, note) in index.notes {
            for tag in note.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        guard !tagCounts.isEmpty else { return "[]" }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(50).map { $0.key }
        if let data = try? JSONSerialization.data(withJSONObject: topTags, options: []),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }

    // Disk fallback: 기존 로직 유지 (prefix(5) 포함)
    return buildTagVocabularyFromDisk()
}
```

기존 `buildTagVocabulary()` 본문은 `private func buildTagVocabularyFromDisk()` 으로 이동.

---

### 3.3 FR-03: buildProjectContext() Index 전환 + extractScope 삭제

**변경 파일**: `Sources/Pipeline/ProjectContextBuilder.swift`

현재: 프로젝트 폴더 순회 → 인덱스 노트 읽기 → frontmatter + body 파싱

변경 후:
```swift
func buildProjectContext() -> String {
    // Index-first
    if let index = noteIndex {
        var lines: [String] = []
        for (folderKey, folder) in index.folders where folder.para == "project" {
            let name = (folderKey as NSString).lastPathComponent
            let summary = folder.summary
            let tags = folder.tags.isEmpty ? "" : folder.tags.joined(separator: ", ")

            // area 정보: 해당 폴더의 노트 중 area 필드가 있는 것에서 추출
            let areaValue = index.notes.values
                .first(where: { $0.folder == folderKey && $0.area != nil })?.area
            let areaStr = areaValue.map { " (Area: \($0))" } ?? ""

            lines.append("- \(name): \(summary) [\(tags)]\(areaStr)")
        }
        return lines.isEmpty ? "활성 프로젝트 없음" : lines.joined(separator: "\n")
    }

    // Disk fallback
    return buildProjectContextFromDisk()
}
```

**삭제 대상**:
- `extractScope(from:)` — 분류기 프롬프트에서 scope 참조하지 않음. buildProjectContext()에서만 호출되며, index 전환 후 불필요.
- disk fallback에서도 extractScope 호출 제거 (summary + tags만으로 충분)

---

### 3.4 FR-02: buildSubfolderContext() 보강 + Classifier 프롬프트 수정

**변경 파일**: `Sources/Pipeline/ProjectContextBuilder.swift`, `Sources/Services/Claude/Classifier.swift`

#### 3.4.1 buildSubfolderContext() 변경

현재 출력:
```json
{"area":["Dev","Health"],"resource":["Swift","Infra"]}
```

변경 후 출력:
```json
{
  "area": [
    {"name":"Dev","tags":["swift","infra"],"summary":"개발 관련 자료","noteCount":5},
    {"name":"Health","tags":["운동","식단"],"summary":"건강 관리","noteCount":3}
  ],
  "resource": [
    {"name":"Swift","tags":["ios","swiftui"],"summary":"Swift 개발 참고자료","noteCount":8}
  ]
}
```

구현:
```swift
func buildSubfolderContext() -> String {
    // 1. 디스크에서 폴더 목록 (빈 폴더 포함)
    let subfolders = pathManager.existingSubfolders()

    // 2. Enriched 구조 생성
    var dict: [String: [[String: Any]]] = [:]

    for (category, folderNames) in subfolders {
        guard !folderNames.isEmpty else { continue }
        let paraPrefix: String
        switch category {
        case "area": paraPrefix = "2_Area"
        case "resource": paraPrefix = "3_Resource"
        case "archive": paraPrefix = "4_Archive"
        default: continue
        }

        var entries: [[String: Any]] = []
        for name in folderNames.sorted() {
            var entry: [String: Any] = ["name": name]

            // Index에서 tags/summary 보강
            if let index = noteIndex {
                let folderKey = "\(paraPrefix)/\(name)"
                if let folderInfo = index.folders[folderKey] {
                    if !folderInfo.tags.isEmpty {
                        entry["tags"] = folderInfo.tags
                    }
                    if !folderInfo.summary.isEmpty {
                        entry["summary"] = folderInfo.summary
                    }
                }
                // noteCount 집계
                let count = index.notes.values.filter { $0.folder == folderKey }.count
                if count > 0 {
                    entry["noteCount"] = count
                }
            }

            entries.append(entry)
        }
        dict[category] = entries
    }

    guard !dict.isEmpty else { return "{}" }
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]),
       let json = String(data: data, encoding: .utf8) {
        return json
    }
    return "{}"
}
```

#### 3.4.2 Classifier 프롬프트 수정

`Classifier.swift`의 Stage1/Stage2 프롬프트에서 subfolderContext 설명 변경:

현재:
```
## 기존 하위 폴더 (이 목록의 정확한 이름만 사용)
{subfolderContext}
새 폴더가 필요하면 targetFolder에 "NEW:폴더명"을 사용하세요.
```

변경 후:
```
## 기존 하위 폴더 (이 목록의 정확한 이름만 사용)
{subfolderContext}
각 폴더의 name, tags, summary, noteCount를 참고하여 가장 적합한 폴더를 선택하세요.
새 폴더가 필요하면 targetFolder에 "NEW:폴더명"을 사용하세요. 기존 폴더와 비슷한 이름이 있으면 반드시 기존 이름을 사용하세요.
```

---

### 3.5 FR-04: buildWeightedContext() Fallback 삭제

**변경 파일**: `Sources/Pipeline/ProjectContextBuilder.swift`

현재 구조:
1. 루트 인덱스 노트 body 읽기 (유지)
2. body 비면 → `buildCategoryFallback()` → `buildProjectDocuments()` / `buildFolderSummaries()` / `buildArchiveSummary()` (삭제)

변경 후:
```swift
func buildWeightedContext() -> String {
    let categories: [(path: String, label: String, weight: String)] = [
        (pathManager.projectsPath, "Project", "높은 연결 가중치"),
        (pathManager.areaPath, "Area", "중간 연결 가중치"),
        (pathManager.resourcePath, "Resource", "중간 연결 가중치"),
        (pathManager.archivePath, "Archive", "낮은 연결 가중치"),
    ]

    var sections: [String] = []
    for (basePath, label, weight) in categories {
        let categoryName = (basePath as NSString).lastPathComponent
        let mocPath = (basePath as NSString).appendingPathComponent("\(categoryName).md")

        if let content = try? String(contentsOfFile: mocPath, encoding: .utf8) {
            let (_, body) = Frontmatter.parse(markdown: content)
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("### \(label) (\(weight))\n\(trimmed)")
            }
        }
        // No fallback — enriched subfolderContext가 폴더 수준 정보 대체
    }

    return sections.isEmpty ? "" : sections.joined(separator: "\n\n")
}
```

**삭제 대상** (4개 함수, ~100줄):
- `buildCategoryFallback(basePath:label:weight:)` (line 157)
- `buildProjectDocuments()` (line 174)
- `buildFolderSummaries(at:label:)` (line 226)
- `buildArchiveSummary()` (line 347)

**빈 문자열 반환 변경**: fallback 없으면 해당 카테고리 섹션 생략. 다른 context 함수들(projectContext, subfolderContext, areaContext)이 이미 폴더 수준 정보를 커버.

---

### 3.6 FR-05: Area projects 필드 정리

**변경 파일**: `Sources/Services/PARAMover.swift`, `Sources/Services/ProjectManager.swift`

#### 3.6.1 공유 유틸리티 함수

`FrontmatterWriter`에 Area projects 정리 함수 추가:

```swift
extension FrontmatterWriter {
    /// Remove a project name from an Area index note's `projects` field
    static func removeProjectFromArea(
        projectName: String,
        areaName: String,
        pkmRoot: String
    ) {
        let pm = PKMPathManager(root: pkmRoot)
        let areaIndexPath = (pm.areaPath as NSString)
            .appendingPathComponent(areaName)
            .appending("/\(areaName).md")

        guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
        let (var fm, body) = Frontmatter.parse(markdown: content)
        guard var projects = fm.projects, projects.contains(projectName) else { return }

        projects.removeAll { $0 == projectName }
        fm.projects = projects.isEmpty ? nil : projects

        let updated = fm.inject(into: fm.stringify() + "\n" + body)
        try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
    }

    /// Rename a project reference in an Area index note's `projects` field
    static func renameProjectInArea(
        oldName: String,
        newName: String,
        areaName: String,
        pkmRoot: String
    ) {
        let pm = PKMPathManager(root: pkmRoot)
        let areaIndexPath = (pm.areaPath as NSString)
            .appendingPathComponent(areaName)
            .appending("/\(areaName).md")

        guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
        let (var fm, body) = Frontmatter.parse(markdown: content)
        guard var projects = fm.projects, projects.contains(oldName) else { return }

        projects = projects.map { $0 == oldName ? newName : $0 }
        fm.projects = projects

        let updated = fm.inject(into: fm.stringify() + "\n" + body)
        try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
    }
}
```

#### 3.6.2 Area 이름 탐색

프로젝트가 어떤 Area에 속하는지 찾는 방법:
1. **Index-first**: `noteIndex.notes`에서 해당 프로젝트 폴더의 노트 중 `area` 필드가 있는 것 탐색
2. **Disk fallback**: 프로젝트 인덱스 노트의 `frontmatter.area` 읽기
3. **전수 탐색**: 모든 Area 인덱스 노트의 `projects` 필드에서 프로젝트명 검색

```swift
extension FrontmatterWriter {
    /// Find which Area contains a given project name
    static func findAreaForProject(
        projectName: String,
        pkmRoot: String
    ) -> String? {
        let pm = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default

        // 1. 프로젝트 인덱스 노트에서 area 필드 확인
        let projectIndexPath = (pm.projectsPath as NSString)
            .appendingPathComponent(projectName)
            .appending("/\(projectName).md")
        if let content = try? String(contentsOfFile: projectIndexPath, encoding: .utf8) {
            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            if let area = frontmatter.area { return area }
        }

        // 2. 모든 Area 인덱스 노트의 projects 필드 검색
        guard let areas = try? fm.contentsOfDirectory(atPath: pm.areaPath) else { return nil }
        for area in areas {
            guard !area.hasPrefix("."), !area.hasPrefix("_") else { continue }
            let areaIndexPath = (pm.areaPath as NSString)
                .appendingPathComponent(area)
                .appending("/\(area).md")
            guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { continue }
            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            if let projects = frontmatter.projects, projects.contains(projectName) {
                return area
            }
        }
        return nil
    }
}
```

#### 3.6.3 호출 위치 (7곳)

| 파일 | 메서드 | 동작 |
|------|--------|------|
| PARAMover | deleteFolder(name:category:) | project 삭제 시 → removeProjectFromArea |
| PARAMover | moveFolder(name:from:to:) | project 이동 시 → removeProjectFromArea |
| PARAMover | mergeFolder(source:into:category:) | project 병합 시 → removeProjectFromArea (source) |
| PARAMover | renameFolder(oldName:newName:category:) | project 이름 변경 시 → renameProjectInArea |
| ProjectManager | completeProject(name:) | project 완료(아카이브) 시 → removeProjectFromArea |
| ProjectManager | reactivateProject(name:) | project 재활성화 시 → area projects에 다시 추가 (updateAreaProjects 호출) |
| OnboardingView | removeProject(_:) | 온보딩 중 project 제거 시 → removeProjectFromArea |

각 메서드에서 `category == .project` (또는 project 관련 동작) 일 때만 Area 정리 수행.

#### 3.6.4 VaultCheckPipeline 정합성 검증

VaultCheckPipeline Phase 1 (Audit) 이후에 Area projects 정합성 검증 추가:

```swift
// Phase 2.6: Prune stale project references from Area index notes
let existingProjects = Self.collectExistingProjectNames(pm: pm)
Self.pruneStaleAreaProjects(pkmRoot: pkmRoot, existingProjects: existingProjects)
```

존재하지 않는 프로젝트를 Area의 `projects` 필드에서 제거. 실시간 정리 누락 시 다음 볼트 점검에서 보완.

---

## 4. Interface Changes

### 4.1 ProjectContextBuilder Init 변경

```swift
// Before
struct ProjectContextBuilder {
    let pkmRoot: String
}

// After
struct ProjectContextBuilder {
    let pkmRoot: String
    let noteIndex: NoteIndex?  // nil이면 모든 함수가 disk fallback

    init(pkmRoot: String, noteIndex: NoteIndex? = nil) {
        self.pkmRoot = pkmRoot
        self.noteIndex = noteIndex
    }
}
```

### 4.2 호출부 변경

`Sources/Pipeline/InboxProcessor.swift`에서:

```swift
// Before
let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot)

// After
let pm = PKMPathManager(root: pkmRoot)
let noteIndex = pm.loadNoteIndex()
let contextBuilder = ProjectContextBuilder(pkmRoot: pkmRoot, noteIndex: noteIndex)
```

### 4.3 Classifier 프롬프트 subfolderContext 설명

Stage1/Stage2 buildPrompt에서 subfolderContext 안내 문구 1줄 추가 (3.4.2 참조).

---

## 5. Implementation Order

| 순서 | FR | 변경 파일 | 예상 변경량 |
|------|-----|----------|-----------|
| 1 | FR-06 | NoteIndexGenerator.swift | +2줄 (area 필드) |
| 2 | Shared | PKMPathManager.swift | +6줄 (loadNoteIndex) |
| 3 | Init | ProjectContextBuilder.swift, InboxProcessor.swift | +10줄 (noteIndex 주입) |
| 4 | FR-01 | ProjectContextBuilder.swift | +20줄 index, 기존 → fallback 이동 |
| 5 | FR-03 | ProjectContextBuilder.swift | +20줄 index, -20줄 extractScope 삭제 |
| 6 | FR-02 | ProjectContextBuilder.swift, Classifier.swift | +30줄 enriched, 프롬프트 수정 |
| 7 | FR-04 | ProjectContextBuilder.swift | -100줄 (fallback 4개 함수 삭제) |
| 8 | FR-05 | FrontmatterWriter.swift, PARAMover.swift, ProjectManager.swift, OnboardingView.swift, VaultCheckPipeline.swift | +80줄 |

**총 예상**: +70줄, -120줄 = 순 -50줄 감소

---

## 6. Risk & Mitigation

| Risk | Severity | Mitigation |
|------|----------|------------|
| Index 없는 첫 실행 | Low | 모든 함수에 disk fallback 유지. noteIndex == nil이면 기존 동작 |
| enriched subfolderContext로 프롬프트 토큰 증가 | Low | 폴더당 ~50토큰 추가. 볼트 50폴더 기준 ~2500토큰. Stage1 context 제한 대비 여유 |
| buildWeightedContext fallback 삭제로 분류 품질 변동 | Medium | enriched subfolderContext가 폴더 수준 tags/summary 제공하므로 대체. 실제 분류 결과 비교 검증 필요 |
| Area projects 정리 로직 추가로 파일 쓰기 증가 | Low | 프로젝트 삭제/이동 시에만 발생. 1-2회 파일 쓰기 |
| note-index.json과 실제 폴더 불일치 (빈 폴더) | Low | subfolderContext는 디스크에서 폴더 목록 획득 후 index로 보강. 빈 폴더도 name만으로 표시 |

---

## 7. Testing Strategy

1. **빌드 검증**: `swift build` 경고 0개
2. **Index 있는 경우**: 실제 볼트에서 분류 실행 → 기존 대비 결과 비교
3. **Index 없는 경우**: `.meta/note-index.json` 삭제 후 분류 → 기존과 동일 동작 확인
4. **태그 품질**: buildTagVocabulary() 출력 비교 (before: prefix(5) 샘플, after: 전수 집계)
5. **Area 정리**: 프로젝트 삭제 → Area 인덱스 노트의 projects 필드에서 제거 확인
6. **VaultCheck**: 볼트 점검 실행 → stale project references 정리 확인
