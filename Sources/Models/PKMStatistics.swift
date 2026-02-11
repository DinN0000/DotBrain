import Foundation

/// Statistics data model for the PKM dashboard
struct PKMStatistics {
    var totalFiles: Int = 0
    var byCategory: [String: Int] = [:]  // "project", "area", "resource", "archive"
    var recentActivity: [ActivityEntry] = []
    var apiCost: Double = 0
    var duplicatesFound: Int = 0
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let fileName: String
    let category: String
    let date: Date
    let action: String  // "classified", "deduplicated", "deleted"
}
