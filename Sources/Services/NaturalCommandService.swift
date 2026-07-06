import Foundation

/// Structured constraints resolved from a free-text inbox instruction.
struct InboxInstructionResolution: Sendable {
    let destination: InboxDestination?
    let includedFileNames: Set<String>?
    let inboxCount: Int
}

actor NaturalCommandService {
    static let shared = NaturalCommandService()

    private init() {}

    /// Resolve a free-text inbox instruction into structured constraints.
    /// An instruction the planner cannot map to a structured plan is not an
    /// error — it still guides classification as raw prompt text. Explicit
    /// failures (a named folder that doesn't exist, empty inbox, no matching
    /// files) keep surfacing.
    func resolveInboxInstruction(
        _ instruction: String,
        pkmRoot: String
    ) async throws -> InboxInstructionResolution {
        let inboxPaths = InboxScanner(pkmRoot: pkmRoot).scan()
        let pathManager = PKMPathManager(root: pkmRoot)
        let fileManager = FileManager.default
        var folders: [NaturalCommandFolder] = []
        for category in PARACategory.allCases {
            let basePath = pathManager.paraPath(for: category)
            guard let entries = try? fileManager.contentsOfDirectory(atPath: basePath) else { continue }
            for entry in entries where !entry.hasPrefix(".") && !entry.hasPrefix("_") {
                let path = (basePath as NSString).appendingPathComponent(entry)
                var isDirectory: ObjCBool = false
                guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
                      isDirectory.boolValue else { continue }
                folders.append(NaturalCommandFolder(name: entry, category: category))
            }
        }
        let context = NaturalCommandContext(
            surface: .inbox,
            inboxCount: inboxPaths.count,
            folders: folders,
            inboxFileNames: inboxPaths.map { ($0 as NSString).lastPathComponent }
        )

        let resolved: NaturalCommandPlan?
        do {
            resolved = try await plan(instruction, context: context)
        } catch NaturalCommandError.unsupported {
            resolved = nil
        }
        let (destination, included) = try Self.applying(resolved, inboxFileNames: context.inboxFileNames)
        return InboxInstructionResolution(
            destination: destination,
            includedFileNames: included,
            inboxCount: inboxPaths.count
        )
    }

    /// Turn a validated plan into inbox constraints. nil plan = guidance-only
    /// (no destination, no file filter). Pure — unit tested.
    static func applying(
        _ plan: NaturalCommandPlan?,
        inboxFileNames: [String]
    ) throws -> (destination: InboxDestination?, includedFileNames: Set<String>?) {
        guard let plan else { return (nil, nil) }

        var destination: InboxDestination?
        if plan.action == .processInboxToFolder, let category = plan.targetCategory {
            destination = InboxDestination(category: category, folderName: plan.folderName)
        }
        var selected = Set(inboxFileNames)
        if let included = plan.includedFileNames { selected = Set(included) }
        if let excluded = plan.excludedFileNames { selected.subtract(excluded) }
        guard !selected.isEmpty else {
            throw NaturalCommandError.unavailable(L10n.NaturalCommand.noMatchingFiles)
        }
        return (destination, selected)
    }

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
        Schema fields (do not copy these type hints as literal values — output only the actual chosen value):
        - action: exactly one of these words: processInbox, processInboxToFolder, createFolder, renameFolder, moveFolder, updateFolderDescription, completeProject, reactivateProject, unsupported
        - category, sourceCategory, targetCategory: exactly one of these words: project, area, resource, archive — or JSON null. Never write more than one word and never write a "|" character.
        - folderName, newName, description: a plain string, or JSON null
        - includedFileNames, excludedFileNames: a JSON array of exact strings, or JSON null

        Example of a valid response (folderName must come from context, never from this example):
        {"action":"processInbox","category":null,"sourceCategory":null,"targetCategory":null,"folderName":null,"newName":null,"description":null,"includedFileNames":null,"excludedFileNames":null}

        Rules:
        - Use only folder names present in context for rename, move, complete, and reactivate.
        - On the inbox surface, processInboxToFolder means organize current Inbox items into a destination.
          The destination is either one existing folder (set targetCategory and folderName), or a whole
          PARA category like "Project에 넣어줘" (set targetCategory and leave folderName null — a folder
          per file is then chosen automatically within that category).
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
            NSLog("[NaturalCommandService] JSON 중괄호를 찾지 못함 — 응답 처음 200자: %@", String(trimmed.prefix(200)))
            throw NaturalCommandError.invalidResponse
        }
        guard let data = json.data(using: .utf8) else {
            throw NaturalCommandError.invalidResponse
        }
        let normalizedData = Self.normalizingEnumFields(in: data) ?? data
        guard let plan = try? JSONDecoder().decode(NaturalCommandPlan.self, from: normalizedData) else {
            NSLog("[NaturalCommandService] JSON 디코딩 실패 — 추출된 JSON 처음 200자: %@", String(json.prefix(200)))
            throw NaturalCommandError.invalidResponse
        }
        return plan
    }

    private static let categoryFieldKeys: Set<String> = ["category", "sourceCategory", "targetCategory"]
    private static let validCategoryValues = Set(PARACategory.allCases.map(\.rawValue))
    private static let validActionValues = Set(NaturalCommandPlan.Action.allCases.map(\.rawValue))

    private static func normalizedEnumToken(_ value: Any?, validValues: Set<String>) -> String? {
        guard let raw = value as? String else { return nil }
        func match(_ token: String) -> String? {
            let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
            if validValues.contains(trimmedToken) { return trimmedToken }
            return validValues.first { $0.caseInsensitiveCompare(trimmedToken) == .orderedSame }
        }
        let candidate = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = match(candidate) { return exact }
        // Model echoed the prompt's "a|b|c" type hint literally. Salvage only
        // when the echo contains exactly one valid token — picking the first
        // of several would fabricate a choice the model never made.
        var salvaged: Set<String> = []
        for token in candidate.split(separator: "|") {
            if let found = match(String(token)) { salvaged.insert(found) }
        }
        return salvaged.count == 1 ? salvaged.first : nil
    }

    /// Recover from models that echo the prompt's enum type hints literally
    /// (e.g. "project|area|resource|archive" or "Project" instead of "project").
    /// Salvages a valid token when unambiguous; otherwise falls back to a
    /// value the rest of the pipeline already handles gracefully (nil for
    /// category fields, "unsupported" for action) instead of failing the
    /// whole decode.
    private static func normalizingEnumFields(in data: Data) -> Data? {
        guard var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        object["action"] = normalizedEnumToken(object["action"], validValues: validActionValues)
            ?? NaturalCommandPlan.Action.unsupported.rawValue

        for key in categoryFieldKeys where object[key] != nil {
            object[key] = normalizedEnumToken(object[key], validValues: validCategoryValues) ?? NSNull()
        }

        return try? JSONSerialization.data(withJSONObject: object)
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
            // Category-only destination ("Project에 넣어줘"): folderName stays
            // nil and classification is constrained to the category downstream.
            var resolvedName: String?
            if let name = plan.folderName {
                guard let existing = existingFolder(
                    named: name,
                    category: category,
                    in: context
                ) else {
                    throw NaturalCommandError.folderNotFound(name)
                }
                resolvedName = existing.name
            }
            let selection = try validatedFileSelection(plan, context: context)
            return NaturalCommandPlan(
                action: .processInboxToFolder,
                category: nil,
                sourceCategory: nil,
                targetCategory: category,
                folderName: resolvedName,
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
