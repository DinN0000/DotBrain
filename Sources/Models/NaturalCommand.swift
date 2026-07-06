import Foundation

enum NaturalCommandSurface: String, Codable {
    case inbox
    case folderManagement
}

struct NaturalCommandFolder: Codable, Equatable {
    let name: String
    let category: PARACategory
    var description: String? = nil
}

struct NaturalCommandContext: Codable {
    let surface: NaturalCommandSurface
    let inboxCount: Int
    let folders: [NaturalCommandFolder]
    var inboxFileNames: [String] = []
}

struct InboxDestination: Equatable, Sendable {
    let category: PARACategory
    let folderName: String
}

struct NaturalCommandPlan: Codable, Equatable, Identifiable {
    enum Action: String, Codable, CaseIterable {
        case processInbox
        case processInboxToFolder
        case createFolder
        case renameFolder
        case moveFolder
        case updateFolderDescription
        case completeProject
        case reactivateProject
        case unsupported
    }

    var id: String {
        [action.rawValue, category?.rawValue, sourceCategory?.rawValue,
         targetCategory?.rawValue, folderName, newName, description]
            .compactMap { $0 }
            .joined(separator: "|")
    }

    let action: Action
    let category: PARACategory?
    let sourceCategory: PARACategory?
    let targetCategory: PARACategory?
    let folderName: String?
    let newName: String?
    var description: String? = nil
    var includedFileNames: [String]? = nil
    var excludedFileNames: [String]? = nil

    var confirmationText: String {
        switch action {
        case .processInbox:
            return L10n.NaturalCommand.processInbox
        case .processInboxToFolder:
            return L10n.NaturalCommand.processInboxToFolder(
                folderName ?? "",
                targetCategory?.displayName ?? ""
            )
        case .createFolder:
            return L10n.NaturalCommand.createFolder(folderName ?? "", category?.displayName ?? "")
        case .renameFolder:
            return L10n.NaturalCommand.renameFolder(folderName ?? "", newName ?? "")
        case .moveFolder:
            return L10n.NaturalCommand.moveFolder(
                folderName ?? "",
                sourceCategory?.displayName ?? "",
                targetCategory?.displayName ?? ""
            )
        case .updateFolderDescription:
            return L10n.NaturalCommand.updateFolderDescription(folderName ?? "", description ?? "")
        case .completeProject:
            return L10n.NaturalCommand.completeProject(folderName ?? "")
        case .reactivateProject:
            return L10n.NaturalCommand.reactivateProject(folderName ?? "")
        case .unsupported:
            return L10n.NaturalCommand.unsupported
        }
    }
}

enum NaturalCommandError: LocalizedError {
    case invalidResponse
    case unsupported
    case missingArgument
    case folderNotFound(String)
    case invalidFolderName
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return L10n.NaturalCommand.invalidResponse
        case .unsupported: return L10n.NaturalCommand.unsupported
        case .missingArgument: return L10n.NaturalCommand.missingArgument
        case .folderNotFound(let name): return L10n.NaturalCommand.folderNotFound(name)
        case .invalidFolderName: return L10n.NaturalCommand.invalidFolderName
        case .unavailable(let reason): return reason
        }
    }
}
