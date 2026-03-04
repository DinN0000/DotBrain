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

        let searchString = String(text.prefix(4096))  // Frontmatter is always near the top
        let range = NSRange(searchString.startIndex..., in: searchString)

        if let match = Frontmatter.frontmatterRegex.firstMatch(in: searchString, range: range),
           let fullMatchRange = Range(match.range, in: searchString),
           let fmRange = Range(match.range(at: 1), in: searchString) {
            let frontmatterContent = "---\n" + String(searchString[fmRange]) + "\n---"
            // Convert index back to the original text
            let offset = text.distance(from: text.startIndex, to: text.index(text.startIndex, offsetBy: searchString.distance(from: searchString.startIndex, to: fullMatchRange.upperBound)))
            return (frontmatterContent, text.index(text.startIndex, offsetBy: offset))
        }

        return ("", text.startIndex)
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

}
