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

    enum MatchType {
        case tagMatch
        case bodyMatch
        case summaryMatch
        case titleMatch

        var displayName: String {
            switch self {
            case .tagMatch: return L10n.Search.tagMatch
            case .bodyMatch: return L10n.Search.bodyMatch
            case .summaryMatch: return L10n.Search.summaryMatch
            case .titleMatch: return L10n.Search.titleMatch
            }
        }
    }
}
