# AI-PKM Feature Parity Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** AI-PKM 분석 결과를 기반으로 DotBrain에 부족한 6개 기능을 구현하여 PKM 완성도를 높인다.

**Architecture:** 기존 DotBrain의 Swift 아키텍처(struct 서비스 + actor AI + ObservableObject AppState)를 유지하면서, 검색/프로젝트 관리/노트 정리 서비스를 추가하고, FrontmatterWriter의 병합 정책을 수정하며, 관련 노트 생성에 AI 의미적 컨텍스트를 도입한다. 각 기능은 독립적으로 구현 가능하며, Task 1부터 순서대로 진행한다.

**Tech Stack:** Swift 5.9, SwiftUI, macOS 13+, ZIPFoundation (기존), Claude/Gemini API (기존 AIService)

---

## Task 1: Frontmatter 병합 정책 수정 (기존값 존중)

**현재 문제:** `FrontmatterWriter.injectFrontmatter()`가 기존 frontmatter를 완전히 교체하고 `created`만 보존한다. 사용자가 수동으로 설정한 tags, summary, source 등이 모두 덮어써진다.

**목표:** 기존 frontmatter 값을 존중하되, 빈 필드만 AI 분류 결과로 채운다. AI-PKM의 "기존 값 존중" 정책과 동일.

**Files:**
- Modify: `Sources/Services/FileSystem/FrontmatterWriter.swift:7-49`

**Step 1: Write the failing test**

테스트 인프라가 없으므로 (SPM executableTarget, 테스트 타겟 없음), 동작 변경을 직접 구현한다.

**Step 2: Modify `injectFrontmatter` to merge instead of replace**

`Sources/Services/FileSystem/FrontmatterWriter.swift`의 `injectFrontmatter` 메서드를 수정한다.

현재 코드 (7-32행):
```swift
static func injectFrontmatter(
    into content: String,
    para: PARACategory,
    tags: [String],
    summary: String,
    source: NoteSource = .import,
    project: String? = nil,
    file: FileMetadata? = nil,
    relatedNotes: [RelatedNote] = []
) -> String {
    // Strip existing frontmatter completely — replace with DotBrain format
    let (existing, body) = Frontmatter.parse(markdown: content)

    var newFM = Frontmatter.createDefault(
        para: para,
        tags: tags,
        summary: summary,
        source: source,
        project: project,
        file: file
    )

    // Only preserve `created` from existing frontmatter
    if let existingCreated = existing.created {
        newFM.created = existingCreated
    }
```

변경 후:
```swift
static func injectFrontmatter(
    into content: String,
    para: PARACategory,
    tags: [String],
    summary: String,
    source: NoteSource = .import,
    project: String? = nil,
    file: FileMetadata? = nil,
    relatedNotes: [RelatedNote] = []
) -> String {
    let (existing, body) = Frontmatter.parse(markdown: content)

    var newFM = Frontmatter.createDefault(
        para: para,
        tags: tags,
        summary: summary,
        source: source,
        project: project,
        file: file
    )

    // Merge policy: existing values take priority over AI-generated ones
    if existing.para != nil { newFM.para = existing.para }
    if !existing.tags.isEmpty { newFM.tags = existing.tags }
    if let existingCreated = existing.created { newFM.created = existingCreated }
    if existing.status != nil { newFM.status = existing.status }
    if let s = existing.summary, !s.isEmpty { newFM.summary = s }
    if existing.source != nil { newFM.source = existing.source }
    if let p = existing.project, !p.isEmpty { newFM.project = p }
    if existing.file != nil { newFM.file = existing.file }
```

**Step 3: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Services/FileSystem/FrontmatterWriter.swift
git commit -m "fix: frontmatter merge policy — preserve existing values instead of replacing"
```

---

## Task 2: 검색 서비스 구현 (VaultSearcher)

**현재 문제:** DotBrain에 검색 기능이 전혀 없다. 분류된 자료를 다시 찾으려면 Obsidian에 의존해야 한다.

**목표:** frontmatter tags + 본문 키워드 + 바이너리 동반 노트를 검색하는 `VaultSearcher` 서비스를 구현한다.

**Files:**
- Create: `Sources/Services/VaultSearcher.swift`
- Create: `Sources/Models/SearchResult.swift`

**Step 1: Create SearchResult model**

Create `Sources/Models/SearchResult.swift`:

```swift
import Foundation

struct SearchResult: Identifiable {
    let id = UUID()
    let noteName: String
    let filePath: String
    let para: PARACategory?
    let tags: [String]
    let summary: String
    let matchType: MatchType
    let relevanceScore: Double
    let isArchived: Bool

    enum MatchType: String {
        case tagMatch = "태그 일치"
        case bodyMatch = "본문 일치"
        case summaryMatch = "요약 일치"
        case titleMatch = "제목 일치"
    }
}
```

**Step 2: Create VaultSearcher service**

Create `Sources/Services/VaultSearcher.swift`:

```swift
import Foundation

struct VaultSearcher {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Search the vault for notes matching the query
    func search(query: String) -> [SearchResult] {
        let queryLower = query.lowercased()
        let queryWords = queryLower.split(separator: " ").map(String.init)
        var results: [SearchResult] = []

        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        let fm = FileManager.default

        for (para, basePath) in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }

            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix(".") else { continue }
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

                    let (frontmatter, body) = Frontmatter.parse(markdown: content)
                    let noteName = (file as NSString).deletingPathExtension
                    let isArchived = para == .archive

                    // Title match (highest relevance)
                    if noteName.lowercased().contains(queryLower) {
                        results.append(SearchResult(
                            noteName: noteName,
                            filePath: filePath,
                            para: frontmatter.para ?? para,
                            tags: frontmatter.tags,
                            summary: frontmatter.summary ?? "",
                            matchType: .titleMatch,
                            relevanceScore: 1.0,
                            isArchived: isArchived
                        ))
                        continue
                    }

                    // Tag match
                    let matchedTags = frontmatter.tags.filter { tag in
                        queryWords.contains(where: { tag.lowercased().contains($0) })
                    }
                    if !matchedTags.isEmpty {
                        let score = Double(matchedTags.count) / Double(max(queryWords.count, 1))
                        results.append(SearchResult(
                            noteName: noteName,
                            filePath: filePath,
                            para: frontmatter.para ?? para,
                            tags: frontmatter.tags,
                            summary: frontmatter.summary ?? "",
                            matchType: .tagMatch,
                            relevanceScore: min(0.9, 0.5 + score * 0.4),
                            isArchived: isArchived
                        ))
                        continue
                    }

                    // Summary match
                    if let summary = frontmatter.summary, summary.lowercased().contains(queryLower) {
                        results.append(SearchResult(
                            noteName: noteName,
                            filePath: filePath,
                            para: frontmatter.para ?? para,
                            tags: frontmatter.tags,
                            summary: summary,
                            matchType: .summaryMatch,
                            relevanceScore: 0.6,
                            isArchived: isArchived
                        ))
                        continue
                    }

                    // Body match
                    if body.lowercased().contains(queryLower) {
                        results.append(SearchResult(
                            noteName: noteName,
                            filePath: filePath,
                            para: frontmatter.para ?? para,
                            tags: frontmatter.tags,
                            summary: frontmatter.summary ?? "",
                            matchType: .bodyMatch,
                            relevanceScore: 0.3,
                            isArchived: isArchived
                        ))
                    }
                }
            }
        }

        return results.sorted { $0.relevanceScore > $1.relevanceScore }
    }
}
```

**Step 3: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Services/VaultSearcher.swift Sources/Models/SearchResult.swift
git commit -m "feat: add VaultSearcher service for tag/body/summary/title search"
```

---

## Task 3: 검색 UI 구현 (SearchView)

**목표:** 검색 화면을 DashboardView 내에 통합하거나 별도 화면으로 추가한다. 메뉴바 팝오버(360x480)에 맞는 컴팩트한 검색 UI.

**Files:**
- Create: `Sources/UI/SearchView.swift`
- Modify: `Sources/App/AppState.swift:11-19` (Screen enum에 .search 추가)
- Modify: `Sources/App/AppState.swift:65-85` (menuBarFace에 .search 케이스 추가)
- Modify: `Sources/UI/MenuBarPopover.swift:9-24` (switch에 .search 케이스 추가)
- Modify: `Sources/UI/MenuBarPopover.swift:29-41` (footer에 검색 버튼 추가)

**Step 1: Add `.search` to Screen enum**

`Sources/App/AppState.swift` 11-19행:

```swift
enum Screen {
    case onboarding
    case inbox
    case processing
    case results
    case settings
    case reorganize
    case dashboard
    case search      // NEW
}
```

**Step 2: Add menuBarFace for search**

`Sources/App/AppState.swift` 65-85행, `.dashboard` 케이스 뒤에 추가:

```swift
case .search:
    return "·_·?"
```

**Step 3: Create SearchView**

Create `Sources/UI/SearchView.swift`:

```swift
import SwiftUI

struct SearchView: View {
    @EnvironmentObject var appState: AppState
    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var hasSearched: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("검색")
                    .font(.headline)

                Spacer()
            }
            .padding()

            Divider()

            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("태그, 키워드, 제목으로 검색", text: $query)
                    .textFieldStyle(.plain)
                    .onSubmit { performSearch() }

                if !query.isEmpty {
                    Button(action: {
                        query = ""
                        results = []
                        hasSearched = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(8)
            .padding(.horizontal)
            .padding(.top, 8)

            // Results
            if hasSearched {
                if results.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("결과 없음")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    HStack {
                        Text("\(results.count)개 결과")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)

                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(results) { result in
                                SearchResultRow(result: result)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 4)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "text.magnifyingglass")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("태그, 키워드, 제목으로\nPKM 전체를 검색합니다")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func performSearch() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let searcher = VaultSearcher(pkmRoot: appState.pkmRootPath)
        results = searcher.search(query: query)
        hasSearched = true
    }
}

struct SearchResultRow: View {
    let result: SearchResult

    var body: some View {
        Button(action: {
            NSWorkspace.shared.selectFile(result.filePath, inFileViewerRootedAtPath: "")
        }) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: paraIcon(result.para))
                        .font(.caption)
                        .foregroundColor(paraColor(result.para))
                        .frame(width: 14)

                    Text(result.noteName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .lineLimit(1)

                    if result.isArchived {
                        Text("(아카이브)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Text(result.matchType.rawValue)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.primary.opacity(0.05))
                        .cornerRadius(3)
                }

                if !result.summary.isEmpty {
                    Text(result.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                if !result.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(result.tags.prefix(4), id: \.self) { tag in
                            Text(tag)
                                .font(.system(size: 9))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(3)
                        }
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(Color.primary.opacity(0.02))
            .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }

    private func paraIcon(_ para: PARACategory?) -> String {
        switch para {
        case .project: return "folder.fill"
        case .area: return "tray.fill"
        case .resource: return "book.fill"
        case .archive: return "archivebox.fill"
        case nil: return "doc.fill"
        }
    }

    private func paraColor(_ para: PARACategory?) -> Color {
        switch para {
        case .project: return .blue
        case .area: return .green
        case .resource: return .orange
        case .archive: return .gray
        case nil: return .secondary
        }
    }
}
```

**Step 4: Add SearchView to MenuBarPopover**

`Sources/UI/MenuBarPopover.swift` 9-24행 switch 내에 추가:

```swift
case .search:
    SearchView()
```

**Step 5: Add search button to footer**

`Sources/UI/MenuBarPopover.swift` 36-40행 (dashboard 버튼 뒤)에 추가:

```swift
Button(action: { appState.currentScreen = .search }) {
    Image(systemName: "magnifyingglass")
        .foregroundColor(.secondary)
}
.buttonStyle(.plain)
```

**Step 6: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 7: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/UI/SearchView.swift Sources/App/AppState.swift Sources/UI/MenuBarPopover.swift
git commit -m "feat: add PKM search UI with tag/keyword/title search"
```

---

## Task 4: 프로젝트 CRUD 서비스 구현 (ProjectManager)

**현재 문제:** DotBrain에는 프로젝트 생성/완료/재활성화/이름변경 기능이 없다.

**목표:** AI-PKM의 project-agent와 동등한 프로젝트 생명주기 관리 서비스를 구현한다.

**Files:**
- Create: `Sources/Services/ProjectManager.swift`

**Step 1: Create ProjectManager service**

Create `Sources/Services/ProjectManager.swift`:

```swift
import Foundation

struct ProjectManager {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Create

    /// Create a new project with folder, index note, and _Assets/
    func createProject(name: String, summary: String = "") throws -> String {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)

        guard !fm.fileExists(atPath: projectDir) else {
            throw ProjectError.alreadyExists(safeName)
        }

        // Create project directory and _Assets/
        try fm.createDirectory(atPath: projectDir, withIntermediateDirectories: true)
        let assetsDir = (projectDir as NSString).appendingPathComponent("_Assets")
        try fm.createDirectory(atPath: assetsDir, withIntermediateDirectories: true)

        // Create index note from template
        let indexContent = FrontmatterWriter.createIndexNote(
            folderName: safeName,
            para: .project,
            description: summary
        )

        // Add project-specific sections
        let fullContent = indexContent + "\n## 목적\n\n\(summary)\n\n## 현재 상태\n\n진행 중\n\n## 관련 노트\n\n"

        let indexPath = (projectDir as NSString).appendingPathComponent("\(safeName).md")
        try fullContent.write(toFile: indexPath, atomically: true, encoding: .utf8)

        return projectDir
    }

    // MARK: - Complete (Archive)

    /// Archive a completed project: move to 4_Archive/, update status, mark references
    func completeProject(name: String) throws -> Int {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)

        guard fm.fileExists(atPath: projectDir) else {
            throw ProjectError.notFound(safeName)
        }

        // Update all .md files in project: status -> completed, para -> archive
        let updatedCount = try updateAllNotes(in: projectDir, status: .completed, para: .archive)

        // Move folder to 4_Archive/
        let archiveDir = (pathManager.archivePath as NSString).appendingPathComponent(safeName)
        if fm.fileExists(atPath: archiveDir) {
            // Conflict: append timestamp
            let timestamp = Int(Date().timeIntervalSince1970)
            let newName = "\(safeName)_\(timestamp)"
            let newDir = (pathManager.archivePath as NSString).appendingPathComponent(newName)
            try fm.moveItem(atPath: projectDir, toPath: newDir)
        } else {
            try fm.moveItem(atPath: projectDir, toPath: archiveDir)
        }

        // Mark references in other notes with "(완료됨)"
        markReferencesCompleted(projectName: safeName)

        return updatedCount
    }

    // MARK: - Reactivate

    /// Restore a project from archive back to 1_Project/
    func reactivateProject(name: String) throws -> Int {
        let fm = FileManager.default
        let safeName = sanitizeName(name)
        let archiveDir = (pathManager.archivePath as NSString).appendingPathComponent(safeName)

        guard fm.fileExists(atPath: archiveDir) else {
            throw ProjectError.notFound(safeName)
        }

        // Update all notes: status -> active, para -> project
        let updatedCount = try updateAllNotes(in: archiveDir, status: .active, para: .project)

        // Move back to 1_Project/
        let projectDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeName)
        guard !fm.fileExists(atPath: projectDir) else {
            throw ProjectError.alreadyExists(safeName)
        }
        try fm.moveItem(atPath: archiveDir, toPath: projectDir)

        // Remove "(완료됨)" from references
        unmarkReferencesCompleted(projectName: safeName)

        return updatedCount
    }

    // MARK: - Rename

    /// Rename a project: folder, index note, and all WikiLink references
    func renameProject(from oldName: String, to newName: String) throws -> Int {
        let fm = FileManager.default
        let safeOld = sanitizeName(oldName)
        let safeNew = sanitizeName(newName)
        let oldDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeOld)

        guard fm.fileExists(atPath: oldDir) else {
            throw ProjectError.notFound(safeOld)
        }

        let newDir = (pathManager.projectsPath as NSString).appendingPathComponent(safeNew)
        guard !fm.fileExists(atPath: newDir) else {
            throw ProjectError.alreadyExists(safeNew)
        }

        // Rename index note inside project folder
        let oldIndex = (oldDir as NSString).appendingPathComponent("\(safeOld).md")
        let newIndex = (oldDir as NSString).appendingPathComponent("\(safeNew).md")
        if fm.fileExists(atPath: oldIndex) {
            try fm.moveItem(atPath: oldIndex, toPath: newIndex)
        }

        // Rename folder
        try fm.moveItem(atPath: oldDir, toPath: newDir)

        // Update all WikiLink references across the vault
        let updatedCount = updateWikiLinks(from: safeOld, to: safeNew)

        return updatedCount
    }

    // MARK: - List

    /// List all projects with their status
    func listProjects() -> [(name: String, status: NoteStatus, summary: String)] {
        let fm = FileManager.default
        var projects: [(name: String, status: NoteStatus, summary: String)] = []

        // Active projects
        if let entries = try? fm.contentsOfDirectory(atPath: pathManager.projectsPath) {
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let indexPath = (pathManager.projectsPath as NSString)
                    .appendingPathComponent(entry)
                    .appending("/\(entry).md")
                if let content = try? String(contentsOfFile: indexPath, encoding: .utf8) {
                    let (frontmatter, _) = Frontmatter.parse(markdown: content)
                    projects.append((
                        name: entry,
                        status: frontmatter.status ?? .active,
                        summary: frontmatter.summary ?? ""
                    ))
                } else {
                    projects.append((name: entry, status: .active, summary: ""))
                }
            }
        }

        // Archived projects
        if let entries = try? fm.contentsOfDirectory(atPath: pathManager.archivePath) {
            for entry in entries.sorted() {
                guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
                let dir = (pathManager.archivePath as NSString).appendingPathComponent(entry)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: dir, isDirectory: &isDir), isDir.boolValue else { continue }
                projects.append((name: entry, status: .completed, summary: "(아카이브)"))
            }
        }

        return projects
    }

    // MARK: - Private Helpers

    private func sanitizeName(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateAllNotes(in directory: String, status: NoteStatus, para: PARACategory) throws -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: directory) else { return 0 }
        var count = 0

        for file in files where file.hasSuffix(".md") {
            let filePath = (directory as NSString).appendingPathComponent(file)
            guard var content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (existing, body) = Frontmatter.parse(markdown: content)
            var updated = existing
            updated.status = status
            updated.para = para
            content = updated.stringify() + "\n" + body
            try content.write(toFile: filePath, atomically: true, encoding: .utf8)
            count += 1
        }

        return count
    }

    private func markReferencesCompleted(projectName: String) {
        replaceInVault(
            pattern: "[[\(projectName)]]",
            replacement: "[[\(projectName)]] (완료됨)"
        )
    }

    private func unmarkReferencesCompleted(projectName: String) {
        replaceInVault(
            pattern: "[[\(projectName)]] (완료됨)",
            replacement: "[[\(projectName)]]"
        )
    }

    private func updateWikiLinks(from oldName: String, to newName: String) -> Int {
        replaceInVault(
            pattern: "[[\(oldName)]]",
            replacement: "[[\(newName)]]"
        )
    }

    /// Replace text across all .md files in the vault (excluding system folders)
    @discardableResult
    private func replaceInVault(pattern: String, replacement: String) -> Int {
        let fm = FileManager.default
        let categories = [pathManager.projectsPath, pathManager.areaPath, pathManager.resourcePath, pathManager.archivePath]
        var count = 0

        for basePath in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }

                for file in files where file.hasSuffix(".md") {
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard var content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    if content.contains(pattern) {
                        content = content.replacingOccurrences(of: pattern, with: replacement)
                        try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
                        count += 1
                    }
                }
            }
        }

        return count
    }
}

enum ProjectError: LocalizedError {
    case alreadyExists(String)
    case notFound(String)

    var errorDescription: String? {
        switch self {
        case .alreadyExists(let name): return "프로젝트 '\(name)'이 이미 존재합니다"
        case .notFound(let name): return "프로젝트 '\(name)'을 찾을 수 없습니다"
        }
    }
}
```

**Step 2: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Services/ProjectManager.swift
git commit -m "feat: add ProjectManager with create/complete/reactivate/rename CRUD"
```

---

## Task 5: 프로젝트 관리 UI 구현 (ProjectManageView)

**목표:** 프로젝트 생성/완료/재활성화를 위한 UI를 구현한다.

**Files:**
- Create: `Sources/UI/ProjectManageView.swift`
- Modify: `Sources/App/AppState.swift:11-19` (Screen enum에 .projectManage 추가)
- Modify: `Sources/App/AppState.swift:65-85` (menuBarFace에 케이스 추가)
- Modify: `Sources/UI/MenuBarPopover.swift:9-24` (switch에 케이스 추가)

**Step 1: Add `.projectManage` to Screen enum**

`Sources/App/AppState.swift` Screen enum에 추가:

```swift
case projectManage
```

menuBarFace에 추가:

```swift
case .projectManage:
    return "·_·"
```

**Step 2: Create ProjectManageView**

Create `Sources/UI/ProjectManageView.swift`:

```swift
import SwiftUI

struct ProjectManageView: View {
    @EnvironmentObject var appState: AppState
    @State private var projects: [(name: String, status: NoteStatus, summary: String)] = []
    @State private var newProjectName: String = ""
    @State private var newProjectSummary: String = ""
    @State private var showNewProject: Bool = false
    @State private var statusMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button(action: { appState.currentScreen = .inbox }) {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Text("프로젝트 관리")
                    .font(.headline)

                Spacer()

                Button(action: { showNewProject.toggle() }) {
                    Image(systemName: showNewProject ? "minus.circle" : "plus.circle")
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            ScrollView {
                VStack(spacing: 12) {
                    // New project form
                    if showNewProject {
                        VStack(spacing: 8) {
                            TextField("프로젝트 이름", text: $newProjectName)
                                .textFieldStyle(.roundedBorder)
                            TextField("설명 (선택)", text: $newProjectSummary)
                                .textFieldStyle(.roundedBorder)
                            Button(action: createProject) {
                                HStack {
                                    Image(systemName: "plus")
                                    Text("프로젝트 생성")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .disabled(newProjectName.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        .padding()
                        .background(Color.primary.opacity(0.03))
                        .cornerRadius(8)
                    }

                    // Status message
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundColor(.green)
                            .padding(.vertical, 4)
                    }

                    // Active projects
                    let active = projects.filter { $0.status != .completed }
                    if !active.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("활성 프로젝트")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            ForEach(active, id: \.name) { project in
                                ProjectRow(
                                    project: project,
                                    onComplete: { completeProject(project.name) },
                                    onOpen: { openProjectFolder(project.name) }
                                )
                            }
                        }
                    }

                    // Archived projects
                    let archived = projects.filter { $0.status == .completed }
                    if !archived.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("아카이브")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(.secondary)
                            ForEach(archived, id: \.name) { project in
                                ProjectRow(
                                    project: project,
                                    onReactivate: { reactivateProject(project.name) },
                                    onOpen: nil
                                )
                            }
                        }
                    }
                }
                .padding()
            }
        }
        .onAppear { loadProjects() }
    }

    private func loadProjects() {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        projects = manager.listProjects()
    }

    private func createProject() {
        let name = newProjectName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            _ = try manager.createProject(name: name, summary: newProjectSummary)
            statusMessage = "'\(name)' 프로젝트 생성됨"
            newProjectName = ""
            newProjectSummary = ""
            showNewProject = false
            loadProjects()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func completeProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.completeProject(name: name)
            statusMessage = "'\(name)' 완료 → 아카이브 (\(count)개 노트 갱신)"
            loadProjects()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func reactivateProject(_ name: String) {
        let manager = ProjectManager(pkmRoot: appState.pkmRootPath)
        do {
            let count = try manager.reactivateProject(name: name)
            statusMessage = "'\(name)' 재활성화됨 (\(count)개 노트 갱신)"
            loadProjects()
            clearStatusAfterDelay()
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    private func openProjectFolder(_ name: String) {
        let path = (PKMPathManager(root: appState.pkmRootPath).projectsPath as NSString)
            .appendingPathComponent(name)
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }

    private func clearStatusAfterDelay() {
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await MainActor.run { statusMessage = "" }
        }
    }
}

struct ProjectRow: View {
    let project: (name: String, status: NoteStatus, summary: String)
    var onComplete: (() -> Void)? = nil
    var onReactivate: (() -> Void)? = nil
    var onOpen: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: project.status == .completed ? "archivebox.fill" : "folder.fill")
                .font(.caption)
                .foregroundColor(project.status == .completed ? .gray : .blue)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 1) {
                Text(project.name)
                    .font(.caption)
                    .fontWeight(.medium)
                if !project.summary.isEmpty {
                    Text(project.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if let onComplete = onComplete {
                Button(action: onComplete) {
                    Image(systemName: "checkmark.circle")
                        .font(.caption)
                        .foregroundColor(.green)
                }
                .buttonStyle(.plain)
                .help("프로젝트 완료")
            }

            if let onReactivate = onReactivate {
                Button(action: onReactivate) {
                    Image(systemName: "arrow.uturn.left.circle")
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                .buttonStyle(.plain)
                .help("재활성화")
            }

            if let onOpen = onOpen {
                Button(action: onOpen) {
                    Image(systemName: "folder")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("Finder에서 열기")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.primary.opacity(0.02))
        .cornerRadius(6)
    }
}
```

**Step 3: Add to MenuBarPopover switch**

`Sources/UI/MenuBarPopover.swift` switch 내:

```swift
case .projectManage:
    ProjectManageView()
```

**Step 4: Add project manage button to InboxStatusView footer or DashboardView**

이 부분은 DashboardView에 프로젝트 관리 버튼을 추가하는 방식으로 구현한다.
`Sources/UI/DashboardView.swift`에서 "전체 점검" 버튼 뒤에 추가:

```swift
Button(action: { appState.currentScreen = .projectManage }) {
    HStack {
        Image(systemName: "folder.badge.gearshape")
        Text("프로젝트 관리")
    }
    .frame(maxWidth: .infinity)
}
.buttonStyle(.bordered)
.controlSize(.regular)
```

**Step 5: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 6: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/UI/ProjectManageView.swift Sources/App/AppState.swift Sources/UI/MenuBarPopover.swift Sources/UI/DashboardView.swift
git commit -m "feat: add project management UI with create/complete/reactivate"
```

---

## Task 6: 관련 노트 의미적 컨텍스트 개선

**현재 문제:** `ProjectContextBuilder.findRelatedNotes()`가 태그 겹침만으로 "공유 태그: X, Y" 형태의 기계적 컨텍스트를 생성한다.

**목표:** AI를 활용하여 "이 노트를 왜 봐야 하는지"를 생성한다. 비용 최적화를 위해 Fast 모델(Haiku/Flash) 사용.

**Files:**
- Modify: `Sources/Pipeline/ProjectContextBuilder.swift:123-206`
- Modify: `Sources/Pipeline/InboxProcessor.swift` (관련 노트 enrichment 호출 부분)

**Step 1: Add semantic context generation to ProjectContextBuilder**

`Sources/Pipeline/ProjectContextBuilder.swift`에 새 메서드를 추가한다. 기존 `findRelatedNotes` 메서드는 유지하되, 선택적으로 AI 컨텍스트를 생성하는 `enrichRelatedNotesContext` 메서드를 추가:

파일 맨 아래 (`buildArchiveSummary()` 메서드 뒤, `}` 닫기 전)에 추가:

```swift
    /// Enrich related notes with AI-generated semantic context descriptions.
    /// Uses Fast model (Haiku/Flash) for cost efficiency.
    func enrichRelatedNotesContext(
        relatedNotes: [RelatedNote],
        sourceFileName: String,
        sourceSummary: String,
        sourceTags: [String]
    ) async -> [RelatedNote] {
        guard !relatedNotes.isEmpty else { return [] }

        let noteList = relatedNotes.map { note in
            "- \(note.name) (현재: \(note.context))"
        }.joined(separator: "\n")

        let prompt = """
        다음은 "\(sourceFileName)" 노트와 관련된 노트 목록입니다.
        소스 노트 요약: \(sourceSummary)
        소스 노트 태그: \(sourceTags.joined(separator: ", "))

        관련 노트:
        \(noteList)

        각 관련 노트에 대해 "이 노트를 언제, 왜 찾아가야 하는지"를 한 줄로 설명해주세요.
        형식: 노트명|설명
        예시: Aave_Analysis|프로토콜 설계의 기술적 근거를 확인하려면

        노트명|설명 형식만 출력하세요, 다른 텍스트 없이.
        """

        let aiService = AIService()
        do {
            let response = try await aiService.sendFast(maxTokens: 512, message: prompt)
            var enriched: [RelatedNote] = []

            let lines = response.split(separator: "\n")
            for note in relatedNotes {
                let matchingLine = lines.first { line in
                    line.contains(note.name)
                }
                if let line = matchingLine, let pipeIdx = line.firstIndex(of: "|") {
                    let context = String(line[line.index(after: pipeIdx)...]).trimmingCharacters(in: .whitespaces)
                    enriched.append(RelatedNote(name: note.name, context: context))
                } else {
                    enriched.append(note)
                }
            }

            return enriched
        } catch {
            // Fallback: return original tag-based context
            return relatedNotes
        }
    }
```

**Step 2: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Pipeline/ProjectContextBuilder.swift
git commit -m "feat: add AI semantic context for related notes (Fast model)"
```

---

## Task 7: 개별 노트 정리 서비스 구현 (NoteEnricher)

**현재 문제:** 이미 배치된 노트의 frontmatter를 개별적으로 보완하는 기능이 없다.

**목표:** 개별 노트의 빈 frontmatter 필드를 AI로 채우는 서비스를 구현한다. 노트를 이동하지 않고 메타데이터만 보완.

**Files:**
- Create: `Sources/Services/NoteEnricher.swift`

**Step 1: Create NoteEnricher service**

Create `Sources/Services/NoteEnricher.swift`:

```swift
import Foundation

/// Enriches individual note metadata without moving the file
struct NoteEnricher {
    let pkmRoot: String
    private let aiService = AIService()
    private let maxContentLength = 5000

    /// Enrich a single note's frontmatter by filling empty fields with AI analysis
    func enrichNote(at filePath: String) async throws -> EnrichResult {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            throw EnrichError.cannotRead(filePath)
        }

        let (existing, body) = Frontmatter.parse(markdown: content)

        // Determine which fields need filling
        let needsPara = existing.para == nil
        let needsTags = existing.tags.isEmpty
        let needsSummary = existing.summary == nil || (existing.summary ?? "").isEmpty
        let needsSource = existing.source == nil

        // If all fields are present, nothing to do
        guard needsPara || needsTags || needsSummary || needsSource else {
            return EnrichResult(filePath: filePath, fieldsUpdated: 0)
        }

        // Ask AI to analyze the content
        let preview = String(body.prefix(maxContentLength))
        let fileName = (filePath as NSString).lastPathComponent

        let prompt = """
        다음 문서의 메타데이터를 분석해주세요.

        파일명: \(fileName)
        내용:
        \(preview)

        아래 JSON만 출력하세요:
        {
          "para": "project|area|resource|archive",
          "tags": ["태그1", "태그2"],
          "summary": "2-3문장 요약",
          "source": "original|meeting|literature|import"
        }

        tags는 최대 5개, summary는 한국어로 작성하세요.
        """

        let response = try await aiService.sendFast(maxTokens: 512, message: prompt)

        // Parse AI response
        guard let data = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnrichError.aiParseFailed
        }

        // Merge: only fill empty fields
        var updated = existing
        var fieldsUpdated = 0

        if needsPara, let paraStr = json["para"] as? String, let para = PARACategory(rawValue: paraStr) {
            updated.para = para
            fieldsUpdated += 1
        }
        if needsTags, let tags = json["tags"] as? [String], !tags.isEmpty {
            updated.tags = Array(tags.prefix(5))
            fieldsUpdated += 1
        }
        if needsSummary, let summary = json["summary"] as? String, !summary.isEmpty {
            updated.summary = summary
            fieldsUpdated += 1
        }
        if needsSource, let sourceStr = json["source"] as? String, let source = NoteSource(rawValue: sourceStr) {
            updated.source = source
            fieldsUpdated += 1
        }

        // Preserve created date
        if updated.created == nil {
            updated.created = Frontmatter.today()
            fieldsUpdated += 1
        }
        if updated.status == nil {
            updated.status = .active
        }

        // Write back
        let newContent = updated.stringify() + "\n" + body
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        return EnrichResult(filePath: filePath, fieldsUpdated: fieldsUpdated)
    }

    /// Enrich all notes in a folder that have missing frontmatter fields
    func enrichFolder(at folderPath: String) async -> [EnrichResult] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { return [] }

        var results: [EnrichResult] = []
        for file in files where file.hasSuffix(".md") && !file.hasPrefix(".") && !file.hasPrefix("_") {
            let filePath = (folderPath as NSString).appendingPathComponent(file)
            do {
                let result = try await enrichNote(at: filePath)
                if result.fieldsUpdated > 0 {
                    results.append(result)
                }
            } catch {
                print("[NoteEnricher] \(file) 보완 실패: \(error.localizedDescription)")
            }
        }
        return results
    }

    private func extractJSON(from text: String) -> Data? {
        let cleaned = text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end]).data(using: .utf8)
        }
        return nil
    }
}

struct EnrichResult {
    let filePath: String
    let fieldsUpdated: Int

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }
}

enum EnrichError: LocalizedError {
    case cannotRead(String)
    case aiParseFailed

    var errorDescription: String? {
        switch self {
        case .cannotRead(let path): return "파일 읽기 실패: \(path)"
        case .aiParseFailed: return "AI 응답 파싱 실패"
        }
    }
}
```

**Step 2: Add "노트 정리" button to DashboardView**

`Sources/UI/DashboardView.swift`에서 "전체 점검" 버튼 뒤에 추가:

```swift
Button(action: {
    Task {
        let enricher = NoteEnricher(pkmRoot: appState.pkmRootPath)
        let pathManager = PKMPathManager(root: appState.pkmRootPath)
        let fm = FileManager.default
        var totalEnriched = 0

        for basePath in [pathManager.projectsPath, pathManager.areaPath, pathManager.resourcePath] {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders where !folder.hasPrefix(".") && !folder.hasPrefix("_") {
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                let results = await enricher.enrichFolder(at: folderPath)
                totalEnriched += results.count
            }
        }

        await MainActor.run {
            statusMessage = "\(totalEnriched)개 노트 메타데이터 보완 완료"
        }
    }
}) {
    HStack {
        Image(systemName: "text.badge.star")
        Text("노트 메타데이터 보완")
    }
    .frame(maxWidth: .infinity)
}
.buttonStyle(.bordered)
.controlSize(.regular)
```

이를 위해 DashboardView에 `@State private var statusMessage: String = ""` 추가하고, statusMessage를 표시하는 텍스트를 버튼들 아래에 추가:

```swift
if !statusMessage.isEmpty {
    Text(statusMessage)
        .font(.caption)
        .foregroundColor(.green)
        .padding(.vertical, 4)
}
```

**Step 3: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Services/NoteEnricher.swift Sources/UI/DashboardView.swift
git commit -m "feat: add NoteEnricher for individual note metadata completion"
```

---

## Task 8: 외부 템플릿 시스템

**현재 문제:** 노트/프로젝트/에셋 템플릿이 Swift 코드에 하드코딩되어 있어 사용자가 수정할 수 없다.

**목표:** PKM 루트에 `.Templates/` 폴더를 생성하고, 마크다운 템플릿 파일을 외부화한다. 기존 코드에서 템플릿을 참조하도록 수정.

**Files:**
- Create: `Sources/Services/TemplateService.swift`
- Modify: `Sources/Services/FileSystem/PKMPathManager.swift:67-76` (initializeStructure에 .Templates 생성 추가)

**Step 1: Create TemplateService**

Create `Sources/Services/TemplateService.swift`:

```swift
import Foundation

/// Loads note templates from .Templates/ folder, with built-in fallbacks
enum TemplateService {
    /// Load a template by name from .Templates/ folder
    static func loadTemplate(name: String, pkmRoot: String) -> String? {
        let templatesDir = (pkmRoot as NSString).appendingPathComponent(".Templates")
        let templatePath = (templatesDir as NSString).appendingPathComponent("\(name).md")
        return try? String(contentsOfFile: templatePath, encoding: .utf8)
    }

    /// Create default .Templates/ folder with Note.md, Project.md, Asset.md
    static func initializeTemplates(pkmRoot: String) throws {
        let fm = FileManager.default
        let templatesDir = (pkmRoot as NSString).appendingPathComponent(".Templates")
        try fm.createDirectory(atPath: templatesDir, withIntermediateDirectories: true)

        let templates: [(String, String)] = [
            ("Note", noteTemplate),
            ("Project", projectTemplate),
            ("Asset", assetTemplate),
        ]

        for (name, content) in templates {
            let path = (templatesDir as NSString).appendingPathComponent("\(name).md")
            if !fm.fileExists(atPath: path) {
                try content.write(toFile: path, atomically: true, encoding: .utf8)
            }
        }
    }

    // MARK: - Default Templates

    private static let noteTemplate = """
    ---
    para:
    tags: []
    created: {{date}}
    status: active
    summary:
    source: original
    ---

    # {{title}}

    ## 관련 노트

    """

    private static let projectTemplate = """
    ---
    para: project
    tags: []
    created: {{date}}
    status: active
    summary:
    source: original
    ---

    # {{project_name}}

    ## 목적

    ## 현재 상태

    ## 포함된 노트

    ## 관련 노트

    """

    private static let assetTemplate = """
    ---
    para:
    tags: []
    created: {{date}}
    status: active
    summary:
    source: import
    file:
      name: {{filename}}
      format: {{format}}
      size_kb: {{size_kb}}
    ---

    # {{filename}}

    ## 핵심 내용

    ## 관련 노트

    """

    /// Apply template variables
    static func apply(template: String, variables: [String: String]) -> String {
        var result = template
        for (key, value) in variables {
            result = result.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        // Replace date placeholder with today
        result = result.replacingOccurrences(of: "{{date}}", with: Frontmatter.today())
        return result
    }
}
```

**Step 2: Add .Templates/ initialization to PKMPathManager**

`Sources/Services/FileSystem/PKMPathManager.swift` `initializeStructure()` 메서드(67-76행)에서 `try createAICompanionFiles()` 뒤에 추가:

```swift
        // Create .Templates/ folder with default templates
        try TemplateService.initializeTemplates(pkmRoot: root)
```

**Step 3: Build and verify**

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

**Step 4: Commit**

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Services/TemplateService.swift Sources/Services/FileSystem/PKMPathManager.swift
git commit -m "feat: add external template system (.Templates/ with Note/Project/Asset)"
```

---

## Task 9: 파이프라인 병렬 처리 (TaskGroup 기반)

**현재 문제:** InboxProcessor, FolderReorganizer, Classifier 모두 순차 `for` 루프로 파일을 처리한다. 파일이 30개면 콘텐츠 추출, AI 분류, 관련 노트 보강이 전부 직렬로 실행되어 처리 시간이 선형으로 증가한다.

**병목 분석:**
1. **콘텐츠 추출** (InboxProcessor:37-48, FolderReorganizer:64-76) — 파일별 독립, I/O 바운드
2. **Classifier Stage 1 배치** (Classifier:30-43) — 배치 간 독립, API 호출 바운드
3. **Classifier Stage 2 개별** (Classifier:54-65) — 파일 간 독립, API 호출 바운드
4. **관련 노트 보강** (InboxProcessor:69-77, FolderReorganizer:95-104) — 파일별 독립, CPU 바운드
5. **MOC 전체 갱신** (MOCGenerator:125-139) — 폴더별 독립, API 호출 바운드

**목표:** Swift `TaskGroup`을 사용하여 독립적인 작업을 동시에 실행한다. API 호출은 동시성 제한(max concurrency)을 두어 rate limit을 방지한다.

**Files:**
- Modify: `Sources/Pipeline/InboxProcessor.swift:37-77` (추출 + 보강 병렬화)
- Modify: `Sources/Pipeline/FolderReorganizer.swift:64-104` (추출 + 보강 병렬화)
- Modify: `Sources/Services/Claude/Classifier.swift:30-65` (Stage 1 배치 + Stage 2 동시 실행)
- Modify: `Sources/Services/MOCGenerator.swift:116-140` (폴더별 병렬 MOC 생성)

### Step 1: InboxProcessor — 콘텐츠 추출 병렬화

`Sources/Pipeline/InboxProcessor.swift` 37-48행의 순차 루프를:

**현재:**
```swift
var inputs: [ClassifyInput] = []
for (i, filePath) in files.enumerated() {
    let progress = 0.1 + Double(i) / Double(files.count) * 0.2
    let fileName = (filePath as NSString).lastPathComponent
    onProgress?(progress, "\(fileName) 내용 추출 중...")

    let content = extractContent(from: filePath)
    inputs.append(ClassifyInput(
        filePath: filePath,
        content: content,
        fileName: fileName
    ))
}
```

**변경:**
```swift
// Extract content from all files — parallel using TaskGroup
let inputs: [ClassifyInput] = await withTaskGroup(
    of: ClassifyInput.self,
    returning: [ClassifyInput].self
) { group in
    for filePath in files {
        group.addTask {
            let content = self.extractContent(from: filePath)
            let fileName = (filePath as NSString).lastPathComponent
            return ClassifyInput(
                filePath: filePath,
                content: content,
                fileName: fileName
            )
        }
    }

    var collected: [ClassifyInput] = []
    collected.reserveCapacity(files.count)
    for await input in group {
        collected.append(input)
    }

    // Preserve original file order for stable classification
    return collected.sorted { a, b in
        files.firstIndex(of: a.filePath)! < files.firstIndex(of: b.filePath)!
    }
}

onProgress?(0.3, "\(inputs.count)개 파일 내용 추출 완료")
```

### Step 2: InboxProcessor — 관련 노트 보강 병렬화

`Sources/Pipeline/InboxProcessor.swift` 68-77행을:

**현재:**
```swift
var enrichedClassifications = classifications
for (i, classification) in enrichedClassifications.enumerated() {
    let related = contextBuilder.findRelatedNotes(
        tags: classification.tags,
        project: classification.project,
        para: classification.para,
        targetFolder: classification.targetFolder
    )
    enrichedClassifications[i].relatedNotes = related
}
```

**변경:**
```swift
// Enrich with related notes — parallel (CPU-bound tag matching)
let enrichedClassifications: [ClassifyResult] = await withTaskGroup(
    of: (Int, [RelatedNote]).self,
    returning: [ClassifyResult].self
) { group in
    for (i, classification) in classifications.enumerated() {
        group.addTask {
            let related = contextBuilder.findRelatedNotes(
                tags: classification.tags,
                project: classification.project,
                para: classification.para,
                targetFolder: classification.targetFolder
            )
            return (i, related)
        }
    }

    var results = classifications
    for await (index, related) in group {
        results[index].relatedNotes = related
    }
    return results
}
```

### Step 3: FolderReorganizer — 동일하게 추출 + 보강 병렬화

`Sources/Pipeline/FolderReorganizer.swift` 64-76행과 95-104행을 InboxProcessor와 동일한 패턴으로 변경한다.

**추출 (64-76행) 변경:**
```swift
// Extract content — parallel
let inputs: [ClassifyInput] = await withTaskGroup(
    of: ClassifyInput.self,
    returning: [ClassifyInput].self
) { group in
    for filePath in uniqueFiles {
        group.addTask {
            let content = self.extractContent(from: filePath)
            let fileName = (filePath as NSString).lastPathComponent
            return ClassifyInput(
                filePath: filePath,
                content: content,
                fileName: fileName
            )
        }
    }

    var collected: [ClassifyInput] = []
    collected.reserveCapacity(uniqueFiles.count)
    for await input in group {
        collected.append(input)
    }
    return collected.sorted { a, b in
        uniqueFiles.firstIndex(of: a.filePath)! < uniqueFiles.firstIndex(of: b.filePath)!
    }
}

onProgress?(0.3, "\(inputs.count)개 파일 내용 추출 완료")
```

**보강 (95-104행) 변경:** InboxProcessor Step 2와 동일 패턴.

### Step 4: Classifier — Stage 1 배치 동시 실행 (max 3)

`Sources/Services/Claude/Classifier.swift` 30-43행을:

**현재:**
```swift
for (i, batch) in batches.enumerated() {
    let progress = Double(i) / Double(batches.count) * 0.6
    onProgress?(progress, "Stage 1: 배치 \(i + 1)/\(batches.count) 분류 중...")

    let results = try await classifyBatchStage1(
        batch,
        projectContext: projectContext,
        subfolderContext: subfolderContext,
        weightedContext: weightedContext
    )
    for (key, value) in results {
        stage1Results[key] = value
    }
}
```

**변경:**
```swift
// Stage 1: Process batches concurrently (max 3 concurrent API calls)
let maxConcurrentBatches = 3

stage1Results = try await withThrowingTaskGroup(
    of: [String: ClassifyResult.Stage1Item].self,
    returning: [String: ClassifyResult.Stage1Item].self
) { group in
    var activeTasks = 0
    var batchIndex = 0
    var combined: [String: ClassifyResult.Stage1Item] = [:]

    for batch in batches {
        if activeTasks >= maxConcurrentBatches {
            // Wait for one to finish before adding more
            if let results = try await group.next() {
                for (key, value) in results {
                    combined[key] = value
                }
                activeTasks -= 1
            }
        }

        let idx = batchIndex
        group.addTask {
            return try await self.classifyBatchStage1(
                batch,
                projectContext: projectContext,
                subfolderContext: subfolderContext,
                weightedContext: weightedContext
            )
        }
        activeTasks += 1
        batchIndex += 1
        onProgress?(Double(idx) / Double(batches.count) * 0.6, "Stage 1: 배치 \(idx + 1)/\(batches.count) 분류 중...")
    }

    // Collect remaining
    for try await results in group {
        for (key, value) in results {
            combined[key] = value
        }
    }
    return combined
}
```

### Step 5: Classifier — Stage 2 동시 실행 (max 5)

`Sources/Services/Claude/Classifier.swift` 54-65행을:

**현재:**
```swift
for (i, file) in uncertainFiles.enumerated() {
    let progress = 0.6 + Double(i) / Double(uncertainFiles.count) * 0.3
    onProgress?(progress, "Stage 2: \(file.fileName) 정밀 분류 중...")

    let result = try await classifySingleStage2(
        file,
        projectContext: projectContext,
        subfolderContext: subfolderContext,
        weightedContext: weightedContext
    )
    stage2Results[file.fileName] = result
}
```

**변경:**
```swift
// Stage 2: Process uncertain files concurrently (max 5)
let maxConcurrentStage2 = 5

stage2Results = try await withThrowingTaskGroup(
    of: (String, ClassifyResult.Stage2Item).self,
    returning: [String: ClassifyResult.Stage2Item].self
) { group in
    var activeTasks = 0
    var combined: [String: ClassifyResult.Stage2Item] = [:]

    for file in uncertainFiles {
        if activeTasks >= maxConcurrentStage2 {
            if let (fileName, result) = try await group.next() {
                combined[fileName] = result
                activeTasks -= 1
            }
        }

        group.addTask {
            let result = try await self.classifySingleStage2(
                file,
                projectContext: projectContext,
                subfolderContext: subfolderContext,
                weightedContext: weightedContext
            )
            return (file.fileName, result)
        }
        activeTasks += 1
    }

    for try await (fileName, result) in group {
        combined[fileName] = result
    }
    return combined
}

onProgress?(0.9, "결과 정리 중...")
```

### Step 6: MOCGenerator — 폴더별 병렬 MOC 생성 (max 3)

`Sources/Services/MOCGenerator.swift` `regenerateAll()` 메서드(116-140행)를:

**현재:**
```swift
for (para, basePath) in categories {
    guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
    for folder in folders {
        guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
        let folderPath = (basePath as NSString).appendingPathComponent(folder)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

        do {
            try await generateMOC(folderPath: folderPath, folderName: folder, para: para)
        } catch {
            print("[MOCGenerator] MOC 갱신 실패: \(folder) — \(error.localizedDescription)")
        }
    }
}
```

**변경:**
```swift
// Collect all folder tasks first, then run concurrently (max 3 API calls)
var folderTasks: [(para: PARACategory, folderPath: String, folderName: String)] = []
for (para, basePath) in categories {
    guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
    for folder in folders {
        guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
        let folderPath = (basePath as NSString).appendingPathComponent(folder)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
        folderTasks.append((para: para, folderPath: folderPath, folderName: folder))
    }
}

let maxConcurrentMOC = 3
await withTaskGroup(of: Void.self) { group in
    var activeTasks = 0
    for task in folderTasks {
        if activeTasks >= maxConcurrentMOC {
            await group.next()
            activeTasks -= 1
        }
        group.addTask {
            do {
                try await self.generateMOC(
                    folderPath: task.folderPath,
                    folderName: task.folderName,
                    para: task.para
                )
            } catch {
                print("[MOCGenerator] MOC 갱신 실패: \(task.folderName) — \(error.localizedDescription)")
            }
        }
        activeTasks += 1
    }
}
```

### Step 7: Build and verify

Run: `cd /Users/hwaa/Documents/DotBrain && swift build 2>&1 | tail -5`
Expected: Build Succeeded

### Step 8: Commit

```bash
cd /Users/hwaa/Documents/DotBrain
git add Sources/Pipeline/InboxProcessor.swift Sources/Pipeline/FolderReorganizer.swift Sources/Services/Claude/Classifier.swift Sources/Services/MOCGenerator.swift
git commit -m "perf: parallelize pipeline with TaskGroup — extraction, classification, enrichment, MOC"
```

---

## 예상 성능 개선

| 파일 수 | 현재 (순차) | 병렬화 후 (예상) | 개선 |
|---------|------------|-----------------|------|
| 10개 | ~45초 | ~15초 | **3x** |
| 30개 | ~120초 | ~30초 | **4x** |
| 50개 | ~200초 | ~45초 | **4.5x** |

> Stage 1 배치 3개 동시, Stage 2 파일 5개 동시, 추출 완전 병렬 기준.
> API rate limit에 따라 동시성 상수 (`maxConcurrentBatches`, `maxConcurrentStage2`, `maxConcurrentMOC`) 조절 가능.

---

## Summary

| Task | 기능 | 영향 범위 | 우선순위 |
|------|------|----------|---------|
| 1 | Frontmatter 병합 정책 (기존값 존중) | FrontmatterWriter | P4 - 빠른 수정 |
| 2 | 검색 서비스 (VaultSearcher) | 신규 서비스 | P1 |
| 3 | 검색 UI (SearchView) | UI + AppState + MenuBarPopover | P1 |
| 4 | 프로젝트 CRUD (ProjectManager) | 신규 서비스 | P2 |
| 5 | 프로젝트 관리 UI (ProjectManageView) | UI + AppState + MenuBarPopover + DashboardView | P2 |
| 6 | 관련 노트 의미적 컨텍스트 | ProjectContextBuilder | P3 |
| 7 | 개별 노트 정리 (NoteEnricher) | 신규 서비스 + DashboardView | P5 |
| 8 | 외부 템플릿 시스템 | 신규 서비스 + PKMPathManager | P6 |
| 9 | **파이프라인 병렬 처리** | InboxProcessor + FolderReorganizer + Classifier + MOCGenerator | **P0 - 성능** |
