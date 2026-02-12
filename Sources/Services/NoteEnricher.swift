import Foundation

/// Enriches individual note metadata without moving the file
struct NoteEnricher {
    let pkmRoot: String
    private let aiService = AIService()
    private let maxContentLength = 5000

    /// Enrich a single note's frontmatter by filling empty fields with AI analysis
    func enrichNote(at filePath: String) async throws -> EnrichResult {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            throw EnrichError.cannotRead(filePath)
        }

        let (existing, body) = Frontmatter.parse(markdown: content)

        // Determine which fields need filling
        let needsPara = existing.para == nil
        let needsTags = existing.tags.isEmpty
        let needsSummary = existing.summary == nil || (existing.summary ?? "").isEmpty
        let needsSource = existing.source == nil

        // If all fields are present, nothing to do
        guard needsPara || needsTags || needsSummary || needsSource else {
            return EnrichResult(filePath: filePath, fieldsUpdated: 0)
        }

        // Ask AI to analyze the content
        let preview = String(body.prefix(maxContentLength))
        let fileName = (filePath as NSString).lastPathComponent

        let prompt = """
        다음 문서의 메타데이터를 분석해주세요.

        파일명: \(fileName)
        내용:
        \(preview)

        아래 JSON만 출력하세요:
        {
          "para": "project|area|resource|archive",
          "tags": ["태그1", "태그2"],
          "summary": "2-3문장 요약",
          "source": "original|meeting|literature|import"
        }

        tags는 최대 5개, summary는 한국어로 작성하세요.
        """

        let response = try await aiService.sendFast(maxTokens: 512, message: prompt)

        // Parse AI response
        guard let data = extractJSON(from: response),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EnrichError.aiParseFailed
        }

        // Merge: only fill empty fields
        var updated = existing
        var fieldsUpdated = 0

        if needsPara, let paraStr = json["para"] as? String, let para = PARACategory(rawValue: paraStr) {
            updated.para = para
            fieldsUpdated += 1
        }
        if needsTags, let tags = json["tags"] as? [String], !tags.isEmpty {
            updated.tags = Array(tags.prefix(5))
            fieldsUpdated += 1
        }
        if needsSummary, let summary = json["summary"] as? String, !summary.isEmpty {
            updated.summary = summary
            fieldsUpdated += 1
        }
        if needsSource, let sourceStr = json["source"] as? String, let source = NoteSource(rawValue: sourceStr) {
            updated.source = source
            fieldsUpdated += 1
        }

        // Preserve created date
        if updated.created == nil {
            updated.created = Frontmatter.today()
            fieldsUpdated += 1
        }
        if updated.status == nil {
            updated.status = .active
        }

        // Write back
        let newContent = updated.stringify() + "\n" + body
        try newContent.write(toFile: filePath, atomically: true, encoding: .utf8)

        return EnrichResult(filePath: filePath, fieldsUpdated: fieldsUpdated)
    }

    /// Enrich all notes in a folder that have missing frontmatter fields
    func enrichFolder(at folderPath: String) async -> [EnrichResult] {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(atPath: folderPath) else { return [] }

        let mdFiles = files.filter { $0.hasSuffix(".md") && !$0.hasPrefix(".") && !$0.hasPrefix("_") }
            .map { (folderPath as NSString).appendingPathComponent($0) }

        var results: [EnrichResult] = []

        await withTaskGroup(of: EnrichResult?.self) { group in
            var active = 0
            var index = 0

            while index < mdFiles.count || !group.isEmpty {
                // Launch up to 3 concurrent tasks
                while active < 3 && index < mdFiles.count {
                    let filePath = mdFiles[index]
                    index += 1
                    active += 1
                    group.addTask {
                        try? await self.enrichNote(at: filePath)
                    }
                }

                if let result = await group.next() {
                    active -= 1
                    if let r = result {
                        results.append(r)
                    }
                }
            }
        }

        return results
    }

    private func extractJSON(from text: String) -> Data? {
        let cleaned = text
            .replacingOccurrences(of: #"^```(?:json)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let start = cleaned.firstIndex(of: "{"),
           let end = cleaned.lastIndex(of: "}") {
            return String(cleaned[start...end]).data(using: .utf8)
        }
        return nil
    }
}

struct EnrichResult {
    let filePath: String
    let fieldsUpdated: Int

    var fileName: String {
        (filePath as NSString).lastPathComponent
    }
}

enum EnrichError: LocalizedError {
    case cannotRead(String)
    case aiParseFailed

    var errorDescription: String? {
        switch self {
        case .cannotRead(let path): return "파일 읽기 실패: \(path)"
        case .aiParseFailed: return "AI 응답 파싱 실패"
        }
    }
}
