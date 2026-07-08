import Foundation

/// One-time v18 migration. Vaults written by earlier versions stored reverse
/// links with the forward directional relation — e.g. a backlink filed under
/// "### 선행 지식" because the forward link was `prerequisite`. v18 inverts
/// directional relations at write time, but writeRelatedNotes dedups by name
/// and never rewrites existing lines, so old mislabeled entries would persist
/// forever (and the link diet would preferentially keep them). Reverse entries
/// are reliably identifiable by their canned reverseRelationContext string,
/// which forward (AI-authored) contexts never use.
struct ReverseLinkRelationMigrator: Sendable {
    let pkmRoot: String

    private static let markerRelPath = ".meta/reverse-link-migration-v1"

    /// Directional relations whose reverse context marks a pre-v18 backlink.
    /// A missing context key drops the rule entirely — never falls back to ""
    /// which would match any same-relation entry with an empty context.
    private static let migratable: [(relation: String, context: String)] =
        ["prerequisite", "reference"].compactMap { relation in
            SemanticLinker.reverseRelationContext[relation].map { (relation: relation, context: $0) }
        }

    func migrateIfNeeded() async {
        let fm = FileManager.default
        let markerPath = (pkmRoot as NSString).appendingPathComponent(Self.markerRelPath)
        guard !fm.fileExists(atPath: markerPath) else { return }
        guard fm.fileExists(atPath: pkmRoot) else { return }

        let (modified, failures) = migrateAll()

        if !modified.isEmpty {
            // Without a hash update the next vault check re-processes every
            // migrated file as a content change (pointless AI calls)
            let cache = ContentHashCache(pkmRoot: pkmRoot)
            await cache.load()
            await cache.updateHashes(modified)
            await cache.save()
            VaultLogService(pkmRoot: pkmRoot).append(
                kind: "migration",
                summary: "구버전 역링크 관계 재지정: \(modified.count)개 노트"
            )
            NSLog("[ReverseLinkRelationMigrator] %d개 노트의 역링크 관계 재지정", modified.count)
        }

        // A write failure (disk/permission) leaves a note mislabeled forever if
        // the marker suppresses future runs. Skip the marker so the next launch
        // retries — already-migrated notes no longer match the rules, so the
        // rescan only reprocesses whatever actually failed.
        guard failures == 0 else { return }

        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }
        try? "1".write(toFile: markerPath, atomically: true, encoding: .utf8)
    }

    // MARK: - Private

    private enum Outcome {
        case migrated   // section rewritten with corrected relations
        case skipped    // nothing to migrate, or user-authored/refused
        case failed     // write threw — must retry, do not mark done
    }

    private func migrateAll() -> (modified: [String], failures: Int) {
        // Reuse the shared enumerator so the path-traversal guard (isPathSafe)
        // and hidden/system-entry skipping stay in one place
        let pathManager = PKMPathManager(root: pkmRoot)
        let writer = RelatedNotesWriter()
        var modified: [String] = []
        var failures = 0

        for filePath in pathManager.allMarkdownFiles() {
            switch migrateFile(filePath, writer: writer) {
            case .migrated: modified.append(filePath)
            case .failed: failures += 1
            case .skipped: break
            }
        }
        return (modified, failures)
    }

    /// Sections with user-authored content are skipped (replaceEntries refuses
    /// them). Only a thrown write is a `.failed` — a `false` return is a clean
    /// no-op skip.
    private func migrateFile(_ filePath: String, writer: RelatedNotesWriter) -> Outcome {
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8),
              let parsed = writer.parseRelatedNotes(content),
              !parsed.hasUnrecognized else { return .skipped }

        var changed = false
        let migrated: [RelatedNotesWriter.Entry] = parsed.entries.map { entry in
            for rule in Self.migratable
            where entry.relation == rule.relation && entry.context == rule.context {
                changed = true
                return (name: entry.name, context: entry.context, relation: "related")
            }
            return entry
        }
        guard changed else { return .skipped }

        do {
            return try writer.replaceEntries(filePath: filePath, entries: migrated)
                ? .migrated : .skipped
        } catch {
            NSLog("[ReverseLinkRelationMigrator] 재기록 실패: %@ — %@",
                  filePath, error.localizedDescription)
            return .failed
        }
    }
}
