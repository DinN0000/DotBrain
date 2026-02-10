import Foundation

/// Result of binary file text extraction
struct ExtractResult {
    let success: Bool
    let file: FileInfo?
    let metadata: [String: Any]
    let text: String?
    let error: String?

    struct FileInfo {
        let name: String
        let format: String
        let sizeKB: Double
    }

    static func failure(name: String, error: String) -> ExtractResult {
        ExtractResult(
            success: false,
            file: FileInfo(name: name, format: "", sizeKB: 0),
            metadata: [:],
            text: nil,
            error: error
        )
    }
}
