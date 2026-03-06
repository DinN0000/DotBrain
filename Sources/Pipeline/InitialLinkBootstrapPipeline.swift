import Foundation

/// One-time bootstrap for existing vaults after the first successful inbox import.
/// Fills missing metadata across the vault, refreshes the note index, and builds
/// an initial semantic link graph so the first run is not dependent on Vault Check.
struct InitialLinkBootstrapPipeline {
    let pkmRoot: String

    struct Progress {
        let phase: String
        let fraction: Double
    }

    struct Result {
        let enrichedCount: Int
        let linksCreated: Int
        let filesIndexed: Int
    }

    private static let markerFileName = "initial-link-bootstrap-v1"

    static func needsBootstrap(pkmRoot: String) -> Bool {
        !FileManager.default.fileExists(atPath: markerPath(pkmRoot: pkmRoot))
    }

    static func markCompleted(pkmRoot: String) {
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        try? FileManager.default.createDirectory(atPath: metaDir, withIntermediateDirectories: true)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        try? timestamp.write(toFile: markerPath(pkmRoot: pkmRoot), atomically: true, encoding: .utf8)
    }

    func run(onProgress: @escaping @Sendable (Progress) -> Void) async -> Result {
        let pathManager = PKMPathManager(root: pkmRoot)
        let allMarkdownFiles = pathManager.allMarkdownFiles()

        guard !allMarkdownFiles.isEmpty else {
            Self.markCompleted(pkmRoot: pkmRoot)
            return Result(enrichedCount: 0, linksCreated: 0, filesIndexed: 0)
        }

        onProgress(Progress(phase: "초기 메타데이터 보완 중...", fraction: 0.05))

        let enricher = NoteEnricher(pkmRoot: pkmRoot)
        let filesToEnrich = allMarkdownFiles.filter { PARACategory.fromPath($0) != .archive }
        let enrichResults = await enricher.enrichFiles(filesToEnrich)
        let enrichedCount = enrichResults.filter { $0.fieldsUpdated > 0 }.count

        if Task.isCancelled {
            return Result(enrichedCount: enrichedCount, linksCreated: 0, filesIndexed: 0)
        }

        onProgress(Progress(phase: "초기 노트 인덱스 갱신 중...", fraction: 0.40))

        let dirtyFolders = Set(allMarkdownFiles.map {
            ($0 as NSString).deletingLastPathComponent
        })
        if !dirtyFolders.isEmpty {
            let indexGenerator = NoteIndexGenerator(pkmRoot: pkmRoot)
            await indexGenerator.updateForFolders(dirtyFolders)
        }

        if Task.isCancelled {
            return Result(enrichedCount: enrichedCount, linksCreated: 0, filesIndexed: dirtyFolders.count)
        }

        onProgress(Progress(phase: "초기 시맨틱 링크 구축 중...", fraction: 0.55))

        let linker = SemanticLinker(pkmRoot: pkmRoot)
        let linkResult = await linker.linkAll(changedFiles: nil) { progress, status in
            onProgress(Progress(phase: status, fraction: 0.55 + progress * 0.35))
        }

        if Task.isCancelled {
            return Result(
                enrichedCount: enrichedCount,
                linksCreated: linkResult.linksCreated,
                filesIndexed: dirtyFolders.count
            )
        }

        onProgress(Progress(phase: "초기 링크 캐시 저장 중...", fraction: 0.93))

        let cache = ContentHashCache(pkmRoot: pkmRoot)
        await cache.load()
        await cache.updateHashes(pathManager.allMarkdownFiles())
        await cache.save()

        Self.markCompleted(pkmRoot: pkmRoot)
        onProgress(Progress(phase: "초기 링크 구축 완료", fraction: 1.0))

        return Result(
            enrichedCount: enrichedCount,
            linksCreated: linkResult.linksCreated,
            filesIndexed: dirtyFolders.count
        )
    }

    private static func markerPath(pkmRoot: String) -> String {
        let metaDir = (pkmRoot as NSString).appendingPathComponent(".meta")
        return (metaDir as NSString).appendingPathComponent(markerFileName)
    }
}
