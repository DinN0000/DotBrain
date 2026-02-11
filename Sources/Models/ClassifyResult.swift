import Foundation

/// Result of AI classification for a single file
struct ClassifyResult: Codable {
    let para: PARACategory
    let tags: [String]
    let summary: String
    let targetFolder: String
    var project: String?
    var confidence: Double

    /// Stage 1 batch classification item from Haiku
    struct Stage1Item: Codable {
        let fileName: String
        let para: PARACategory
        let tags: [String]
        let confidence: Double
        var project: String?
        var targetFolder: String?
    }

    /// Stage 2 precise classification item from Sonnet
    struct Stage2Item: Codable {
        let para: PARACategory
        let tags: [String]
        let summary: String
        let targetFolder: String
        var project: String?
        var confidence: Double?
    }
}

/// Input for classifier
struct ClassifyInput {
    let filePath: String
    let content: String
    let fileName: String
}
