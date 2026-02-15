import Foundation

/// Common file content extraction utility — eliminates duplication across Pipeline modules
enum FileContentExtractor {
    /// Extract text content from a file for AI classification input
    /// - Parameters:
    ///   - filePath: Path to the file
    ///   - maxLength: Maximum character count (default 5000)
    /// - Returns: Extracted text content
    static func extract(from filePath: String, maxLength: Int = 5000) -> String {
        if BinaryExtractor.isBinaryFile(filePath) {
            let result = BinaryExtractor.extract(at: filePath)
            let text = result.text ?? "[바이너리 파일: \(result.file?.name ?? "unknown")]"
            return String(text.prefix(maxLength))
        }

        if let content = try? String(contentsOfFile: filePath, encoding: .utf8) {
            return String(content.prefix(maxLength))
        }

        return "[읽기 실패: \((filePath as NSString).lastPathComponent)]"
    }
}
