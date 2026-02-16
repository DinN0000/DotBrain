import Foundation

/// Collects and persists PKM statistics
class StatisticsService {
    private let pkmRoot: String

    /// Actor for atomic read-modify-write on UserDefaults (replaces DispatchQueue serial)
    private static let atomicActor = StatisticsActor()

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

    /// Record a classification activity (thread-safe via actor)
    static func recordActivity(fileName: String, category: String, action: String, detail: String = "") {
        Task {
            await atomicActor.recordActivity(
                fileName: fileName, category: category,
                action: action, detail: detail
            )
        }
    }

    /// Add to cumulative API cost (thread-safe via actor)
    static func addApiCost(_ cost: Double) {
        Task {
            await atomicActor.addApiCost(cost)
        }
    }

    /// Increment duplicates found counter (thread-safe via actor)
    static func incrementDuplicates() {
        Task {
            await atomicActor.incrementDuplicates()
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
            return ActivityEntry(
                fileName: fileName,
                category: category,
                date: date,
                action: action,
                detail: dict["detail"] ?? ""
            )
        }
    }

    private static func loadActivityHistory() -> [[String: String]] {
        (UserDefaults.standard.array(forKey: "pkmActivityHistory") as? [[String: String]]) ?? []
    }
}

/// Private actor for thread-safe UserDefaults mutations (replaces DispatchQueue serial)
private actor StatisticsActor {
    func recordActivity(fileName: String, category: String, action: String, detail: String) {
        var history = (UserDefaults.standard.array(forKey: "pkmActivityHistory") as? [[String: String]]) ?? []
        let entry: [String: String] = [
            "fileName": fileName,
            "category": category,
            "action": action,
            "detail": detail,
            "date": ISO8601DateFormatter().string(from: Date()),
        ]
        history.insert(entry, at: 0)
        if history.count > 100 {
            history = Array(history.prefix(100))
        }
        UserDefaults.standard.set(history, forKey: "pkmActivityHistory")
    }

    func addApiCost(_ cost: Double) {
        let current = UserDefaults.standard.double(forKey: "pkmApiCost")
        UserDefaults.standard.set(current + cost, forKey: "pkmApiCost")
    }

    func incrementDuplicates() {
        let current = UserDefaults.standard.integer(forKey: "pkmDuplicatesFound")
        UserDefaults.standard.set(current + 1, forKey: "pkmDuplicatesFound")
    }
}
