# Semantic Note Linking Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the limited ContextLinker with a comprehensive SemanticLinker that creates rich cross-note connections using tag overlap, MOC co-membership, and AI filtering — triggered during vault audit, inbox processing, and AI reclassification.

**Architecture:** Five new Swift files under `Sources/Services/SemanticLinker/` (TagNormalizer, LinkCandidateGenerator, LinkAIFilter, RelatedNotesWriter, SemanticLinker orchestrator). Integration into three existing pipelines: DashboardView (vault audit), InboxProcessor (inbox), VaultReorganizer (reclassification). The old ContextLinker is replaced by SemanticLinker in InboxProcessor.

**Tech Stack:** Swift 5.9, macOS 13+, SPM. Uses existing `AIService.sendFast()` for Haiku/Flash calls, `Frontmatter` model for parsing/writing, `ContextMapBuilder` for MOC data, `withTaskGroup` for concurrency.

**Note:** This project has no test infrastructure (no Tests/ directory, no XCTest). Verification is done via `swift build` and manual vault audit testing.

---

### Task 1: TagNormalizer

**Files:**
- Create: `Sources/Services/SemanticLinker/TagNormalizer.swift`

**Step 1: Create the TagNormalizer file**

```swift
import Foundation

/// Phase 1: Normalize tags across the vault
/// - Adds project folder name as tag to project subfolder notes
/// - Propagates project field value as tag for Area/Resource/Archive notes
struct TagNormalizer: Sendable {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    struct Result {
        var filesModified: Int = 0
        var tagsAdded: Int = 0
    }

    /// Normalize tags across the entire vault
    func normalize() throws -> Result {
        var result = Result()
        let fm = FileManager.default

        // 1. Project folder notes: ensure project folder name is in tags
        let projectsBase = pathManager.projectsPath
        if let projects = try? fm.contentsOfDirectory(atPath: projectsBase) {
            for project in projects {
                guard !project.hasPrefix("."), !project.hasPrefix("_") else { continue }
                let projectPath = (projectsBase as NSString).appendingPathComponent(project)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: projectPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: projectPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    guard file != "\(project).md" else { continue } // skip index note

                    let filePath = (projectPath as NSString).appendingPathComponent(file)
                    if try addTagIfMissing(filePath: filePath, tag: project) {
                        result.filesModified += 1
                        result.tagsAdded += 1
                    }
                }
            }
        }

        // 2. Non-project notes with project field: ensure project value is in tags
        let nonProjectBases = [pathManager.areaPath, pathManager.resourcePath, pathManager.archivePath]
        for basePath in nonProjectBases {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    guard file != "\(folder).md" else { continue }

                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }
                    let (frontmatter, _) = Frontmatter.parse(markdown: content)

                    guard let projectName = frontmatter.project, !projectName.isEmpty else { continue }

                    if try addTagIfMissing(filePath: filePath, tag: projectName) {
                        result.filesModified += 1
                        result.tagsAdded += 1
                    }
                }
            }
        }

        return result
    }

    /// Add a tag to a note's frontmatter if not already present. Returns true if modified.
    @discardableResult
    private func addTagIfMissing(filePath: String, tag: String) throws -> Bool {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return false }
        let (frontmatter, body) = Frontmatter.parse(markdown: content)

        let normalizedTag = tag.trimmingCharacters(in: .whitespaces)
        guard !normalizedTag.isEmpty else { return false }

        // Check if tag already exists (case-insensitive)
        let lowerTag = normalizedTag.lowercased()
        if frontmatter.tags.contains(where: { $0.lowercased() == lowerTag }) {
            return false
        }

        var updatedFM = frontmatter
        updatedFM.tags.append(normalizedTag)

        let newContent = updatedFM.stringify() + "\n" + body
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        return true
    }
}
```

**Step 2: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/SemanticLinker/TagNormalizer.swift
git commit -m "feat: add TagNormalizer for project-based tag propagation"
```

---

### Task 2: LinkCandidateGenerator

**Files:**
- Create: `Sources/Services/SemanticLinker/LinkCandidateGenerator.swift`

**Step 1: Create the LinkCandidateGenerator file**

```swift
import Foundation

/// Phase 2: Generate link candidates based on tag overlap, MOC co-membership, and shared project field
struct LinkCandidateGenerator: Sendable {

    /// Metadata for a single note in the vault
    struct NoteInfo {
        let name: String           // basename without .md
        let filePath: String
        let tags: [String]
        let summary: String
        let project: String?
        let folderName: String
        let para: PARACategory
        let existingRelated: Set<String>  // names already in Related Notes
    }

    /// A scored candidate for linking
    struct Candidate {
        let name: String
        let summary: String
        let tags: [String]
        let score: Double
    }

    /// Generate candidates for a note, ranked by relevance score
    func generateCandidates(
        for note: NoteInfo,
        allNotes: [NoteInfo],
        mocEntries: [ContextMapEntry],
        maxCandidates: Int = 10
    ) -> [Candidate] {
        // Build MOC co-membership index: note name → set of folder names
        var mocFolders: [String: Set<String>] = [:]
        for entry in mocEntries {
            mocFolders[entry.noteName, default: []].insert(entry.folderName)
        }

        let noteFolders = mocFolders[note.name] ?? []
        let noteTags = Set(note.tags.map { $0.lowercased() })

        var candidates: [Candidate] = []

        for other in allNotes {
            // Skip self
            guard other.name != note.name else { continue }
            // Skip already linked
            guard !note.existingRelated.contains(other.name) else { continue }

            var score: Double = 0

            // Signal 1: Tag overlap (weight: high)
            let otherTags = Set(other.tags.map { $0.lowercased() })
            let tagOverlap = noteTags.intersection(otherTags).count
            if tagOverlap >= 2 {
                score += Double(tagOverlap) * 1.5
            } else if tagOverlap == 1 {
                score += 0.5
            }

            // Signal 2: MOC co-membership (weight: medium)
            let otherFolders = mocFolders[other.name] ?? []
            let sharedFolders = noteFolders.intersection(otherFolders)
            if !sharedFolders.isEmpty {
                score += Double(sharedFolders.count) * 1.0
            }

            // Signal 3: Shared project field (weight: high)
            if let noteProject = note.project, !noteProject.isEmpty,
               let otherProject = other.project, !otherProject.isEmpty,
               noteProject.lowercased() == otherProject.lowercased() {
                score += 2.0
            }

            // Only include if at least one signal fired
            guard score > 0 else { continue }

            candidates.append(Candidate(
                name: other.name,
                summary: other.summary,
                tags: other.tags,
                score: score
            ))
        }

        // Sort by score descending, take top N
        return Array(candidates.sorted { $0.score > $1.score }.prefix(maxCandidates))
    }
}
```

**Step 2: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/SemanticLinker/LinkCandidateGenerator.swift
git commit -m "feat: add LinkCandidateGenerator with tag/MOC/project scoring"
```

---

### Task 3: LinkAIFilter

**Files:**
- Create: `Sources/Services/SemanticLinker/LinkAIFilter.swift`

**Step 1: Create the LinkAIFilter file**

This uses `AIService.sendFast()` (Haiku/Flash) for batch candidate filtering. Supports both single-note and multi-note batch calls. Parses JSON responses with the same resilient approach as `ContextLinker.parseResponse()`.

```swift
import Foundation

/// Phase 3: AI-based filtering of link candidates with context generation
struct LinkAIFilter: Sendable {
    private let aiService = AIService.shared

    struct FilteredLink {
        let name: String
        let context: String
    }

    /// Filter candidates for multiple notes in a single batch AI call
    func filterBatch(
        notes: [(name: String, summary: String, tags: [String], candidates: [LinkCandidateGenerator.Candidate])],
        maxResultsPerNote: Int = 5
    ) async throws -> [[FilteredLink]] {
        guard !notes.isEmpty else { return [] }

        let noteDescriptions = notes.enumerated().map { (i, note) in
            let candidateList = note.candidates.enumerated().map { (j, c) in
                "  [\(j)] \(c.name) — \(c.tags.prefix(3).joined(separator: ", ")) — \(c.summary)"
            }.joined(separator: "\n")

            return """
            ### 노트 \(i): \(note.name)
            태그: \(note.tags.joined(separator: ", "))
            요약: \(note.summary)
            후보:
            \(candidateList)
            """
        }.joined(separator: "\n\n")

        let prompt = """
        각 노트에 대해 가장 관련 깊은 후보를 최대 \(maxResultsPerNote)개씩 선택하세요.

        \(noteDescriptions)

        ## 규칙
        1. 실질적 맥락 연관성 기준 선택 (단순 태그 일치 불충분)
        2. context: "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        3. 관련 없는 후보 제외

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"noteIndex": 0, "links": [{"index": 0, "context": "~하려면 참고"}]}]
        """

        let response = try await aiService.sendFast(maxTokens: 2048, message: prompt)
        StatisticsService.addApiCost(Double(notes.count) * 0.0005)

        return parseBatchResponse(response, notes: notes, maxResultsPerNote: maxResultsPerNote)
    }

    /// Filter candidates for a single note
    func filterSingle(
        noteName: String,
        noteSummary: String,
        noteTags: [String],
        candidates: [LinkCandidateGenerator.Candidate],
        maxResults: Int = 5
    ) async throws -> [FilteredLink] {
        guard !candidates.isEmpty else { return [] }

        let candidateList = candidates.enumerated().map { (i, c) in
            "[\(i)] \(c.name) — 태그: \(c.tags.joined(separator: ", ")) — \(c.summary)"
        }.joined(separator: "\n")

        let prompt = """
        다음 노트와 가장 관련이 깊은 후보를 최대 \(maxResults)개 선택하고, 각각 연결 이유를 작성하세요.

        노트: \(noteName)
        태그: \(noteTags.joined(separator: ", "))
        요약: \(noteSummary)

        ## 후보 목록
        \(candidateList)

        ## 규칙
        1. 단순 태그 일치가 아닌 실질적 맥락 연관성 기준
        2. context는 "~하려면", "~할 때", "~와 비교할 때" 형식 (한국어, 15자 이내)
        3. 관련 없는 후보는 제외

        ## 응답 (순수 JSON, 코드블록 없이)
        [{"index": 0, "context": "~하려면 참고"}]
        """

        let response = try await aiService.sendFast(maxTokens: 512, message: prompt)
        StatisticsService.addApiCost(0.0005)

        return parseSingleResponse(response, candidates: candidates, maxResults: maxResults)
    }

    // MARK: - Parsing

    private func parseSingleResponse(
        _ text: String,
        candidates: [LinkCandidateGenerator.Candidate],
        maxResults: Int
    ) -> [FilteredLink] {
        let cleaned = stripCodeBlock(text)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else { return [] }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else { return [] }

        struct Item: Decodable { let index: Int; let context: String? }

        guard let items = try? JSONDecoder().decode([Item].self, from: data) else { return [] }

        return items.prefix(maxResults).compactMap { item in
            guard item.index >= 0, item.index < candidates.count else { return nil }
            return FilteredLink(
                name: candidates[item.index].name,
                context: item.context ?? "관련 문서"
            )
        }
    }

    private func parseBatchResponse(
        _ text: String,
        notes: [(name: String, summary: String, tags: [String], candidates: [LinkCandidateGenerator.Candidate])],
        maxResultsPerNote: Int
    ) -> [[FilteredLink]] {
        let cleaned = stripCodeBlock(text)

        guard let startBracket = cleaned.firstIndex(of: "["),
              let endBracket = cleaned.lastIndex(of: "]") else {
            return Array(repeating: [], count: notes.count)
        }

        let jsonStr = String(cleaned[startBracket...endBracket])
        guard let data = jsonStr.data(using: .utf8) else {
            return Array(repeating: [], count: notes.count)
        }

        struct LinkItem: Decodable { let index: Int; let context: String? }
        struct NoteItem: Decodable { let noteIndex: Int; let links: [LinkItem]? }

        guard let items = try? JSONDecoder().decode([NoteItem].self, from: data) else {
            return Array(repeating: [], count: notes.count)
        }

        var results = Array(repeating: [FilteredLink](), count: notes.count)
        for item in items {
            guard item.noteIndex >= 0, item.noteIndex < notes.count else { continue }
            let candidates = notes[item.noteIndex].candidates
            let links = (item.links ?? []).prefix(maxResultsPerNote).compactMap { link -> FilteredLink? in
                guard link.index >= 0, link.index < candidates.count else { return nil }
                return FilteredLink(
                    name: candidates[link.index].name,
                    context: link.context ?? "관련 문서"
                )
            }
            results[item.noteIndex] = links
        }
        return results
    }

    private func stripCodeBlock(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 2: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/SemanticLinker/LinkAIFilter.swift
git commit -m "feat: add LinkAIFilter for AI-based candidate filtering with context"
```

---

### Task 4: RelatedNotesWriter

**Files:**
- Create: `Sources/Services/SemanticLinker/RelatedNotesWriter.swift`

**Step 1: Create the RelatedNotesWriter file**

This handles parsing existing `## Related Notes` sections, merging new links (preserving manual entries), and writing back. Verifies file existence for every link before writing.

```swift
import Foundation

/// Phase 4: Write Related Notes section into markdown files
/// Merges AI-generated links with existing manual links, preserving manual entries
struct RelatedNotesWriter: Sendable {

    /// Write or update the Related Notes section in a file
    /// - noteNames: Set of all valid note basenames for existence verification
    func writeRelatedNotes(
        filePath: String,
        newLinks: [LinkAIFilter.FilteredLink],
        noteNames: Set<String>
    ) throws {
        guard !newLinks.isEmpty else { return }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        // Verify all link targets exist
        let verifiedLinks = newLinks.filter { noteNames.contains($0.name) }
        guard !verifiedLinks.isEmpty else { return }

        // Parse existing Related Notes section
        let (existingEntries, sectionRange) = parseRelatedNotes(content)

        // Merge: existing entries take priority (treated as manual)
        let existingNames = Set(existingEntries.map { $0.name })
        var mergedEntries = existingEntries

        // Don't add self-reference
        let selfName = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension

        for link in verifiedLinks {
            guard !existingNames.contains(link.name) else { continue }
            guard link.name != selfName else { continue }
            mergedEntries.append((name: link.name, context: link.context))
        }

        // Cap at 5 (existing/manual first)
        let finalEntries = Array(mergedEntries.prefix(5))
        guard !finalEntries.isEmpty else { return }

        // Build new section text
        let sectionLines = finalEntries.map { entry in
            let safeName = sanitizeWikilink(entry.name)
            let safeContext = entry.context
                .replacingOccurrences(of: "[[", with: "")
                .replacingOccurrences(of: "]]", with: "")
            return "- [[\(safeName)]] — \(safeContext)"
        }
        let sectionText = "\n\n## Related Notes\n\n" + sectionLines.joined(separator: "\n") + "\n"

        // Replace or append
        var newContent: String
        if let range = sectionRange {
            newContent = content.replacingCharacters(in: range, with: sectionText)
        } else {
            newContent = content.trimmingCharacters(in: .whitespacesAndNewlines) + sectionText
        }

        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Parsing

    /// Parse existing Related Notes from markdown content
    private func parseRelatedNotes(_ content: String) -> (entries: [(name: String, context: String)], range: Range<String.Index>?) {
        guard let headerRange = content.range(of: "\n## Related Notes") ?? content.range(of: "## Related Notes") else {
            return ([], nil)
        }

        // Find leading whitespace before header
        var sectionStart = headerRange.lowerBound
        while sectionStart > content.startIndex {
            let prev = content.index(before: sectionStart)
            if content[prev] == "\n" {
                sectionStart = prev
                break
            }
            sectionStart = prev
        }

        // Find end of section (next ## heading or end of file)
        let afterHeader = String(content[headerRange.upperBound...])
        var sectionEndOffset = content.distance(from: content.startIndex, to: content.endIndex)
        var lineOffset = content.distance(from: content.startIndex, to: headerRange.upperBound)

        for line in afterHeader.components(separatedBy: "\n").dropFirst() {
            lineOffset += line.count + 1
            if line.hasPrefix("## ") {
                sectionEndOffset = lineOffset - line.count - 1
                break
            }
        }

        let sectionEnd = content.index(content.startIndex, offsetBy: min(sectionEndOffset, content.count))
        let range = sectionStart..<sectionEnd

        // Parse entries from the section
        var entries: [(name: String, context: String)] = []
        let sectionContent = String(content[headerRange.upperBound..<sectionEnd])

        for line in sectionContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("- [[") else { continue }

            guard let startRange = trimmed.range(of: "[["),
                  let endRange = trimmed.range(of: "]]") else { continue }

            let name = String(trimmed[startRange.upperBound..<endRange.lowerBound])
            guard !name.isEmpty else { continue }

            let afterLink = String(trimmed[endRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let context: String
            if afterLink.hasPrefix("—") || afterLink.hasPrefix("-") {
                context = String(afterLink.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                context = "관련 문서"
            }

            entries.append((name: name, context: context))
        }

        return (entries, range)
    }

    private func sanitizeWikilink(_ name: String) -> String {
        name.replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: "\\", with: "-")
            .replacingOccurrences(of: "..", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
```

**Step 2: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/SemanticLinker/RelatedNotesWriter.swift
git commit -m "feat: add RelatedNotesWriter with merge and broken link prevention"
```

---

### Task 5: SemanticLinker Orchestrator

**Files:**
- Create: `Sources/Services/SemanticLinker/SemanticLinker.swift`

**Step 1: Create the SemanticLinker orchestrator file**

This ties all four phases together. Provides `linkAll()` for bulk vault audit and `linkNotes(filePaths:)` for targeted inbox/reclassification.

```swift
import Foundation

/// Orchestrates the full semantic linking pipeline:
/// Tag normalization → Candidate generation → AI filtering → Related Notes writing
struct SemanticLinker: Sendable {
    let pkmRoot: String
    private let maxConcurrentAI = 3
    private let batchSize = 5

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    struct LinkResult {
        var tagsNormalized: TagNormalizer.Result
        var notesLinked: Int
        var linksCreated: Int
    }

    // MARK: - Public API

    /// Run semantic linking for the entire vault (bulk mode for vault audit)
    func linkAll(onProgress: ((Double, String) -> Void)? = nil) async -> LinkResult {
        // Phase 1: Tag normalization
        onProgress?(0.0, "태그 정규화 중...")
        let tagResult: TagNormalizer.Result
        do {
            tagResult = try TagNormalizer(pkmRoot: pkmRoot).normalize()
            NSLog("[SemanticLinker] 태그 정규화: %d 파일, %d 태그 추가", tagResult.filesModified, tagResult.tagsAdded)
        } catch {
            NSLog("[SemanticLinker] 태그 정규화 실패: %@", error.localizedDescription)
            tagResult = TagNormalizer.Result()
        }
        onProgress?(0.1, "태그 정규화 완료")

        // Build vault note index + context map
        onProgress?(0.1, "볼트 인덱스 구축 중...")
        let allNotes = buildNoteIndex()
        let contextMap = await ContextMapBuilder(pkmRoot: pkmRoot).build()
        let noteNames = Set(allNotes.map { $0.name })
        onProgress?(0.2, "\(allNotes.count)개 노트 인덱스 완료")

        guard !allNotes.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        // Phase 2: Generate candidates for all notes
        let candidateGen = LinkCandidateGenerator()
        var notesWithCandidates: [(note: LinkCandidateGenerator.NoteInfo, candidates: [LinkCandidateGenerator.Candidate])] = []
        for note in allNotes {
            let candidates = candidateGen.generateCandidates(
                for: note,
                allNotes: allNotes,
                mocEntries: contextMap.entries
            )
            if !candidates.isEmpty {
                notesWithCandidates.append((note: note, candidates: candidates))
            }
        }

        onProgress?(0.3, "\(notesWithCandidates.count)개 노트에 후보 생성 완료")

        guard !notesWithCandidates.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        // Phase 3: AI filter in batches (max 3 concurrent)
        let aiFilter = LinkAIFilter()
        let batches = stride(from: 0, to: notesWithCandidates.count, by: batchSize).map {
            Array(notesWithCandidates[$0..<min($0 + batchSize, notesWithCandidates.count)])
        }

        var allLinks: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink])] = []
        let totalBatches = batches.count
        var completedBatches = 0

        await withTaskGroup(of: [(filePath: String, noteName: String, links: [LinkAIFilter.FilteredLink])].self) { group in
            var activeTasks = 0

            for batch in batches {
                if activeTasks >= maxConcurrentAI {
                    if let results = await group.next() {
                        allLinks.append(contentsOf: results)
                        activeTasks -= 1
                        completedBatches += 1
                        let progress = 0.3 + Double(completedBatches) / Double(totalBatches) * 0.5
                        onProgress?(progress, "AI 필터링 \(completedBatches)/\(totalBatches) 배치")
                    }
                }

                group.addTask {
                    let batchInput = batch.map { item in
                        (name: item.note.name, summary: item.note.summary, tags: item.note.tags, candidates: item.candidates)
                    }

                    do {
                        let results = try await aiFilter.filterBatch(notes: batchInput)
                        return zip(batch, results).map { (item, links) in
                            (filePath: item.note.filePath, noteName: item.note.name, links: links)
                        }
                    } catch {
                        NSLog("[SemanticLinker] AI 필터 배치 실패: %@", error.localizedDescription)
                        return batch.map { item in
                            (filePath: item.note.filePath, noteName: item.note.name, links: [LinkAIFilter.FilteredLink]())
                        }
                    }
                }
                activeTasks += 1
            }

            for await results in group {
                allLinks.append(contentsOf: results)
                completedBatches += 1
                let progress = 0.3 + Double(completedBatches) / Double(totalBatches) * 0.5
                onProgress?(progress, "AI 필터링 \(completedBatches)/\(totalBatches) 배치")
            }
        }

        onProgress?(0.8, "관련 노트 기록 중...")

        // Phase 4: Write links (forward + reverse)
        let writer = RelatedNotesWriter()
        let notePathMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0.filePath) })

        // Build reverse link map: target → [(source, context)]
        var reverseLinks: [String: [(name: String, context: String)]] = [:]
        for entry in allLinks {
            for link in entry.links {
                let reverseContext = "\(entry.noteName)에서 참조"
                reverseLinks[link.name, default: []].append((name: entry.noteName, context: reverseContext))
            }
        }

        var notesLinked = 0
        var linksCreated = 0

        // Write forward links
        for entry in allLinks where !entry.links.isEmpty {
            do {
                try writer.writeRelatedNotes(filePath: entry.filePath, newLinks: entry.links, noteNames: noteNames)
                notesLinked += 1
                linksCreated += entry.links.count
            } catch {
                NSLog("[SemanticLinker] 링크 기록 실패: %@ — %@", entry.noteName, error.localizedDescription)
            }
        }

        // Write reverse links
        for (targetName, sources) in reverseLinks {
            guard let targetPath = notePathMap[targetName] else { continue }
            let reverseFilteredLinks = sources.map { LinkAIFilter.FilteredLink(name: $0.name, context: $0.context) }
            do {
                try writer.writeRelatedNotes(filePath: targetPath, newLinks: reverseFilteredLinks, noteNames: noteNames)
                linksCreated += reverseFilteredLinks.count
            } catch {
                NSLog("[SemanticLinker] 역방향 링크 기록 실패: %@ — %@", targetName, error.localizedDescription)
            }
        }

        onProgress?(1.0, "시맨틱 링크 완료: \(notesLinked)개 노트, \(linksCreated)개 링크")

        return LinkResult(tagsNormalized: tagResult, notesLinked: notesLinked, linksCreated: linksCreated)
    }

    /// Run semantic linking for specific files (for inbox processing / reclassification)
    func linkNotes(filePaths: [String], onProgress: ((Double, String) -> Void)? = nil) async -> LinkResult {
        let tagResult = TagNormalizer.Result() // Skip bulk normalization for targeted linking

        let allNotes = buildNoteIndex()
        let contextMap = await ContextMapBuilder(pkmRoot: pkmRoot).build()
        let noteNames = Set(allNotes.map { $0.name })

        // Filter to target notes
        let targetNames = Set(filePaths.map {
            (($0 as NSString).lastPathComponent as NSString).deletingPathExtension
        })
        let targetNotes = allNotes.filter { targetNames.contains($0.name) }

        guard !targetNotes.isEmpty else {
            return LinkResult(tagsNormalized: tagResult, notesLinked: 0, linksCreated: 0)
        }

        let candidateGen = LinkCandidateGenerator()
        let aiFilter = LinkAIFilter()
        let writer = RelatedNotesWriter()
        let notePathMap = Dictionary(uniqueKeysWithValues: allNotes.map { ($0.name, $0.filePath) })

        var notesLinked = 0
        var linksCreated = 0

        for (i, note) in targetNotes.enumerated() {
            let candidates = candidateGen.generateCandidates(
                for: note,
                allNotes: allNotes,
                mocEntries: contextMap.entries
            )
            guard !candidates.isEmpty else { continue }

            do {
                let filtered = try await aiFilter.filterSingle(
                    noteName: note.name,
                    noteSummary: note.summary,
                    noteTags: note.tags,
                    candidates: candidates
                )

                if !filtered.isEmpty {
                    try writer.writeRelatedNotes(filePath: note.filePath, newLinks: filtered, noteNames: noteNames)
                    notesLinked += 1
                    linksCreated += filtered.count

                    // Reverse links
                    for link in filtered {
                        guard let targetPath = notePathMap[link.name] else { continue }
                        let reverseLink = LinkAIFilter.FilteredLink(name: note.name, context: "\(note.name)에서 참조")
                        try writer.writeRelatedNotes(filePath: targetPath, newLinks: [reverseLink], noteNames: noteNames)
                        linksCreated += 1
                    }
                }
            } catch {
                NSLog("[SemanticLinker] 노트 링크 실패: %@ — %@", note.name, error.localizedDescription)
            }

            let progress = Double(i + 1) / Double(targetNotes.count)
            onProgress?(progress, "\(note.name) 연결 완료")
        }

        return LinkResult(tagsNormalized: tagResult, notesLinked: notesLinked, linksCreated: linksCreated)
    }

    // MARK: - Private

    /// Build index of all notes in the vault with their metadata
    private func buildNoteIndex() -> [LinkCandidateGenerator.NoteInfo] {
        let fm = FileManager.default
        var notes: [LinkCandidateGenerator.NoteInfo] = []

        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        for (para, basePath) in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix("."), !file.hasPrefix("_") else { continue }
                    guard file != "\(folder).md" else { continue } // Skip index notes

                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

                    let (frontmatter, body) = Frontmatter.parse(markdown: content)
                    let baseName = (file as NSString).deletingPathExtension

                    // Parse existing Related Notes
                    let existingRelated = parseExistingRelatedNames(body)

                    notes.append(LinkCandidateGenerator.NoteInfo(
                        name: baseName,
                        filePath: filePath,
                        tags: frontmatter.tags,
                        summary: frontmatter.summary ?? "",
                        project: frontmatter.project,
                        folderName: folder,
                        para: para,
                        existingRelated: existingRelated
                    ))
                }
            }
        }

        return notes
    }

    /// Extract note names from existing ## Related Notes section
    private func parseExistingRelatedNames(_ body: String) -> Set<String> {
        var names = Set<String>()
        var inSection = false

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Related Notes") {
                inSection = true
                continue
            }
            if trimmed.hasPrefix("## ") && inSection {
                break
            }
            if inSection, trimmed.hasPrefix("- [[") {
                if let start = trimmed.range(of: "[["),
                   let end = trimmed.range(of: "]]") {
                    let name = String(trimmed[start.upperBound..<end.lowerBound])
                    if !name.isEmpty { names.insert(name) }
                }
            }
        }

        return names
    }
}
```

**Step 2: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Services/SemanticLinker/SemanticLinker.swift
git commit -m "feat: add SemanticLinker orchestrator with bulk and targeted modes"
```

---

### Task 6: Integrate into Vault Audit (DashboardView)

**Files:**
- Modify: `Sources/UI/DashboardView.swift`

**Step 1: Add linksCreated to VaultCheckResult**

Find the `VaultCheckResult` struct (near line 590) and add `linksCreated: Int` field.

**Step 2: Add semantic linking step after MOC regeneration**

In the `runVaultCheck()` method, after step 4 (MOC regenerate, `await generator.regenerateAll()`), add:

```swift
// 5. Semantic linking
if Task.isCancelled { return }
await MainActor.run { vaultCheckPhase = "노트 간 시맨틱 연결 중..." }
let linker = SemanticLinker(pkmRoot: root)
let linkResult = await linker.linkAll { progress, status in
    Task { @MainActor in
        vaultCheckPhase = status
    }
}
let semanticLinksCreated = linkResult.linksCreated
```

**Step 3: Update result snapshot**

Update the `VaultCheckResult` construction to include `linksCreated: semanticLinksCreated`.

**Step 4: Update StatisticsService detail to include link count**

Update the activity detail string to include semanticLinksCreated.

**Step 5: Update the result display section**

In the vault check results view (near line 236), add a row for semantic links:

```swift
if result.linksCreated > 0 {
    auditResultRow(icon: "link", label: "시맨틱 링크 생성", count: result.linksCreated, color: .blue)
}
```

**Step 6: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 7: Commit**

```bash
git add Sources/UI/DashboardView.swift
git commit -m "feat: integrate SemanticLinker into vault audit pipeline"
```

---

### Task 7: Integrate into InboxProcessor

**Files:**
- Modify: `Sources/Pipeline/InboxProcessor.swift`

**Step 1: Replace ContextLinker with SemanticLinker**

The current ContextLinker phase (lines 108-140) runs BEFORE file movement with in-flight classification data. Replace this with SemanticLinker that runs AFTER file movement using on-disk state.

Remove the ContextLinker block (lines 108-140: the `// Enrich with related notes` section). Keep the `enrichedClassifications` variable but remove the ContextLinker-specific code.

**Step 2: Add SemanticLinker after file moves**

After the MOC update section (near line 254), add semantic linking for successfully moved files:

```swift
// Semantic link: connect newly moved files with vault
let successPaths = processed.filter(\.isSuccess).map(\.targetPath)
if !successPaths.isEmpty {
    onProgress?(0.96, "시맨틱 연결 중...")
    let linker = SemanticLinker(pkmRoot: pkmRoot)
    let _ = await linker.linkNotes(filePaths: successPaths)
}
```

**Step 3: Clean up unused ContextLinker import**

Remove the `ContextLinker` usage entirely. The `ContextMapBuilder` import remains since `SemanticLinker` uses it internally.

**Step 4: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 5: Commit**

```bash
git add Sources/Pipeline/InboxProcessor.swift
git commit -m "feat: replace ContextLinker with SemanticLinker in inbox processing"
```

---

### Task 8: Integrate into VaultReorganizer

**Files:**
- Modify: `Sources/Pipeline/VaultReorganizer.swift`

**Step 1: Add SemanticLinker after file moves in execute()**

After the MOC update section (near line 276, after `await mocGenerator.updateMOCsForFolders(affectedFolders)`), add:

```swift
// Semantic link: reconnect moved files with vault
let successPaths = results.filter(\.isSuccess).map(\.targetPath)
if !successPaths.isEmpty {
    onProgress?(0.97, "시맨틱 연결 중...")
    let linker = SemanticLinker(pkmRoot: pkmRoot)
    let _ = await linker.linkNotes(filePaths: successPaths)
}
```

**Step 2: Verify build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -5`
Expected: Build Succeeded

**Step 3: Commit**

```bash
git add Sources/Pipeline/VaultReorganizer.swift
git commit -m "feat: integrate SemanticLinker into vault reorganization pipeline"
```

---

### Task 9: Build, Deploy, and Manual Test

**Step 1: Full release build**

Run: `cd /tmp/DotBrain-src && swift build -c release 2>&1 | tail -20`
Expected: Build Succeeded with no warnings in SemanticLinker files

**Step 2: Deploy to ~/Applications**

Run: `cp /tmp/DotBrain-src/.build/release/DotBrain ~/Applications/DotBrain.app/Contents/MacOS/DotBrain`

**Step 3: Test via vault audit**

Launch DotBrain → Dashboard → 볼트 점검. Verify:
- Progress shows "태그 정규화 중..." → "AI 필터링 N/M 배치" → "시맨틱 링크 완료: N개 노트, M개 링크"
- Result shows "시맨틱 링크 생성" count
- Open a few notes in Obsidian — verify `## Related Notes` sections have new cross-category links
- Verify no broken links created (all `[[targets]]` exist as files)

**Step 4: Commit all remaining changes**

```bash
git add -A
git commit -m "feat: complete semantic linking system with vault-wide cross-note connections"
```

---

## File Summary

| Action | File | Task |
|--------|------|------|
| Create | `Sources/Services/SemanticLinker/TagNormalizer.swift` | 1 |
| Create | `Sources/Services/SemanticLinker/LinkCandidateGenerator.swift` | 2 |
| Create | `Sources/Services/SemanticLinker/LinkAIFilter.swift` | 3 |
| Create | `Sources/Services/SemanticLinker/RelatedNotesWriter.swift` | 4 |
| Create | `Sources/Services/SemanticLinker/SemanticLinker.swift` | 5 |
| Modify | `Sources/UI/DashboardView.swift` | 6 |
| Modify | `Sources/Pipeline/InboxProcessor.swift` | 7 |
| Modify | `Sources/Pipeline/VaultReorganizer.swift` | 8 |

## Dependencies Between Tasks

- Tasks 1-4 are independent (can be done in any order)
- Task 5 depends on Tasks 1-4 (imports all four)
- Tasks 6-8 depend on Task 5 (use SemanticLinker)
- Task 9 depends on all previous tasks
