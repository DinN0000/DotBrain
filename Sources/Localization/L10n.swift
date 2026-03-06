import Foundation

/// Centralized localization strings.
/// Usage: `Text(L10n.Screen.inbox)` or `L10n.Processing.preparing`
enum L10n {
    static let bundle: Bundle = {
        // Production: .app bundle (Contents/Resources/ has .lproj)
        if Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko") != nil {
            return .main
        }
        // Development: find Resources/ relative to executable
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("Resources")
            if let bundle = Bundle(path: candidate.path),
               bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko") != nil {
                return bundle
            }
            dir = dir.deletingLastPathComponent()
        }
        return .main
    }()

    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    // MARK: - Screen Names

    enum Screen {
        static let inbox = tr("screen.inbox")
        static let dashboard = tr("screen.dashboard")
        static let settings = tr("screen.settings")
        static let paraManage = tr("screen.para_manage")
        static let search = tr("screen.search")
        static let vaultInspector = tr("screen.vault_inspector")
        static let aiStatistics = tr("screen.ai_statistics")
        static let results = tr("screen.results")
        static let folderRelationExplorer = tr("screen.folder_relation_explorer")
    }

    // MARK: - Processing Phases

    enum Processing {
        static let preparing = tr("processing.preparing")
        static let extracting = tr("processing.extracting")
        static let classifying = tr("processing.classifying")
        static let linking = tr("processing.linking")
        static let processing = tr("processing.processing")
        static let finishing = tr("processing.finishing")
    }

    // MARK: - Search

    enum Search {
        static let tagMatch = tr("search.tag_match")
        static let bodyMatch = tr("search.body_match")
        static let summaryMatch = tr("search.summary_match")
        static let titleMatch = tr("search.title_match")
    }

    // MARK: - AI Provider

    enum Provider {
        static let costIncluded = tr("provider.cost_included")
        static let costPerFile = tr("provider.cost_per_file")
        static let freeTier = tr("provider.free_tier")
    }
}
