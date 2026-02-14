import Foundation

/// Analyzes folder organization quality without AI calls.
/// Produces a health score (0.0-1.0) with actionable issues for real-time use.
struct FolderHealthAnalyzer {

    // MARK: - Types

    enum Issue {
        case tooManyFiles(count: Int)
        case missingFrontmatter(count: Int, total: Int)
        case lowTagDiversity(uniqueTags: Int, fileCount: Int)
        case noIndexNote

        var localizedDescription: String {
            switch self {
            case .tooManyFiles(let count):
                return "\(count)개 파일 — 세분화 필요"
            case .missingFrontmatter(let count, _):
                return "\(count)개 파일 메타데이터 누락"
            case .lowTagDiversity:
                return "태그 다양성 부족"
            case .noIndexNote:
                return "인덱스 노트 없음"
            }
        }
    }

    struct HealthScore {
        let folderPath: String
        let folderName: String
        let category: PARACategory
        let score: Double
        let fileCount: Int
        let issues: [Issue]

        var label: String {
            if score >= 0.8 { return "good" }
            if score >= 0.5 { return "attention" }
            return "urgent"
        }
    }

    // MARK: - Single Folder Analysis

    /// Analyze a single folder and return its health score
    static func analyze(
        folderPath: String,
        folderName: String,
        category: PARACategory
    ) -> HealthScore {
        let fm = FileManager.default
        let entries = (try? fm.contentsOfDirectory(atPath: folderPath)) ?? []

        // Filter out hidden and system-prefixed entries
        let visibleEntries = entries.filter { !$0.hasPrefix(".") && !$0.hasPrefix("_") }

        let mdFiles = visibleEntries.filter { entry in
            entry.hasSuffix(".md")
                && (entry as NSString).deletingPathExtension != folderName
        }

        let indexNoteName = "\(folderName).md"
        let allFiles = visibleEntries.filter { $0 != indexNoteName }
        let fileCount = allFiles.count

        var issues: [Issue] = []

        // Issue: Too many files in a single folder
        if fileCount > 20 {
            issues.append(.tooManyFiles(count: fileCount))
        }

        // Scan markdown files for frontmatter and tag data
        let (missingFMCount, allTags) = scanMarkdownFiles(mdFiles, in: folderPath)

        if missingFMCount > 0, !mdFiles.isEmpty {
            issues.append(.missingFrontmatter(count: missingFMCount, total: mdFiles.count))
        }

        // Issue: Low tag diversity across files
        let uniqueTagCount = Set(allTags).count
        if !mdFiles.isEmpty, uniqueTagCount < 2 {
            issues.append(.lowTagDiversity(uniqueTags: uniqueTagCount, fileCount: mdFiles.count))
        }

        // Issue: No index/MOC note for the folder
        let indexNotePath = (folderPath as NSString).appendingPathComponent(indexNoteName)
        if !fm.fileExists(atPath: indexNotePath) {
            issues.append(.noIndexNote)
        }

        let score = calculateScore(from: issues)

        return HealthScore(
            folderPath: folderPath,
            folderName: folderName,
            category: category,
            score: score,
            fileCount: fileCount,
            issues: issues
        )
    }

    // MARK: - Batch Analysis

    /// Analyze multiple folders efficiently, returning results sorted by worst health first
    static func analyzeAll(
        folderPaths: Set<String>,
        pkmRoot: String
    ) -> [HealthScore] {
        folderPaths.compactMap { folderPath -> HealthScore? in
            let folderName = (folderPath as NSString).lastPathComponent
            guard let category = categoryFromPath(folderPath, pkmRoot: pkmRoot) else { return nil }
            return analyze(folderPath: folderPath, folderName: folderName, category: category)
        }.sorted { $0.score < $1.score }
    }

    // MARK: - Private Helpers

    /// Scan markdown files for missing frontmatter and collect all tags
    private static func scanMarkdownFiles(
        _ mdFiles: [String],
        in folderPath: String
    ) -> (missingCount: Int, allTags: [String]) {
        var missingCount = 0
        var allTags: [String] = []

        for mdFile in mdFiles {
            let filePath = (folderPath as NSString).appendingPathComponent(mdFile)
            // Read only first 4KB — frontmatter is typically < 1KB
            guard let handle = FileHandle(forReadingAtPath: filePath) else {
                missingCount += 1
                continue
            }
            let data = handle.readData(ofLength: 4096)
            handle.closeFile()
            guard let content = String(data: data, encoding: .utf8) else {
                missingCount += 1
                continue
            }

            let (frontmatter, _) = Frontmatter.parse(markdown: content)
            if frontmatter.para == nil, frontmatter.tags.isEmpty {
                missingCount += 1
            }
            allTags.append(contentsOf: frontmatter.tags)
        }

        return (missingCount, allTags)
    }

    /// Calculate health score by deducting penalties from a perfect 1.0
    private static func calculateScore(from issues: [Issue]) -> Double {
        var score = 1.0

        for issue in issues {
            switch issue {
            case .tooManyFiles(let count):
                // Deduct up to 0.3 as file count exceeds 20, scaling over 40 extra files
                score -= min(Double(count - 20) / 40.0, 0.3)
            case .missingFrontmatter(let count, let total):
                // Deduct proportionally, up to 0.3 when all files lack frontmatter
                let ratio = Double(count) / Double(max(total, 1))
                score -= ratio * 0.3
            case .lowTagDiversity:
                score -= 0.15
            case .noIndexNote:
                score -= 0.1
            }
        }

        return max(0, min(1, score))
    }

    /// Determine PARA category from a folder path using canonicalized prefix matching
    private static func categoryFromPath(_ path: String, pkmRoot: String) -> PARACategory? {
        let pathManager = PKMPathManager(root: pkmRoot)
        let resolvedPath = URL(fileURLWithPath: path).resolvingSymlinksInPath().path
        for category in PARACategory.allCases {
            let base = pathManager.paraPath(for: category)
            let resolvedBase = URL(fileURLWithPath: base).resolvingSymlinksInPath().path
            if resolvedPath.hasPrefix(resolvedBase + "/") || resolvedPath == resolvedBase {
                return category
            }
        }
        return nil
    }
}
