import Foundation

/// Detects link removals by diffing Related Notes snapshots between vault checks.
struct LinkStateDetector: Sendable {
    let pkmRoot: String

    struct LinkSnapshot: Codable, Sendable {
        /// noteName -> Set of target note names linked from Related Notes section
        var noteLinks: [String: [String]]

        func linksSet(for note: String) -> Set<String> {
            Set(noteLinks[note] ?? [])
        }
    }

    // MARK: - Snapshot Persistence

    func loadSnapshot() -> LinkSnapshot? {
        let path = snapshotPath()
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(LinkSnapshot.self, from: data)
    }

    func saveSnapshot(_ snapshot: LinkSnapshot) {
        let fm = FileManager.default
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        if !fm.fileExists(atPath: metaDir) {
            try? fm.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(snapshot) else { return }
        try? data.write(to: URL(fileURLWithPath: snapshotPath()), options: .atomic)
    }

    // MARK: - Build Current Snapshot

    func buildCurrentSnapshot(allNotes: [LinkCandidateGenerator.NoteInfo]) -> LinkSnapshot {
        var noteLinks: [String: [String]] = [:]

        for note in allNotes {
            guard let content = try? String(contentsOfFile: note.filePath, encoding: .utf8) else { continue }
            let related = parseRelatedNames(content)
            if !related.isEmpty {
                noteLinks[note.name] = Array(related).sorted()
            }
        }

        return LinkSnapshot(noteLinks: noteLinks)
    }

    // MARK: - Diff Detection

    func detectRemovals(
        previous: LinkSnapshot,
        current: LinkSnapshot,
        noteInfoMap: [String: LinkCandidateGenerator.NoteInfo]
    ) -> [LinkFeedbackEntry] {
        var removals: [LinkFeedbackEntry] = []
        let timestamp = ISO8601DateFormatter().string(from: Date())

        for (noteName, prevTargets) in previous.noteLinks {
            let currentTargets = current.linksSet(for: noteName)
            let prevSet = Set(prevTargets)

            // Links that existed before but are gone now = user removed
            let removed = prevSet.subtracting(currentTargets)
            guard !removed.isEmpty else { continue }

            let sourceInfo = noteInfoMap[noteName]

            for targetName in removed {
                let targetInfo = noteInfoMap[targetName]
                removals.append(LinkFeedbackEntry(
                    date: timestamp,
                    sourceNote: noteName,
                    targetNote: targetName,
                    sourceFolder: sourceInfo?.folderName ?? "",
                    targetFolder: targetInfo?.folderName ?? "",
                    action: "removed"
                ))
            }
        }

        return removals
    }

    // MARK: - Helpers

    private func parseRelatedNames(_ content: String) -> Set<String> {
        var names = Set<String>()
        var inSection = false

        for line in content.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("## Related Notes") {
                inSection = true
                continue
            }
            if trimmed.hasPrefix("## ") && inSection {
                break
            }
            if inSection, trimmed.hasPrefix("- [[") {
                if let start = trimmed.range(of: "[["),
                   let end = trimmed.range(of: "]]") {
                    let name = String(trimmed[start.upperBound..<end.lowerBound])
                    if !name.isEmpty { names.insert(name) }
                }
            }
        }

        return names
    }

    private func snapshotPath() -> String {
        (pkmRoot as NSString).appendingPathComponent(".meta/link-snapshot.json")
    }
}
