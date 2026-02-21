import Foundation

/// Builds a VaultContextMap from note-index.json (pure file I/O, no AI calls)
struct ContextMapBuilder: Sendable {
    let pkmRoot: String

    private var indexPath: String {
        ((pkmRoot as NSString).appendingPathComponent(".meta") as NSString)
            .appendingPathComponent("note-index.json")
    }

    /// Build context map from note index
    func build() async -> VaultContextMap {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: indexPath)),
              let index = try? JSONDecoder().decode(NoteIndex.self, from: data) else {
            return VaultContextMap(entries: [], folderCount: 0, buildDate: Date())
        }

        var entries: [ContextMapEntry] = []

        for (noteName, note) in index.notes {
            let para = PARACategory(rawValue: note.para) ?? .archive
            let folder = index.folders[note.folder]

            // Extract note name from path (remove folder prefix and .md suffix)
            let baseName: String
            if let lastSlash = noteName.lastIndex(of: "/") {
                let fileName = String(noteName[noteName.index(after: lastSlash)...])
                baseName = (fileName as NSString).deletingPathExtension
            } else {
                baseName = (noteName as NSString).deletingPathExtension
            }

            entries.append(ContextMapEntry(
                noteName: baseName,
                summary: note.summary,
                folderName: note.folder,
                para: para,
                folderSummary: folder?.summary ?? "",
                tags: folder?.tags ?? []
            ))
        }

        return VaultContextMap(
            entries: entries,
            folderCount: index.folders.count,
            buildDate: Date()
        )
    }
}
