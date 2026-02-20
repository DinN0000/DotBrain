import Foundation
import CryptoKit

/// Actor-based cache for SHA256 content hashes of .md files.
/// Persists to `pkmRoot/.dotbrain/content-hashes.json`.
actor ContentHashCache {
    private let pkmRoot: String
    private let cachePath: String
    private var cache: [String: CacheEntry] = [:]  // relative path -> entry

    struct CacheEntry: Codable {
        let hash: String
        let lastChecked: String  // ISO8601
        let fileSize: Int
    }

    enum FileStatus {
        case unchanged
        case modified
        case new
    }

    struct FileStatusEntry {
        let filePath: String
        let fileName: String
        let status: FileStatus
    }

    init(pkmRoot: String) {
        self.pkmRoot = pkmRoot
        self.cachePath = (pkmRoot as NSString).appendingPathComponent(".dotbrain/content-hashes.json")
    }

    // MARK: - Persistence

    /// Load cached hashes from disk
    func load() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cachePath),
              let data = fm.contents(atPath: cachePath) else {
            return
        }
        do {
            cache = try JSONDecoder().decode([String: CacheEntry].self, from: data)
        } catch {
            // Corrupted cache file -- start fresh
            cache = [:]
        }
    }

    /// Write cached hashes to disk
    func save() {
        let fm = FileManager.default
        let dirPath = (cachePath as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dirPath) {
            try? fm.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
        }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(cache)
            try data.write(to: URL(fileURLWithPath: cachePath))
        } catch {
            // Silently fail -- cache is a best-effort optimization
        }
    }

    // MARK: - File Status Checks

    /// Check a single file's status against its cached hash
    func checkFile(_ filePath: String) -> FileStatus {
        guard isPathSafe(filePath) else { return .new }

        let relativePath = self.relativePath(for: filePath)
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return .new
        }
        let currentHash = computeSHA256(content)

        guard let entry = cache[relativePath] else {
            return .new
        }
        return entry.hash == currentHash ? .unchanged : .modified
    }

    /// Check all .md files in a folder and return their statuses
    func checkFolder(_ folderPath: String) -> [FileStatusEntry] {
        guard isPathSafe(folderPath) else { return [] }

        let fm = FileManager.default
        var results: [FileStatusEntry] = []

        guard let enumerator = fm.enumerator(atPath: folderPath) else {
            return []
        }
        while let element = enumerator.nextObject() as? String {
            guard element.hasSuffix(".md") else { continue }
            let fullPath = (folderPath as NSString).appendingPathComponent(element)
            let fileName = (element as NSString).lastPathComponent

            // Skip hidden and system files
            if fileName.hasPrefix(".") || fileName.hasPrefix("_") {
                continue
            }

            let status = checkFile(fullPath)
            results.append(FileStatusEntry(
                filePath: fullPath,
                fileName: fileName,
                status: status
            ))
        }
        return results
    }

    // MARK: - Hash Updates

    /// Update the cached hash for a single file
    func updateHash(_ filePath: String) {
        guard isPathSafe(filePath) else { return }

        let relativePath = self.relativePath(for: filePath)
        guard let content = try? String(contentsOfFile: filePath, encoding: .utf8) else {
            return
        }
        let hash = computeSHA256(content)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: filePath)[.size] as? Int) ?? 0
        let formatter = ISO8601DateFormatter()

        cache[relativePath] = CacheEntry(
            hash: hash,
            lastChecked: formatter.string(from: Date()),
            fileSize: fileSize
        )
    }

    /// Update cached hashes for multiple files, then save to disk
    func updateHashes(_ filePaths: [String]) {
        for filePath in filePaths {
            updateHash(filePath)
        }
        save()
    }

    // MARK: - Private Helpers

    /// Compute SHA256 hex digest of a string's UTF-8 data
    private func computeSHA256(_ content: String) -> String {
        let data = Data(content.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Convert an absolute path to a path relative to pkmRoot
    private func relativePath(for absolutePath: String) -> String {
        let resolvedRoot = URL(fileURLWithPath: pkmRoot).resolvingSymlinksInPath().path
        let resolvedPath = URL(fileURLWithPath: absolutePath).resolvingSymlinksInPath().path
        let normalizedRoot = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        if resolvedPath.hasPrefix(normalizedRoot) {
            return String(resolvedPath.dropFirst(normalizedRoot.count))
        }
        return absolutePath
    }

    /// Validate that a path is safely within the PKM root (prevents symlink traversal)
    private func isPathSafe(_ path: String) -> Bool {
        let resolvedRoot = URL(fileURLWithPath: pkmRoot).standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedPath = URL(fileURLWithPath: path).standardizedFileURL.resolvingSymlinksInPath().path
        if resolvedPath == resolvedRoot { return true }
        let normalizedRoot = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        return resolvedPath.hasPrefix(normalizedRoot)
    }
}
