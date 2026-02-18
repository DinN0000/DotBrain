import Foundation
import ZIPFoundation

/// Extracts text and metadata from PPTX files (ZIP + XML)
enum PPTXExtractor {
    static let maxTextLength = 50_000

    // MARK: - Cached Regex Patterns
    private static let drawingMLTextRegex = try! NSRegularExpression(pattern: #"<(?:[^:]+:)?t[^>]*>([^<]*)</(?:[^:]+:)?t>"#)

    static func extract(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let sizeKB = Double(fileSize) / 1024.0

        let archive: Archive
        do {
            archive = try Archive(url: url, accessMode: .read)
        } catch {
            return .failure(name: fileName, error: "PPTX 파일을 열 수 없습니다: \(error.localizedDescription)")
        }

        // Extract metadata from docProps/core.xml
        var metadata = extractOOXMLMetadata(from: archive)

        // Find slide files
        var slideEntries: [(Int, Entry)] = []
        for entry in archive {
            if let match = entry.path.range(of: #"ppt/slides/slide(\d+)\.xml"#, options: .regularExpression) {
                let numStr = entry.path[match].replacingOccurrences(of: "ppt/slides/slide", with: "")
                    .replacingOccurrences(of: ".xml", with: "")
                if let num = Int(numStr) {
                    slideEntries.append((num, entry))
                }
            }
        }
        slideEntries.sort { $0.0 < $1.0 }
        metadata["slide_count"] = slideEntries.count

        // Extract text from each slide
        var slidesText: [String] = []

        for (idx, entry) in slideEntries {
            guard let content = readEntry(entry, from: archive) else { continue }
            let texts = extractDrawingMLTexts(from: content)

            if !texts.isEmpty {
                slidesText.append("[슬라이드 \(idx)]\n\(texts.joined(separator: "\n"))")
            }
        }

        var text: String? = slidesText.isEmpty ? nil : slidesText.joined(separator: "\n\n")
        if let t = text, t.count > maxTextLength {
            text = String(t.prefix(maxTextLength)) + "\n... (잘림)"
        }

        return ExtractResult(
            success: true,
            file: ExtractResult.FileInfo(name: fileName, format: "pptx", sizeKB: round(sizeKB * 10) / 10),
            metadata: metadata,
            text: text,
            error: nil
        )
    }

    /// Extract text elements from DrawingML XML (a:t tags)
    private static func extractDrawingMLTexts(from xml: String) -> [String] {
        var texts: [String] = []

        let nsRange = NSRange(xml.startIndex..., in: xml)
        let matches = drawingMLTextRegex.matches(in: xml, range: nsRange)

        for match in matches {
            if let textRange = Range(match.range(at: 1), in: xml) {
                let text = String(xml[textRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty {
                    texts.append(text)
                }
            }
        }

        return texts
    }
}

// MARK: - Shared OOXML utilities

private var _metadataRegexCache: [String: NSRegularExpression] = [:]

func readEntry(_ entry: Entry, from archive: Archive, maxBytes: Int = 4_000_000) -> String? {
    var data = Data()
    do {
        _ = try archive.extract(entry) { chunk in
            data.append(chunk)
            guard data.count <= maxBytes else { throw OOXMLError.tooLarge }
        }
        return String(data: data, encoding: .utf8)
    } catch is OOXMLError {
        // Hit size limit — return what we have
        return data.isEmpty ? nil : String(data: data, encoding: .utf8)
    } catch {
        return nil
    }
}

private enum OOXMLError: Error { case tooLarge }

func extractOOXMLMetadata(from archive: Archive) -> [String: Any] {
    var metadata: [String: Any] = [:]

    guard let coreEntry = archive["docProps/core.xml"],
          let content = readEntry(coreEntry, from: archive) else {
        return metadata
    }

    let fields = ["title", "creator", "subject", "description", "created", "modified"]
    for field in fields {
        let pattern = "<[^>]*:?\(field)[^>]*>([^<]+)<"

        let regex: NSRegularExpression
        if let cached = _metadataRegexCache[pattern] {
            regex = cached
        } else if let newRegex = try? NSRegularExpression(pattern: pattern) {
            _metadataRegexCache[pattern] = newRegex
            regex = newRegex
        } else {
            continue
        }

        if let match = regex.firstMatch(in: content, range: NSRange(content.startIndex..., in: content)),
           let range = Range(match.range(at: 1), in: content) {
            let value = String(content[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty {
                let key = field == "creator" ? "author" : field
                metadata[key] = value
            }
        }
    }

    return metadata
}
