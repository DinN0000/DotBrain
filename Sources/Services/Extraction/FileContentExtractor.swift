import Foundation

/// Common file content extraction utility — eliminates duplication across Pipeline modules
/// Uses smart extraction for markdown files: frontmatter + intro + headings + tail
/// to maximize classification quality while minimizing memory usage
enum FileContentExtractor {

    // MARK: - Public API

    /// Extract text content from a file for AI classification input
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - maxLength: Maximum character count (default 5000)
    /// - Returns: Extracted text content with structural context
    static func extract(from filePath: String, maxLength: Int = 5000) -> String {
        if BinaryExtractor.isBinaryFile(filePath) {
            let result = BinaryExtractor.extract(at: filePath)
            let text = result.text ?? "[바이너리 파일: \(result.file?.name ?? "unknown")]"
            return String(text.prefix(maxLength))
        }

        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        if ext == "md" || ext == "markdown" {
            return extractMarkdownSmart(from: filePath, maxLength: maxLength)
        }

        // Non-markdown text files: stream head + tail
        return extractTextHeadTail(from: filePath, maxLength: maxLength)
    }

    /// Extract a short preview suitable for batch classification (Stage 1)
    /// Includes frontmatter summary, heading outline, and first paragraph
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - maxLength: Maximum character count (default 800)
    /// - Returns: Condensed structural preview
    static func extractPreview(from filePath: String, content: String, maxLength: Int = 800) -> String {
        let ext = URL(fileURLWithPath: filePath).pathExtension.lowercased()
        guard ext == "md" || ext == "markdown" else {
            return String(content.prefix(maxLength))
        }

        return buildMarkdownPreview(from: content, maxLength: maxLength)
    }

    // MARK: - Markdown Smart Extraction

    /// Extract markdown content preserving structural context:
    /// 1. Frontmatter (full) — existing metadata is gold
    /// 2. First ~1500 chars — intro and core content
    /// 3. All headings — document outline for topic understanding
    /// 4. Last ~500 chars — conclusions, references, links
    private static func extractMarkdownSmart(from filePath: String, maxLength: Int) -> String {
        // Stream-read: only load what we need via FileHandle
        guard let handle = FileHandle(forReadingAtPath: filePath) else {
            return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
        }
        defer { handle.closeFile() }

        // Read up to 1MB for analysis (covers most markdown notes)
        let chunkSize = 1024 * 1024
        let data = handle.readData(ofLength: chunkSize)
        guard let fullText = String(data: data, encoding: .utf8), !fullText.isEmpty else {
            return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
        }

        // If file fits in maxLength, return as-is
        if fullText.count <= maxLength {
            return fullText
        }

        // Get file size to check if we read the whole thing
        let fileSize = handle.seekToEndOfFile()
        let hasMore = fileSize > chunkSize

        // Parse frontmatter boundary
        let (frontmatterText, bodyStartIndex) = extractFrontmatterRaw(from: fullText)

        let body = String(fullText[bodyStartIndex...])

        // Budget allocation (within maxLength)
        let frontmatterBudget = min(frontmatterText.count, maxLength / 5)     // ~20%
        let introBudget = maxLength * 3 / 10                                   // ~30%
        let headingBudget = maxLength * 3 / 10                                 // ~30%
        let tailBudget = maxLength - frontmatterBudget - introBudget - headingBudget  // ~20%

        var parts: [String] = []

        // Part 1: Frontmatter
        if !frontmatterText.isEmpty {
            parts.append(String(frontmatterText.prefix(frontmatterBudget)))
        }

        // Part 2: Intro (first N chars of body)
        let intro = String(body.prefix(introBudget))
        parts.append(intro)

        // Part 3: Heading outline (all ## headings from entire document)
        let headings = extractHeadings(from: body)
        if !headings.isEmpty {
            let headingSection = "\n[문서 구조]\n" + headings.joined(separator: "\n")
            let trimmedHeadings = String(headingSection.prefix(headingBudget))
            // Only add if we have headings beyond what's in the intro
            let introHeadingCount = intro.components(separatedBy: "\n").filter { $0.hasPrefix("#") }.count
            if headings.count > introHeadingCount {
                parts.append(trimmedHeadings)
            }
        }

        // Part 4: Tail (last N chars — conclusions, references, links)
        let tailSource = hasMore ? body : fullText
        if tailSource.count > introBudget + 200 {
            let tail = String(tailSource.suffix(tailBudget))
            // Avoid duplicating intro content
            if !intro.contains(tail.prefix(50)) {
                parts.append("\n[문서 끝부분]\n" + tail)
            }
        }

        let result = parts.joined(separator: "\n")
        return String(result.prefix(maxLength))
    }

    /// Build a condensed preview for Stage 1 batch classification
    /// Focuses on: existing tags/summary from frontmatter + heading outline + first paragraph
    private static func buildMarkdownPreview(from content: String, maxLength: Int) -> String {
        let (frontmatterText, bodyStartIndex) = extractFrontmatterRaw(from: content)
        let body = String(content[bodyStartIndex...])

        var parts: [String] = []

        // Extract key frontmatter fields (tags, summary, para) — these are classification gold
        let fmSummary = extractFrontmatterField(from: frontmatterText, field: "summary")
        let fmTags = extractFrontmatterField(from: frontmatterText, field: "tags")
        let fmPara = extractFrontmatterField(from: frontmatterText, field: "para")

        if let para = fmPara { parts.append("para: \(para)") }
        if let tags = fmTags { parts.append("tags: \(tags)") }
        if let summary = fmSummary { parts.append("summary: \(summary)") }

        // All headings — gives document structure in minimal space
        let headings = extractHeadings(from: body)
        if !headings.isEmpty {
            parts.append("구조: " + headings.prefix(10).joined(separator: " > "))
        }

        // First meaningful paragraph (skip empty lines and headings)
        let firstParagraph = extractFirstParagraph(from: body, maxLength: maxLength / 2)
        if !firstParagraph.isEmpty {
            parts.append(firstParagraph)
        }

        let result = parts.joined(separator: "\n")
        return String(result.prefix(maxLength))
    }

    // MARK: - Non-Markdown Text Extraction

    /// Read head + tail of a text file without loading entire file
    private static func extractTextHeadTail(from filePath: String, maxLength: Int) -> String {
        guard let handle = FileHandle(forReadingAtPath: filePath) else {
            return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
        }
        defer { handle.closeFile() }

        let headSize = maxLength * 4  // UTF-8 worst case: 4 bytes per char
        let headData = handle.readData(ofLength: headSize)

        guard let headText = String(data: headData, encoding: .utf8), !headText.isEmpty else {
            return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
        }

        if headText.count <= maxLength {
            return headText
        }

        // File is larger — read tail too
        let fileSize = handle.seekToEndOfFile()
        let tailBudget = maxLength / 4
        let headBudget = maxLength - tailBudget - 30  // 30 chars for separator

        var result = String(headText.prefix(headBudget))

        if fileSize > UInt64(headSize) {
            let tailOffset = max(0, fileSize - UInt64(tailBudget * 4))
            handle.seek(toFileOffset: tailOffset)
            let tailData = handle.readData(ofLength: tailBudget * 4)
            if let tailText = String(data: tailData, encoding: .utf8), tailText.count > 50 {
                result += "\n\n[... 중략 ...]\n\n" + String(tailText.suffix(tailBudget))
            }
        }

        return String(result.prefix(maxLength))
    }

    // MARK: - Helpers

    /// Extract raw frontmatter text and body start index
    private static func extractFrontmatterRaw(from text: String) -> (frontmatter: String, bodyStart: String.Index) {
        guard text.hasPrefix("---") else {
            return ("", text.startIndex)
        }

        let searchText = text.prefix(4096)  // Frontmatter is always near the top
        let range = NSRange(searchText.startIndex..., in: searchText)

        if let match = Frontmatter.frontmatterRegex.firstMatch(in: String(searchText), range: range) {
            let fullMatchRange = Range(match.range, in: searchText)!
            let fmRange = Range(match.range(at: 1), in: searchText)!
            let frontmatterContent = "---\n" + String(searchText[fmRange]) + "\n---"
            return (frontmatterContent, fullMatchRange.upperBound)
        }

        return ("", text.startIndex)
    }

    /// Extract a specific field value from raw frontmatter YAML
    private static func extractFrontmatterField(from fmText: String, field: String) -> String? {
        for line in fmText.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("\(field):") {
                let value = trimmed.dropFirst(field.count + 1).trimmingCharacters(in: .whitespaces)
                if !value.isEmpty && value != "[]" && value != "\"\"" {
                    return value
                }
            }
        }
        return nil
    }

    /// Extract all headings from markdown body
    private static func extractHeadings(from body: String) -> [String] {
        var headings: [String] = []
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("#") {
                // Preserve heading level indicator
                headings.append(trimmed)
            }
        }
        return headings
    }

    /// Extract first meaningful paragraph (skip blank lines, headings, frontmatter markers)
    private static func extractFirstParagraph(from body: String, maxLength: Int) -> String {
        var paragraph = ""
        var foundContent = false

        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines before content
            if trimmed.isEmpty {
                if foundContent { break }  // End of first paragraph
                continue
            }

            // Skip headings — we already capture those separately
            if trimmed.hasPrefix("#") {
                if foundContent { break }
                continue
            }

            foundContent = true
            paragraph += (paragraph.isEmpty ? "" : " ") + trimmed

            if paragraph.count >= maxLength { break }
        }

        return String(paragraph.prefix(maxLength))
    }
}
