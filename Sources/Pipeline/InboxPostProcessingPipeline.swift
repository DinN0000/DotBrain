import Foundation

/// Runs non-structural inbox follow-up work after files have already been moved.
/// This keeps the initial processing path fast while still enriching and linking
/// newly imported notes before the one-time full bootstrap runs.
struct InboxPostProcessingPipeline {
    let pkmRoot: String
    let filePaths: [String]
    let affectedFolders: Set<String>

    struct Progress {
        let fraction: Double
        let phase: String
    }

    struct Result {
        let enrichedCount: Int
        let linkedNotes: Int
        let linksCreated: Int
    }

    func run(onProgress: ((Progress) -> Void)? = nil) async -> Result {
        let successPaths = Array(Set(filePaths.filter { !$0.isEmpty })).sorted()
        guard !successPaths.isEmpty else {
            return Result(enrichedCount: 0, linkedNotes: 0, linksCreated: 0)
        }

        let mdPaths = successPaths.filter { $0.hasSuffix(".md") }
        let folders = affectedFolders.isEmpty ? Self.affectedFolders(for: successPaths) : affectedFolders

        if !folders.isEmpty {
            onProgress?(Progress(fraction: 0.1, phase: "노트 인덱스 갱신 중..."))
            let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
            await indexGenerator.updateForFolders(folders)
        }

        var enrichedCount = 0
        if !mdPaths.isEmpty {
            onProgress?(Progress(fraction: 0.4, phase: "메타데이터 보완 중..."))
            let enricher = NoteEnricher(pkmRoot: pkmRoot)
            let enrichResults = await enricher.enrichFiles(mdPaths)
            enrichedCount = enrichResults.reduce(0) { $0 + $1.fieldsUpdated }

            if enrichResults.contains(where: { $0.fieldsUpdated > 0 }), !folders.isEmpty {
                let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
                await indexGenerator.updateForFolders(folders)
            }
        }

        onProgress?(Progress(fraction: 0.7, phase: "시맨틱 연결 중..."))
        let linkResult = await SemanticLinker(pkmRoot: pkmRoot).linkNotes(filePaths: successPaths)

        if !mdPaths.isEmpty {
            onProgress?(Progress(fraction: 0.9, phase: "해시 캐시 저장 중..."))
            let cache = ContentHashCache(pkmRoot: pkmRoot)
            await cache.load()
            await cache.updateHashes(mdPaths)
            await cache.save()
        }

        onProgress?(Progress(fraction: 1.0, phase: "링크 후처리 완료"))
        return Result(
            enrichedCount: enrichedCount,
            linkedNotes: linkResult.notesLinked,
            linksCreated: linkResult.linksCreated
        )
    }

    private static func affectedFolders(for targetPaths: [String]) -> Set<String> {
        Set(targetPaths.compactMap { path -> String? in
            guard !path.isEmpty else { return nil }
            let dir = (path as NSString).deletingLastPathComponent
            return dir.isEmpty ? nil : dir
        })
    }
}
