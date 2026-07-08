import CryptoKit
import Foundation

/// Maintains AI-synthesized folder entity pages (<folder>.md marker section).
/// One sendFast call per changed folder; unchanged folders are skipped by
/// comparing the members hash stored inside the marker section.
struct FolderSynthesizer: Sendable {
    let pkmRoot: String

    /// Bytes of each changed member body fed into the prompt.
    static let changedBodyBytes = 8192
    /// Max changed member bodies fed into a single folder prompt.
    static let maxChangedBodies = 5
    /// Carry-forward cap for the "최근 흐름" timeline.
    static let recentFlowCap = 20

    private var pathManager: PKMPathManager { PKMPathManager(root: pkmRoot) }

    /// A written folder page plus the one-line 요지 harvested from it. Callers
    /// re-hash `path` in ContentHashCache; `gist` feeds `.meta/log.md`.
    struct Output: Sendable {
        let path: String
        let gist: String
    }

    /// Synthesize the given folders (absolute paths). `changedNotePaths` are
    /// absolute paths whose bodies changed this run; the intersection with a
    /// folder's members is fed into the prompt in full. Returns paths of
    /// folder notes actually written.
    func synthesizeFolders(
        _ folderPaths: Set<String>,
        changedNotePaths: Set<String>
    ) async -> [Output] {
        guard let index = pathManager.loadNoteIndex() else { return [] }
        let descriptions = FolderDescriptionStore.load(pkmRoot: pkmRoot)
        let fm = FileManager.default
        let today = Frontmatter.today()
        // Normalize the absolute changed paths to vault-relative once so they
        // can be intersected with member entry.path (also vault-relative).
        let changedRel = Set(changedNotePaths.map { relativePath($0) })
        var written: [Output] = []

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
            // Feed the full previous synthesis so 최근 흐름 items carry forward
            let previous = existing.flatMap { FolderNotePage.synthesisSection(from: $0) }
            // Bodies of changed members that belong to this folder (up to 5)
            let changedNotes = memberEntries
                .filter { changedRel.contains($0.path.precomposedStringWithCanonicalMapping) }
                .prefix(Self.maxChangedBodies)
                .compactMap { entry -> (name: String, body: String)? in
                    let abs = (pkmRoot as NSString).appendingPathComponent(entry.path)
                    guard let body = NoteExcerptReader.read(abs, maxBytes: Self.changedBodyBytes) else {
                        return nil
                    }
                    let name = ((entry.path as NSString).lastPathComponent as NSString)
                        .deletingPathExtension
                    return (name: name, body: body)
                }

            do {
                let raw = try await requestSynthesis(
                    folderName: folderName, para: para, members: memberEntries,
                    userDescription: userDescription, previousSynthesis: previous,
                    changedNotes: Array(changedNotes), today: today
                )
                // A missing section would blank a compounding artifact
                // (모순/노후/흐름) — keep the previous synthesis instead.
                guard Self.isValidSynthesis(raw) else {
                    NSLog("[FolderSynthesizer] 형식 불량, 이전 종합 유지: %@", folderName)
                    continue
                }
                let (synthesis, gist) = Self.extractGist(from: raw)
                let updated = FolderNotePage.replacingSynthesis(
                    in: existing, synthesis: synthesis,
                    inputsHash: hash, folderName: folderName, para: para
                )
                try updated.write(toFile: notePath, atomically: true, encoding: .utf8)
                written.append(Output(path: notePath, gist: gist))
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

    /// Every section the prompt promises. Each carries a distinct compounding
    /// artifact — 모순 (contradictions), 노후 (superseded notes), 최근 흐름
    /// (evolution). The validator strings MUST match the prompt headings
    /// byte-for-byte (all `##`); any mismatch rejects every response and
    /// freezes the page.
    static let requiredSections = [
        "## 개요", "## 최근 흐름", "## 핵심 노트", "## 모순", "## 노후",
    ]

    static func isValidSynthesis(_ text: String) -> Bool {
        requiredSections.allSatisfy { text.contains($0) }
    }

    /// Split the trailing "요지: ..." line off the synthesis. The gist is
    /// logged to `.meta/log.md`; the line itself never lands on the page.
    static func extractGist(from text: String) -> (synthesis: String, gist: String) {
        var lines = text.components(separatedBy: "\n")
        var gist = ""
        for i in lines.indices.reversed() {
            let trimmed = lines[i].trimmingCharacters(in: CharacterSet(charactersIn: " \t*#"))
            guard trimmed.hasPrefix("요지") else { continue }
            var rest = String(trimmed.dropFirst("요지".count)).trimmingCharacters(in: .whitespaces)
            if rest.hasPrefix(":") || rest.hasPrefix("：") {
                rest = String(rest.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            gist = rest.trimmingCharacters(in: CharacterSet(charactersIn: " \t*"))
            lines.remove(at: i)
            break
        }
        let synthesis = lines.joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (synthesis, gist)
    }

    /// Build the synthesis prompt. Pure and static so the heading levels can be
    /// asserted to match `requiredSections` exactly (blocker fix #3).
    static func buildPrompt(
        folderName: String,
        para: PARACategory,
        members: [NoteIndexEntry],
        userDescription: String?,
        previousSynthesis: String?,
        changedNotes: [(name: String, body: String)],
        today: String
    ) -> String {
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
        let previousSection = previousSynthesis.map {
            "\n## 이전 종합 (기준선 — 최근 흐름 항목을 유지하며 새 정보로 갱신)\n\($0)\n"
        } ?? "\n## 이전 종합\n(없음 — 첫 종합)\n"
        let changedSection = changedNotes.isEmpty
            ? "(없음 — 멤버 목록/요약 변경만 반영)"
            : changedNotes.map { "### \($0.name)\n\($0.body)" }.joined(separator: "\n\n")

        return """
        PKM 볼트의 "\(folderName)" 폴더(\(para.displayName))를 종합하는 허브 문서 본문을 작성하세요. 오늘 날짜: \(today)

        ## 멤버 노트 목록
        \(memberLines)
        \(descriptionSection)\(previousSection)
        ## 새로 반영할 본문
        \(changedSection)

        ## 출력 형식 (마크다운, 이 구조 그대로)
        ## 개요
        (폴더 전체를 요약하는 2~3문장)

        ## 최근 흐름
        (이전 "최근 흐름" 항목을 그대로 유지하고, 이번 갱신 항목을 맨 위에 추가. 형식: - \(today): 변경 요지. 최근 \(recentFlowCap)개까지만)

        ## 핵심 노트
        (최대 7개 bullet, 형식: - [[정확한 노트명]] — 역할)

        ## 모순
        (멤버 노트 간 상충 지점. 형식: - [[노트A]] vs [[노트B]]: 상충 내용. 없으면 "- 감지된 모순 없음")

        ## 노후
        (새 정보로 사실상 대체된 노트. 형식: - [[옛노트]]: [[새노트]]에 의해 대체됨 (\(today)). 없으면 "- 없음")

        요지: (이번 종합의 핵심을 한 문장으로. 위 섹션들 다음 마지막 줄에 배치)

        ## 규칙
        1. 노트명은 위 멤버 노트 목록의 이름을 글자 그대로 사용 (창작 금지)
        2. 한국어로 작성, 이모지 금지
        3. 출력 형식 외의 다른 섹션이나 설명은 추가하지 않음
        4. 모순·노후는 실제 내용 충돌이 있을 때만 기록 — 억지로 만들지 않음
        """
    }

    // MARK: - AI

    private func requestSynthesis(
        folderName: String,
        para: PARACategory,
        members: [NoteIndexEntry],
        userDescription: String?,
        previousSynthesis: String?,
        changedNotes: [(name: String, body: String)],
        today: String
    ) async throws -> String {
        let prompt = Self.buildPrompt(
            folderName: folderName, para: para, members: members,
            userDescription: userDescription, previousSynthesis: previousSynthesis,
            changedNotes: changedNotes, today: today
        )
        let response = try await AIService.shared.sendFastWithUsage(maxTokens: 2048, message: prompt)
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
