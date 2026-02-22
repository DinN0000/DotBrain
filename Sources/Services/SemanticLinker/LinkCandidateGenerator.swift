import Foundation

struct LinkCandidateGenerator: Sendable {

    struct NoteInfo {
        let name: String
        let filePath: String
        let tags: [String]
        let summary: String
        let project: String?
        let folderName: String
        let folderRelPath: String  // e.g. "2_Area/SwiftUI-패턴"
        let para: PARACategory
        let existingRelated: Set<String>
    }

    struct Candidate {
        let name: String
        let summary: String
        let tags: [String]
        let score: Double
    }

    struct PreparedIndex {
        let tagIndex: [String: [Int]]       // lowercased tag -> note indices
        let projectIndex: [String: [Int]]   // lowercased project -> note indices
        let mocFolders: [String: Set<String>]
    }

    func prepareIndex(allNotes: [NoteInfo], mocEntries: [ContextMapEntry]) -> PreparedIndex {
        var tagIndex: [String: [Int]] = [:]
        var projectIndex: [String: [Int]] = [:]

        for (i, note) in allNotes.enumerated() {
            for tag in note.tags {
                tagIndex[tag.lowercased(), default: []].append(i)
            }
            if let project = note.project, !project.isEmpty {
                projectIndex[project.lowercased(), default: []].append(i)
            }
        }

        var mocFolders: [String: Set<String>] = [:]
        for entry in mocEntries {
            mocFolders[entry.noteName, default: []].insert(entry.folderName)
        }

        return PreparedIndex(tagIndex: tagIndex, projectIndex: projectIndex, mocFolders: mocFolders)
    }

    /// Sorted pair key for folder relation lookup (matches FolderRelationStore.pairKey)
    static func pairKey(_ a: String, _ b: String) -> String {
        a < b ? "\(a)|\(b)" : "\(b)|\(a)"
    }

    /// Original API — builds PreparedIndex internally, delegates to index-based overload
    func generateCandidates(
        for note: NoteInfo,
        allNotes: [NoteInfo],
        mocEntries: [ContextMapEntry],
        folderBonus: Double = 1.0,
        excludeSameFolder: Bool = false,
        folderRelations: FolderRelationStore? = nil
    ) -> [Candidate] {
        let prepared = prepareIndex(allNotes: allNotes, mocEntries: mocEntries)
        let suppressSet = folderRelations?.suppressPairs() ?? []
        let boostSet = folderRelations?.boostPairKeys() ?? []
        return generateCandidates(
            for: note,
            allNotes: allNotes,
            preparedIndex: prepared,
            folderBonus: folderBonus,
            excludeSameFolder: excludeSameFolder,
            suppressSet: suppressSet,
            boostSet: boostSet
        )
    }

    /// Index-based candidate generation using reverse indices for tag/project lookup.
    /// Accepts pre-built suppress/boost sets to avoid repeated disk I/O.
    func generateCandidates(
        for note: NoteInfo,
        allNotes: [NoteInfo],
        preparedIndex: PreparedIndex,
        folderBonus: Double = 1.0,
        excludeSameFolder: Bool = false,
        suppressSet: Set<String> = [],
        boostSet: Set<String> = []
    ) -> [Candidate] {
        let noteTags = Set(note.tags.map { $0.lowercased() })
        let noteFolders = preparedIndex.mocFolders[note.name] ?? []

        // Collect candidate indices from reverse indices
        var candidateScores: [Int: Double] = [:]

        // Tag reverse index: collect notes sharing tags
        for tag in noteTags {
            guard let indices = preparedIndex.tagIndex[tag] else { continue }
            for idx in indices {
                candidateScores[idx, default: 0] += 1  // count shared tags
            }
        }

        // Project reverse index: collect notes sharing project
        if let noteProject = note.project, !noteProject.isEmpty {
            let projectKey = noteProject.lowercased()
            if let indices = preparedIndex.projectIndex[projectKey] {
                for idx in indices {
                    candidateScores[idx, default: 0] += 0  // mark as candidate
                }
            }
        }

        // MOC folder overlap: scan all notes with shared MOC folders (rare, small set)
        if !noteFolders.isEmpty {
            for (i, other) in allNotes.enumerated() {
                let otherFolders = preparedIndex.mocFolders[other.name] ?? []
                if !noteFolders.isDisjoint(with: otherFolders) {
                    candidateScores[i, default: 0] += 0  // mark as candidate
                }
            }
        }

        // Folder boost: scan boost pairs to find boosted notes
        if !boostSet.isEmpty {
            for (i, other) in allNotes.enumerated() {
                let key = Self.pairKey(note.folderRelPath, other.folderRelPath)
                if boostSet.contains(key) {
                    candidateScores[i, default: 0] += 0  // mark as candidate
                }
            }
        }

        // Score only collected candidates
        var candidates: [Candidate] = []

        for (idx, _) in candidateScores {
            let other = allNotes[idx]
            guard other.name != note.name else { continue }
            guard !note.existingRelated.contains(other.name) else { continue }
            if excludeSameFolder && other.folderName == note.folderName { continue }

            // Folder relation checks
            var folderBoostApplied = false
            let key = Self.pairKey(note.folderRelPath, other.folderRelPath)
            if suppressSet.contains(key) { continue }
            folderBoostApplied = boostSet.contains(key)

            var score: Double = 0

            // Tag overlap: minimum 2 tags required for genuine relevance
            let otherTags = Set(other.tags.map { $0.lowercased() })
            let tagOverlap = noteTags.intersection(otherTags).count
            if tagOverlap >= 2 {
                score += Double(tagOverlap) * 1.5
            }

            let otherFolders = preparedIndex.mocFolders[other.name] ?? []
            let sharedFolders = noteFolders.intersection(otherFolders)
            if !sharedFolders.isEmpty {
                score += Double(sharedFolders.count) * folderBonus
            }

            if let noteProject = note.project, !noteProject.isEmpty,
               let otherProject = other.project, !otherProject.isEmpty,
               noteProject.lowercased() == otherProject.lowercased() {
                score += 2.0
            }

            // Folder relation: boost +2.0
            if folderBoostApplied {
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
