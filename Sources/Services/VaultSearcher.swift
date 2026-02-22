import Foundation

struct VaultSearcher {
    let pkmRoot: String
    private static let maxResults = 200

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Search the vault for notes matching the query.
    /// Phase 1: match title/tags/summary from note-index.json (zero file I/O).
    /// Phase 2: fallback to directory scan for body matches if index results < 10.
    func search(query: String) -> [SearchResult] {
        let queryLower = query.lowercased()
        let queryWords = queryLower.split(separator: " ").map(String.init)
        var results: [SearchResult] = []
        var indexMatchedPaths = Set<String>()

        let rootPrefix: String = {
            let canonical = URL(fileURLWithPath: pkmRoot).resolvingSymlinksInPath().path
            return canonical.hasSuffix("/") ? canonical : canonical + "/"
        }()

        // Phase 1: index-based search (no file I/O)
        if let index = loadNoteIndex() {
            for (_, entry) in index.notes {
                let filePath = rootPrefix + entry.path
                let noteName = ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
                let para = PARACategory(rawValue: entry.para)
                let isArchived = para == .archive

                // Title match
                if noteName.lowercased().contains(queryLower) {
                    results.append(SearchResult(
                        noteName: noteName,
                        filePath: filePath,
                        para: para,
                        tags: entry.tags,
                        summary: entry.summary,
                        matchType: .titleMatch,
                        relevanceScore: 1.0,
                        isArchived: isArchived
                    ))
                    indexMatchedPaths.insert(filePath)
                    continue
                }

                // Tag match
                let matchedTags = entry.tags.filter { tag in
                    queryWords.contains(where: { tag.lowercased().contains($0) })
                }
                if !matchedTags.isEmpty {
                    let score = Double(matchedTags.count) / Double(max(queryWords.count, 1))
                    results.append(SearchResult(
                        noteName: noteName,
                        filePath: filePath,
                        para: para,
                        tags: entry.tags,
                        summary: entry.summary,
                        matchType: .tagMatch,
                        relevanceScore: min(0.9, 0.5 + score * 0.4),
                        isArchived: isArchived
                    ))
                    indexMatchedPaths.insert(filePath)
                    continue
                }

                // Summary match
                if !entry.summary.isEmpty, entry.summary.lowercased().contains(queryLower) {
                    results.append(SearchResult(
                        noteName: noteName,
                        filePath: filePath,
                        para: para,
                        tags: entry.tags,
                        summary: entry.summary,
                        matchType: .summaryMatch,
                        relevanceScore: 0.6,
                        isArchived: isArchived
                    ))
                    indexMatchedPaths.insert(filePath)
                }
            }
        }

        // Phase 2: fallback body search via directory scan (only if index results < 10)
        if results.count < 10 {
            let bodyResults = searchBodies(queryLower: queryLower, excluding: indexMatchedPaths)
            results.append(contentsOf: bodyResults)
        }

        return Array(results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(Self.maxResults))
    }

    // MARK: - Private

    private func loadNoteIndex() -> NoteIndex? {
        let indexPath = pathManager.noteIndexPath
        guard let data = FileManager.default.contents(atPath: indexPath) else { return nil }
        return try? JSONDecoder().decode(NoteIndex.self, from: data)
    }

    private func searchBodies(queryLower: String, excluding: Set<String>) -> [SearchResult] {
        var results: [SearchResult] = []
        let fm = FileManager.default

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
                guard pathManager.isPathSafe(folderPath) else { continue }

                guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { continue }
                for file in files {
                    guard file.hasSuffix(".md"), !file.hasPrefix(".") else { continue }
                    let filePath = (folderPath as NSString).appendingPathComponent(file)
                    guard !excluding.contains(filePath) else { continue }
                    guard let handle = FileHandle(forReadingAtPath: filePath) else { continue }
                    let data = handle.readData(ofLength: 65536)
                    handle.closeFile()
                    guard let content = String(data: data, encoding: .utf8) else { continue }

                    let (frontmatter, body) = Frontmatter.parse(markdown: content)
                    if body.range(of: queryLower, options: .caseInsensitive) != nil {
                        let noteName = (file as NSString).deletingPathExtension
                        results.append(SearchResult(
                            noteName: noteName,
                            filePath: filePath,
                            para: frontmatter.para ?? para,
                            tags: frontmatter.tags,
                            summary: frontmatter.summary ?? "",
                            matchType: .bodyMatch,
                            relevanceScore: 0.3,
                            isArchived: para == .archive
                        ))
                    }
                }
            }
        }

        return results
    }
}
