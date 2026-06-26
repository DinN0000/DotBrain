import Foundation

actor NaturalCommandService {
    static let shared = NaturalCommandService()

    private init() {}

    func plan(_ input: String, context: NaturalCommandContext) async throws -> NaturalCommandPlan {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NaturalCommandError.missingArgument }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let contextData = try encoder.encode(context)
        let contextJSON = String(decoding: contextData, as: UTF8.self)

        let system = """
        You translate a user's Korean or English request into exactly one DotBrain command.
        Return one JSON object only. Never return Markdown or explanatory text.
        Schema:
        {"action":"processInbox|processInboxToFolder|createFolder|renameFolder|moveFolder|updateFolderDescription|completeProject|reactivateProject|unsupported","category":"project|area|resource|archive|null","sourceCategory":"project|area|resource|archive|null","targetCategory":"project|area|resource|archive|null","folderName":"string|null","newName":"string|null","description":"string|null","includedFileNames":["exact name"]|null,"excludedFileNames":["exact name"]|null}

        Rules:
        - Use only folder names present in context for rename, move, complete, and reactivate.
        - On the inbox surface, processInboxToFolder means organize every current Inbox item into one existing folder.
        - For requests like "only these", set includedFileNames. For "except these", set excludedFileNames.
        - Copy Inbox file names exactly from context. Leave both file lists null for all files.
        - On the inbox surface, only processInbox and processInboxToFolder are allowed.
        - On the folderManagement surface, processInbox is not allowed.
        - updateFolderDescription changes one existing project or area folder description. Put the new text in description.
        - Never infer delete, merge, shell, file-edit, or arbitrary filesystem actions; return unsupported.
        - completeProject applies only to project. reactivateProject applies only to archive.
        - Preserve folder names exactly as shown in context.
        - If the request is ambiguous or needs more than one command, return unsupported.
        """
        let message = "Context: \(contextJSON)\nUser request: \(trimmed)"
        let raw = try await AIService.shared.sendFast(
            maxTokens: 400,
            message: message,
            systemMessage: system
        )

        let decoded = try decodePlan(raw)
        return try validate(decoded, context: context)
    }

    func decodePlan(_ raw: String) throws -> NaturalCommandPlan {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if let first = trimmed.firstIndex(of: "{"), let last = trimmed.lastIndex(of: "}"), first <= last {
            json = String(trimmed[first...last])
        } else {
            throw NaturalCommandError.invalidResponse
        }
        guard let data = json.data(using: .utf8),
              let plan = try? JSONDecoder().decode(NaturalCommandPlan.self, from: data) else {
            throw NaturalCommandError.invalidResponse
        }
        return plan
    }

    func validate(_ plan: NaturalCommandPlan, context: NaturalCommandContext) throws -> NaturalCommandPlan {
        guard plan.action != .unsupported else { throw NaturalCommandError.unsupported }

        switch context.surface {
        case .inbox:
            guard plan.action == .processInbox ||
                    plan.action == .processInboxToFolder else {
                throw NaturalCommandError.unsupported
            }
        case .folderManagement:
            guard plan.action != .processInbox &&
                    plan.action != .processInboxToFolder else {
                throw NaturalCommandError.unsupported
            }
        }

        switch plan.action {
        case .processInbox:
            guard context.inboxCount > 0 else {
                throw NaturalCommandError.unavailable(L10n.NaturalCommand.emptyInbox)
            }
            let selection = try validatedFileSelection(plan, context: context)
            return NaturalCommandPlan(
                action: .processInbox,
                category: nil,
                sourceCategory: nil,
                targetCategory: nil,
                folderName: nil,
                newName: nil,
                includedFileNames: selection.included,
                excludedFileNames: selection.excluded
            )
        case .processInboxToFolder:
            guard context.inboxCount > 0 else {
                throw NaturalCommandError.unavailable(L10n.NaturalCommand.emptyInbox)
            }
            guard let category = plan.targetCategory else {
                throw NaturalCommandError.missingArgument
            }
            guard let existing = existingFolder(
                named: plan.folderName,
                category: category,
                in: context
            ) else {
                throw NaturalCommandError.folderNotFound(plan.folderName ?? "")
            }
            let selection = try validatedFileSelection(plan, context: context)
            return NaturalCommandPlan(
                action: .processInboxToFolder,
                category: nil,
                sourceCategory: nil,
                targetCategory: category,
                folderName: existing.name,
                newName: nil,
                includedFileNames: selection.included,
                excludedFileNames: selection.excluded
            )
        case .createFolder:
            guard let category = plan.category,
                  let name = validNewName(plan.folderName) else {
                throw NaturalCommandError.invalidFolderName
            }
            return NaturalCommandPlan(
                action: .createFolder,
                category: category,
                sourceCategory: nil,
                targetCategory: nil,
                folderName: name,
                newName: nil
            )
        case .renameFolder:
            guard let category = plan.category else { throw NaturalCommandError.missingArgument }
            guard let existing = existingFolder(named: plan.folderName, category: category, in: context) else {
                throw NaturalCommandError.folderNotFound(plan.folderName ?? "")
            }
            guard let newName = validNewName(plan.newName) else {
                throw NaturalCommandError.invalidFolderName
            }
            return NaturalCommandPlan(
                action: .renameFolder,
                category: category,
                sourceCategory: nil,
                targetCategory: nil,
                folderName: existing.name,
                newName: newName
            )
        case .moveFolder:
            guard let source = plan.sourceCategory,
                  let target = plan.targetCategory else {
                throw NaturalCommandError.missingArgument
            }
            guard source != target else { throw NaturalCommandError.unsupported }
            guard let existing = existingFolder(named: plan.folderName, category: source, in: context) else {
                throw NaturalCommandError.folderNotFound(plan.folderName ?? "")
            }
            return NaturalCommandPlan(
                action: .moveFolder,
                category: nil,
                sourceCategory: source,
                targetCategory: target,
                folderName: existing.name,
                newName: nil
            )
        case .updateFolderDescription:
            guard let category = plan.category,
                  category == .project || category == .area else {
                throw NaturalCommandError.unsupported
            }
            guard let existing = existingFolder(named: plan.folderName, category: category, in: context) else {
                throw NaturalCommandError.folderNotFound(plan.folderName ?? "")
            }
            guard let description = validDescription(plan.description) else {
                throw NaturalCommandError.missingArgument
            }
            return NaturalCommandPlan(
                action: .updateFolderDescription,
                category: category,
                sourceCategory: nil,
                targetCategory: nil,
                folderName: existing.name,
                newName: nil,
                description: description
            )
        case .completeProject:
            guard let existing = existingFolder(named: plan.folderName, category: .project, in: context) else {
                throw NaturalCommandError.folderNotFound(plan.folderName ?? "")
            }
            return NaturalCommandPlan(
                action: .completeProject,
                category: .project,
                sourceCategory: nil,
                targetCategory: .archive,
                folderName: existing.name,
                newName: nil
            )
        case .reactivateProject:
            guard let existing = existingFolder(named: plan.folderName, category: .archive, in: context) else {
                throw NaturalCommandError.folderNotFound(plan.folderName ?? "")
            }
            return NaturalCommandPlan(
                action: .reactivateProject,
                category: .archive,
                sourceCategory: nil,
                targetCategory: .project,
                folderName: existing.name,
                newName: nil
            )
        case .unsupported:
            throw NaturalCommandError.unsupported
        }
    }

    private func existingFolder(
        named name: String?,
        category: PARACategory,
        in context: NaturalCommandContext
    ) -> NaturalCommandFolder? {
        guard let name else { return nil }
        let normalized = name.precomposedStringWithCanonicalMapping
        return context.folders.first {
            $0.category == category &&
            $0.name.precomposedStringWithCanonicalMapping.compare(
                normalized,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) == .orderedSame
        }
    }

    private func validNewName(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.count <= 255,
              !trimmed.hasPrefix("."),
              !trimmed.hasPrefix("_"),
              !trimmed.contains("/"),
              !trimmed.contains("\\"),
              !trimmed.contains("\0"),
              trimmed != ".",
              trimmed != ".." else { return nil }
        return trimmed
    }

    private func validDescription(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= 1_000 else { return nil }
        return trimmed
    }

    private func validatedFileSelection(
        _ plan: NaturalCommandPlan,
        context: NaturalCommandContext
    ) throws -> (included: [String]?, excluded: [String]?) {
        func canonicalize(_ names: [String]?) throws -> [String]? {
            guard let names else { return nil }
            var result: [String] = []
            for name in names {
                guard let existing = context.inboxFileNames.first(where: {
                    $0.compare(name, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
                }) else {
                    throw NaturalCommandError.unavailable(L10n.NaturalCommand.fileNotFound(name))
                }
                if !result.contains(existing) { result.append(existing) }
            }
            return result.isEmpty ? nil : result
        }
        return (try canonicalize(plan.includedFileNames), try canonicalize(plan.excludedFileNames))
    }

}
