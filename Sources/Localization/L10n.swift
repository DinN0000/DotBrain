import Foundation

/// Centralized localization strings.
/// Usage: `Text(L10n.Screen.inbox)` or `L10n.Processing.preparing`
enum L10n {
    static let bundle: Bundle = {
        // Production: .app bundle (Contents/Resources/ has .lproj)
        if Bundle.main.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko") != nil {
            return .main
        }
        // Development: find Resources/ relative to executable
        let execURL = URL(fileURLWithPath: ProcessInfo.processInfo.arguments[0])
            .resolvingSymlinksInPath()
        var dir = execURL.deletingLastPathComponent()
        for _ in 0..<5 {
            let candidate = dir.appendingPathComponent("Resources")
            if let bundle = Bundle(path: candidate.path),
               bundle.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: "ko") != nil {
                return bundle
            }
            dir = dir.deletingLastPathComponent()
        }
        return .main
    }()

    private static func tr(_ key: String) -> String {
        NSLocalizedString(key, bundle: bundle, comment: "")
    }

    static func tr(_ key: String, _ args: CVarArg...) -> String {
        String(format: tr(key), arguments: args)
    }

    // MARK: - Screen Names

    enum Screen {
        static let inbox = tr("screen.inbox")
        static let dashboard = tr("screen.dashboard")
        static let settings = tr("screen.settings")
        static let paraManage = tr("screen.para_manage")
        static let search = tr("screen.search")
        static let vaultInspector = tr("screen.vault_inspector")
        static let aiStatistics = tr("screen.ai_statistics")
        static let results = tr("screen.results")
        static let folderRelationExplorer = tr("screen.folder_relation_explorer")
    }

    // MARK: - Processing

    enum Processing {
        static let preparing = tr("processing.preparing")
        static let extracting = tr("processing.extracting")
        static let classifying = tr("processing.classifying")
        static let linking = tr("processing.linking")
        static let processing = tr("processing.processing")
        static let finishing = tr("processing.finishing")
        static let folderReorganizing = tr("processing.folder_reorganizing")
        static let inboxProcessing = tr("processing.inbox_processing")
        static let cancel = tr("processing.cancel")
        static func filesReady(_ count: Int) -> String { tr("processing.files_ready", count) }
        static let linkingNotes = tr("processing.linking_notes")
    }

    // MARK: - Search

    enum Search {
        static let tagMatch = tr("search.tag_match")
        static let bodyMatch = tr("search.body_match")
        static let summaryMatch = tr("search.summary_match")
        static let titleMatch = tr("search.title_match")
        static let placeholder = tr("search.placeholder")
        static let clearLabel = tr("search.clear_label")
        static let searching = tr("search.searching")
        static let noResults = tr("search.no_results")
        static func resultCount(_ count: Int) -> String { tr("search.result_count", count) }
        static let searchDescription = tr("search.description")
        static let archived = tr("search.archived")
    }

    // MARK: - AI Provider

    enum Provider {
        static let costIncluded = tr("provider.cost_included")
        static let costPerFile = tr("provider.cost_per_file")
        static let freeTier = tr("provider.free_tier")
        static let free = tr("provider.free")
        static let subscription = tr("provider.subscription")
        static func activeLabel(_ name: String) -> String { tr("provider.active_label", name) }
        static let active = tr("provider.active")
        static let activate = tr("provider.activate")
        static func switchTo(_ name: String) -> String { tr("provider.switch_to", name) }
    }

    // MARK: - Dashboard

    enum Dashboard {
        static func totalFiles(_ count: Int) -> String { tr("dashboard.total_files", count) }
        static func urgentFolders(_ count: Int) -> String { tr("dashboard.urgent_folders", count) }
        static let view = tr("dashboard.view")
        static let manualTools = tr("dashboard.manual_tools")
        static let manualToolsDesc = tr("dashboard.manual_tools_desc")
        static let folderManage = tr("dashboard.folder_manage")
        static let folderManageDesc = tr("dashboard.folder_manage_desc")
        static let searchTitle = tr("dashboard.search")
        static let searchDesc = tr("dashboard.search_desc")
        static let aiManage = tr("dashboard.ai_manage")
        static let aiManageDesc = tr("dashboard.ai_manage_desc")
        static let vaultInspect = tr("dashboard.vault_inspect")
        static let vaultInspectDesc = tr("dashboard.vault_inspect_desc")
        static let aiStats = tr("dashboard.ai_stats")
        static let aiStatsDesc = tr("dashboard.ai_stats_desc")
        static let recentActivity = tr("dashboard.recent_activity")
        static let noActivity = tr("dashboard.no_activity")
        // Action labels
        static let classified = tr("dashboard.action.classified")
        static let reorganized = tr("dashboard.action.reorganized")
        static let relocated = tr("dashboard.action.relocated")
        static let vaultReorganized = tr("dashboard.action.vault_reorganized")
        static let deduplicated = tr("dashboard.action.deduplicated")
        static let deleted = tr("dashboard.action.deleted")
        static let started = tr("dashboard.action.started")
        static let completed = tr("dashboard.action.completed")
        static let error = tr("dashboard.action.error")
        // Category labels
        static let catProject = tr("dashboard.category.project")
        static let catArea = tr("dashboard.category.area")
        static let catResource = tr("dashboard.category.resource")
        static let catArchive = tr("dashboard.category.archive")
        static let catSystem = tr("dashboard.category.system")
    }

    // MARK: - Inbox

    enum Inbox {
        static let empty = tr("inbox.empty")
        static let dragHint = tr("inbox.drag_hint")
        static let selectFiles = tr("inbox.select_files")
        static let dropToAdd = tr("inbox.drop_to_add")
        static func moreFiles(_ count: Int) -> String { tr("inbox.more_files", count) }
        static func estimatedTime(_ seconds: Int) -> String { tr("inbox.estimated_time", seconds) }
        static let addLabel = tr("inbox.add_label")
        static let clearLabel = tr("inbox.clear_label")
        static let clearTitle = tr("inbox.clear_title")
        static let clearButton = tr("inbox.clear_button")
        static let cancelButton = tr("inbox.cancel_button")
        static func clearMessage(_ count: Int) -> String { tr("inbox.clear_message", count) }
        static let organize = tr("inbox.organize")
        static let setApiKey = tr("inbox.set_api_key")
        static let pickVaultTitle = tr("inbox.pick_vault_title")
        static func addedCount(_ count: Int) -> String { tr("inbox.added_count", count) }
        static func skippedCode(_ count: Int) -> String { tr("inbox.skipped_code", count) }
        static func failedCount(_ count: Int) -> String { tr("inbox.failed_count", count) }
        static let noAddableFiles = tr("inbox.no_addable_files")
        static func clearFailed(_ count: Int) -> String { tr("inbox.clear_failed", count) }
        static let clearSuccess = tr("inbox.clear_success")
        static let pickFilesTitle = tr("inbox.pick_files_title")
    }

    // MARK: - Results

    enum Results {
        static let title = tr("results.title")
        static let goBack = tr("results.go_back")
        static let openInFinder = tr("results.open_in_finder")
        static let noFiles = tr("results.no_files")
        static func confirmWaiting(_ count: Int) -> String { tr("results.confirm_waiting", count) }
        static let skipAll = tr("results.skip_all")
        static func movedTo(_ target: String) -> String { tr("results.moved_to", target) }
        static let deletedLabel = tr("results.deleted")
        static let errorOccurred = tr("results.error_occurred")
        static func filesOrganized(_ count: Int) -> String { tr("results.files_organized", count) }
        static func relocatedCount(_ count: Int) -> String { tr("results.relocated_count", count) }
        static func skippedCount(_ count: Int) -> String { tr("results.skipped_count", count) }
        static func errorCount(_ count: Int) -> String { tr("results.error_count", count) }
        static func waitingCount(_ count: Int) -> String { tr("results.waiting_count", count) }
        static let autoTagged = tr("results.auto_tagged")
        static let nextSteps = tr("results.next_steps")
        static let analyzingFolders = tr("results.analyzing_folders")
        static let allFoldersGood = tr("results.all_folders_good")
        static let cleanAll = tr("results.clean_all")
        static func tooManyFiles(_ count: Int) -> String { tr("results.too_many_files", count) }
        static func missingFrontmatter(_ count: Int) -> String { tr("results.missing_frontmatter", count) }
        static let lowTagDiversity = tr("results.low_tag_diversity")
        static let cleanUp = tr("results.clean_up")
        // Confirmation
        static let unmatchedProjectHint = tr("results.unmatched_project_hint")
        static let unmatchedProjectGeneric = tr("results.unmatched_project_generic")
        static let nameConflictHint = tr("results.name_conflict_hint")
        static let misclassifiedHint = tr("results.misclassified_hint")
        static let lowConfidenceHint = tr("results.low_confidence_hint")
        static let projectName = tr("results.project_name")
        static let create = tr("results.create")
        static let createProject = tr("results.create_project")
        static let skip = tr("results.skip")
        static let delete = tr("results.delete")
    }

    // MARK: - Settings

    enum Settings {
        static let aiSettings = tr("settings.ai_settings")
        static let changeApiKey = tr("settings.change_api_key")
        static let deleteKey = tr("settings.delete_key")
        static let keyDeleted = tr("settings.key_deleted")
        static let keySaved = tr("settings.key_saved")
        static let keySaveFailed = tr("settings.key_save_failed")
        static func keyFormatNeeded(_ prefix: String) -> String { tr("settings.key_format_needed", prefix) }
        static let cliInstalled = tr("settings.cli_installed")
        static let cliPipeMode = tr("settings.cli_pipe_mode")
        static let cliNotFound = tr("settings.cli_not_found")
        static let cliInstallHint = tr("settings.cli_install_hint")
        static let save = tr("settings.save")
        static let cancel = tr("settings.cancel")
        static let pkmFolder = tr("settings.pkm_folder")
        static let paraConfirmed = tr("settings.para_confirmed")
        static let paraNotFound = tr("settings.para_not_found")
        static let change = tr("settings.change")
        static let createStructure = tr("settings.create_structure")
        static let fullDiskAccess = tr("settings.full_disk_access")
        static let granted = tr("settings.granted")
        static let needed = tr("settings.needed")
        static let fdaDescription = tr("settings.fda_description")
        static let openSystemSettings = tr("settings.open_system_settings")
        static let appInfo = tr("settings.app_info")
        static let latest = tr("settings.latest")
        static let checkingUpdate = tr("settings.checking_update")
        static let checkUpdate = tr("settings.check_update")
        static func updateAvailable(_ version: String) -> String { tr("settings.update_available", version) }
        static let cantReadRelease = tr("settings.cant_read_release")
        static func checkFailed(_ error: String) -> String { tr("settings.check_failed", error) }
        static let invalidVersion = tr("settings.invalid_version")
        static func updateFailed(_ error: String) -> String { tr("settings.update_failed", error) }
        static let unknown = tr("settings.unknown")
        static let onboarding = tr("settings.onboarding")
        static let restartOnboarding = tr("settings.restart_onboarding")
        static let help = tr("settings.help")
        static let quit = tr("settings.quit")
        // Help popover
        static let helpTitle = tr("settings.help_title")
        static let helpStep1 = tr("settings.help_step1")
        static let helpStep2 = tr("settings.help_step2")
        static let helpStep3 = tr("settings.help_step3")
        static let helpStep4 = tr("settings.help_step4")
        static let paraStructure = tr("settings.para_structure")
        static let paraProject = tr("settings.para_project")
        static let paraArea = tr("settings.para_area")
        static let paraResource = tr("settings.para_resource")
        static let paraArchive = tr("settings.para_archive")
        static let bugReport = tr("settings.bug_report")
        static let recheckCli = tr("settings.recheck_cli")
        static let pickVaultTitle = tr("settings.pick_vault_title")
    }

    // MARK: - AI Statistics

    enum AIStats {
        static let estimatedCost = tr("aistats.estimated_cost")
        static let costByOperation = tr("aistats.cost_by_operation")
        static let recentCalls = tr("aistats.recent_calls")
        static let noUsage = tr("aistats.no_usage")
        static let noUsageHint = tr("aistats.no_usage_hint")
        // Operation labels
        static let opClassify = tr("aistats.op.classify")
        static let opClassifyStage1 = tr("aistats.op.classify_stage1")
        static let opClassifyStage2 = tr("aistats.op.classify_stage2")
        static let opEnrich = tr("aistats.op.enrich")
        static let opMoc = tr("aistats.op.moc")
        static let opSemanticLink = tr("aistats.op.semantic_link")
        static let opSummary = tr("aistats.op.summary")
    }

    // MARK: - MenuBar

    enum MenuBar {
        static let taskConflict = tr("menubar.task_conflict")
        static let confirm = tr("menubar.confirm")
        static let fdaBanner = tr("menubar.fda_banner")
        static let fdaButton = tr("menubar.fda_button")
        static let fdaAutoRestart = tr("menubar.fda_auto_restart")
    }

    // MARK: - PARA Manage

    enum PARAManage {
        static let scanning = tr("para_manage.scanning")
        static let noFolders = tr("para_manage.no_folders")
        static let createHint = tr("para_manage.create_hint")
        static let folderName = tr("para_manage.folder_name")
        static let deleteFolder = tr("para_manage.delete_folder")
        static let deleteButton = tr("para_manage.delete_button")
        static func deleteMessage(_ name: String) -> String { tr("para_manage.delete_message", name) }
        static let renameTitle = tr("para_manage.rename_title")
        static let newName = tr("para_manage.new_name")
        static let renameButton = tr("para_manage.rename_button")
        static func renameMessage(_ name: String) -> String { tr("para_manage.rename_message", name) }
        static func moveTo(_ target: String) -> String { tr("para_manage.move_to", target) }
        static let completeProject = tr("para_manage.complete_project")
        static let reactivate = tr("para_manage.reactivate")
        static let autoReorganize = tr("para_manage.auto_reorganize")
        static let mergeInto = tr("para_manage.merge_into")
        static let rename = tr("para_manage.rename")
        static let openInFinder = tr("para_manage.open_in_finder")
        static let invalidName = tr("para_manage.invalid_name")
        static func alreadyExists(_ name: String) -> String { tr("para_manage.already_exists", name) }
        static func folderCreated(_ name: String) -> String { tr("para_manage.folder_created", name) }
        static func moveResult(_ name: String, _ target: String, _ count: Int) -> String { tr("para_manage.move_result", name, target, count) }
        static func completeResult(_ name: String, _ count: Int) -> String { tr("para_manage.complete_result", name, count) }
        static func reactivateResult(_ name: String, _ count: Int) -> String { tr("para_manage.reactivate_result", name, count) }
        static func renameResult(_ old: String, _ new: String, _ count: Int) -> String { tr("para_manage.rename_result", old, new, count) }
        static func deleteResult(_ name: String) -> String { tr("para_manage.delete_result", name) }
        static func mergeResult(_ source: String, _ target: String, _ count: Int) -> String { tr("para_manage.merge_result", source, target, count) }
    }

    // MARK: - Folder Relations

    enum FolderRelation {
        static let description = tr("folder_relation.description")
        static let loading = tr("folder_relation.loading")
        static let allReviewed = tr("folder_relation.all_reviewed")
        static let goBack = tr("folder_relation.go_back")
        static func reviewComplete(_ count: Int) -> String { tr("folder_relation.review_complete", count) }
        static let existingLink = tr("folder_relation.existing_link")
        static let newSuggestion = tr("folder_relation.new_suggestion")
        static func noteCount(_ para: String, _ count: Int) -> String { tr("folder_relation.note_count", para, count) }
    }

    // MARK: - Common

    enum Common {
        static let cancel = tr("common.cancel")
    }
}
