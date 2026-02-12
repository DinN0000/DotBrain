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
                    if body.range(of: queryLower, options: .caseInsensitive) != nil {
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

        return Array(results.sorted { $0.relevanceScore > $1.relevanceScore }.prefix(200))
    }
}
