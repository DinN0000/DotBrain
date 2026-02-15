import Foundation

/// Collects and persists PKM statistics
class StatisticsService {
    private let pkmRoot: String

    /// Serial queue for atomic read-modify-write on UserDefaults
    private static let serialQueue = DispatchQueue(label: "com.hwaa.dotbrain.statistics")

    init(pkmRoot: String) {
        self.pkmRoot = pkmRoot
    }

    /// Scan PARA folders and return current statistics
    func collectStatistics() -> PKMStatistics {
        let pathManager = PKMPathManager(root: pkmRoot)
        let fm = FileManager.default

        var stats = PKMStatistics()

        let categories: [(String, String)] = [
            ("project", pathManager.projectsPath),
            ("area", pathManager.areaPath),
            ("resource", pathManager.resourcePath),
            ("archive", pathManager.archivePath),
        ]

        for (name, path) in categories {
            let count = countFiles(in: path, fileManager: fm)
            stats.byCategory[name] = count
            stats.totalFiles += count
        }

        stats.recentActivity = loadRecentActivity()
        stats.apiCost = UserDefaults.standard.double(forKey: "pkmApiCost")
        stats.duplicatesFound = UserDefaults.standard.integer(forKey: "pkmDuplicatesFound")

        return stats
    }

    /// Record a classification activity (thread-safe)
    static func recordActivity(fileName: String, category: String, action: String) {
        serialQueue.sync {
            var history = loadActivityHistory()
            let entry: [String: String] = [
                "fileName": fileName,
                "category": category,
                "action": action,
                "date": ISO8601DateFormatter().string(from: Date()),
            ]
            history.insert(entry, at: 0)
            if history.count > 100 {
                history = Array(history.prefix(100))
            }
            UserDefaults.standard.set(history, forKey: "pkmActivityHistory")
        }
    }

    /// Add to cumulative API cost (thread-safe)
    static func addApiCost(_ cost: Double) {
        serialQueue.sync {
            let current = UserDefaults.standard.double(forKey: "pkmApiCost")
            UserDefaults.standard.set(current + cost, forKey: "pkmApiCost")
        }
    }

    /// Increment duplicates found counter (thread-safe)
    static func incrementDuplicates() {
        serialQueue.sync {
            let current = UserDefaults.standard.integer(forKey: "pkmDuplicatesFound")
            UserDefaults.standard.set(current + 1, forKey: "pkmDuplicatesFound")
        }
    }

    // MARK: - Private

    private func countFiles(in dirPath: String, fileManager fm: FileManager) -> Int {
        guard let enumerator = fm.enumerator(atPath: dirPath) else { return 0 }
        var count = 0
        while let element = enumerator.nextObject() as? String {
            let name = (element as NSString).lastPathComponent
            if !name.hasPrefix(".") && !name.hasPrefix("_") {
                var isDir: ObjCBool = false
                let fullPath = (dirPath as NSString).appendingPathComponent(element)
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    count += 1
                }
            }
        }
        return count
    }

    private func loadRecentActivity() -> [ActivityEntry] {
        return Self.loadActivityEntries()
    }

    static func loadActivityEntries() -> [ActivityEntry] {
        let history = loadActivityHistory()
        let formatter = ISO8601DateFormatter()
        return history.compactMap { dict in
            guard let fileName = dict["fileName"],
                  let category = dict["category"],
                  let action = dict["action"],
                  let dateStr = dict["date"],
                  let date = formatter.date(from: dateStr) else { return nil }
            return ActivityEntry(fileName: fileName, category: category, date: date, action: action)
        }
    }

    private static func loadActivityHistory() -> [[String: String]] {
        (UserDefaults.standard.array(forKey: "pkmActivityHistory") as? [[String: String]]) ?? []
    }
}
