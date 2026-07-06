import CryptoKit
import Foundation

/// Maintains AI-synthesized folder entity pages (<folder>.md marker section).
/// One sendFast call per changed folder; unchanged folders are skipped by
/// comparing the members hash stored inside the marker section.
struct FolderSynthesizer: Sendable {
    let pkmRoot: String

    private var pathManager: PKMPathManager { PKMPathManager(root: pkmRoot) }

    /// Synthesize the given folders (absolute paths). Returns paths of folder
    /// notes actually written (callers re-hash these in ContentHashCache).
    func synthesizeFolders(_ folderPaths: Set<String>) async -> [String] {
        guard let index = pathManager.loadNoteIndex() else { return [] }
        let descriptions = FolderDescriptionStore.load(pkmRoot: pkmRoot)
        let fm = FileManager.default
        var written: [String] = []

        for folderPath in folderPaths.sorted() {
            if Task.isCancelled { break }
            guard let para = PARACategory.fromPath(folderPath), para != .archive else { continue }

            let relPath = relativePath(folderPath)
            // Category roots have no entity page
            guard relPath != para.folderName else { continue }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: folderPath, isDirectory: &isDir), isDir.boolValue,
                  pathManager.isPathSafe(folderPath) else { continue }

            let folderName = (folderPath as NSString).lastPathComponent
                .precomposedStringWithCanonicalMapping
            let memberEntries = Self.members(in: index, folderRelPath: relPath)
            guard !memberEntries.isEmpty else { continue }

            let notePath = (folderPath as NSString).appendingPathComponent("\(folderName).md")
            let existing = try? String(contentsOfFile: notePath, encoding: .utf8)
            let hash = Self.inputsHash(members: memberEntries)
            if let existing, FolderNotePage.inputsHash(from: existing) == hash { continue }

            let userDescription = descriptions.description(for: folderName, category: para)
            let previous = existing.flatMap { FolderNotePage.overview(from: $0) }

            do {
                let synthesis = try await requestSynthesis(
                    folderName: folderName, para: para, members: memberEntries,
                    userDescription: userDescription, previousOverview: previous
                )
                // Malformed output means a blank or broken section — keep the
                // previous synthesis instead
                guard synthesis.contains("## 개요") else { continue }
                let updated = FolderNotePage.replacingSynthesis(
                    in: existing, synthesis: synthesis,
                    inputsHash: hash, folderName: folderName, para: para
                )
                try updated.write(toFile: notePath, atomically: true, encoding: .utf8)
                written.append(notePath)
            } catch {
                // Keep the previous synthesis on any failure — never blank the page
                NSLog("[FolderSynthesizer] 종합 실패: %@ — %@", folderName, error.localizedDescription)
            }
        }
        return written
    }

    // MARK: - Pure Helpers

    /// Member notes of a folder, excluding the folder note itself
    static func members(in index: NoteIndex, folderRelPath: String) -> [NoteIndexEntry] {
        let folderKey = folderRelPath.precomposedStringWithCanonicalMapping
        let folderName = (folderKey as NSString).lastPathComponent
        return index.notes.values
            .filter { entry in
                guard entry.folder.precomposedStringWithCanonicalMapping == folderKey else { return false }
                let baseName = ((entry.path as NSString).lastPathComponent as NSString)
                    .deletingPathExtension.precomposedStringWithCanonicalMapping
                return baseName != folderName
            }
            .sorted { $0.path < $1.path }
    }

    /// Order-independent hash over member metadata that feeds the synthesis
    /// prompt — unchanged members mean the AI call can be skipped
    static func inputsHash(members: [NoteIndexEntry]) -> String {
        let lines = members
            .map { entry in
                let tags = entry.tags.joined(separator: ",")
                return "\(entry.path)|\(entry.summary)|\(entry.status ?? "")|\(tags)"
            }
            .sorted()
            .joined(separator: "\n")
        let digest = SHA256.hash(data: Data(lines.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - AI

    private func requestSynthesis(
        folderName: String,
        para: PARACategory,
        members: [NoteIndexEntry],
        userDescription: String?,
        previousOverview: String?
    ) async throws -> String {
        let memberLines = members.map { entry in
            let name = ((entry.path as NSString).lastPathComponent as NSString).deletingPathExtension
            let status = entry.status.map { " [\($0)]" } ?? ""
            let tags = entry.tags.isEmpty ? "" : " (태그: \(entry.tags.prefix(5).joined(separator: ", ")))"
            let summary = entry.summary.isEmpty ? "요약 없음" : entry.summary
            return "- \(name)\(status)\(tags) — \(summary)"
        }.joined(separator: "\n")

        let descriptionSection = userDescription.map {
            "\n## 사용자 폴더 설명\n\($0)\n개요는 이 설명과 모순되지 않아야 합니다.\n"
        } ?? ""
        let previousSection = previousOverview.map {
            "\n## 직전 개요 (연속성 참고)\n\($0)\n"
        } ?? ""

        let prompt = """
        PKM 볼트의 "\(folderName)" 폴더(\(para.displayName))를 종합하는 허브 문서 본문을 작성하세요.

        ## 멤버 노트 목록
        \(memberLines)
        \(descriptionSection)\(previousSection)
        ## 출력 형식 (마크다운, 이 구조 그대로)
        ## 개요
        (폴더 전체를 요약하는 2~3문장)

        ### 최근 흐름
        (최대 5개 bullet — 멤버 노트에서 드러나는 진행 흐름, 날짜를 알 수 있으면 함께 표기)

        ### 핵심 노트
        (최대 7개 bullet, 형식: - [[정확한 노트명]] — 역할)

        ## 규칙
        1. 노트명은 위 멤버 노트 목록의 이름을 글자 그대로 사용 (창작 금지)
        2. 한국어로 작성, 이모지 금지
        3. 출력 형식 외의 다른 섹션이나 설명은 추가하지 않음
        """

        let response = try await AIService.shared.sendFastWithUsage(maxTokens: 1024, message: prompt)
        if let usage = response.usage {
            let model = await AIService.shared.fastModel
            StatisticsService.logTokenUsage(
                operation: "folder-synthesis", model: model,
                usage: usage, isEstimated: response.isEstimated
            )
        }
        return stripCodeBlock(response.text)
    }

    // MARK: - Private

    /// Convert an absolute path to a vault-relative path (same canonicalization
    /// as NoteIndexGenerator: resolve symlinks, strip root, NFC-normalize)
    private func relativePath(_ absolutePath: String) -> String {
        let canonicalRoot = URL(fileURLWithPath: pkmRoot).resolvingSymlinksInPath().path
        let rootPrefix = canonicalRoot.hasSuffix("/") ? canonicalRoot : canonicalRoot + "/"
        let canonicalPath = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath().path
        guard canonicalPath.hasPrefix(rootPrefix) else {
            return absolutePath.precomposedStringWithCanonicalMapping
        }
        return String(canonicalPath.dropFirst(rootPrefix.count))
            .precomposedStringWithCanonicalMapping
    }

    private func stripCodeBlock(_ text: String) -> String {
        text
            .replacingOccurrences(of: #"^```(?:markdown|md)?\s*\n?"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\n?```\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
