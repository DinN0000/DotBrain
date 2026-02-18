import Foundation

/// Builds a VaultContextMap by parsing all MOC files (pure file I/O, no AI calls)
struct ContextMapBuilder: Sendable {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    /// Build context map from all MOC files across PARA categories
    func build() async -> VaultContextMap {
        let categories: [(PARACategory, String)] = [
            (.project, pathManager.projectsPath),
            (.area, pathManager.areaPath),
            (.resource, pathManager.resourcePath),
            (.archive, pathManager.archivePath),
        ]

        let fm = FileManager.default
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

        // Parse all MOC files in parallel
        let allEntries: [ContextMapEntry] = await withTaskGroup(
            of: [ContextMapEntry].self,
            returning: [ContextMapEntry].self
        ) { group in
            var nextIndex = 0
            let maxConcurrent = 3

            while nextIndex < min(maxConcurrent, folderTasks.count) {
                let task = folderTasks[nextIndex]
                group.addTask {
                    return self.parseMOC(
                        folderPath: task.folderPath,
                        folderName: task.folderName,
                        para: task.para
                    )
                }
                nextIndex += 1
            }

            var collected: [ContextMapEntry] = []
            for await entries in group {
                collected.append(contentsOf: entries)
                if nextIndex < folderTasks.count {
                    let task = folderTasks[nextIndex]
                    group.addTask {
                        return self.parseMOC(
                            folderPath: task.folderPath,
                            folderName: task.folderName,
                            para: task.para
                        )
                    }
                    nextIndex += 1
                }
            }
            return collected
        }

        return VaultContextMap(
            entries: allEntries,
            folderCount: folderTasks.count,
            buildDate: Date()
        )
    }

    /// Parse a single MOC file to extract document entries
    private func parseMOC(folderPath: String, folderName: String, para: PARACategory) -> [ContextMapEntry] {
        let mocPath = (folderPath as NSString).appendingPathComponent("\(folderName).md")

        guard let content = try? String(contentsOfFile: mocPath, encoding: .utf8) else {
            return []
        }

        let (frontmatter, body) = Frontmatter.parse(markdown: content)
        let folderTags = frontmatter.tags
        let folderSummary = frontmatter.summary ?? ""

        // Parse "## 문서 목록" section for [[WikiLink]] — summary entries
        var entries: [ContextMapEntry] = []
        var inDocSection = false

        for line in body.components(separatedBy: "\n") {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)

            if trimmedLine.hasPrefix("## 문서 목록") {
                inDocSection = true
                continue
            }

            // Another ## heading ends the document section
            if trimmedLine.hasPrefix("## ") && inDocSection {
                break
            }

            if inDocSection, trimmedLine.hasPrefix("- [[") {
                if let (noteName, summary) = parseDocListEntry(trimmedLine) {
                    entries.append(ContextMapEntry(
                        noteName: noteName,
                        summary: summary,
                        folderName: folderName,
                        para: para,
                        folderSummary: folderSummary,
                        tags: folderTags
                    ))
                }
            }
        }

        return entries
    }

    /// Parse a single doc list entry: "- [[NoteName]] — summary" or "- [[NoteName]]"
    private func parseDocListEntry(_ line: String) -> (name: String, summary: String)? {
        // Extract text between [[ and ]]
        guard let startRange = line.range(of: "[["),
              let endRange = line.range(of: "]]") else {
            return nil
        }

        let noteName = String(line[startRange.upperBound..<endRange.lowerBound])
        guard !noteName.isEmpty else { return nil }

        // Extract summary after " — " if present
        let afterLink = String(line[endRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        let summary: String
        if afterLink.hasPrefix("—") || afterLink.hasPrefix("—") {
            summary = afterLink.dropFirst().trimmingCharacters(in: .whitespaces)
        } else if afterLink.hasPrefix("-") {
            summary = afterLink.dropFirst().trimmingCharacters(in: .whitespaces)
        } else {
            summary = ""
        }

        return (name: noteName, summary: summary)
    }
}
