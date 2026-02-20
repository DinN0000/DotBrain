import Foundation

struct LinkCandidateGenerator: Sendable {

    struct NoteInfo {
        let name: String
        let filePath: String
        let tags: [String]
        let summary: String
        let project: String?
        let folderName: String
        let para: PARACategory
        let existingRelated: Set<String>
    }

    struct Candidate {
        let name: String
        let summary: String
        let tags: [String]
        let score: Double
    }

    func generateCandidates(
        for note: NoteInfo,
        allNotes: [NoteInfo],
        mocEntries: [ContextMapEntry],
        folderBonus: Double = 1.0,
        excludeSameFolder: Bool = false
    ) -> [Candidate] {
        var mocFolders: [String: Set<String>] = [:]
        for entry in mocEntries {
            mocFolders[entry.noteName, default: []].insert(entry.folderName)
        }

        let noteFolders = mocFolders[note.name] ?? []
        let noteTags = Set(note.tags.map { $0.lowercased() })

        var candidates: [Candidate] = []

        for other in allNotes {
            guard other.name != note.name else { continue }
            guard !note.existingRelated.contains(other.name) else { continue }
            if excludeSameFolder && other.folderName == note.folderName { continue }

            var score: Double = 0

            // Tag overlap: minimum 2 tags required for genuine relevance
            let otherTags = Set(other.tags.map { $0.lowercased() })
            let tagOverlap = noteTags.intersection(otherTags).count
            if tagOverlap >= 2 {
                score += Double(tagOverlap) * 1.5
            }

            let otherFolders = mocFolders[other.name] ?? []
            let sharedFolders = noteFolders.intersection(otherFolders)
            if !sharedFolders.isEmpty {
                score += Double(sharedFolders.count) * folderBonus
            }

            if let noteProject = note.project, !noteProject.isEmpty,
               let otherProject = other.project, !otherProject.isEmpty,
               noteProject.lowercased() == otherProject.lowercased() {
                score += 2.0
            }

            // Minimum score threshold for meaningful connections
            guard score >= 3.0 else { continue }

            candidates.append(Candidate(
                name: other.name,
                summary: other.summary,
                tags: other.tags,
                score: score
            ))
        }

        // No artificial limit — all qualifying candidates pass to AI filter
        return candidates.sorted { $0.score > $1.score }
    }
}
