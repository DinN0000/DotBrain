import Foundation

struct RelatedNotesWriter: Sendable {

    typealias Entry = (name: String, context: String, relation: String)

    struct ParsedSection {
        var entries: [Entry]
        var range: Range<String.Index>
        /// True when the section contains user-authored lines this writer
        /// doesn't own (free text, sub-bullets, custom ### labels). Those
        /// bytes must never be rewritten — only appended after.
        var hasUnrecognized: Bool
    }

    /// Canonical relation ordering (also the display/priority order) and
    /// Korean labels — the single owner other SemanticLinker components
    /// (RelatedNotesPruner) read from.
    static let relationOrder = ["prerequisite", "project", "reference", "related"]
    static let relationLabels: [String: String] = [
        "prerequisite": "선행 지식",
        "project": "관련 프로젝트",
        "reference": "참고 자료",
        "related": "함께 보기",
    ]

    /// Korean label → relation, derived so it can never drift from relationLabels
    private static let relationMap: [String: String] =
        Dictionary(uniqueKeysWithValues: relationLabels.map { ($0.value, $0.key) })

    /// Returns true when the file was actually written — callers use this to
    /// re-hash modified files in ContentHashCache.
    @discardableResult
    func writeRelatedNotes(
        filePath: String,
        newLinks: [LinkAIFilter.FilteredLink],
        noteNames: Set<String>
    ) throws -> Bool {
        guard !newLinks.isEmpty else { return false }
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else { return false }

        let verifiedLinks = newLinks.filter { noteNames.contains($0.name) }
        guard !verifiedLinks.isEmpty else { return false }

        let parsed = parseRelatedNotes(content)
        let existingEntries = parsed?.entries ?? []
        let existingNames = Set(existingEntries.map { $0.name })
        let selfName = ((filePath as NSString).lastPathComponent as NSString).deletingPathExtension

        // batchSeen: the incoming batch itself can repeat a name (same-named
        // notes in different folders feeding reverse links) — first wins
        var batchSeen = Set<String>()
        let addedEntries: [Entry] = verifiedLinks.compactMap { link in
            guard !existingNames.contains(link.name),
                  link.name != selfName,
                  batchSeen.insert(link.name).inserted else { return nil }
            return (name: link.name, context: link.context, relation: link.relation)
        }

        // Section contains user content: append new entries at the section end
        // and leave every existing byte untouched
        if let parsed, parsed.hasUnrecognized {
            guard !addedEntries.isEmpty else { return false }
            var insertText = addedEntries.map { formatEntry($0) }.joined(separator: "\n") + "\n"
            let insertAt = parsed.range.upperBound
            if insertAt > content.startIndex, content[content.index(before: insertAt)] != "\n" {
                insertText = "\n" + insertText
            }
            var newContent = content
            newContent.insert(contentsOf: insertText, at: insertAt)
            try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
            return true
        }

        let finalEntries = existingEntries + addedEntries
        guard !finalEntries.isEmpty else { return false }

        let sectionText = renderSection(finalEntries)

        var newContent: String
        if let parsed {
            newContent = content.replacingCharacters(in: parsed.range, with: sectionText)
        } else {
            newContent = content.trimmingCharacters(in: .whitespacesAndNewlines) + sectionText
        }

        guard newContent != content else { return false }
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        return true
    }

    /// Rewrite the section to exactly `entries` — used by the link diet
    /// (RelatedNotesPruner). Refuses when the section contains user-authored
    /// bytes: those files are never pruned.
    @discardableResult
    func replaceEntries(filePath: String, entries: [Entry]) throws -> Bool {
        guard !entries.isEmpty,
              let content = try? String(contentsOfFile: filePath, encoding: .utf8),
              let parsed = parseRelatedNotes(content),
              !parsed.hasUnrecognized else { return false }

        let newContent = content.replacingCharacters(in: parsed.range, with: renderSection(entries))
        guard newContent != content else { return false }
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)
        return true
    }

    private func renderSection(_ entries: [Entry]) -> String {
        let relationTypes = Set(entries.map { $0.relation })

        // Any non-"related" type forces grouped rendering — even a single-type
        // section. A flat list has no ### header, so parseRelatedNotes would
        // read every entry back as "related" and the type would be lost on the
        // next merge/prune round-trip.
        if !relationTypes.isSubset(of: ["related"]) {
            // Group by relation type
            var grouped: [String] = []
            for rel in Self.relationOrder {
                let group = entries.filter { $0.relation == rel }
                guard !group.isEmpty else { continue }
                let label = Self.relationLabels[rel] ?? rel
                grouped.append("### \(label)")
                for entry in group {
                    grouped.append(formatEntry(entry))
                }
            }
            return "\n\n## Related Notes\n\n" + grouped.joined(separator: "\n") + "\n"
        }
        // Flat list (all same relation or all "related")
        let sectionLines = entries.map { formatEntry($0) }
        return "\n\n## Related Notes\n\n" + sectionLines.joined(separator: "\n") + "\n"
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

    func parseRelatedNotes(_ content: String) -> ParsedSection? {
        guard let headerRange = content.range(of: "\n## Related Notes") ?? content.range(of: "## Related Notes") else {
            return nil
        }

        var sectionStart = headerRange.lowerBound
        if sectionStart > content.startIndex && content[content.index(before: sectionStart)] == "\n" {
            sectionStart = content.index(before: sectionStart)
        }

        // Section ends at the newline before the next H2 header, or EOF
        let sectionEnd: String.Index
        if let nextHeader = content.range(of: "\n## ", range: headerRange.upperBound..<content.endIndex) {
            sectionEnd = nextHeader.lowerBound
        } else {
            sectionEnd = content.endIndex
        }

        var entries: [Entry] = []
        var hasUnrecognized = false
        var currentRelation = "related"
        let sectionContent = String(content[headerRange.upperBound..<sectionEnd])

        for (i, line) in sectionContent.components(separatedBy: "\n").enumerated() {
            if i == 0 { continue }  // remainder of the header line itself

            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            // Detect ### sub-headers for grouped format
            if trimmed.hasPrefix("### ") {
                let label = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                if let relation = Self.relationMap[label] {
                    currentRelation = relation
                } else {
                    // Custom user label — preserve, don't regroup
                    hasUnrecognized = true
                }
                continue
            }

            guard trimmed.hasPrefix("- [["),
                  let startRange = trimmed.range(of: "[["),
                  let endRange = trimmed.range(of: "]]"),
                  case let name = String(trimmed[startRange.upperBound..<endRange.lowerBound]),
                  !name.isEmpty else {
                hasUnrecognized = true
                continue
            }

            let afterLink = String(trimmed[endRange.upperBound...]).trimmingCharacters(in: .whitespaces)
            let context: String
            if afterLink.hasPrefix("—") || afterLink.hasPrefix("-") {
                context = String(afterLink.dropFirst()).trimmingCharacters(in: .whitespaces)
            } else {
                context = "관련 문서"
            }

            entries.append((name: name, context: context, relation: currentRelation))
        }

        return ParsedSection(
            entries: entries,
            range: sectionStart..<sectionEnd,
            hasUnrecognized: hasUnrecognized
        )
    }

    private func sanitizeWikilink(_ name: String) -> String {
        FrontmatterWriter.sanitizeWikilink(name)
    }
}
