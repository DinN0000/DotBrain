import CryptoKit
import Foundation

/// Maintains AI-synthesized category hub pages
/// (`<N_Category>/<N_Category>.md`) for 1_Project / 2_Area / 3_Resource.
/// Where `FolderSynthesizer` synthesizes *inside* one folder, this synthesizes
/// *across* a category's subfolders (지형/교차연결/모순). One sendFast call per
/// changed category; unchanged categories are skipped by comparing the stable
/// slice hash stored inside the marker section. Archive has no hub.
struct CategoryHubSynthesizer: Sendable {
    let pkmRoot: String

    /// Max subfolders fed into a single hub prompt (most-recently-changed first).
    static let maxSubfolders = 12
    /// Byte cap for each subfolder's stable slice — bounds the token budget.
    static let perSliceBytes = 1500

    private var pathManager: PKMPathManager { PKMPathManager(root: pkmRoot) }

    /// One subfolder's STABLE, bounded contribution to the hub: its 개요 + 핵심
    /// 노트 only (never the churny 최근 흐름), so a subfolder's timeline update
    /// does not flip the hub hash. `modified` orders the top-N cap; `name`/`slice`
    /// feed both the prompt and the hash (feed == gate).
    struct SubfolderSlice: Sendable {
        let name: String
        let slice: String
        let modified: Date
    }

    /// Synthesize hub pages for the given category root folders (absolute paths,
    /// e.g. `.../1_Project`). Archive and non-roots are ignored. A category with
    /// fewer than 2 subfolders has any existing hub marker section stripped.
    /// Each written hub's 요지 is chronicled to `.meta/log.md` here. Returns hub
    /// pages actually written (callers re-hash them in ContentHashCache).
    func synthesizeCategories(_ categoryPaths: Set<String>) async -> [String] {
        guard let index = pathManager.loadNoteIndex() else { return [] }
        let fm = FileManager.default
        let today = Frontmatter.today()
        let log = VaultLogService(pkmRoot: pkmRoot)
        let rootPrefix = pathManager.canonicalRootPrefix()
        var written: [String] = []

        for categoryPath in categoryPaths.sorted() {
            if Task.isCancelled { break }
            guard let para = PARACategory.fromPath(categoryPath), para != .archive else { continue }
            // Must be the category root itself (never a subfolder)
            guard categoryPath == pathManager.paraPath(for: para),
                  pathManager.isPathSafe(categoryPath) else { continue }

            let categoryName = para.folderName
            let hubPath = (categoryPath as NSString).appendingPathComponent("\(categoryName).md")
            let existing = try? String(contentsOfFile: hubPath, encoding: .utf8)

            let subfolders = Self.subfolderPaths(in: categoryPath)
            // Structural gate: a hub needs at least two subfolders to have any
            // cross-subfolder tension to synthesize. Below that, strip the now
            // meaningless hub section.
            guard subfolders.count >= 2 else {
                if let existing, let stripped = FolderNotePage.strippingSynthesis(from: existing) {
                    if stripped.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        try? fm.removeItem(atPath: hubPath)
                    } else {
                        try? stripped.write(toFile: hubPath, atomically: true, encoding: .utf8)
                    }
                }
                continue
            }

            // Build a STABLE slice per subfolder (page 개요+핵심노트, or index summary)
            let slices = subfolders.compactMap {
                buildSlice(subfolderPath: $0, index: index, rootPrefix: rootPrefix)
            }
            guard slices.count >= 2 else { continue }

            // Cap at the top-N most-recently-changed subfolders, then re-sort by
            // name so mtime jitter never reorders the hash input (feed == gate).
            let capped = slices
                .sorted { $0.modified > $1.modified }
                .prefix(Self.maxSubfolders)
                .sorted { $0.name < $1.name }
            let sliceArray = Array(capped)

            let hash = Self.inputsHash(slices: sliceArray)
            if let existing, FolderNotePage.inputsHash(from: existing) == hash { continue }

            do {
                let raw = try await requestSynthesis(
                    categoryName: categoryName, para: para, slices: sliceArray, today: today
                )
                // A missing section would blank a compounding artifact — keep the
                // previous hub synthesis instead.
                guard Self.isValidSynthesis(raw) else {
                    NSLog("[CategoryHubSynthesizer] 형식 불량, 이전 종합 유지: %@", categoryName)
                    continue
                }
                // Reuse the folder gist parser — hub gist semantics are identical
                let (synthesis, gist) = FolderSynthesizer.extractGist(from: raw)
                let updated = FolderNotePage.replacingSynthesis(
                    in: existing, synthesis: synthesis,
                    inputsHash: hash, folderName: categoryName, para: para
                )
                try updated.write(toFile: hubPath, atomically: true, encoding: .utf8)
                written.append(hubPath)
                if !gist.isEmpty {
                    log.append(kind: "synthesis", summary: "\(categoryName): \(gist)")
                }
            } catch {
                NSLog("[CategoryHubSynthesizer] 종합 실패: %@ — %@", categoryName, error.localizedDescription)
            }
        }
        return written
    }

    // MARK: - Pure Helpers

    /// Category root folders (absolute) for a set of changed folders — maps each
    /// PARA subfolder to its category root and drops Archive/non-PARA. Both
    /// pipelines call this to derive the affected categories after subfolder
    /// synthesis.
    static func categoryRoots(for folderPaths: Set<String>, pkmRoot: String) -> Set<String> {
        let pm = PKMPathManager(root: pkmRoot)
        var roots = Set<String>()
        for folder in folderPaths {
            guard let para = PARACategory.fromPath(folder), para != .archive else { continue }
            roots.insert(pm.paraPath(for: para))
        }
        return roots
    }

    /// Direct child subfolders of a category root — skips hidden/underscore
    /// directories (Unsorted catch-all is included; `_`-prefixed is not) and files.
    static func subfolderPaths(in categoryPath: String) -> [String] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: categoryPath) else { return [] }
        var result: [String] = []
        for name in entries where !name.hasPrefix(".") && !name.hasPrefix("_") {
            let full = (categoryPath as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else { continue }
            result.append(full)
        }
        return result.sorted()
    }

    /// Order-independent hash over the stable slices that feed the hub prompt —
    /// keyed on the exact same 개요+핵심노트 content (feed == gate), so a
    /// subfolder's 최근 흐름/timestamp change does not flip the hub hash.
    static func inputsHash(slices: [SubfolderSlice]) -> String {
        let lines = slices
            .map { "\($0.name)\n\($0.slice)" }
            .sorted()
            .joined(separator: "\n---\n")
        let digest = SHA256.hash(data: Data(lines.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Truncate a string to at most `maxBytes` UTF-8 bytes without splitting a
    /// multibyte character.
    static func capToBytes(_ text: String, _ maxBytes: Int) -> String {
        guard text.utf8.count > maxBytes else { return text }
        var result = ""
        var count = 0
        for ch in text {
            let n = String(ch).utf8.count
            if count + n > maxBytes { break }
            result.append(ch)
            count += n
        }
        return result
    }

    /// Every section the hub prompt promises. The validator strings MUST match
    /// the prompt headings byte-for-byte (all `##`); any mismatch rejects every
    /// response and freezes the hub.
    static let requiredSections = ["## 지형", "## 교차연결", "## 모순"]

    static func isValidSynthesis(_ text: String) -> Bool {
        requiredSections.allSatisfy { text.contains($0) }
    }

    /// Build the hub synthesis prompt. Pure and static so the heading levels can
    /// be asserted to match `requiredSections` exactly.
    static func buildPrompt(
        categoryName: String,
        para: PARACategory,
        slices: [SubfolderSlice],
        today: String
    ) -> String {
        let subfolderSections = slices
            .map { "### \($0.name)\n\($0.slice)" }
            .joined(separator: "\n\n")

        return """
        PKM 볼트의 "\(categoryName)"(\(para.displayName)) 카테고리 전체를 가로지르는 허브 문서 본문을 작성하세요. 오늘 날짜: \(today)
        아래는 이 카테고리의 하위 폴더별 개요와 핵심 노트입니다. 개별 폴더 내부가 아니라 폴더들 사이의 관계에 집중하세요.

        ## 하위 폴더 요약
        \(subfolderSections)

        ## 출력 형식 (마크다운, 이 구조 그대로)
        ## 지형
        (이 카테고리가 다루는 주제 지형을 2~3문장으로. 어떤 하위 폴더가 무엇을 담당하는지)

        ## 교차연결
        (서로 다른 하위 폴더를 잇는 지점. 형식: - [[폴더A]] ↔ [[폴더B]]: 연결 내용. 없으면 "- 감지된 교차연결 없음")

        ## 모순
        (하위 폴더 간 상충하는 방향/결론. 형식: - [[폴더A]] vs [[폴더B]]: 상충 내용. 없으면 "- 감지된 모순 없음")

        요지: (이 카테고리의 현재 상태를 한 문장으로. 위 섹션들 다음 마지막 줄에 배치)

        ## 규칙
        1. 폴더명은 위 "하위 폴더 요약"의 이름을 글자 그대로 사용 (창작 금지)
        2. 한국어로 작성, 이모지 금지
        3. 출력 형식 외의 다른 섹션이나 설명은 추가하지 않음
        4. 교차연결·모순은 실제 근거가 있을 때만 기록 — 억지로 만들지 않음
        """
    }

    // MARK: - Slice building (file I/O)

    /// Build one subfolder's stable slice: its page's 개요+핵심노트, or the
    /// NoteIndex folder summary when the subfolder has no page yet.
    private func buildSlice(
        subfolderPath: String, index: NoteIndex, rootPrefix: String
    ) -> SubfolderSlice? {
        let fm = FileManager.default
        let name = (subfolderPath as NSString).lastPathComponent
            .precomposedStringWithCanonicalMapping
        let pagePath = (subfolderPath as NSString).appendingPathComponent("\(name).md")

        var sliceText: String?
        if let content = try? String(contentsOfFile: pagePath, encoding: .utf8) {
            sliceText = CategoryHubPage.stableSlice(from: content)
        }
        if sliceText == nil {
            let rel = pathManager.relativePath(subfolderPath, rootPrefix: rootPrefix)
            if let summary = index.folders[rel]?.summary, !summary.isEmpty {
                sliceText = "## 개요\n\(summary)"
            }
        }
        guard let text = sliceText else { return nil }

        // Recency for the top-N cap: prefer the page mtime, fall back to the
        // directory mtime.
        let modified = ((try? fm.attributesOfItem(atPath: pagePath))?[.modificationDate] as? Date)
            ?? ((try? fm.attributesOfItem(atPath: subfolderPath))?[.modificationDate] as? Date)
            ?? .distantPast
        return SubfolderSlice(name: name, slice: Self.capToBytes(text, Self.perSliceBytes), modified: modified)
    }

    // MARK: - AI

    private func requestSynthesis(
        categoryName: String,
        para: PARACategory,
        slices: [SubfolderSlice],
        today: String
    ) async throws -> String {
        let prompt = Self.buildPrompt(
            categoryName: categoryName, para: para, slices: slices, today: today
        )
        let response = try await AIService.shared.sendFastWithUsage(maxTokens: 2048, message: prompt)
        if let usage = response.usage {
            let model = await AIService.shared.fastModel
            StatisticsService.logTokenUsage(
                operation: "category-hub-synthesis", model: model,
                usage: usage, isEstimated: response.isEstimated
            )
        }
        return FolderSynthesizer.stripCodeBlock(response.text)
    }
}
