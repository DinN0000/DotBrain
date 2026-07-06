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
    var area: String?
    var projects: [String]?
    var file: FileMetadata?
    /// Raw lines of frontmatter keys this parser doesn't own (Obsidian
    /// aliases, cssclasses, user-defined properties, ...). Preserved verbatim
    /// so parse→stringify rewrites never drop user metadata.
    var unknownRawLines: [String] = []

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

    /// Frontmatter keys this parser owns; anything else is preserved verbatim
    private static let recognizedKeys: Set<String> = [
        "para", "tags", "created", "status", "summary", "source",
        "project", "area", "projects", "file",
    ]

    /// Lightweight YAML parser (no external deps, frontmatter-level only)
    private static func parseYamlSimple(_ yaml: String) -> Frontmatter {
        var fm = Frontmatter(tags: [])
        var currentKey = ""
        var currentArray: [String]?
        var currentObj: [String: String]?
        var collectingUnknown = false
        var blockScalarKey: String?
        var blockScalarLines: [String] = []

        func flushPending() {
            if let arr = currentArray {
                applyValue(to: &fm, key: currentKey, array: arr)
                currentArray = nil
            }
            if let obj = currentObj {
                applyObject(to: &fm, key: currentKey, obj: obj)
                currentObj = nil
            }
            if let key = blockScalarKey {
                applyScalar(to: &fm, key: key, value: blockScalarLines.joined(separator: "\n"))
                blockScalarKey = nil
                blockScalarLines = []
            }
            collectingUnknown = false
        }

        for line in yaml.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .init(charactersIn: "\r"))

            if trimmed.isEmpty { continue }

            let isContinuation = trimmed.first == " " || trimmed.first == "\t"

            // Unknown-key block: keep every continuation line byte-for-byte
            if collectingUnknown, isContinuation || trimmed.hasPrefix("- ") {
                fm.unknownRawLines.append(trimmed)
                continue
            }

            // Block scalar body (summary: >- etc.) for a recognized key
            if blockScalarKey != nil, isContinuation {
                blockScalarLines.append(trimmed.trimmingCharacters(in: .whitespaces))
                continue
            }

            // Array item (  - value)
            if trimmed.hasPrefix("  - "), currentArray != nil {
                let value = String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespaces)
                currentArray?.append(unescapeYAML(value))
                continue
            }

            // Nested object property (  key: value)
            if trimmed.hasPrefix("  "), currentObj != nil {
                if let colonIdx = trimmed.firstIndex(of: ":") {
                    let key = trimmed[trimmed.index(trimmed.startIndex, offsetBy: 2)..<colonIdx]
                        .trimmingCharacters(in: .whitespaces)
                    let val = trimmed[trimmed.index(after: colonIdx)...]
                        .trimmingCharacters(in: .whitespaces)
                    currentObj?[key] = unescapeYAML(val)
                }
                continue
            }

            // Save previous array/object/block scalar
            flushPending()

            // Top-level key: value — find first colon outside quotes
            guard let colonIdx = findFirstUnquotedColon(in: trimmed) else { continue }
            let key = String(trimmed[..<colonIdx]).trimmingCharacters(in: .whitespaces)
            let rawValue = String(trimmed[trimmed.index(after: colonIdx)...]).trimmingCharacters(in: .whitespaces)

            currentKey = key

            // Keys we don't own are collected raw and re-emitted by stringify()
            if !recognizedKeys.contains(key) {
                collectingUnknown = true
                fm.unknownRawLines.append(trimmed)
                continue
            }

            if rawValue.isEmpty {
                // Could be array or object on next lines
                currentArray = []
                currentObj = [:]
                continue
            }

            // Block scalar indicator — body lines follow, joined with newlines
            if ["|", ">", "|-", ">-", "|+", ">+"].contains(rawValue) {
                blockScalarKey = key
                blockScalarLines = []
                continue
            }

            // Inline array [a, b, c]
            if rawValue.hasPrefix("[") && rawValue.hasSuffix("]") {
                let inner = String(rawValue.dropFirst().dropLast())
                let items = inner.split(separator: ",").map {
                    unescapeYAML($0.trimmingCharacters(in: .whitespaces))
                }
                applyValue(to: &fm, key: key, array: items)
                continue
            }

            // Scalar value
            applyScalar(to: &fm, key: key, value: unescapeYAML(rawValue))
        }

        // Flush remaining
        flushPending()

        return fm
    }

    /// Inverse of escapeYAML. Strips one layer of quoting and unescapes;
    /// unquoted values are returned untouched (a bare trailing quote or
    /// apostrophe is real content, not quoting).
    private static func unescapeYAML(_ raw: String) -> String {
        if raw.count >= 2, raw.hasPrefix("\""), raw.hasSuffix("\"") {
            let inner = raw.dropFirst().dropLast()
            var result = ""
            result.reserveCapacity(inner.count)
            var pendingEscape = false
            for ch in inner {
                if pendingEscape {
                    switch ch {
                    case "n": result.append("\n")
                    case "r": result.append("\r")
                    case "t": result.append("\t")
                    case "\"", "\\": result.append(ch)
                    default:
                        result.append("\\")
                        result.append(ch)
                    }
                    pendingEscape = false
                } else if ch == "\\" {
                    pendingEscape = true
                } else {
                    result.append(ch)
                }
            }
            if pendingEscape { result.append("\\") }
            return result
        }
        if raw.count >= 2, raw.hasPrefix("'"), raw.hasSuffix("'") {
            return String(raw.dropFirst().dropLast())
                .replacingOccurrences(of: "''", with: "'")
        }
        return raw
    }

    /// Find first colon that is not inside single or double quotes
    private static func findFirstUnquotedColon(in text: String) -> String.Index? {
        var inDouble = false
        var inSingle = false
        var prev: Character = "\0"

        for idx in text.indices {
            let ch = text[idx]
            if ch == "\"" && !inSingle && prev != "\\" { inDouble.toggle() }
            else if ch == "'" && !inDouble && prev != "\\" { inSingle.toggle() }
            else if ch == ":" && !inDouble && !inSingle { return idx }
            prev = ch
        }
        return nil
    }

    private static func applyScalar(to fm: inout Frontmatter, key: String, value: String) {
        switch key {
        case "para": fm.para = PARACategory(rawValue: value)
        case "created": fm.created = value
        case "status": fm.status = NoteStatus(rawValue: value)
        case "summary": fm.summary = value
        case "source": fm.source = NoteSource(rawValue: value)
        case "project": fm.project = value
        case "area": fm.area = value
        default: break
        }
    }

    private static func applyValue(to fm: inout Frontmatter, key: String, array: [String]) {
        switch key {
        case "tags": fm.tags = array
        case "projects": fm.projects = array
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

    /// Always double-quote and escape a value for YAML output
    private static func quoteYAML(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
        return "\"\(escaped)\""
    }

    /// Escape a string for safe YAML output (quotes only when needed)
    private static func escapeYAML(_ value: String) -> String {
        // Leading YAML indicators (aliases, anchors, block markers, ...)
        // break strict parsers like Obsidian's unless quoted
        let leadingIndicator = value.first.map { "-?*&!|>%@`,".contains($0) } ?? false
        let needsQuoting = value.contains(":") || value.contains("#") ||
            value.contains("\"") || value.contains("'") ||
            value.contains("\n") || value.contains("\r") ||
            value.hasPrefix(" ") || value.hasSuffix(" ") ||
            value.hasPrefix("[") || value.hasPrefix("{") ||
            leadingIndicator ||
            value == "true" || value == "false" ||
            value == "null" || value == "yes" || value == "no"

        guard needsQuoting else { return value }
        return quoteYAML(value)
    }

    /// Convert frontmatter to YAML string (with --- delimiters)
    func stringify() -> String {
        var lines: [String] = ["---"]

        if let para = para {
            lines.append("para: \(para.rawValue)")
        }
        if !tags.isEmpty {
            let escapedTags = tags.map { Frontmatter.quoteYAML($0) }
            lines.append("tags: [\(escapedTags.joined(separator: ", "))]")
        }
        if let created = created {
            lines.append("created: \(Frontmatter.escapeYAML(created))")
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
        if let area = area {
            lines.append("area: \(Frontmatter.escapeYAML(area))")
        }
        if let projects = projects, !projects.isEmpty {
            let escaped = projects.map { Frontmatter.escapeYAML($0) }
            lines.append("projects: [\(escaped.joined(separator: ", "))]")
        }
        if let file = file {
            lines.append("file:")
            lines.append("  name: \(Frontmatter.escapeYAML(file.name))")
            lines.append("  format: \(Frontmatter.escapeYAML(file.format))")
            lines.append("  size_kb: \(file.sizeKB)")
        }
        lines.append(contentsOf: unknownRawLines)

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
        if existing.area != nil { merged.area = existing.area }
        if let p = existing.projects, !p.isEmpty { merged.projects = p }
        if existing.file != nil { merged.file = existing.file }
        if !existing.unknownRawLines.isEmpty { merged.unknownRawLines = existing.unknownRawLines }

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
        area: String? = nil,
        projects: [String]? = nil,
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
            area: area,
            projects: projects,
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
