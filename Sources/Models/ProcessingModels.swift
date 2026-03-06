import Foundation

enum ProcessingPhase {
    case preparing
    case extracting
    case classifying
    case linking
    case processing
    case finishing

    var displayName: String {
        switch self {
        case .preparing: return L10n.Processing.preparing
        case .extracting: return L10n.Processing.extracting
        case .classifying: return L10n.Processing.classifying
        case .linking: return L10n.Processing.linking
        case .processing: return L10n.Processing.processing
        case .finishing: return L10n.Processing.finishing
        }
    }
}

struct ProcessedFileResult: Identifiable {
    enum Status {
        case success
        case relocated(from: String)
        case skipped(String)
        case deleted
        case deduplicated(String)
        case error(String)
    }

    let id = UUID()
    let fileName: String
    let para: PARACategory
    let targetPath: String
    let tags: [String]
    var status: Status = .success

    var isSuccess: Bool {
        switch status {
        case .success, .relocated, .deduplicated: return true
        default: return false
        }
    }

    var isError: Bool {
        if case .error = status { return true }
        return false
    }

    var error: String? {
        if case .error(let message) = status { return message }
        return nil
    }

    var isAsset: Bool {
        targetPath.contains("/_Assets/")
    }

    var displayTarget: String {
        let url = URL(fileURLWithPath: targetPath)
        let components = url.pathComponents
        let meaningful = components.filter { $0 != "/" }

        // _Assets files: show subfolder (e.g. "_Assets/images")
        if let idx = meaningful.firstIndex(of: "_Assets"), idx + 1 < meaningful.count {
            return "_Assets/\(meaningful[idx + 1])"
        }

        if meaningful.count >= 2 {
            return meaningful.suffix(2).joined(separator: "/")
        }
        return meaningful.last ?? targetPath
    }
}

struct PendingConfirmation: Identifiable {
    enum Reason {
        case lowConfidence
        case nameConflict
        case misclassified
        case unmatchedProject
    }

    let id = UUID()
    let fileName: String
    let filePath: String
    let content: String
    let options: [ClassifyResult]
    var reason: Reason = .lowConfidence
    var suggestedProjectName: String?
}
