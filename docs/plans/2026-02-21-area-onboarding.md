# Area-Project Onboarding Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add Area(domain) registration to onboarding so AI classifier gets Area-Project hierarchy from the first classification.

**Architecture:** Extend onboarding from 5 to 6 steps. Store Area-Project relationships in frontmatter metadata (`area:` field on Project index notes, `projects:` array on Area index notes). Feed Area context to Classifier via ProjectContextBuilder.

**Tech Stack:** SwiftUI (OnboardingView), Frontmatter model, ProjectContextBuilder, Classifier prompt

---

### Task 1: Add `area` and `projects` fields to Frontmatter model

**Files:**
- Modify: `Sources/Models/Frontmatter.swift`

**Step 1: Add fields to struct**

In `Frontmatter` struct (line 32), add two fields after `project`:

```swift
var area: String?
var projects: [String]?
```

**Step 2: Add parsing support**

In `applyScalar` (around line 165), add case:
```swift
case "area": fm.area = value
```

In `applyValue` (around line 176), add case:
```swift
case "projects": fm.projects = array
```

**Step 3: Add serialization support**

In `stringify()` (around line 243), after the `project` block add:
```swift
if let area = area {
    lines.append("area: \(Frontmatter.escapeYAML(area))")
}
if let projects = projects, !projects.isEmpty {
    let escaped = projects.map { "\"\(Frontmatter.escapeYAML($0))\"" }
    lines.append("projects: [\(escaped.joined(separator: ", "))]")
}
```

**Step 4: Add `createDefault` variant for Area**

In `Frontmatter` extension or static methods, no change needed — `createIndexNote` in FrontmatterWriter already accepts `para: .area`. The `area` and `projects` fields will be set by the caller when creating index notes.

**Step 5: Build and verify**

Run: `swift build`
Expected: Build succeeds with no errors.

**Step 6: Commit**

```
git add Sources/Models/Frontmatter.swift
git commit -m "feat: add area and projects fields to Frontmatter model"
```

---

### Task 2: Update FrontmatterWriter for Area index notes

**Files:**
- Modify: `Sources/Services/FileSystem/FrontmatterWriter.swift`

**Step 1: Extend `createIndexNote` to accept optional area and projects**

Change signature:
```swift
static func createIndexNote(
    folderName: String,
    para: PARACategory,
    description: String = "",
    area: String? = nil,
    projects: [String]? = nil
) -> String {
    var fm = Frontmatter.createDefault(
        para: para,
        tags: [],
        summary: description,
        source: .original
    )
    fm.area = area
    fm.projects = projects

    return """
    \(fm.stringify())

    ## 포함된 노트

    """
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: Build succeeds. Existing callers use default nil values, no breakage.

**Step 3: Commit**

```
git add Sources/Services/FileSystem/FrontmatterWriter.swift
git commit -m "feat: extend createIndexNote with area and projects fields"
```

---

### Task 3: Add Area step to OnboardingView (Step 2: Domain registration)

**Files:**
- Modify: `Sources/UI/OnboardingView.swift`

**Step 1: Update state and step count**

Change `totalSteps` from 5 to 6:
```swift
private let totalSteps = 6
```

Add state for areas:
```swift
@State private var areas: [String] = []
@State private var newAreaName: String = ""
```

**Step 2: Update step routing in body**

Change the switch to insert areaStep at position 2, shift projectStep to 3:
```swift
switch step {
case 0: welcomeStep
case 1: folderStep
case 2: areaStep          // NEW
case 3: projectStep        // was 2
case 4: providerAndKeyStep // was 3
case 5: trialStep          // was 4
default: trialStep
}
```

**Step 3: Update folderStep's "다음" button**

In folderStep (currently at end of step 1), the goNext call already calls `loadExistingProjects()`. Add `loadExistingAreas()` before it:

```swift
Button(action: {
    if !isStructureReady {
        if !validateAndCreateFolder() { return }
    }
    loadExistingAreas()
    goNext()
}) {
```

**Step 4: Build areaStep view**

Model it after projectStep. Title: "도메인(제품명)을 등록하세요". Description: "지속적으로 관리하는 영역입니다. 프로젝트들을 묶는 상위 카테고리 역할을 합니다."

```swift
private var areaStep: some View {
    VStack(spacing: 0) {
        stepHeader(
            title: "도메인 등록",
            desc: "지속적으로 관리하는 영역입니다.\n프로젝트들을 묶는 상위 카테고리 역할을 합니다."
        )

        Spacer()

        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("예: 제품명, 사업 도메인, 팀 이름 등. 여러 프로젝트가 속하는 상위 영역을 등록하세요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(10)
            .background(Color.blue.opacity(0.05))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.blue.opacity(0.15), lineWidth: 1)
            )
            .cornerRadius(6)

            HStack(spacing: 8) {
                TextField("도메인 이름 입력 후 + 버튼", text: $newAreaName)
                    .textFieldStyle(.roundedBorder)
                    .font(.subheadline)
                    .onSubmit { addArea() }

                Button(action: addArea) {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .disabled(newAreaName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !areas.isEmpty {
                ScrollView {
                    VStack(spacing: 3) {
                        ForEach(areas, id: \.self) { name in
                            HStack(spacing: 8) {
                                Image(systemName: "square.stack.3d.up.fill")
                                    .font(.caption)
                                    .foregroundColor(.green)
                                Text(name)
                                    .font(.subheadline)

                                Spacer()

                                Button(action: { removeArea(name) }) {
                                    Image(systemName: "xmark")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.secondary.opacity(0.05))
                            .cornerRadius(6)
                        }
                    }
                }
                .frame(maxHeight: 90)
            } else {
                Text("건너뛰어도 됩니다. 나중에 추가할 수 있어요.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 24)

        Spacer()

        HStack {
            Button("이전") { goBack() }
                .buttonStyle(.bordered)
                .controlSize(.regular)

            Spacer()

            Button(action: {
                loadExistingProjects()
                goNext()
            }) {
                Text("다음")
                    .frame(minWidth: 80)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(.horizontal, 32)
        .padding(.bottom, 20)
    }
    .padding(.horizontal)
}
```

**Step 5: Add area helper functions**

```swift
private func loadExistingAreas() {
    let pathManager = PKMPathManager(root: appState.pkmRootPath)
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(atPath: pathManager.areaPath) else { return }

    areas = entries.filter { name in
        guard !name.hasPrefix("."), !name.hasPrefix("_") else { return false }
        let fullPath = (pathManager.areaPath as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        return fm.fileExists(atPath: fullPath, isDirectory: &isDir) && isDir.boolValue
    }.sorted()
}

private func addArea() {
    let raw = newAreaName.trimmingCharacters(in: .whitespaces)
    let name = sanitizeProjectName(raw)
    guard !name.isEmpty, !areas.contains(name) else { return }

    let pathManager = PKMPathManager(root: appState.pkmRootPath)
    let areaDir = (pathManager.areaPath as NSString).appendingPathComponent(name)
    guard pathManager.isPathSafe(areaDir) else { return }
    let fm = FileManager.default

    do {
        try fm.createDirectory(atPath: areaDir, withIntermediateDirectories: true)
        let indexPath = (areaDir as NSString).appendingPathComponent("\(name).md")
        if !fm.fileExists(atPath: indexPath) {
            let content = FrontmatterWriter.createIndexNote(
                folderName: name,
                para: .area,
                description: "\(name) 도메인"
            )
            try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }
        areas.append(name)
        areas.sort()
        newAreaName = ""
    } catch {
        NSLog("[OnboardingView] Area 생성 실패: %@", error.localizedDescription)
        newAreaName = ""
    }
}

private func removeArea(_ name: String) {
    let pathManager = PKMPathManager(root: appState.pkmRootPath)
    let areaDir = (pathManager.areaPath as NSString).appendingPathComponent(name)
    try? FileManager.default.trashItem(at: URL(fileURLWithPath: areaDir), resultingItemURL: nil)
    areas.removeAll { $0 == name }
}
```

**Step 6: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 7: Commit**

```
git add Sources/UI/OnboardingView.swift
git commit -m "feat: add Area(domain) registration step to onboarding"
```

---

### Task 4: Extend projectStep with Area picker

**Files:**
- Modify: `Sources/UI/OnboardingView.swift`

**Step 1: Add state for selected area**

```swift
@State private var selectedArea: String = ""
```

**Step 2: Add Area picker to projectStep**

In projectStep, between the TextField HStack and the project list, add a Picker:

```swift
if !areas.isEmpty {
    HStack(spacing: 8) {
        Text("Area:")
            .font(.caption)
            .foregroundColor(.secondary)
        Picker("", selection: $selectedArea) {
            Text("없음").tag("")
            ForEach(areas, id: \.self) { area in
                Text(area).tag(area)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: 150)
    }
}
```

**Step 3: Update addProject to write area metadata**

Modify `addProject()` to pass area to the index note and update the Area's index note:

```swift
private func addProject() {
    let raw = newProjectName.trimmingCharacters(in: .whitespaces)
    let name = sanitizeProjectName(raw)
    guard !name.isEmpty, !projects.contains(name) else { return }

    let pathManager = PKMPathManager(root: appState.pkmRootPath)
    let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(name)
    guard pathManager.isPathSafe(projectDir) else { return }
    let fm = FileManager.default

    let areaName = selectedArea.isEmpty ? nil : selectedArea

    do {
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let indexPath = (projectDir as NSString).appendingPathComponent("\(name).md")
        if !fm.fileExists(atPath: indexPath) {
            let content = FrontmatterWriter.createIndexNote(
                folderName: name,
                para: .project,
                description: "\(name) 프로젝트",
                area: areaName
            )
            try content.write(toFile: indexPath, atomically: true, encoding: .utf8)
        }

        // Update Area index note's projects list
        if let area = areaName {
            updateAreaProjects(area: area, addProject: name)
        }

        projects.append(name)
        projects.sort()
        newProjectName = ""
    } catch {
        NSLog("[OnboardingView] 프로젝트 생성 실패: %@", error.localizedDescription)
        newProjectName = ""
    }
}
```

**Step 4: Add updateAreaProjects helper**

```swift
private func updateAreaProjects(area: String, addProject projectName: String) {
    let pathManager = PKMPathManager(root: appState.pkmRootPath)
    let areaIndexPath = (pathManager.areaPath as NSString)
        .appendingPathComponent(area)
        .appending("/\(area).md")

    guard let content = try? String(contentsOfFile: areaIndexPath, encoding: .utf8) else { return }
    var (fm, body) = Frontmatter.parse(markdown: content)

    var currentProjects = fm.projects ?? []
    if !currentProjects.contains(projectName) {
        currentProjects.append(projectName)
        currentProjects.sort()
    }
    fm.projects = currentProjects

    let updated = fm.stringify() + "\n" + body
    try? updated.write(toFile: areaIndexPath, atomically: true, encoding: .utf8)
}
```

**Step 5: Show area badge in project list**

In the project list ForEach, show area name as a badge. This requires tracking which project belongs to which area. Add a simple dictionary:

```swift
@State private var projectAreas: [String: String] = [:]
```

When adding a project: `projectAreas[name] = areaName ?? ""`

In the project row, after the project name text:
```swift
if let area = projectAreas[name], !area.isEmpty {
    Text(area)
        .font(.caption2)
        .foregroundColor(.green)
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
        .background(Color.green.opacity(0.1))
        .cornerRadius(4)
}
```

**Step 6: Update projectStep skip logic**

The existing projectStep checks `appState.hasAPIKey` to skip to step 4. Update to skip to step 5 (since steps shifted):

```swift
Button(action: {
    if appState.hasAPIKey {
        direction = 1
        step = 5  // was 4
        UserDefaults.standard.set(step, forKey: "onboardingStep")
    } else {
        goNext()
    }
}) {
```

**Step 7: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 8: Commit**

```
git add Sources/UI/OnboardingView.swift
git commit -m "feat: add Area picker to project registration step"
```

---

### Task 5: Extend ProjectContextBuilder with Area context

**Files:**
- Modify: `Sources/Pipeline/ProjectContextBuilder.swift`

**Step 1: Add `buildAreaContext()` method**

```swift
/// Build Area-Project mapping context for classifier prompts
func buildAreaContext() -> String {
    let areaPath = pathManager.areaPath
    let fm = FileManager.default

    guard let entries = try? fm.contentsOfDirectory(atPath: areaPath) else {
        return ""
    }

    var lines: [String] = []

    for entry in entries.sorted() {
        guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
        let areaDir = (areaPath as NSString).appendingPathComponent(entry)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: areaDir, isDirectory: &isDir), isDir.boolValue else { continue }
        guard pathManager.isPathSafe(areaDir) else { continue }

        let indexPath = (areaDir as NSString).appendingPathComponent("\(entry).md")
        var projectList = ""
        if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            if let projects = frontmatter.projects, !projects.isEmpty {
                projectList = projects.joined(separator: ", ")
            }
        }
        let detail = projectList.isEmpty ? "(프로젝트 없음)" : projectList
        lines.append("- \(entry): \(detail)")
    }

    return lines.isEmpty ? "" : lines.joined(separator: "\n")
}
```

**Step 2: Update `buildProjectContext()` to include area info**

In `buildProjectContext()`, read the `area` field from project index notes and append it:

Change line 36 from:
```swift
lines.append("- \(entry): \(summary) [\(tags)]")
```
to:
```swift
let areaStr = frontmatter.area.map { " (Area: \($0))" } ?? ""
lines.append("- \(entry): \(summary) [\(tags)]\(areaStr)")
```

And for the no-content case (line 38):
```swift
lines.append("- \(entry)")
```
stays as-is (no area info available without reading the index note).

**Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 4: Commit**

```
git add Sources/Pipeline/ProjectContextBuilder.swift
git commit -m "feat: add Area context building to ProjectContextBuilder"
```

---

### Task 6: Feed Area context to Classifier prompt

**Files:**
- Modify: `Sources/Services/Claude/Classifier.swift`

**Step 1: Add areaContext parameter to classify methods**

Add `areaContext: String` parameter to `classifyFiles`, `classifyStage1`, `classifyStage2`, and `buildStage1Prompt`. Thread it through from `classifyFiles` down to prompt builder.

In `classifyFiles`:
```swift
func classifyFiles(
    _ inputs: [ClassifyInput],
    projectContext: String,
    subfolderContext: String,
    projectNames: [String],
    weightedContext: String,
    areaContext: String = "",        // NEW
    tagVocabulary: String = "[]",
    onProgress: ((Double, String) -> Void)? = nil
) async throws -> [ClassifyResult] {
```

Thread `areaContext` through to `classifyStage1` and into `buildStage1Prompt`.

**Step 2: Insert Area context into Stage 1 prompt**

In `buildStage1Prompt`, after the `## 활성 프로젝트 목록` section, add:

```swift
let areaSection = areaContext.isEmpty ? "" : """

## Area(도메인) 목록
아래 등록된 도메인과 소속 프로젝트를 참고하세요. Area는 여러 프로젝트를 묶는 상위 영역입니다.
\(areaContext)

"""
```

Insert `\(areaSection)` in the prompt string after the project context section.

**Step 3: Strengthen area classification rule**

In the classification rules table, update the area row:
```
| area | 등록된 도메인 전반의 관리/운영 문서. 특정 프로젝트에 속하지 않지만 도메인과 관련된 문서 | 도메인 운영, 인프라 관리, 정책 문서 | 관련시만 |
```

**Step 4: Build and verify**

Run: `swift build`
Expected: Build succeeds.

**Step 5: Commit**

```
git add Sources/Services/Claude/Classifier.swift
git commit -m "feat: feed Area context to Classifier prompt"
```

---

### Task 7: Update all Classifier callers to pass areaContext

**Files:**
- Modify: `Sources/Pipeline/InboxProcessor.swift`
- Modify: `Sources/Pipeline/VaultReorganizer.swift`

**Step 1: Update InboxProcessor**

In `process()`, after `let tagVocabulary = ...` (around line 44), add:
```swift
let areaContext = contextBuilder.buildAreaContext()
```

Pass it to `classifier.classifyFiles`:
```swift
let classifications = try await classifier.classifyFiles(
    inputs,
    projectContext: projectContext,
    subfolderContext: subfolderContext,
    projectNames: projectNames,
    weightedContext: weightedContext,
    areaContext: areaContext,
    tagVocabulary: tagVocabulary,
    ...
)
```

**Step 2: Update VaultReorganizer**

In `scan()`, after `let weightedContext = ...` (around line 92), add:
```swift
let areaContext = contextBuilder.buildAreaContext()
```

Pass it to `classifier.classifyFiles`:
```swift
let classifications = try await classifier.classifyFiles(
    inputs,
    projectContext: projectContext,
    subfolderContext: subfolderContext,
    projectNames: projectNames,
    weightedContext: weightedContext,
    areaContext: areaContext,
    ...
)
```

**Step 3: Build and verify**

Run: `swift build`
Expected: Build succeeds with zero warnings.

**Step 4: Commit**

```
git add Sources/Pipeline/InboxProcessor.swift Sources/Pipeline/VaultReorganizer.swift
git commit -m "feat: pass areaContext to Classifier from InboxProcessor and VaultReorganizer"
```
