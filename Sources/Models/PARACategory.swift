import Foundation

/// PARA methodology categories
enum PARACategory: String, Codable, CaseIterable {
    case project
    case area
    case resource
    case archive

    var folderName: String {
        switch self {
        case .project: return "1_Project"
        case .area: return "2_Area"
        case .resource: return "3_Resource"
        case .archive: return "4_Archive"
        }
    }

    var displayName: String {
        switch self {
        case .project: return "Project"
        case .area: return "Area"
        case .resource: return "Resource"
        case .archive: return "Archive"
        }
    }

    var icon: String {
        switch self {
        case .project: return "folder.fill"
        case .area: return "square.stack.3d.up.fill"
        case .resource: return "book.fill"
        case .archive: return "archivebox.fill"
        }
    }

    /// Initialize from folder path prefix
    init?(folderPrefix: String) {
        switch folderPrefix {
        case "1_Project": self = .project
        case "2_Area": self = .area
        case "3_Resource": self = .resource
        case "4_Archive": self = .archive
        default: return nil
        }
    }

    /// Detect PARA category from a file/folder path containing a PARA folder segment
    static func fromPath(_ path: String) -> PARACategory? {
        if path.contains("/1_Project/") || path.contains("/1_Project") { return .project }
        if path.contains("/2_Area/") || path.contains("/2_Area") { return .area }
        if path.contains("/3_Resource/") || path.contains("/3_Resource") { return .resource }
        if path.contains("/4_Archive/") || path.contains("/4_Archive") { return .archive }
        return nil
    }
}
