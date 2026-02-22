# Pipeline Optimization Design Document

> **Summary**: FR-01~04 구현을 위한 파일별 정확한 코드 변경 설계
>
> **Project**: DotBrain
> **Author**: hwai
> **Date**: 2026-02-18
> **Status**: Draft
> **Planning Doc**: [pipeline-optimization.plan.md](./pipeline-optimization.plan.md)

---

## 1. Overview

### 1.1 Design Goals

- FR-01: 옵션 버그 수정 + relatedNotes 유실 수정
- FR-02: Stage 1 분류 정확도 향상, API 비용 절감
- FR-03/04: Context Build I/O 50+ → 4 파일로 축소

### 1.2 Design Principles

- 기존 파이프라인 흐름 유지 (함수 시그니처 변경 최소화)
- Fallback 보장 (루트 MOC 없으면 기존 방식)
- 기존 테스트/UI 코드에 영향 주지 않음

---

## 2. FR-01: Area 옵션 + relatedNotes 유실 수정

### 2.1 파일: `Sources/Pipeline/InboxProcessor.swift`

#### 변경 A: `generateUnmatchedProjectOptions()` (lines 371-410)

**Before:**
```swift
private func generateUnmatchedProjectOptions(
    for base: ClassifyResult,
    projectNames: [String]
) -> [ClassifyResult] {
    var options: [ClassifyResult] = []

    // Option 1: Resource (safe fallback)
    options.append(ClassifyResult(
        para: .resource,
        tags: base.tags,
        summary: base.summary,
        targetFolder: base.targetFolder,
        project: nil,
        confidence: 0.7
    ))

    // Option 2: Archive (completed project)
    options.append(ClassifyResult(
        para: .archive,
        tags: base.tags,
        summary: base.summary,
        targetFolder: base.suggestedProject ?? "",
        project: nil,
        confidence: 0.5
    ))

    // Option 3: Existing projects (top 3, in case fuzzy match was too strict)
    for projectName in projectNames.prefix(3) {
        options.append(ClassifyResult(
            para: .project,
            tags: base.tags,
            summary: base.summary,
            targetFolder: "",
            project: projectName,
            confidence: 0.5
        ))
    }

    return options
}
```

**After:**
```swift
private func generateUnmatchedProjectOptions(
    for base: ClassifyResult,
    projectNames: [String]
) -> [ClassifyResult] {
    var options: [ClassifyResult] = []

    // Option 1: Resource (safe fallback)
    options.append(ClassifyResult(
        para: .resource,
        tags: base.tags,
        summary: base.summary,
        targetFolder: base.targetFolder,
        project: nil,
        confidence: 0.7,
        relatedNotes: base.relatedNotes
    ))

    // Option 2: Area (ongoing responsibility)
    options.append(ClassifyResult(
        para: .area,
        tags: base.tags,
        summary: base.summary,
        targetFolder: base.targetFolder,
        project: nil,
        confidence: 0.6,
        relatedNotes: base.relatedNotes
    ))

    // Option 3: Archive (completed/inactive)
    options.append(ClassifyResult(
        para: .archive,
        tags: base.tags,
        summary: base.summary,
        targetFolder: base.suggestedProject ?? "",
        project: nil,
        confidence: 0.5,
        relatedNotes: base.relatedNotes
    ))

    return options
}
```

**변경 요약**:
- 기존 프로젝트 옵션(Option 3 루프) 제거
- Area 옵션 추가 (Resource 뒤, Archive 앞)
- 모든 옵션에 `relatedNotes: base.relatedNotes` 전달
- `projectNames` 파라미터는 시그니처에 유지 (호출부 변경 불필요)

#### 변경 B: `generateOptions()` (lines 413-431)

**Before:**
```swift
private func generateOptions(for base: ClassifyResult, projectNames: [String]) -> [ClassifyResult] {
    var options: [ClassifyResult] = [base]

    for category in PARACategory.allCases where category != base.para {
        var alt = base
        alt.confidence = 0.5
        options.append(ClassifyResult(
            para: category,
            tags: base.tags,
            summary: base.summary,
            targetFolder: base.targetFolder,
            project: category == .project ? projectNames.first : nil,
            confidence: 0.5
        ))
    }

    return options
}
```

**After:**
```swift
private func generateOptions(for base: ClassifyResult, projectNames: [String]) -> [ClassifyResult] {
    var options: [ClassifyResult] = [base]

    for category in PARACategory.allCases where category != base.para {
        options.append(ClassifyResult(
            para: category,
            tags: base.tags,
            summary: base.summary,
            targetFolder: base.targetFolder,
            project: category == .project ? projectNames.first : nil,
            confidence: 0.5,
            relatedNotes: base.relatedNotes
        ))
    }

    return options
}
```

**변경 요약**:
- 미사용 `var alt = base` 제거
- 대안 옵션에 `relatedNotes: base.relatedNotes` 추가
- 첫 번째 옵션 `[base]`는 이미 relatedNotes 포함 (변경 불필요)

#### 변경 C: `ClassifyResult` init 호환성 확인

`ClassifyResult`의 `relatedNotes`는 기본값 `[]`이 있으므로 기존 호출부 변경 불필요:
```swift
var relatedNotes: [RelatedNote] = []  // line 17 -- 기본값 있음
```

단, `ClassifyResult` init에서 `relatedNotes`를 받으려면 **memberwise init에 포함되는지 확인** 필요. Swift struct은 모든 stored property를 memberwise init에 포함하되, 기본값이 있으면 생략 가능. `relatedNotes: base.relatedNotes`로 명시 전달 가능.

#### 변경 D: `AppState.createProjectAndClassify()` (lines 495-529)

> 5개 에이전트 검토에서 3개 에이전트가 동시에 지적한 누락 경로.
> 사용자가 "새 프로젝트 생성" 버튼을 눌렀을 때 새 `ClassifyResult`를 생성하면서 `relatedNotes`가 유실되는 버그.

**파일**: `Sources/App/AppState.swift`

**Before:**
```swift
let classification = ClassifyResult(
    para: .project,
    tags: base.tags,
    summary: base.summary,
    targetFolder: "",
    project: projectName,
    confidence: 1.0
)
```

**After:**
```swift
let classification = ClassifyResult(
    para: .project,
    tags: base.tags,
    summary: base.summary,
    targetFolder: "",
    project: projectName,
    confidence: 1.0,
    relatedNotes: base.relatedNotes
)
```

**변경 요약**:
- `generateUnmatchedProjectOptions()`가 options에 `relatedNotes`를 전달해도, 이 함수에서 새 ClassifyResult를 만들면서 다시 유실되는 문제 수정
- FR-01의 relatedNotes 유실 수정 범위를 완성하는 필수 변경

---

## 3. FR-02: Stage 1 프리뷰 제거 (800 -> 5000)

### 3.1 파일: `Sources/Services/Claude/Classifier.swift`

#### 변경 A: 상수 (lines 7-9)

**Before:**
```swift
private let batchSize = 10
private let confidenceThreshold = 0.8
private let previewLength = 800
```

**After:**
```swift
private let batchSize = 5
private let confidenceThreshold = 0.8
// previewLength 삭제
```

#### 변경 B: Stage 1 배치 분류 함수 (lines 183-190)

**Before:**
```swift
let previews = files.map { file in
    let preview = FileContentExtractor.extractPreview(
        from: file.filePath,
        content: file.content,
        maxLength: previewLength
    )
    return (fileName: file.fileName, preview: preview)
}

let prompt = buildStage1Prompt(previews, projectContext: ..., ...)
```

**After:**
```swift
let fileContents = files.map { file in
    (fileName: file.fileName, content: file.content)
}

let prompt = buildStage1Prompt(fileContents, projectContext: ..., ...)
```

#### 변경 C: `buildStage1Prompt` 시그니처 + 본문 (lines 270-278)

**Before:**
```swift
private func buildStage1Prompt(
    _ files: [(fileName: String, preview: String)],
    ...
) -> String {
    let fileList = files.enumerated().map { (i, f) in
        "[\(i)] 파일명: \(f.fileName)\n미리보기: \(f.preview)"
    }.joined(separator: "\n\n")
```

**After:**
```swift
private func buildStage1Prompt(
    _ files: [(fileName: String, content: String)],
    ...
) -> String {
    let fileList = files.enumerated().map { (i, f) in
        "[\(i)] 파일명: \(f.fileName)\n내용: \(f.content)"
    }.joined(separator: "\n\n")
```

**변경 요약**:
- 파라미터 타입: `preview` -> `content`
- 프롬프트 라벨: `"미리보기:"` -> `"내용:"`
- `extractPreview` 호출 제거 (`FileContentExtractor.extractPreview()` 함수 자체는 유지 -- ContextLinker가 사용)

#### 변경 D: content 길이 방어 코드

> `file.content`는 `InboxProcessor.extractContent()`에서 최대 5000자로 추출되지만, 이는 암묵적 계약. `buildStage1Prompt` 내에서 명시적 제한을 추가하여 향후 `maxLength` 기본값 변경 시에도 토큰 폭발을 방지.

**After** (`buildStage1Prompt` 내부):
```swift
let fileList = files.enumerated().map { (i, f) in
    let truncated = String(f.content.prefix(5000))
    return "[\(i)] 파일명: \(f.fileName)\n내용: \(truncated)"
}.joined(separator: "\n\n")
```

#### 변경 E: API 비용 추정값 갱신

**파일**: `Sources/Pipeline/InboxProcessor.swift` (line 109)

**Before:**
```swift
let estimatedCost = Double(inputs.count) * 0.001  // ~$0.001 per file (rough estimate)
```

**After:**
```swift
let estimatedCost = Double(inputs.count) * 0.005  // ~$0.005 per file (Stage 1 full content + Stage 2 fallback)
```

**근거**: 실제 비용은 Claude 기준 ~$0.007/file, Gemini 기준 ~$0.003/file. 중간값 $0.005로 조정.

### 3.2 비용 분석 (프로바이더별)

> 5개 에이전트 검토에서 Plan 문서 비용표가 Gemini best-case에 치우침 지적. 프로바이더별 비용을 명시.

#### 손익분기 조건

- **Claude**: Stage 2 fallback rate가 40% -> 30.5% 이하로 내려가면 순이득
- **Gemini**: Stage 2 fallback rate가 40% -> 35.5% 이하로 내려가면 순이득

#### 200파일 시나리오 비용 비교

| 시나리오 | Claude Before | Claude After | Gemini Before | Gemini After |
|----------|-------------|-------------|--------------|-------------|
| Best (S2: 10%) | $1.85 | $0.98 (-47%) | $0.85 | $0.39 (-54%) |
| Expected (S2: 20%) | $1.85 | $1.40 (-24%) | $0.85 | $0.58 (-32%) |
| Worst (S2: 30%) | $1.85 | $1.82 (-1.4%) | $0.85 | $0.76 (-11%) |

#### 총 분류 시간 추정

- Before: Stage1 ~14s + Stage2 ~81s = **~95s**
- After (expected): Stage1 ~35s + Stage2 ~21s = **~56s** (약 40% 단축)

Stage 1 배치 수 2배 증가(20->40)로 시간이 늘지만, Stage 2 감소(80건->40건)로 총 시간은 단축.

### 3.3 파일: `Sources/Services/AICompanionService.swift` (line 760)

문서 텍스트 업데이트:
```
Before: "파일 미리보기(200자)로 빠르게 분류 (10개씩 배치, 최대 3개 동시)"
After:  "파일 전체 내용(5000자)으로 분류 (5개씩 배치, 최대 3개 동시)"
```

---

## 4. FR-04: 루트 MOC 보강

### 4.1 파일: `Sources/Services/MOCGenerator.swift`

#### 변경: `generateCategoryRootMOC()` (lines 135-191)

**Before (lines 140-164, subfolder 수집):**
```swift
var subfolders: [(name: String, summary: String, fileCount: Int)] = []
// ... name, summary, fileCount만 수집
```

**After (subfolder 수집 + 태그 + 문서 목록):**
```swift
var subfolders: [(name: String, summary: String, fileCount: Int, tags: [String], docs: [(name: String, tags: String, summary: String)])] = []

for entry in entries.sorted() {
    guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
    let entryPath = (basePath as NSString).appendingPathComponent(entry)
    var isDir: ObjCBool = false
    guard fm.fileExists(atPath: entryPath, isDirectory: &isDir), isDir.boolValue else { continue }

    // Read subfolder MOC for summary and tags
    let subMOCPath = (entryPath as NSString).appendingPathComponent("\(entry).md")
    var summary = ""
    var folderTags: [String] = []
    if let content = try? String(contentsOfFile: subMOCPath, encoding: .utf8) {
        let (frontmatter, _) = Frontmatter.parse(markdown: content)
        summary = frontmatter.summary ?? ""
        folderTags = frontmatter.tags
    }

    // Count files
    let subEntries = (try? fm.contentsOfDirectory(atPath: entryPath)) ?? []
    let mdFiles = subEntries.filter {
        !$0.hasPrefix(".") && !$0.hasPrefix("_") && $0.hasSuffix(".md") && $0 != "\(entry).md"
    }
    let fileCount = mdFiles.count

    // For Project category: collect per-document info (max 10)
    var docs: [(name: String, tags: String, summary: String)] = []
    if para == .project {
        for file in mdFiles.sorted().prefix(10) {
            let filePath = (entryPath as NSString).appendingPathComponent(file)
            let baseName = (file as NSString).deletingPathExtension
            if let fileContent = try? String(contentsOfFile: filePath, encoding: .utf8) {
                let (fileFM, _) = Frontmatter.parse(markdown: fileContent)
                let tagStr = fileFM.tags.prefix(3).joined(separator: ", ")
                docs.append((name: baseName, tags: tagStr, summary: fileFM.summary ?? ""))
            }
        }
    }

    subfolders.append((name: entry, summary: summary, fileCount: fileCount, tags: folderTags, docs: docs))
}
```

**Before (lines 168-174, frontmatter):**
```swift
let frontmatter = Frontmatter.createDefault(
    para: para,
    tags: [],
    summary: "\(para.displayName) 카테고리 인덱스 — \(subfolders.count)개 폴더",
    source: .original
)
```

**After (태그 집계):**
```swift
// Aggregate tags from all subfolders
var categoryTags: [String: Int] = [:]
for subfolder in subfolders {
    for tag in subfolder.tags {
        categoryTags[tag, default: 0] += 1
    }
}
let topTags = categoryTags.sorted { $0.value > $1.value }
    .prefix(10).map { $0.key }

let frontmatter = Frontmatter.createDefault(
    para: para,
    tags: topTags,
    summary: "\(para.displayName) 카테고리 인덱스 — \(subfolders.count)개 폴더",
    source: .original
)
```

**Before (lines 176-187, content):**
```swift
var content = frontmatter.stringify()
content += "\n\n# \(categoryName)\n\n"
content += "## 폴더 목록\n\n"

for folder in subfolders {
    let countLabel = folder.fileCount > 0 ? " (\(folder.fileCount)개)" : ""
    if folder.summary.isEmpty {
        content += "- [[\(folder.name)]]\(countLabel)\n"
    } else {
        content += "- [[\(folder.name)]] — \(folder.summary)\(countLabel)\n"
    }
}
```

**After (폴더별 태그 + Project 문서 목록):**
```swift
var content = frontmatter.stringify()
content += "\n\n# \(categoryName)\n\n"
content += "## 폴더 목록\n\n"

for folder in subfolders {
    let countLabel = folder.fileCount > 0 ? " (\(folder.fileCount)개)" : ""
    let tagLabel = folder.tags.isEmpty ? "" : " [\(folder.tags.prefix(5).joined(separator: ", "))]"

    if folder.summary.isEmpty {
        content += "- [[\(folder.name)]]\(tagLabel)\(countLabel)\n"
    } else {
        content += "- [[\(folder.name)]] — \(folder.summary)\(tagLabel)\(countLabel)\n"
    }

    // Project: include per-document listings
    for doc in folder.docs {
        let detail = [doc.tags, doc.summary].filter { !$0.isEmpty }.joined(separator: " — ")
        if detail.isEmpty {
            content += "  - [[\(doc.name)]]\n"
        } else {
            content += "  - [[\(doc.name)]]: \(detail)\n"
        }
    }
}
```

### 4.2 루트 MOC 출력 예시

**1_Project.md:**
```markdown
---
para: project
tags: ["swift", "pkm", "automation", "ai"]
summary: "Project 카테고리 인덱스 — 3개 폴더"
---

# 1_Project

## 폴더 목록

- [[DotBrain]] — PKM 자동 분류 앱 [swift, ai, pkm] (12개)
  - [[architecture]]: swift, design — 시스템 아키텍처 설계
  - [[release-notes]]: changelog — 릴리즈 기록
- [[SideProject]] — 개인 실험 프로젝트 [rust, wasm] (5개)
  - [[prototype]]: rust — 초기 프로토타입
```

**2_Area.md:**
```markdown
---
para: area
tags: ["devops", "learning", "finance"]
summary: "Area 카테고리 인덱스 — 4개 폴더"
---

# 2_Area

## 폴더 목록

- [[DevOps]] — 인프라 운영 [k8s, ci-cd, monitoring] (15개)
- [[Learning]] — 학습 자료 [swift, rust] (8개)
```

---

## 5. FR-03: Context Build 최적화

### 5.1 파일: `Sources/Pipeline/ProjectContextBuilder.swift`

#### 변경: `buildWeightedContext()` (lines 81-109)

기존 함수를 `buildWeightedContextLegacy()`로 rename하고, 새 `buildWeightedContext()`는 루트 MOC를 읽는 방식으로 교체.

**After:**
```swift
/// Build weighted context from root MOC files (optimized: max 4 file reads)
/// Per-category hybrid fallback: uses root MOC when available, legacy for missing categories
func buildWeightedContext() -> String {
    let categories: [(path: String, label: String, emoji: String, weight: String)] = [
        (pathManager.projectsPath, "Project", "🔴", "높은 연결 가중치"),
        (pathManager.areaPath, "Area", "🟡", "중간 연결 가중치"),
        (pathManager.resourcePath, "Resource", "🟡", "중간 연결 가중치"),
        (pathManager.archivePath, "Archive", "⚪", "낮은 연결 가중치"),
    ]

    var sections: [String] = []

    for (basePath, label, emoji, weight) in categories {
        let categoryName = (basePath as NSString).lastPathComponent
        let mocPath = (basePath as NSString).appendingPathComponent("\(categoryName).md")

        // Try root MOC first
        if let content = try? String(contentsOfFile: mocPath, encoding: .utf8) {
            let (_, body) = Frontmatter.parse(markdown: content)
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                sections.append("### \(emoji) \(label) (\(weight))\n\(trimmed)")
                continue
            }
        }

        // Per-category fallback: no root MOC or empty body
        let fallback = buildCategoryFallback(basePath: basePath, label: label, emoji: emoji, weight: weight)
        if !fallback.isEmpty {
            sections.append(fallback)
        }
    }

    return sections.isEmpty ? "기존 문서 없음" : sections.joined(separator: "\n\n")
}

/// Per-category legacy fallback when root MOC is missing or empty
private func buildCategoryFallback(basePath: String, label: String, emoji: String, weight: String) -> String {
    let section: String
    switch label {
    case "Project":
        section = buildProjectDocuments()
    case "Archive":
        section = buildArchiveSummary()
    default:
        section = buildFolderSummaries(at: basePath, label: label)
    }
    guard !section.isEmpty else { return "" }
    return "### \(emoji) \(label) (\(weight))\n\(section)"
}
```

**핵심 설계:**
- **per-category hybrid fallback**: 각 카테고리별로 루트 MOC가 있으면 사용, 없거나 body가 비어있으면 해당 카테고리만 legacy 방식으로 보충
- 기존 all-or-nothing 방식 대비: 4개 중 일부만 MOC가 있어도 정보 손실 없음
- 기존 `buildProjectDocuments()`, `buildFolderSummaries()`, `buildArchiveSummary()`는 private으로 유지
- `buildProjectContext()`, `buildSubfolderContext()`, `extractProjectNames()`는 **변경 없음** (독립 함수)
- FolderReorganizer도 같은 `ProjectContextBuilder` 인스턴스를 사용하므로 **자동 반영**

---

## 6. Implementation Order

| 순서 | FR | 파일 | 예상 변경량 | 의존성 |
|------|-----|------|-----------|--------|
| 1 | FR-01 | InboxProcessor.swift + AppState.swift | ~25줄 수정 | 없음 |
| 2 | FR-02 | Classifier.swift + AICompanionService.swift + InboxProcessor.swift(비용) | ~15줄 수정 | 없음 |
| 3 | FR-04 | MOCGenerator.swift | ~40줄 수정 | 없음 |
| 4 | FR-03 | ProjectContextBuilder.swift | ~40줄 추가/수정 | FR-04 완료 필요 |

---

## 7. Test Plan

### 7.1 Test Cases

| FR | Test | Method |
|----|------|--------|
| FR-01 | Unmatched project 시 Area 옵션 표시 | 수동: project 없는 .md 파일 _Inbox/에 넣고 처리 |
| FR-01 | 사용자 선택 후 relatedNotes가 frontmatter에 주입 | 이동된 파일의 `## Related Notes` 섹션 확인 |
| FR-01 | "새 프로젝트 생성" 후 relatedNotes 유지 | createProjectAndClassify 경로에서 Related Notes 확인 |
| FR-01 | 5가지 확인 경로 전부 relatedNotes 전파 | lowConfidence, unmatchedProject, indexNoteConflict, nameConflict, createProject |
| FR-02 | Stage 2 진입률 감소 | 로그에서 "Stage 2:" 라인 수 비교 (before/after) |
| FR-02 | content 5000자 초과 파일에서 truncation 동작 | 대용량 .md 파일을 _Inbox/에 넣고 처리 |
| FR-02 | `swift build` 경고 0개 | `swift build 2>&1 \| grep warning` |
| FR-03 | 루트 MOC 있는 볼트: 4파일만 읽기 | 로그 또는 디버깅으로 파일 읽기 횟수 확인 |
| FR-03 | 루트 MOC 없는 볼트: 전체 legacy fallback 작동 | 신규 빈 볼트에서 처리 실행 |
| FR-03 | 루트 MOC 일부만 있는 볼트: hybrid fallback | 2개 루트 MOC만 있는 볼트에서 4개 카테고리 컨텍스트 확인 |
| FR-04 | 루트 MOC에 태그, 문서 목록 포함 | 처리 후 1_Project.md 내용 확인 |

---

## Version History

| Version | Date | Changes | Author |
|---------|------|---------|--------|
| 0.1 | 2026-02-18 | Initial draft | hwai |
| 0.2 | 2026-02-18 | 5-agent review 반영: createProjectAndClassify relatedNotes 수정(D), content 길이 방어 코드(D), StatisticsService 비용 갱신(E), per-category hybrid fallback, 프로바이더별 비용 분석, 테스트 케이스 확장 | hwai |
