import Foundation
import PDFKit

/// Extracts text and metadata from PDF files using PDFKit
enum PDFExtractor {
    static let maxTextLength = 50_000

    static func extract(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        guard let document = PDFDocument(url: url) else {
            return .failure(name: url.lastPathComponent, error: "PDF를 열 수 없습니다")
        }

        let fileName = url.lastPathComponent
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let sizeKB = Double(fileSize) / 1024.0

        // Metadata
        var metadata: [String: Any] = [:]
        metadata["page_count"] = document.pageCount

        if let attrs = document.documentAttributes {
            if let title = attrs[PDFDocumentAttribute.titleAttribute] as? String {
                metadata["title"] = title
            }
            if let author = attrs[PDFDocumentAttribute.authorAttribute] as? String {
                metadata["author"] = author
            }
            if let subject = attrs[PDFDocumentAttribute.subjectAttribute] as? String {
                metadata["subject"] = subject
            }
            if let creator = attrs[PDFDocumentAttribute.creatorAttribute] as? String {
                metadata["creator"] = creator
            }
        }

        // Text extraction
        var textChunks: [String] = []
        var totalLength = 0

        for i in 0..<document.pageCount {
            guard totalLength < maxTextLength,
                  let page = document.page(at: i),
                  let pageText = page.string else { continue }

            let trimmed = pageText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                textChunks.append(trimmed)
                totalLength += trimmed.count
            }
        }

        var text: String? = textChunks.isEmpty ? nil : textChunks.joined(separator: "\n\n")
        if let t = text, t.count > maxTextLength {
            text = String(t.prefix(maxTextLength)) + "\n... (잘림)"
        }

        return ExtractResult(
            success: true,
            file: ExtractResult.FileInfo(name: fileName, format: "pdf", sizeKB: round(sizeKB * 10) / 10),
            metadata: metadata,
            text: text,
            error: nil
        )
    }
}
