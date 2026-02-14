import Foundation

/// Generates and updates Map of Content (MOC) files for PARA folders
struct MOCGenerator {
    let pkmRoot: String
    private let aiService = AIService.shared

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Generate/update MOC for a specific folder
    func generateMOC(folderPath: String, folderName: String, para: PARACategory) async throws {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: folderPath) else { return }

        // Collect document info
        var docs: [(name: String, summary: String, tags: [String])] = []

        for entry in entries.sorted() {
            guard entry.hasSuffix(".md"), !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
            guard entry != "\(folderName).md" else { continue } // Skip the MOC itself

            let filePath = (folderPath as NSString).appendingPathComponent(entry)
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { continue }

            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            let baseName = (entry as NSString).deletingPathExtension
            docs.append((
                name: baseName,
                summary: frontmatter.summary ?? "",
                tags: frontmatter.tags
            ))
        }

        guard !docs.isEmpty else { return }

        // Build AI prompt for folder summary
        let docList = docs.map { doc in
            let tags = doc.tags.isEmpty ? "" : " [\(doc.tags.joined(separator: ", "))]"
            return "- \(doc.name): \(doc.summary)\(tags)"
        }.joined(separator: "\n")

        let prompt = """
        다음은 "\(folderName)" 폴더에 포함된 문서 목록입니다:

        \(docList)

        이 폴더의 내용을 2-3문장으로 요약해주세요. 핵심 주제와 용도를 간결하게 설명하세요.
        요약만 출력하세요, 다른 텍스트 없이.
        """

        let folderSummary: String
        do {
            folderSummary = try await aiService.sendFast(maxTokens: 200, message: prompt)
        } catch {
            // Fallback: use basic description without AI
            folderSummary = "\(folderName) 폴더 — \(docs.count)개 문서 포함"
        }

        // Aggregate all tags
        var tagCounts: [String: Int] = [:]
        for doc in docs {
            for tag in doc.tags {
                tagCounts[tag, default: 0] += 1
            }
        }
        let topTags = tagCounts.sorted { $0.value > $1.value }.prefix(10).map { $0.key }

        // Build MOC content
        let frontmatter = Frontmatter.createDefault(
            para: para,
            tags: topTags,
            summary: folderSummary,
            source: .original
        )

        var mocContent = frontmatter.stringify()
        mocContent += "\n\n# \(folderName)\n\n"
        mocContent += "> \(folderSummary)\n\n"
        mocContent += "## 문서 목록\n\n"

        for doc in docs {
            if doc.summary.isEmpty {
                mocContent += "- [[\(doc.name)]]\n"
            } else {
                mocContent += "- [[\(doc.name)]] — \(doc.summary)\n"
            }
        }

        if !topTags.isEmpty {
            mocContent += "\n## 태그 클라우드\n\n"
            mocContent += topTags.joined(separator: ", ") + "\n"
        }

        // Write MOC file
        let mocPath = (folderPath as NSString).appendingPathComponent("\(folderName).md")
        try mocContent.write(toFile: mocPath, atomically: true, encoding: .utf8)
    }

    /// Update MOCs for all folders that were modified during processing
    func updateMOCsForFolders(_ folderPaths: Set<String>) async {
        var parentPaths: Set<String> = []

        for folderPath in folderPaths {
            let folderName = (folderPath as NSString).lastPathComponent
            // Determine PARA category from path
            let para = categoryFromPath(folderPath)
            do {
                try await generateMOC(folderPath: folderPath, folderName: folderName, para: para)
            } catch {
                print("[MOCGenerator] MOC 갱신 실패: \(folderName) — \(error.localizedDescription)")
            }
            // Track parent category paths for root MOC update
            let parentPath = (folderPath as NSString).deletingLastPathComponent
            parentPaths.insert(parentPath)
        }

        // Also update the root-level category MOCs
        for parentPath in parentPaths {
            let para = categoryFromPath(parentPath + "/")
            do {
                try await generateCategoryRootMOC(basePath: parentPath, para: para)
            } catch {
                let name = (parentPath as NSString).lastPathComponent
                print("[MOCGenerator] 카테고리 루트 MOC 갱신 실패: \(name) — \(error.localizedDescription)")
            }
        }
    }

    /// Generate a root-level index note for a PARA category (e.g., 2_Area.md listing all subfolders)
    func generateCategoryRootMOC(basePath: String, para: PARACategory) async throws {
        let fm = FileManager.default
        let categoryName = (basePath as NSString).lastPathComponent
        guard let entries = try? fm.contentsOfDirectory(atPath: basePath) else { return }

        // Collect subfolders with their MOC summaries
        var subfolders: [(name: String, summary: String, fileCount: Int)] = []

        for entry in entries.sorted() {
            guard !entry.hasPrefix("."), !entry.hasPrefix("_") else { continue }
            let entryPath = (basePath as NSString).appendingPathComponent(entry)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: entryPath, isDirectory: &isDir), isDir.boolValue else { continue }

            // Try to read summary from the subfolder's own MOC
            let subMOCPath = (entryPath as NSString).appendingPathComponent("\(entry).md")
            var summary = ""
            if let content = try? String(contentsOfFile: subMOCPath, encoding: .utf8) {
                let (frontmatter, _) = Frontmatter.parse(markdown: content)
                summary = frontmatter.summary ?? ""
            }

            // Count files in subfolder
            let subEntries = (try? fm.contentsOfDirectory(atPath: entryPath)) ?? []
            let fileCount = subEntries.filter {
                !$0.hasPrefix(".") && !$0.hasPrefix("_") && $0.hasSuffix(".md") && $0 != "\(entry).md"
            }.count

            subfolders.append((name: entry, summary: summary, fileCount: fileCount))
        }

        guard !subfolders.isEmpty else { return }

        // Build root MOC content
        let frontmatter = Frontmatter.createDefault(
            para: para,
            tags: [],
            summary: "\(para.displayName) 카테고리 인덱스 — \(subfolders.count)개 폴더",
            source: .original
        )

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

        let mocPath = (basePath as NSString).appendingPathComponent("\(categoryName).md")
        try content.write(toFile: mocPath, atomically: true, encoding: .utf8)
    }

    /// Regenerate all MOCs across the entire vault
    func regenerateAll() async {
        let fm = FileManager.default
        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        // Collect all folder tasks first, then run concurrently (max 3 API calls)
        var folderTasks: [(para: PARACategory, folderPath: String, folderName: String)] = []
        for (para, basePath) in categories {
            guard let folders = try? fm.contentsOfDirectory(atPath: basePath) else { continue }
            for folder in folders {
                guard !folder.hasPrefix("."), !folder.hasPrefix("_") else { continue }
                let folderPath = (basePath as NSString).appendingPathComponent(folder)
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue else { continue }
                // Skip .md files at category root (they're root MOCs, not subfolders)
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

        // Generate root-level category index notes (e.g., 1_Project.md, 2_Area.md, ...)
        for (para, basePath) in categories {
            do {
                try await generateCategoryRootMOC(basePath: basePath, para: para)
            } catch {
                let name = (basePath as NSString).lastPathComponent
                print("[MOCGenerator] 카테고리 루트 MOC 갱신 실패: \(name) — \(error.localizedDescription)")
            }
        }
    }

    private func categoryFromPath(_ path: String) -> PARACategory {
        if path.contains("/1_Project/") { return .project }
        if path.contains("/2_Area/") { return .area }
        if path.contains("/3_Resource/") { return .resource }
        return .archive
    }
}
