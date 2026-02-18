import Foundation

enum ProcessingPhase: String {
    case preparing = "준비"
    case extracting = "분석"
    case classifying = "AI 분류"
    case linking = "노트 연결"
    case processing = "정리"
    case finishing = "마무리"
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

    var displayTarget: String {
        let url = URL(fileURLWithPath: targetPath)
        let components = url.pathComponents
        let meaningful = components.filter { $0 != "/" }
        if meaningful.count >= 2 {
            return meaningful.suffix(2).joined(separator: "/")
        }
        return meaningful.last ?? targetPath
    }
}

struct PendingConfirmation: Identifiable {
    enum Reason {
        case lowConfidence
        case indexNoteConflict
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
