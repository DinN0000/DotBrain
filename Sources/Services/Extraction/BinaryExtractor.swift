import Foundation

/// Main dispatcher for binary file text extraction
enum BinaryExtractor {
    static let maxTextLength = 50_000

    /// Supported binary file extensions
    static let binaryExtensions: Set<String> = [
        "pdf", "pptx", "xlsx", "docx",
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic",
        "mov", "mp4", "avi", "mkv", "wmv", "flv", "webm", "m4v",
    ]

    /// Image file extensions
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic",
    ]

    /// Video file extensions
    static let videoExtensions: Set<String> = [
        "mov", "mp4", "avi", "mkv", "wmv", "flv", "webm", "m4v",
    ]

    /// Check if a file is binary
    static func isBinaryFile(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return binaryExtensions.contains(ext)
    }

    /// Extract text and metadata from a file
    static func extract(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "pdf":
            return PDFExtractor.extract(at: path)
        case "pptx":
            return PPTXExtractor.extract(at: path)
        case "xlsx":
            return XLSXExtractor.extract(at: path)
        case "docx":
            return DOCXExtractor.extract(at: path)
        case "jpg", "jpeg", "png", "gif", "bmp", "webp", "heic":
            return ImageExtractor.extract(at: path)
        case "mov", "mp4", "avi", "mkv", "wmv", "flv", "webm", "m4v":
            let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
            let sizeKB = Double(fileSize) / 1024.0
            return ExtractResult(
                success: true,
                file: ExtractResult.FileInfo(name: url.lastPathComponent, format: ext, sizeKB: round(sizeKB * 10) / 10),
                metadata: ["type": "video"],
                text: nil,
                error: nil
            )
        default:
            // Try reading as text
            return extractAsText(at: path)
        }
    }

    /// Extract content from text-based files
    static func extractAsText(at path: String) -> ExtractResult {
        let url = URL(fileURLWithPath: path)
        let fileName = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? Int) ?? 0
        let sizeKB = Double(fileSize) / 1024.0

        do {
            var content = try String(contentsOfFile: path, encoding: .utf8)
            if content.count > maxTextLength {
                content = String(content.prefix(maxTextLength)) + "\n... (잘림)"
            }
            return ExtractResult(
                success: true,
                file: ExtractResult.FileInfo(name: fileName, format: ext, sizeKB: round(sizeKB * 10) / 10),
                metadata: ["type": "text"],
                text: content,
                error: nil
            )
        } catch {
            return .failure(name: fileName, error: "텍스트 읽기 실패: \(error.localizedDescription)")
        }
    }
}
