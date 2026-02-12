import Foundation

struct SearchResult: Identifiable {
    let id = UUID()
    let noteName: String
    let filePath: String
    let para: PARACategory?
    let tags: [String]
    let summary: String
    let matchType: MatchType
    let relevanceScore: Double
    let isArchived: Bool

    enum MatchType: String {
        case tagMatch = "태그 일치"
        case bodyMatch = "본문 일치"
        case summaryMatch = "요약 일치"
        case titleMatch = "제목 일치"
    }
}
