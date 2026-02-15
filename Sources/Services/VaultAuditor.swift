import Foundation

/// Audit report for the entire PKM vault
struct AuditReport {
    var brokenLinks: [BrokenLink]
    var missingFrontmatter: [String]
    var untaggedFiles: [String]
    var missingPARA: [String]
    var totalScanned: Int

    struct BrokenLink {
        let filePath: String
        let linkTarget: String
        let suggestion: String?
    }

    var totalIssues: Int {
        brokenLinks.count + missingFrontmatter.count + untaggedFiles.count + missingPARA.count
    }
}

/// Result of an automatic repair pass
struct RepairResult {
    var linksFixed: Int
    var frontmatterInjected: Int
    var paraFixed: Int
}

/// Scans the entire PKM vault and reports/fixes issues
struct VaultAuditor {
    let pkmRoot: String

    private var pathManager: PKMPathManager {
        PKMPathManager(root: pkmRoot)
    }

    // MARK: - Audit

    /// Perform a full audit of the vault, returning all detected issues
    func audit() -> AuditReport {
        let files = allMarkdownFiles()
        let noteNames = allNoteNames()

        var brokenLinks: [AuditReport.BrokenLink] = []
        var missingFrontmatter: [String] = []
        var untaggedFiles: [String] = []
        var missingPARA: [String] = []

        let wikiLinkPattern = try! NSRegularExpression(
            pattern: "\\[\\[([^\\]]+)\\]\\]",
            options: []
        )

        for filePath in files {
            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }

            let (frontmatter, body) = Frontmatter.parse(markdown: content)

            // Check frontmatter existence (has at least para)
            if frontmatter.para == nil && frontmatter.tags.isEmpty
                && frontmatter.created == nil && frontmatter.status == nil
            {
                missingFrontmatter.append(filePath)
            }

            // Check tags
            if frontmatter.tags.isEmpty {
                untaggedFiles.append(filePath)
            }

            // Check PARA field
            if frontmatter.para == nil {
                missingPARA.append(filePath)
            }

            // Find all [[WikiLink]] references in the body
            let nsBody = body as NSString
            let matches = wikiLinkPattern.matches(
                in: body,
                range: NSRange(location: 0, length: nsBody.length)
            )

            for match in matches {
                guard let linkRange = Range(match.range(at: 1), in: body) else { continue }
                var linkTarget = String(body[linkRange])

                // Handle pipe aliases: [[target|display]] -> extract target
                if let pipeIndex = linkTarget.firstIndex(of: "|") {
                    linkTarget = String(linkTarget[..<pipeIndex])
                }

                let trimmedTarget = linkTarget.trimmingCharacters(in: .whitespaces)
                guard !trimmedTarget.isEmpty else { continue }

                // Extract basename for path-based links: [[folder/note]] → note
                let resolvedName: String
                if trimmedTarget.contains("/") {
                    resolvedName = (trimmedTarget as NSString).lastPathComponent
                } else {
                    resolvedName = trimmedTarget
                }

                // Check if the target (or its basename) exists as a note
                if !noteNames.contains(trimmedTarget) && !noteNames.contains(resolvedName) {
                    let suggestion = findClosestMatch(resolvedName, in: noteNames)
                    brokenLinks.append(AuditReport.BrokenLink(
                        filePath: filePath,
                        linkTarget: trimmedTarget,
                        suggestion: suggestion
                    ))
                }
            }
        }

        return AuditReport(
            brokenLinks: brokenLinks,
            missingFrontmatter: missingFrontmatter,
            untaggedFiles: untaggedFiles,
            missingPARA: missingPARA,
            totalScanned: files.count
        )
    }

    // MARK: - Repair

    /// Automatically repair issues found in the audit report
    func repair(report: AuditReport) -> RepairResult {
        var linksFixed = 0
        var frontmatterInjected = 0
        var paraFixed = 0

        // Fix broken links where a close suggestion exists
        // Group broken links by file to batch replacements
        var linksByFile: [String: [(target: String, suggestion: String)]] = [:]
        for brokenLink in report.brokenLinks {
            guard let suggestion = brokenLink.suggestion else { continue }
            // Compare using basename for path-based links
            let targetForComparison: String
            if brokenLink.linkTarget.contains("/") {
                targetForComparison = (brokenLink.linkTarget as NSString).lastPathComponent
            } else {
                targetForComparison = brokenLink.linkTarget
            }
            let dist = levenshteinDistance(targetForComparison.lowercased(), suggestion.lowercased())
            // Allow higher edit distance for longer names
            let maxDist = max(3, targetForComparison.count / 3)
            if dist <= maxDist {
                linksByFile[brokenLink.filePath, default: []].append(
                    (target: brokenLink.linkTarget, suggestion: suggestion)
                )
            }
        }

        for (filePath, replacements) in linksByFile {
            guard var content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }
            var modified = false
            for replacement in replacements {
                let oldLink = "[[\(replacement.target)]]"
                let newLink = "[[\(replacement.suggestion)]]"
                if content.contains(oldLink) {
                    content = content.replacingOccurrences(of: oldLink, with: newLink)
                    modified = true
                    linksFixed += 1
                }
                // Also handle pipe alias variant
                let oldPipePrefix = "[[\(replacement.target)|"
                let newPipePrefix = "[[\(replacement.suggestion)|"
                if content.contains(oldPipePrefix) {
                    content = content.replacingOccurrences(of: oldPipePrefix, with: newPipePrefix)
                    // Already counted above if both exist; only count if not yet counted
                }
            }
            if modified {
                try? content.write(toFile: filePath, atomically: true, encoding: .utf8)
            }
        }

        // Fix missing frontmatter: inject minimal frontmatter
        for filePath in report.missingFrontmatter {
            guard var content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }
            let category = inferCategory(from: filePath)
            let fm = Frontmatter(
                para: category,
                tags: [],
                created: Frontmatter.today(),
                status: .active
            )
            content = fm.stringify() + "\n" + content
            if (try? content.write(toFile: filePath, atomically: true, encoding: .utf8)) != nil {
                frontmatterInjected += 1
            }
        }

        // Fix missing PARA: set para based on folder path
        // Skip files that were already handled by missing frontmatter injection
        let alreadyInjected = Set(report.missingFrontmatter)
        for filePath in report.missingPARA {
            if alreadyInjected.contains(filePath) { continue }

            guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
                continue
            }
            let (existingFM, body) = Frontmatter.parse(markdown: content)

            // Only fix if frontmatter exists but para is missing
            guard existingFM.para == nil else { continue }

            var updatedFM = existingFM
            updatedFM.para = inferCategory(from: filePath)

            let newContent = updatedFM.stringify() + "\n" + body
            if (try? newContent.write(toFile: filePath, atomically: true, encoding: .utf8)) != nil {
                paraFixed += 1
            }
        }

        return RepairResult(
            linksFixed: linksFixed,
            frontmatterInjected: frontmatterInjected,
            paraFixed: paraFixed
        )
    }

    // MARK: - Helpers

    /// Enumerate all .md files in the 4 PARA folders recursively
    private func allMarkdownFiles() -> [String] {
        let fm = FileManager.default
        var results: [String] = []

        let folders = [
            pathManager.projectsPath,
            pathManager.areaPath,
            pathManager.resourcePath,
            pathManager.archivePath,
        ]

        for folder in folders {
            guard let enumerator = fm.enumerator(atPath: folder) else { continue }
            while let element = enumerator.nextObject() as? String {
                let name = (element as NSString).lastPathComponent

                // Skip hidden and _ prefixed entries
                if name.hasPrefix(".") || name.hasPrefix("_") {
                    // Only skip descendants for directories; files need continue only
                    let fullCheck = (folder as NSString).appendingPathComponent(element)
                    var isDirCheck: ObjCBool = false
                    if fm.fileExists(atPath: fullCheck, isDirectory: &isDirCheck), isDirCheck.boolValue {
                        enumerator.skipDescendants()
                    }
                    continue
                }

                guard name.hasSuffix(".md") else { continue }

                let fullPath = (folder as NSString).appendingPathComponent(element)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    results.append(fullPath)
                }
            }
        }

        return results
    }

    /// Build a set of all note basenames (without .md) for WikiLink resolution
    private func allNoteNames() -> Set<String> {
        let files = allMarkdownFiles()
        var names = Set<String>()
        for file in files {
            let basename = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
            names.insert(basename)
        }
        return names
    }

    /// Infer PARA category from a file's path
    private func inferCategory(from path: String) -> PARACategory {
        PARACategory.fromPath(path) ?? .resource
    }

    /// Find the closest matching note name for a broken link target
    private func findClosestMatch(_ target: String, in names: Set<String>) -> String? {
        let lowerTarget = target.lowercased()

        // Exact case-insensitive match
        for name in names {
            if name.lowercased() == lowerTarget {
                return name
            }
        }

        // Substring match: target contains name or name contains target
        var substringMatches: [String] = []
        for name in names {
            let lowerName = name.lowercased()
            if lowerName.contains(lowerTarget) || lowerTarget.contains(lowerName) {
                substringMatches.append(name)
            }
        }

        // Return the shortest substring match (most specific)
        if let best = substringMatches.min(by: { $0.count < $1.count }) {
            return best
        }

        // Levenshtein distance: scale max allowed distance by target length
        let maxAllowed = max(3, lowerTarget.count / 3)
        var bestMatch: String?
        var bestDistance = Int.max
        for name in names {
            let dist = levenshteinDistance(lowerTarget, name.lowercased())
            if dist < bestDistance && dist <= maxAllowed {
                bestDistance = dist
                bestMatch = name
            }
        }

        // Word-overlap match: compare underscore-separated tokens
        if bestMatch == nil {
            let targetWords = Set(lowerTarget.split(separator: "_").map(String.init))
            guard targetWords.count >= 2 else { return nil }
            var bestOverlap = 0
            for name in names {
                let nameWords = Set(name.lowercased().split(separator: "_").map(String.init))
                let overlap = targetWords.intersection(nameWords).count
                if overlap > bestOverlap && overlap >= 2 {
                    bestOverlap = overlap
                    bestMatch = name
                }
            }
        }

        return bestMatch
    }

    /// Compute Levenshtein edit distance between two strings
    private func levenshteinDistance(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let aLen = aChars.count
        let bLen = bChars.count

        if aLen == 0 { return bLen }
        if bLen == 0 { return aLen }

        // Use two-row optimization to save memory
        var previousRow = Array(0...bLen)
        var currentRow = Array(repeating: 0, count: bLen + 1)

        for i in 1...aLen {
            currentRow[0] = i
            for j in 1...bLen {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                currentRow[j] = min(
                    previousRow[j] + 1,       // deletion
                    currentRow[j - 1] + 1,    // insertion
                    previousRow[j - 1] + cost  // substitution
                )
            }
            swap(&previousRow, &currentRow)
        }

        return previousRow[bLen]
    }
}
