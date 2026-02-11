import Foundation

/// Note status values
enum NoteStatus: String, Codable {
    case active
    case draft
    case completed
    case onHold = "on-hold"
}

/// Note source values
enum NoteSource: String, Codable {
    case original
    case meeting
    case literature
    case `import` = "import"
}

/// File metadata for binary companion notes
struct FileMetadata: Codable {
    let name: String
    let format: String
    let sizeKB: Double

    enum CodingKeys: String, CodingKey {
        case name, format
        case sizeKB = "size_kb"
    }
}

/// YAML frontmatter structure for PKM notes
struct Frontmatter {
    var para: PARACategory?
    var tags: [String]
    var created: String?
    var status: NoteStatus?
    var summary: String?
    var source: NoteSource?
    var project: String?
    var file: FileMetadata?

    static let frontmatterRegex = try! NSRegularExpression(
        pattern: "^---\\r?\\n([\\s\\S]*?)\\r?\\n---\\r?\\n?",
        options: []
    )

    // MARK: - Parse

    /// Parse frontmatter from markdown text
    static func parse(markdown: String) -> (frontmatter: Frontmatter, body: String) {
        let nsRange = NSRange(markdown.startIndex..., in: markdown)
        guard let match = frontmatterRegex.firstMatch(in: markdown, range: nsRange),
              let yamlRange = Range(match.range(at: 1), in: markdown),
              let fullRange = Range(match.range, in: markdown) else {
            return (Frontmatter(tags: []), markdown)
        }

        let yamlStr = String(markdown[yamlRange])
        let body = String(markdown[fullRange.upperBound...])
        let frontmatter = parseYamlSimple(yamlStr)
        return (frontmatter, body)
    }

    /// Lightweight YAML parser (no external deps, frontmatter-level only)
    private static func parseYamlSimple(_ yaml: String) -> Frontmatter {
        var fm = Frontmatter(tags: [])
        var currentKey = ""
        var currentArray: [String]?
        var currentObj: [String: String]?

        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))

            if trimmed.isEmpty { continue }

            // Array item (  - value)
            if trimmed.hasPrefix("  - "), currentArray != nil {
                let value = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentArray?.append(value)
                continue
            }

            // Nested object property (  key: value)
            if trimmed.hasPrefix("  "), currentObj != nil {
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let key = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colonIdx]
                        .trimmingCharacters(in: .whitespaces)
                    let val = trimmed[trimmed.index(after: colonIdx)...]
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: .init(charactersIn: "\"'"))
                    currentObj?[key] = val
                }
                continue
            }

            // Save previous array/object
            if let arr = currentArray {
                applyValue(to: &fm, key: currentKey, array: arr)
                currentArray = nil
            }
            if let obj = currentObj {
                applyObject(to: &fm, key: currentKey, obj: obj)
                currentObj = nil
            }

            // Top-level key: value
            guard let colonIdx = trimmed.firstIndex(of: ":") else { continue }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            currentKey = key

            if rawValue.isEmpty {
                // Could be array or object on next lines
                currentArray = []
                currentObj = [:]
                continue
            }

            // Inline array [a, b, c]
            if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                let inner = String(rawValue.dropFirst().dropLast())
                let items = inner.split(separator: ",").map {
                    $0.trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: .init(charactersIn: "\"'"))
                }
                applyValue(to: &fm, key: key, array: items)
                continue
            }

            // Scalar value
            let cleaned = rawValue
                .trimmingCharacters(in: .init(charactersIn: "\"'"))
            applyScalar(to: &fm, key: key, value: cleaned)
        }

        // Flush remaining
        if let arr = currentArray {
            applyValue(to: &fm, key: currentKey, array: arr)
        }
        if let obj = currentObj {
            applyObject(to: &fm, key: currentKey, obj: obj)
        }

        return fm
    }

    private static func applyScalar(to fm: inout Frontmatter, key: String, value: String) {
        switch key {
        case "para": fm.para = PARACategory(rawValue: value)
        case "created": fm.created = value
        case "status": fm.status = NoteStatus(rawValue: value)
        case "summary": fm.summary = value
        case "source": fm.source = NoteSource(rawValue: value)
        case "project": fm.project = value
        default: break
        }
    }

    private static func applyValue(to fm: inout Frontmatter, key: String, array: [String]) {
        switch key {
        case "tags": fm.tags = array
        default: break
        }
    }

    private static func applyObject(to fm: inout Frontmatter, key: String, obj: [String: String]) {
        switch key {
        case "file":
            if let name = obj["name"], let format = obj["format"] {
                let sizeKB = Double(obj["size_kb"] ?? "0") ?? 0
                fm.file = FileMetadata(name: name, format: format, sizeKB: sizeKB)
            }
        default: break
        }
    }

    // MARK: - Stringify

    /// Escape a string for safe YAML output
    private static func escapeYAML(_ value: String) -> String {
        let needsQuoting = value.contains(":") || value.contains("#") ||
            value.contains("\"") || value.contains("'") ||
            value.contains("\n") || value.contains("\r") ||
            value.hasPrefix(" ") || value.hasSuffix(" ") ||
            value.hasPrefix("[") || value.hasPrefix("{") ||
            value == "true" || value == "false" ||
            value == "null" || value == "yes" || value == "no"

        guard needsQuoting else { return value }

        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    /// Convert frontmatter to YAML string (with --- delimiters)
    func stringify() -> String {
        var lines: [String] = ["---"]

        if let para = para {
            lines.append("para: \(para.rawValue)")
        }
        if !tags.isEmpty {
            let escapedTags = tags.map { Frontmatter.escapeYAML($0) }
            lines.append("tags: [\(escapedTags.joined(separator: ", "))]")
        }
        if let created = created {
            lines.append("created: \(created)")
        }
        if let status = status {
            lines.append("status: \(status.rawValue)")
        }
        if let summary = summary {
            lines.append("summary: \(Frontmatter.escapeYAML(summary))")
        }
        if let source = source {
            lines.append("source: \(source.rawValue)")
        }
        if let project = project {
            lines.append("project: \(Frontmatter.escapeYAML(project))")
        }
        if let file = file {
            lines.append("file:")
            lines.append("  name: \(Frontmatter.escapeYAML(file.name))")
            lines.append("  format: \(file.format)")
            lines.append("  size_kb: \(file.sizeKB)")
        }

        lines.append("---")
        return lines.joined(separator: "\n")
    }

    // MARK: - Inject

    /// Inject frontmatter into markdown (merge with existing, existing values take priority)
    func inject(into markdown: String) -> String {
        let (existing, body) = Frontmatter.parse(markdown: markdown)

        var merged = self
        // Existing values take priority
        if existing.para != nil { merged.para = existing.para }
        if !existing.tags.isEmpty { merged.tags = existing.tags }
        if existing.created != nil { merged.created = existing.created }
        if existing.status != nil { merged.status = existing.status }
        if let s = existing.summary, !s.isEmpty { merged.summary = s }
        if existing.source != nil { merged.source = existing.source }
        if existing.project != nil { merged.project = existing.project }
        if existing.file != nil { merged.file = existing.file }

        return merged.stringify() + "\n" + body
    }

    // MARK: - Factory

    /// Create default frontmatter with overrides
    static func createDefault(
        para: PARACategory = .resource,
        tags: [String] = [],
        summary: String = "",
        source: NoteSource = .import,
        project: String? = nil,
        file: FileMetadata? = nil
    ) -> Frontmatter {
        Frontmatter(
            para: para,
            tags: tags,
            created: today(),
            status: .active,
            summary: summary,
            source: source,
            project: project,
            file: file
        )
    }

    /// Returns today's date as YYYY-MM-DD
    static func today() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}
