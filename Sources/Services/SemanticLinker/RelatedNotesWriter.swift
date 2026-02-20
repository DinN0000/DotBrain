import Foundation

struct RelatedNotesWriter: Sendable {

    private typealias Entry = (name: String, context: String, relation: String)

    func writeRelatedNotes(
        filePath: String,
        newLinks: [LinkAIFilter.FilteredLink],
        noteNames: Set<String>
    ) throws {
        guard !newLinks.isEmpty else { return }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return }

        let verifiedLinks = newLinks.filter { noteNames.contains($0.name) }
        guard !verifiedLinks.isEmpty else { return }

        let (existingEntries, sectionRange) = parseRelatedNotes(content)

        let existingNames = Set(existingEntries.map { $0.name })
        var mergedEntries: [Entry] = existingEntries

        let selfName = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension

        for link in verifiedLinks {
            guard !existingNames.contains(link.name) else { continue }
            guard link.name != selfName else { continue }
            mergedEntries.append((name: link.name, context: link.context, relation: link.relation))
        }

        let finalEntries = mergedEntries
        guard !finalEntries.isEmpty else { return }

        let sectionText: String
        let relationTypes = Set(finalEntries.map { $0.relation })

        if relationTypes.count > 1 && !relationTypes.isSubset(of: ["related"]) {
            // Group by relation type
            let relationOrder = ["prerequisite", "project", "reference", "related"]
            let relationLabels: [String: String] = [
                "prerequisite": "선행 지식",
                "project": "관련 프로젝트",
                "reference": "참고 자료",
                "related": "함께 보기",
            ]
            var grouped: [String] = []
            for rel in relationOrder {
                let entries = finalEntries.filter { $0.relation == rel }
                guard !entries.isEmpty else { continue }
                let label = relationLabels[rel] ?? rel
                grouped.append("### \(label)")
                for entry in entries {
                    grouped.append(formatEntry(entry))
                }
            }
            sectionText = "\n\n## Related Notes\n\n" + grouped.joined(separator: "\n") + "\n"
        } else {
            // Flat list (all same relation or all "related")
            let sectionLines = finalEntries.map { formatEntry($0) }
            sectionText = "\n\n## Related Notes\n\n" + sectionLines.joined(separator: "\n") + "\n"
        }

        var newContent: String
        if let range = sectionRange {
            newContent = content.replacingCharacters(in: range, with: sectionText)
        } else {
            newContent = content.trimmingCharacters(in: .whitespacesAndNewlines) + sectionText
        }

        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
    }

    // MARK: - Formatting

    private func formatEntry(_ entry: Entry) -> String {
        let safeName = sanitizeWikilink(entry.name)
        let safeContext = entry.context
            .replacingOccurrences(of: "[[", with: "")
            .replacingOccurrences(of: "]]", with: "")
        return "- [[\(safeName)]] — \(safeContext)"
    }

    // MARK: - Parsing

    private func parseRelatedNotes(_ content: String) -> (entries: [Entry], range: Range<String.Index>?) {
        guard let headerRange = content.range(of: "\n## Related Notes") ?? content.range(of: "## Related Notes") else {
            return ([], nil)
        }

        var sectionStart = headerRange.lowerBound
        if sectionStart > content.startIndex && content[content.index(before: sectionStart)] == "\n" {
            sectionStart = content.index(before: sectionStart)
        }

        let afterHeader = String(content[headerRange.upperBound...])
        var sectionEndOffset = content.distance(from: content.startIndex, to: content.endIndex)
        var lineOffset = content.distance(from: content.startIndex, to: headerRange.upperBound)

        // Track current relation group from ### headers
        var currentRelation = "related"

        for line in afterHeader.components(separatedBy: "\n").dropFirst() {
            lineOffset += line.count + 1
            if line.hasPrefix("## ") {
                sectionEndOffset = lineOffset - line.count - 1
                break
            }
        }

        let sectionEnd = content.index(content.startIndex, offsetBy: min(sectionEndOffset, content.count))
        let range = sectionStart..<sectionEnd

        var entries: [Entry] = []
        let sectionContent = String(content[headerRange.upperBound..<sectionEnd])

        let relationMap: [String: String] = [
            "선행 지식": "prerequisite",
            "관련 프로젝트": "project",
            "참고 자료": "reference",
            "함께 보기": "related",
        ]

        currentRelation = "related"
        for line in sectionContent.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Detect ### sub-headers for grouped format
            if trimmed.hasPrefix("### ") {
                let label = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentRelation = relationMap[label] ?? "related"
                continue
            }

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

            entries.append((name: name, context: context, relation: currentRelation))
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
