import Foundation

/// A related note with context description for semantic linking
struct RelatedNote: Codable, Equatable {
    let name: String
    let context: String
}

/// Result of AI classification for a single file
struct ClassifyResult: Codable {
    var para: PARACategory
    var tags: [String]
    let summary: String
    var targetFolder: String
    var project: String?
    var confidence: Double
    var relatedNotes: [RelatedNote] = []
    /// AI's raw project name when fuzzyMatch failed — preserved for user confirmation
    var suggestedProject: String?

    /// Batch classification item
    struct BatchItem: Codable {
        let fileName: String
        let para: PARACategory
        let tags: [String]
        let summary: String
        let confidence: Double
        var project: String?
        var targetFolder: String?
    }
}

/// Input for classifier
struct ClassifyInput {
    let filePath: String
    let content: String
    let fileName: String
}
