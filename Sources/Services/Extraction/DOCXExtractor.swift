import Foundation
import ZIPFoundation

/// Extracts text and metadata from DOCX files (ZIP + XML)
enum DOCXExtractor {
    static let maxTextLength = 50_000

    static func extract(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let sizeKB = Double(fileSize) / 1024.0

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return .failure(name: fileName, error: "DOCX 파일을 열 수 없습니다: \(error.localizedDescription)")
        }

        // Extract metadata from docProps/core.xml
        let metadata = extractOOXMLMetadata(from: archive)

        // Extract text from word/document.xml
        var text: String? = nil

        if let docEntry = archive["word/document.xml"],
           let content = readEntry(docEntry, from: archive) {
            let paragraphs = extractWordParagraphs(from: content)
            if !paragraphs.isEmpty {
                text = paragraphs.joined(separator: "\n")
            }
        }

        if let t = text, t.count > maxTextLength {
            text = String(t.prefix(maxTextLength)) + "\n... (잘림)"
        }

        return ExtractResult(
            success: true,
            file: ExtractResult.FileInfo(name: fileName, format: "docx", sizeKB: round(sizeKB * 10) / 10),
            metadata: metadata,
            text: text,
            error: nil
        )
    }

    /// Extract text from WordprocessingML paragraphs (<w:t> tags)
    private static func extractWordParagraphs(from xml: String) -> [String] {
        var paragraphs: [String] = []

        // Match paragraph blocks: <w:p ...>...</w:p>
        let paraPattern = #"<(?:[^:]+:)?p[\s>][\s\S]*?</(?:[^:]+:)?p>"#
        guard let paraRegex = try? NSRegularExpression(pattern: paraPattern) else { return paragraphs }

        let nsRange = NSRange(xml.startIndex..., in: xml)
        let paraMatches = paraRegex.matches(in: xml, range: nsRange)

        // Pattern for text runs: <w:t>text</w:t> or namespace variants
        let textPattern = #"<(?:[^:]+:)?t[^>]*>([^<]*)</(?:[^:]+:)?t>"#
        guard let textRegex = try? NSRegularExpression(pattern: textPattern) else { return paragraphs }

        for paraMatch in paraMatches {
            guard let paraRange = Range(paraMatch.range, in: xml) else { continue }
            let paraXML = String(xml[paraRange])

            var runs: [String] = []
            let paraNSRange = NSRange(paraXML.startIndex..., in: paraXML)
            let textMatches = textRegex.matches(in: paraXML, range: paraNSRange)

            for textMatch in textMatches {
                if let textRange = Range(textMatch.range(at: 1), in: paraXML) {
                    let text = String(paraXML[textRange])
                    if !text.isEmpty {
                        runs.append(text)
                    }
                }
            }

            if !runs.isEmpty {
                paragraphs.append(runs.joined())
            }
        }

        return paragraphs
    }
}
