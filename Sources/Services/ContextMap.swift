import Foundation

/// A single note entry extracted from a MOC file
struct ContextMapEntry: Sendable {
    let noteName: String        // "Aave_Analysis"
    let summary: String         // MOC에 기록된 요약
    let folderName: String      // "DeFi"
    let para: PARACategory      // .resource
    let folderSummary: String   // 폴더 전체 요약
    let tags: [String]          // 폴더 태그 클라우드
}

/// Vault-wide context map built from all MOC files
struct VaultContextMap: Sendable {
    let entries: [ContextMapEntry]
    let folderCount: Int
    let buildDate: Date

    /// Serialize to prompt text, organized by PARA category
    func toPromptText() -> String {
        guard !entries.isEmpty else { return "볼트에 기존 문서 없음" }

        var sections: [String] = []

        let grouped = Dictionary(grouping: entries) { $0.para }
        let order: [PARACategory] = [.project, .area, .resource, .archive]

        for para in order {
            guard let paraEntries = grouped[para], !paraEntries.isEmpty else { continue }

            let label: String
            switch para {
            case .project: label = "Project"
            case .area: label = "Area"
            case .resource: label = "Resource"
            case .archive: label = "Archive"
            }

            var lines: [String] = ["### \(label)"]

            // Group by folder
            let byFolder = Dictionary(grouping: paraEntries) { $0.folderName }
            for (folderName, folderEntries) in byFolder.sorted(by: { $0.key < $1.key }) {
                let folderSummary = folderEntries.first?.folderSummary ?? ""
                let folderTags = folderEntries.first?.tags ?? []
                let tagsStr = folderTags.isEmpty ? "" : " [\(folderTags.joined(separator: ", "))]"
                lines.append("**\(folderName)**: \(folderSummary)\(tagsStr)")

                for entry in folderEntries {
                    if entry.summary.isEmpty {
                        lines.append("  - [[\(entry.noteName)]]")
                    } else {
                        lines.append("  - [[\(entry.noteName)]] — \(entry.summary)")
                    }
                }
            }

            sections.append(lines.joined(separator: "\n"))
        }

        return sections.joined(separator: "\n\n")
    }
}
