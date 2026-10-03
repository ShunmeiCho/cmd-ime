import AppKit
import Combine
import Foundation
import KeyboardSwitcherCore

enum BoardNotice: Equatable {
    case rejected(String)
    /// Something the app tried to do did not work; the text is what went wrong.
    case failed(String)
    case removed(slotName: String)
    case found(sourceID: String, name: String)
}

/// What the Apps page says about the last App Rule edit, under its board; VoiceOver hears it too.
/// Kept apart from `BoardNotice` so a rule that could not be saved is reported where it was
/// edited, not later on the Slots page.
enum AppRuleNotice: Equatable {
    case done(String)
    case refused(String)
    case failed(String)

    var text: String {
        switch self {
        case .done(let text), .refused(let text), .failed(let text): text
        }
    }
}

/// The outcome of the last Export or Import on the General page, shown under its buttons.
enum SettingsTransferMessage: Equatable {
    case done(String)
    case failed(String)
}

/// The Export or Import under way on the General page. Its file work runs off the main
/// thread, where the event tap runs, and a second one waits until it ends.
enum SettingsTransferActivity: Equatable {
    case exporting
    case checking
    case importing

    var text: String {
        switch self {
        case .exporting: String(localized: "Exporting settings…")
        case .checking: String(localized: "Reading the folder…")
        case .importing: String(localized: "Importing settings…")
        }
    }
}

/// Why a save is refused while an import writes config.json off the main thread.
private struct SettingsImportInProgress: LocalizedError {
    var errorDescription: String? { String(localized: "Settings are being imported. Try again when the import has finished.") }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var config: SwitcherConfig
    @Published var sources: [InputSourceInfo] = []
    @Published var statusText = String(localized: "Ready")
    @Published var isListening = false
    private var autoSpaceActivationObserver: NSObjectProtocol?
    @Published var activeRole: InputRole?
    let triggeredSwitches = SetupTriggerEvents()
    // Keep machine/report state in English; only the presentation is localized.
    @Published private var keyboardControlState = "Starting"
    var isKeyboardControlPaused: Bool { keyboardControlState == "Paused" }

    var keyboardControlStatus: String {
        switch keyboardControlState {
        case "Starting": String(localized: "Starting")
        case "Needs permission": String(localized: "Needs permission")
        case "Paused": String(localized: "Paused")
        case "Active": String(localized: "Active")
        case "Failed": String(localized: "Failed")
        default: keyboardControlState
        }
    }

    @Published var permissions = MacPermissionStatus.current()
    @Published var loginItem = LoginItemService().snapshot()
    @Published var updateStatus: UpdateStatus
    @Published private(set) var slotNotices: [InputRole: String] = [:]

    @Published private(set) var boardNotice: BoardNotice?
    @Published private(set) var appRuleNotice: AppRuleNotice?
    @Published private(set) var canUndoRemoval = false
    @Published private(set) var newSourceIDs: Set<String> = []
    /// Non-nil while an update is being installed; the text is shown as is.
    @Published private(set) var updateInstallStage: String?
    @Published private(set) var updateInstallError: String?
    @Published private(set) var notificationPermission = NotificationPermission.unknown
    /// macOS's own "Automatically switch to a document's input source", which fights App Memory.
    @Published private(set) var isSystemPerDocumentSwitchingOn = false
    /// What App Memory holds right now, app id to source id; empty while it is not running.
    @Published private(set) var rememberedSources: [String: String] = [:]
    @Published private(set) var settingsTransferMessage: SettingsTransferMessage?
    @Published private(set) var settingsTransferActivity: SettingsTransferActivity?
    /// config.json changed while an import was writing; read it again once the import ends.
    private var isReloadHeldBackByImport = false
    /// A quit arrived during an import and was cancelled; the import's end quits again.
    private var isQuitWaitingForImport = false
    /// That quit was a relaunch; the reopen helper starts when the import ends.
    private var isReopenWaitingForImport = false
    /// Light, dark or system, for the settings window only; the switch indicator keeps following its theme.
    @Published var appearance = AppearancePreference.stored {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppearancePreference.defaultsKey)
            for window in NSApp.windows where window.frameAutosaveName == "CmdIMESettings" {
                window.appearance = appearance.nsAppearance
            }
        }
    }
    /// The settings window language. Bundle lookups are fixed per process, so a change shows only
    /// after a relaunch; `launchedInterfaceLanguage` is what this process still shows.
    @Published var interfaceLanguage = InterfaceLanguage.stored {
        didSet { interfaceLanguage.store() }
    }
    let launchedInterfaceLanguage = InterfaceLanguage.stored
    private var updateReminderTimer: Timer?
    @Published private(set) var sourceRefreshMessage: String?
    private var selectedSourceObserver: InputSourceChangeObserver?
    private var sourceChangeObserver: InputSourceChangeObserver?
    private var configWatcher: ConfigFileWatcher?
    private var settingsWindowSubscriptions: Set<AnyCancellable> = []
    private var hasSourceBaseline = false
    private var sourceRefreshGeneration = 0
    private var refreshMessageTask: Task<Void, Never>?

    private var pendingUndo: RemovedSlot? {
        didSet { canUndoRemoval = pendingUndo != nil }
    }

    private let configStore: ConfigStore
    /// Capture first-run detection once; later saves must not make this an upgrade.
    let isFreshConfig: Bool
    private let inputSources = MacInputSourceService()
    private let loginItems = LoginItemService()
    private(set) lazy var switchIndicator = InputIndicatorController(configStore: configStore)
    private let updates = UpdateService()
    private var monitor: EventTapMonitor?
    private lazy var appMemory = AppMemoryController(
        inputSources: inputSources,
        monitor: { [weak self] in self?.monitor },
        sources: { [weak self] in self?.sources ?? [] },
        slotForSourceID: { [weak self] id in
            guard let self else { return nil }
            return InputSourceMatcher.slotID(forSelectedSourceID: id, sources: self.sources, config: self.config)
        },
        sourceForSlot: { [weak self] slot in self?.matchedSource(for: slot) }
    )
    private(set) lazy var indicatorOccasions = IndicatorOccasionController(
        inputSources: inputSources,
        config: { [weak self] in self?.config ?? .default },
        isOwnSwitchPending: { [weak self] in self?.isOwnSwitchPending ?? false },
        present: { [weak self] source in self?.showExternalChangeIndicator(source: source) }
    )
    /// Set while the Settings Switch button's selection is in flight, like the monitor's own
    /// pending flag: source changes seen meanwhile are its steps, not someone else's.
    private var settingsSwitchDeadline: Date?
    /// The user's recipes from `ActivationRecipeStore`, also used by the Switch button.
    private var activationRecipes: [ActivationRecipe] = []
    private var recordingRole: InputRole?
    private var recordingOwner: UUID?

    var isRecordingTrigger: Bool { recordingRole != nil }

    func setShortcutRecording(_ recording: Bool, for role: InputRole, owner: UUID) {
        if recording {
            recordingRole = role
            recordingOwner = owner
            clearSlotNotice(for: role)
        } else if recordingRole == role, recordingOwner == owner {
            recordingRole = nil
            recordingOwner = nil
        }
        monitor?.isCapturingShortcut = recordingRole != nil
    }

    func clearSlotNotice(for role: InputRole) {
        if slotNotices[role] != nil {
            slotNotices[role] = nil
        }
    }

    private func reportSlotFailure(_ message: String, for role: InputRole) {
        statusText = message
        slotNotices[role] = message
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore

        var initialConfig: SwitcherConfig
        var isFirstRun = false
        var recoveryMessage: String?
        do {
            let result = try configStore.loadOrRecover()
            initialConfig = result.config
            isFirstRun = result.isFirstRun
            if let backupURL = result.recoveredBackupURL {
                recoveryMessage = String(localized: "Config was unreadable; backed it up to \(backupURL.lastPathComponent) and reset to defaults.")
            } else if result.config.unreadableBindingCount > 0 {
                // A config written by a newer CmdIME, or a binding for an action since removed
                // (pinyin recovery, after 0.8.3). Everything else was kept, but the user has to
                // hear that a shortcut of theirs is not going to fire.
                let count = result.config.unreadableBindingCount
                recoveryMessage = count == 1
                    ? String(localized: "1 shortcut in your config uses an action this version does not have (from a newer CmdIME, or since removed) and is not active. Everything else was kept.")
                    : String(localized: "\(count) shortcuts in your config use actions this version does not have (from a newer CmdIME, or since removed) and are not active. Everything else was kept.")
            }
        } catch {
            // A config file exists but could not be moved aside: not a first run.
            initialConfig = SwitcherConfig.default.completingSetup()
            recoveryMessage = String(localized: "Could not read config: \(error.localizedDescription). Using defaults.")
        }

        self.isFreshConfig = isFirstRun
        self.config = initialConfig
        self.updateStatus = .idle(currentVersion: Self.currentVersion)
        let scanSucceeded = scan()
        if isFirstRun {
            if scanSucceeded {
                config = SwitcherConfig.detected(from: sources)
                do {
                    try configStore.save(config)
                } catch {
                    recoveryMessage = String(localized: "Could not save detected slots: \(error.localizedDescription)")
                }
            } else {
                recoveryMessage = statusText
            }
        }
        observeInputSourceChanges()
        configWatcher = ConfigFileWatcher(fileURL: configStore.url) { [weak self] in
            self?.reloadConfigFromDisk()
        }
        refreshRuntimeStatus()
        startListeningIfReady()
        syncSystemInputIndicator()
        if let recoveryMessage {
            statusText = recoveryMessage
        }
    }

    /// Picks up config.json edits made outside the app (`keyboardctl`, an editor, an import).
    /// The app's own saves read back as unchanged and do nothing.
    func reloadConfigFromDisk() {
        // An import writes config.json before its themes, fonts and recipes and makes them
        // live together when it ends; reading now would apply half of it.
        guard settingsTransferActivity != .importing else {
            isReloadHeldBackByImport = true
            return
        }
        switch ConfigReload.decide(fileData: try? Data(contentsOf: configStore.url), applied: config) {
        case .unchanged:
            return
        case let .unreadable(reason):
            // Kept as is: a later save here copies the file aside before replacing it.
            statusText = String(localized: "config.json changed but could not be read (\(reason)). Keeping the current settings.")
        case let .apply(next):
            applyConfigFromDisk(next)
            statusText = String(localized: "Applied the changes made to config.json")
        }
    }

    /// Makes settings that are already on disk the live ones, without saving them again.
    /// Themes, fonts and recipes are read again too: `keyboardctl import` writes them
    /// together with the config.
    private func applyConfigFromDisk(_ next: SwitcherConfig) {
        // The removed slot a pending Undo would restore may no longer fit the new slots.
        invalidateUndo()
        config = next
        reconcileNewSources()
        monitor?.updateConfig(next)
        refreshCurrentRole()
        refreshAppMemory()
        indicatorOccasions.update()
        syncSystemInputIndicator()
        indicatorLibrary.reloadThemes()
        indicatorLibrary.reloadFonts()
        loadActivationRecipes()
    }

    /// Where Export Settings suggests saving: a folder name that does not exist yet.
    var suggestedExportName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return String(localized: "CmdIME Settings \(formatter.string(from: Date()))")
    }

    /// Does nothing while another Export or Import runs.
    func exportSettings(to destination: URL) async {
        guard settingsTransferActivity == nil else { return }
        settingsTransferActivity = .exporting
        defer { settingsTransferActivity = nil }
        let transfer = SettingsTransfer(store: configStore)
        do {
            let plan = try await Self.runSettingsFileWork { try transfer.export(to: destination) }
            statusText = String(localized: "Exported settings with \(plan.themeFileNames.count) theme(s) and \(plan.fontFileNames.count) font(s) to \(destination.lastPathComponent)")
            settingsTransferMessage = .done(statusText)
        } catch {
            reportSettingsTransferFailure(error)
        }
    }

    /// What the folder would import, for the confirmation; nil (with the reason shown) when it is
    /// refused, and nil while another Export or Import runs.
    func inspectSettingsImport(_ folder: URL) async -> SettingsImportPlan? {
        guard settingsTransferActivity == nil else { return nil }
        settingsTransferActivity = .checking
        defer { settingsTransferActivity = nil }
        let transfer = SettingsTransfer(store: configStore)
        do {
            return try await Self.runSettingsFileWork { try transfer.inspect(folder) }
        } catch {
            reportSettingsTransferFailure(error)
            return nil
        }
    }

    /// Quitting mid-import would leave the settings partly imported, so every quit that reaches
    /// AppKit (Quit CmdIME, the Dock menu, the restart after Update Now or Relaunch, logout) waits for
    /// the import to end. `keyboardctl quit` force-terminates and is not covered.
    /// Relaunch CmdIME (also the restart after Update Now). During an import the quit waits for it,
    /// possibly longer than the reopen helper waits, so the helper starts only once the import ends.
    /// False when there is no bundle to reopen or the helper could not start.
    func relaunch() -> Bool {
        guard AppRelauncher.canRelaunch else { return false }
        if settingsTransferActivity == .importing {
            isReopenWaitingForImport = true
        } else if !AppRelauncher.scheduleReopenAfterExit() {
            return false
        }
        quit()
        return true
    }

    /// The import a quit waited for has ended. A relaunch starts its reopen helper only now (it waits
    /// a bounded time for this process to exit); if the helper cannot start, CmdIME keeps running
    /// rather than quit with nothing to reopen it.
    private func finishQuitHeldByImport() {
        isQuitWaitingForImport = false
        if isReopenWaitingForImport {
            isReopenWaitingForImport = false
            guard AppRelauncher.scheduleReopenAfterExit() else {
                startListening() // quit() stopped it
                updateInstallStage = nil
                boardNotice = .failed(String(localized: "Relaunch is not available. Quit CmdIME and open it again."))
                return
            }
        }
        NSApp.terminate(nil)
    }

    func shouldDelayQuitForImport() -> Bool {
        guard settingsTransferActivity == .importing else { return false }
        isQuitWaitingForImport = true
        statusText = String(localized: "CmdIME quits when the import has finished")
        return true
    }

    /// Checks the folder first; nothing changes when it is refused. Does nothing while another
    /// Export or Import runs. Saves and config.json reloads wait for it (see `refuseSaveDuringImport`).
    func importSettings(from folder: URL) async {
        guard settingsTransferActivity == nil else { return }
        settingsTransferActivity = .importing
        indicatorLibrary.isImportRunning = true
        defer {
            settingsTransferActivity = nil
            indicatorLibrary.isImportRunning = false
            if isReloadHeldBackByImport {
                isReloadHeldBackByImport = false
                // Unchanged after a finished import; after one that stopped partway, or an
                // edit made meanwhile by someone else, whatever is on disk now.
                reloadConfigFromDisk()
            }
            if isQuitWaitingForImport { finishQuitHeldByImport() }
        }
        let transfer = SettingsTransfer(store: configStore)
        do {
            let result = try await Self.runSettingsFileWork { try transfer.importSettings(from: folder) }
            applyConfigFromDisk(result.config)
            var message = String(localized: "Imported settings from \(folder.lastPathComponent).")
            if let backup = result.backupURL {
                message += String(localized: " The previous ones are in \(backup.deletingLastPathComponent().lastPathComponent)/\(backup.lastPathComponent).")
            }
            if result.plan.config.unreadableBindingCount > 0 {
                message += String(localized: " \(result.plan.config.unreadableBindingCount) trigger(s) use an action this version does not have and were left out.")
            }
            statusText = message
            settingsTransferMessage = .done(message)
        } catch {
            reportSettingsTransferFailure(error)
        }
    }

    /// The `keyboardctl diagnose` text with the app's versions, listener state and
    /// permissions on top, put on the clipboard for an issue report. Nothing typed is in it.
    func copyDiagnostics() {
        refreshRuntimeStatus()
        let summary = DiagnosisReport.appSummary(
            appVersion: Self.currentVersion,
            build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersion,
            keyboardControl: keyboardControlState,
            accessibilityGranted: permissions.accessibilityGranted,
            inputMonitoringGranted: permissions.inputMonitoringGranted
        )
        let report = DiagnosisReport(
            current: try? inputSources.currentInputSource(),
            config: config,
            sources: sources,
            systemPerDocumentSwitching: isSystemPerDocumentSwitchingOn
        )
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(summary + "\n\n" + report.text, forType: .string)
        statusText = String(localized: "Copied diagnostics to the clipboard")
    }

    func revealSettingsBackups() {
        let backups = configStore.url.deletingLastPathComponent()
            .appendingPathComponent(SettingsTransfer.backupsFolderName, isDirectory: true)
        indicatorLibrary.revealInFinder(backups)
    }

    private func reportSettingsTransferFailure(_ error: any Error) {
        statusText = error.localizedDescription
        settingsTransferMessage = .failed(error.localizedDescription)
    }

    /// Export and import read and write whole folders (backups, themes, fonts), so they run off
    /// the main thread: the event tap runs on the main run loop, and a slow disk or a folder full
    /// of fonts must not hold up typing.
    private static func runSettingsFileWork<T: Sendable>(
        _ work: @escaping @Sendable () throws -> T
    ) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    /// While an import writes config.json off the main thread, a save could land between its
    /// writes and leave the file and the applied settings apart.
    private func refuseSaveDuringImport() throws {
        if settingsTransferActivity == .importing { throw SettingsImportInProgress() }
    }

    private func refreshCurrentRole() {
        let selected = try? inputSources.currentInputSource()
        activeRole = InputSourceMatcher.slotID(forSelectedSourceID: selected?.id, sources: sources, config: config)
    }

    private func observeInputSourceChanges() {
        selectedSourceObserver = InputSourceChangeObserver(change: .selectedSourceChanged) { [weak self] in
            // Before the role refresh, so the bubble's switcher slides from the slot it left.
            self?.indicatorOccasions.sourceDidChange()
            self?.refreshCurrentRole()
            self?.appMemory.sourceDidChange()
        }
        refreshCurrentRole()
        indicatorOccasions.update()
        sourceChangeObserver = InputSourceChangeObserver { [weak self] in
            Task { await self?.refreshSources() }
        }
        // The coordinator names its retained settings window "CmdIME". Observe
        // here so switching settings pages cannot unmount the window lifecycle subscription.
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.willCloseNotification] {
            NotificationCenter.default.publisher(for: name)
                .sink { [weak self] notification in
                    MainActor.assumeIsolated {
                        guard let self, let window = notification.object as? NSWindow,
                              window.title == "CmdIME" else { return }
                        if notification.name == NSWindow.didBecomeKeyNotification {
                            Task { await self.refreshSources() }
                        } else {
                            self.clearNewSourceMarkers()
                        }
                    }
                }
                .store(in: &settingsWindowSubscriptions)
        }
    }

    /// In-process scan. A long-running process can keep seeing sources the user
    /// already removed, so everything after launch goes through `refreshSources`.
    @discardableResult
    func scan() -> Bool {
        do {
            apply(scanned: try inputSources.listInputSources())
            return true
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    private func apply(scanned: [InputSourceInfo], isFreshSnapshot: Bool = false) {
        let previous = sources
        sources = scanned
        if hasSourceBaseline {
            let discovered = InputSourceMatcher.newSelectableSources(previous: previous, current: scanned)
                .filter { sourceUsage(of: $0) == .available }
            newSourceIDs.formUnion(discovered.map(\.id))
            if let source = discovered.first {
                boardNotice = .found(sourceID: source.id, name: source.localizedName)
            }
        }
        hasSourceBaseline = true
        reconcileNewSources()
        if isFreshSnapshot {
            monitor?.updateConfig(config, sources: scanned)
        } else {
            monitor?.updateConfig(config)
        }
        refreshCurrentRole()
        statusText = String(localized: "Found \(sources.count) input sources")
        // Refresh is also when an edited recipes file is picked up.
        loadActivationRecipes()
    }

    private static let scannerURL = Bundle.main.executableURL?
        .deletingLastPathComponent()
        .appendingPathComponent("keyboardctl")

    /// Replaces the list with a snapshot taken by a fresh keyboardctl process.
    /// A newer request supersedes this one; a superseded request reports false.
    @discardableResult
    func refreshSources(announce: Bool = false) async -> Bool {
        sourceRefreshGeneration += 1
        let generation = sourceRefreshGeneration
        if announce {
            refreshMessageTask?.cancel()
            sourceRefreshMessage = nil
        }
        do {
            let result = try await inputSources.refreshedInputSources(using: Self.scannerURL)
            guard generation == sourceRefreshGeneration else { return false }
            apply(scanned: result.sources, isFreshSnapshot: result.fallbackReason == nil)
            guard announce else { return true }
            sourceRefreshMessage = result.fallbackReason == nil
                ? String(localized: "Updated - \(selectableSources.count) input sources")
                : String(localized: "Listed \(selectableSources.count) input sources; removed ones may linger until relaunch")
            refreshMessageTask = Task { [weak self] in
                do { try await Task.sleep(nanoseconds: 3_000_000_000) }
                catch { return }
                self?.sourceRefreshMessage = nil
            }
            return true
        } catch is CancellationError {
            return false
        } catch {
            guard generation == sourceRefreshGeneration else { return false }
            statusText = error.localizedDescription
            if announce { reportBoardFailure(statusText) }
            return false
        }
    }

    /// Wire to the settings window closing, not activation or key-window changes.
    func clearNewSourceMarkers() {
        newSourceIDs.removeAll()
        refreshMessageTask?.cancel()
        sourceRefreshMessage = nil
        if case .found = boardNotice { restoreUndoNotice() }
    }

    private func reconcileNewSources() {
        newSourceIDs.formIntersection(Set(selectableSources.filter { sourceUsage(of: $0) == .available }.map(\.id)))
        if case let .found(id, _) = boardNotice, !newSourceIDs.contains(id) {
            restoreUndoNotice()
        }
    }

    private func restoreUndoNotice() {
        boardNotice = pendingUndo.map { .removed(slotName: $0.slot.name) }
    }

    func refreshRuntimeStatus() {
        permissions = MacPermissionStatus.current()
        loginItem = loginItems.snapshot()
        isSystemPerDocumentSwitchingOn = SystemInputSourceSettings.isPerDocumentSwitchingOn()
        if !isListening, permissions.isReady, keyboardControlState == "Needs permission" {
            keyboardControlState = "Paused"
            statusText = String(localized: "Permissions ready. Click Resume to start keyboard control.")
        }
    }

    func requestPermissions() {
        MacPermissionStatus.request()
        refreshRuntimeStatus()
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
        statusText = String(localized: "Opened Accessibility settings")
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
        statusText = String(localized: "Opened Input Monitoring settings")
    }

    private func openPrivacySettings(anchor: String) {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?\(anchor)"
        ) else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    func startListeningIfReady() {
        refreshRuntimeStatus()
        guard permissions.isReady else {
            isListening = false
            keyboardControlState = "Needs permission"
            statusText = String(localized: "Grant permissions, then resume keyboard control")
            return
        }
        startListening()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItems.setEnabled(enabled)
            refreshRuntimeStatus()
            statusText = enabled ? String(localized: "Login item enabled") : String(localized: "Login item disabled")
        } catch {
            refreshRuntimeStatus()
            statusText = error.localizedDescription
            boardNotice = .failed(enabled
                ? String(localized: "Could not enable the login item. \(error.localizedDescription)")
                : String(localized: "Could not disable the login item. \(error.localizedDescription)"))
        }
    }

    private lazy var updateCard = UpdateCardController(model: self)

    private static let systemBadgeHiddenByCmdIMEKey = "systemInputBadgeHiddenByCmdIME"
    /// Set by Quit CmdIME on the General page; applied once the quit really goes through.
    private var restoresSystemBadgeOnExit = false

    /// The process is exiting (AppDelegate.applicationWillTerminate).
    func willTerminate() {
        if restoresSystemBadgeOnExit { syncSystemInputIndicator(bubbleOn: false) }
    }

    /// The only system-wide preference CmdIME writes: macOS's own input source badge (macOS 14+)
    /// stays hidden while the switch indicator is on and comes back when it goes off. A flag in the
    /// app's defaults records that CmdIME hid it, so a badge the user hid by hand is never restored.
    func syncSystemInputIndicator(bubbleOn: Bool? = nil, reportsFailure: Bool = false) {
        guard #available(macOS 14, *) else { return }
        let defaults = UserDefaults.standard
        let isHidden = SystemInputIndicator.isHidden()
        if !isHidden { defaults.removeObject(forKey: Self.systemBadgeHiddenByCmdIMEKey) }
        let action = SystemInputIndicator.sync(
            bubbleOn: bubbleOn ?? config.showSwitchIndicator,
            isHidden: isHidden,
            hiddenByCmdIME: defaults.bool(forKey: Self.systemBadgeHiddenByCmdIMEKey)
        )
        do {
            switch action {
            case .keep:
                return
            case .hide:
                try SystemInputIndicator.setHidden(true)
                defaults.set(true, forKey: Self.systemBadgeHiddenByCmdIMEKey)
            case .restore:
                try SystemInputIndicator.setHidden(false)
                defaults.removeObject(forKey: Self.systemBadgeHiddenByCmdIMEKey)
            }
        } catch {
            guard reportsFailure else { return }
            boardNotice = .failed(
                String(localized: "macOS kept its setting for the input source badge. A configuration profile or a per-host value may be setting it.")
            )
        }
    }

    /// macOS 13 asks the user to approve a login item in System Settings; the switch
    /// stays off until they do.
    var loginItemNeedsApproval: Bool {
        loginItem.isAvailable && !loginItem.isEnabled && loginItem.statusText == String(localized: "Needs approval")
    }

    func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
        statusText = String(localized: "Opened Login Items settings")
    }

    func setSwitchIndicatorVisible(_ visible: Bool) {
        var next = config
        next.showSwitchIndicator = visible
        guard commitShowingWindowFailure(next) else { return }
        indicatorOccasions.update()
        syncSystemInputIndicator(reportsFailure: true)
        statusText = visible ? String(localized: "Switch indicator enabled") : String(localized: "Switch indicator disabled")
    }

    func setCapsLockIndicatorVisible(_ visible: Bool) {
        var next = config
        next.showCapsLockIndicator = visible
        guard commitShowingWindowFailure(next) else { return }
        statusText = visible ? String(localized: "Caps Lock indicator enabled") : String(localized: "Caps Lock indicator disabled")
    }

    func setAutoSpaceBetweenChineseAndEnglish(_ enabled: Bool) {
        var next = config
        next.autoSpaceBetweenChineseAndEnglish = enabled
        guard commitShowingWindowFailure(next) else { return }
        statusText = enabled ? String(localized: "Space between Chinese and English turned on") : String(localized: "Space between Chinese and English turned off")
    }

    var peekTrigger: KeyTrigger? { config.peekBinding?.trigger }

    /// Nil on success, else the reason the trigger was refused.
    @discardableResult
    func commitPeekTrigger(_ trigger: KeyTrigger?) -> String? {
        do {
            let next = try config.replacingPeekBinding(with: trigger)
            if next != config {
                guard commitShowingWindowFailure(next) else { return statusText }
            }
            statusText = trigger.map { String(localized: "\(SwitcherConfig.peekDisplayName): \($0.localizedDisplayName)") }
                ?? String(localized: "Removed the \(SwitcherConfig.peekDisplayName) trigger")
            return nil
        } catch .conflictingBinding(let binding) {
            let reason = String(localized: "\(binding.trigger.localizedDisplayName) is already used by \(config.ownerDescription(of: binding))")
            statusText = reason
            return reason
        } catch {
            statusText = error.localizedDescription
            return error.localizedDescription
        }
    }

    /// Nil on success, else the reason the Toggle was refused. A nil trigger removes it.
    @discardableResult
    func commitToggle(_ trigger: KeyTrigger?, slots first: InputRole, _ second: InputRole) -> String? {
        do {
            let taken = trigger.flatMap { config.toggleTakeover(of: $0, slots: first, second) }
            let previous = config.toggleBinding
            let givenBack = previous?.trigger == trigger ? nil : config.toggleGiveBack(of: previous)
            let next = try config.replacingToggleBinding(with: trigger, slots: first, second)
            if next != config {
                guard commitShowingWindowFailure(next) else { return statusText }
            }
            if let trigger, let role = taken?.action.role {
                statusText = String(localized: "\(SwitcherConfig.toggleDisplayName): \(trigger.localizedDisplayName), moved from \(config.displayName(for: role))")
            } else if trigger == nil, let givenBack {
                statusText = String(localized: "Removed the \(SwitcherConfig.toggleDisplayName) trigger; \(givenBack.trigger.localizedDisplayName) is back on \(config.displayName(for: givenBack.slot))")
            } else {
                statusText = trigger.map { String(localized: "\(SwitcherConfig.toggleDisplayName): \($0.localizedDisplayName)") }
                    ?? String(localized: "Removed the \(SwitcherConfig.toggleDisplayName) trigger")
            }
            return nil
        } catch .conflictingBinding(let binding) {
            let reason = String(localized: "\(binding.trigger.localizedDisplayName) is already used by \(config.ownerDescription(of: binding))")
            statusText = reason
            return reason
        } catch {
            statusText = error.localizedDescription
            return error.localizedDescription
        }
    }

    func setRememberInputSourcePerApp(_ enabled: Bool) {
        var next = config
        next.rememberInputSourcePerApp = enabled
        guard commitShowingWindowFailure(next) else { return }
        statusText = enabled ? String(localized: "Remembering the input source per app") : String(localized: "No longer remembering input sources per app")
    }

    func setAppRule(_ rule: AppRule) {
        if commitFromAppsPage(config.setting(rule)) {
            reportAppRule(.done(rule.rememberInstead
                ? String(localized: "\(rule.name ?? rule.appID) remembers its input source")
                : String(localized: "Rule saved for \(rule.name ?? rule.appID)")))
        }
    }

    /// A drop on the Apps page's rule board: the rule decision is core `AppRuleBoard.drop`.
    func dropApp(appID: String, name: String?, on target: AppRuleTarget) {
        switch AppRuleBoard.drop(appID: appID, name: name, on: target, in: config, ownAppID: Bundle.main.bundleIdentifier) {
        case .unchanged:
            return
        case .refused(let reason):
            reportAppRule(.refused(reason))
        case .changed(let next):
            if commitFromAppsPage(next) {
                let appName = next.appRule(for: appID)?.name ?? appID
                switch target {
                case .keepAsIs: reportAppRule(.done(String(localized: "\(appName) keeps its input source")))
                case .slot(let id): reportAppRule(.done(String(localized: "\(appName) now gets \(config.displayName(for: id))")))
                }
            }
        }
    }

    /// A file dropped on the rule board that is not an app.
    func refuseNonAppDrop() {
        reportAppRule(.refused(String(localized: "Only apps can get a rule.")))
    }

    func removeAppRule(for appID: String) {
        let appName = config.appRule(for: appID)?.name ?? appID
        if commitFromAppsPage(config.removingAppRule(for: appID)) {
            reportAppRule(.done(String(localized: "Rule removed for \(appName)")))
        }
    }

    /// Adds a Website Rule (CONTEXT.md), or replaces the one for the same domain where it stands.
    func setWebsiteRule(_ rule: WebsiteRule) {
        if commitFromAppsPage(config.setting(rule)) {
            reportAppRule(.done(String(localized: "Rule saved for \(rule.domain)")))
        }
    }

    /// A website chip dropped on a lane of the rule board: the decision is core `AppRuleBoard.drop`.
    func dropWebsite(domain: String, on target: AppRuleTarget) {
        switch AppRuleBoard.drop(websiteDomain: domain, on: target, in: config) {
        case .unchanged:
            return
        case .refused(let reason):
            reportAppRule(.refused(reason))
        case .changed(let next):
            if commitFromAppsPage(next) {
                switch target {
                case .keepAsIs: reportAppRule(.done(String(localized: "\(domain) keeps its input source")))
                case .slot(let id): reportAppRule(.done(String(localized: "\(domain) now gets \(config.displayName(for: id))")))
                }
            }
        }
    }

    func removeWebsiteRule(for domain: String) {
        if commitFromAppsPage(config.removingWebsiteRule(for: domain)) {
            reportAppRule(.done(String(localized: "Rule removed for \(domain)")))
        }
    }

    /// A Program Rule added from the sheet, or moved to another lane from its chip.
    func setProgramRule(_ rule: ProgramRule) {
        guard commitFromAppsPage(config.setting(rule)) else { return }
        switch rule.target {
        case .keepAsIs: reportAppRule(.done(String(localized: "\(rule.name) keeps its input source")))
        case .slot(let id): reportAppRule(.done(String(localized: "\(rule.name) now gets \(config.displayName(for: id))")))
        }
    }

    func removeProgramRule(for name: String) {
        if commitFromAppsPage(config.removingProgramRule(for: name)) {
            reportAppRule(.done(String(localized: "Rule removed for \(name)")))
        }
    }

    /// The one switch that pauses every Program Rule and brings them back.
    func setProgramRulesPaused(_ paused: Bool) {
        if commitFromAppsPage(config.settingProgramRulesPaused(paused)) {
            statusText = paused ? String(localized: "Program rules are paused") : String(localized: "Program rules are on")
        }
    }

    func setAppDefaultSlot(_ slot: InputRole?) {
        var next = config
        next.appDefaultSlot = slot
        if commitFromAppsPage(next) {
            statusText = slot.map { String(localized: "Apps without a rule start in \(config.displayName(for: $0))") }
                ?? String(localized: "Apps without a rule keep their input source")
        }
    }

    /// Clears the Apps page notice; with `notice`, only while it is still the one shown, so an
    /// expired confirmation never clears a newer message.
    func dismissAppRuleNotice(_ notice: AppRuleNotice? = nil) {
        guard notice == nil || notice == appRuleNotice else { return }
        appRuleNotice = nil
    }

    private func reportAppRule(_ notice: AppRuleNotice) {
        statusText = notice.text
        appRuleNotice = notice
    }

    /// `commit` for edits made on the Apps page: a failed save is reported there.
    private func commitFromAppsPage(_ next: SwitcherConfig) -> Bool {
        commit(next) { [self] message in
            reportAppRule(.failed(String(localized: "Could not save the change. \(message)")))
        }
    }

    func setRestoreAfterPasswordField(_ enabled: Bool) {
        var next = config
        next.restoreAfterPasswordField = enabled
        if commit(next) {
            statusText = enabled ? String(localized: "Switching back after password fields") : String(localized: "No longer switching back after password fields")
        }
    }

    func forgetRememberedSource(for appID: String) {
        appMemory.forget(appID: appID)
    }

    func forgetAllRememberedSources() {
        appMemory.forgetAll()
    }

    /// Per-app switching follows apps only while one of its settings is on and the listener runs.
    private func refreshAppMemory() {
        appMemory.onMemoryChange = { [weak self] memory in self?.rememberedSources = memory }
        appMemory.update(settings: AppActivationSettings(config: config), isListening: monitor != nil)
    }

    func setSwitchIndicatorSizeFactor(_ factor: Double) {
        let clamped = SwitcherConfig.clampedSwitchIndicatorSizeFactor(factor)
        var next = config
        next.switchIndicatorSizeFactor = clamped
        guard commitShowingWindowFailure(next) else { return }
        statusText = String(localized: "Switch indicator size set to \(Int((clamped * 100).rounded()))%")
    }

    func setSwitchIndicatorColorStyle(_ style: SwitchIndicatorColorStyle) {
        var next = config
        next.switchIndicatorColorStyle = style
        guard commitShowingWindowFailure(next) else { return }
        statusText = String(localized: "Switch indicator color set to \(style.displayName)")
    }

    func setSwitchIndicatorContentStyle(_ style: SwitchIndicatorContentStyle) {
        var next = config
        next.switchIndicatorContentStyle = style
        guard commitShowingWindowFailure(next) else { return }
        statusText = String(localized: "Switch indicator display set to \(style.displayName)")
    }

    var previewSlot: SwitchSlot? {
        activeRole.flatMap { config.slot($0) } ?? config.slots.first
    }

    func checkForUpdates() {
        guard !updateStatus.isChecking else {
            return
        }

        let currentVersion = Self.currentVersion
        updateStatus = .checking(currentVersion: currentVersion)
        statusText = String(localized: "Checking for updates")

        Task {
            do {
                let result = try await updates.check(currentVersion: currentVersion)
                updateStatus = result.isUpdateAvailable
                    ? .available(result)
                    : .upToDate(result)
                statusText = updateStatus.message
            } catch {
                updateStatus = .failed(currentVersion: currentVersion, message: error.localizedDescription)
                statusText = error.localizedDescription
            }
        }
    }

    // MARK: - Update reminder

    private enum ReminderKey {
        static let enabled = "updateReminder.enabled"
        static let frequency = "updateReminder.frequency"
        static let notifies = "updateReminder.notifies"
        static let lastCheck = "updateReminder.lastCheck"
        static let lastNotified = "updateReminder.lastNotifiedVersion"
        static let skipped = "updateReminder.skippedVersion"
    }

    private var reminderState: UpdateReminderState {
        let defaults = UserDefaults.standard
        return UpdateReminderState(
            isEnabled: defaults.object(forKey: ReminderKey.enabled) as? Bool ?? true,
            frequency: defaults.string(forKey: ReminderKey.frequency).flatMap(UpdateCheckFrequency.init) ?? .sixHours,
            notifies: defaults.object(forKey: ReminderKey.notifies) as? Bool ?? true,
            lastCheck: defaults.object(forKey: ReminderKey.lastCheck) as? Date,
            lastNotifiedVersion: defaults.string(forKey: ReminderKey.lastNotified),
            skippedVersion: defaults.string(forKey: ReminderKey.skipped)
        )
    }

    var checksForUpdatesAutomatically: Bool {
        get { reminderState.isEnabled }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: ReminderKey.enabled)
            if newValue { runUpdateReminderIfDue() }
        }
    }

    var updateCheckFrequency: UpdateCheckFrequency {
        get { reminderState.frequency }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue.rawValue, forKey: ReminderKey.frequency)
            runUpdateReminderIfDue()
        }
    }

    var notifiesAboutUpdates: Bool {
        get { reminderState.notifies }
        set {
            objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: ReminderKey.notifies)
            // Turning it on is the user asking for notifications, so this is the moment to let macOS ask.
            guard newValue else {
                updateCard.close()
                return
            }
            Task { notificationPermission = await UpdateNotification.requestPermission() }
        }
    }

    func refreshNotificationPermission() {
        Task { notificationPermission = await UpdateNotification.permission() }
    }

    /// The app has no window most of the time, so it looks for a new release itself,
    /// as often as the user chose, and says so once per version through a system notification.
    func startUpdateReminder() {
        runUpdateReminderIfDue()
        updateReminderTimer = Timer.scheduledTimer(withTimeInterval: 60 * 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.runUpdateReminderIfDue() }
        }
    }

    private func runUpdateReminderIfDue() {
        guard UpdateReminderPolicy.shouldCheck(now: Date(), state: reminderState), !updateStatus.isChecking else { return }
        UserDefaults.standard.set(Date(), forKey: ReminderKey.lastCheck)
        let currentVersion = Self.currentVersion
        Task {
            // A failed background check stays quiet; the next one comes with the next interval.
            guard let result = try? await updates.check(currentVersion: currentVersion), result.isUpdateAvailable else { return }
            updateStatus = .available(result)
            guard UpdateReminderPolicy.shouldNotify(latest: result.latestVersion, current: currentVersion,
                                                    state: reminderState) else { return }
            // Once per version: the notification when macOS allows it, otherwise the card, which
            // shows the same as the settings window's update bar without taking focus.
            if !(await UpdateNotification.post(version: result.latestVersion, headline: result.notes.headline,
                                               releaseURL: result.releaseURL,
                                               isStillWanted: { [weak self] in self?.reminderState.notifies ?? false })) {
                // The permission prompt can sit for a while; the user may have turned this off meanwhile.
                guard reminderState.notifies else { return }
                updateCard.show()
            }
            UserDefaults.standard.set(result.latestVersion, forKey: ReminderKey.lastNotified)
        }
    }

    func skipAvailableUpdate() {
        guard case let .available(result) = updateStatus else { return }
        UserDefaults.standard.set(result.latestVersion, forKey: ReminderKey.skipped)
        updateStatus = .upToDate(result)
    }

    /// One-click update: download, verify, replace this bundle, reopen.
    #if DEBUG
    /// Device check of the update card (`--args -CmdIMEPreviewUpdateCard YES`): a made-up release,
    /// so the check works offline and under GitHub's rate limit. It waits 5 s so the check can put
    /// another app in front first and see that the card does not take focus. Do not press Update Now.
    func previewUpdateCard() {
        Task {
            try? await Task.sleep(for: .seconds(5))
            guard let url = URL(string: "https://github.com/ShunmeiCho/cmd-ime/releases") else { return }
            updateStatus = .available(UpdateCheckResult(
                currentVersion: Self.currentVersion, latestVersion: "9.9.9", releaseURL: url, isUpdateAvailable: true,
                notes: ReleaseNotesSummary(headline: "A preview of the update card with a made-up release.",
                                           items: ["Settings in Chinese and Japanese", "One bubble per switch"])
            ))
            updateCard.show()
        }
    }
    #endif

    /// The notification's Update Now. After a relaunch the found update is gone from memory, so
    /// look again; the settings window then shows the result with its own Update Now.
    func updateFromNotification() {
        if case .available = updateStatus { installAvailableUpdate() } else { checkForUpdates() }
    }

    func installAvailableUpdate() {
        guard case let .available(result) = updateStatus, updateInstallStage == nil else { return }
        updateInstallError = nil
        updateInstallStage = SelfUpdater.Stage.downloading.displayName
        Task {
            do {
                try await SelfUpdater.install(version: result.latestVersion) { [weak self] stage in
                    self?.updateInstallStage = stage.displayName
                }
                updateInstallStage = String(localized: "Restarting…")
                if !relaunch() {
                    updateInstallStage = nil
                    updateInstallError = String(localized: "Updated. Quit CmdIME and open it again to use the new version.")
                }
            } catch {
                updateInstallStage = nil
                updateInstallError = error.localizedDescription
            }
        }
    }

    func openLatestRelease() {
        guard let url = updateStatus.releaseURL else {
            checkForUpdates()
            return
        }
        NSWorkspace.shared.open(url)
        statusText = String(localized: "Opened CmdIME release page")
    }

    func resetSlotsFromDetectedSources() {
        // The window keeps `sources` fresh; an in-process rescan could bring removed ones back.
        guard hasSourceBaseline || scan() else { return }
        do {
            try refuseSaveDuringImport()
            let rebuilt = try configStore.resettingSlots(in: config, from: sources)
            invalidateUndo()
            config = rebuilt
            reconcileNewSources()
            refreshCurrentRole()
            monitor?.updateConfig(rebuilt)
            statusText = String(localized: "Rebuilt \(rebuilt.slots.count) slots from installed input sources")
        } catch {
            // Keep the live config and monitor untouched if backup or save fails.
            statusText = String(localized: "Could not rebuild slots: \(error.localizedDescription)")
        }
    }

    var selectableSources: [InputSourceInfo] {
        InputSourceMatcher.selectableSources(from: sources)
    }

    var unassignedSources: [InputSourceInfo] {
        config.unassignedSources(from: sources)
    }

    func sourceUsage(of source: InputSourceInfo) -> SlotSourceUsage {
        config.sourceUsage(of: source, among: sources)
    }

    @discardableResult
    func addSlot(sourceID: String, at index: Int?) -> InputRole? {
        guard let source = selectableSources.first(where: { $0.id == sourceID }) else {
            reportBoardFailure(SlotError.invalidSource.localizedDescription)
            return nil
        }
        switch sourceUsage(of: source) {
        case .available: break
        case let .owned(owner):
            reportBoardFailure(String(localized: "Already in slot \(config.displayName(for: owner))"))
            return nil
        case let .resolved(owner, _):
            reportBoardFailure(String(localized: "Fallback for \(config.displayName(for: owner))"))
            return nil
        }
        do {
            let added = try config.addingSlot(for: source, at: index)
            guard commit(added.config) else { return nil }
            invalidateUndo()
            boardNotice = nil
            statusText = String(localized: "Added slot \(added.slot.name)")
            return added.slot.id
        } catch {
            reportBoardFailure(error.localizedDescription)
            return nil
        }
    }

    func moveSlot(_ id: InputRole, toFinalIndex index: Int) {
        guard let source = config.slots.firstIndex(where: { $0.id == id }) else { return }
        commitMove(config.movingSlot(from: source, to: index), id: id)
    }

    func moveSlot(_ id: InputRole, by offset: Int) {
        commitMove(config.movingSlot(id, by: offset), id: id)
    }

    private func commitMove(_ next: SwitcherConfig, id: InputRole) {
        guard next.slots != config.slots, commit(next) else { return }
        invalidateUndo()
        boardNotice = nil
        statusText = String(localized: "Moved slot \(config.displayName(for: id))")
    }

    @discardableResult
    func renameSlot(_ id: InputRole, to name: String) -> Bool {
        do {
            let next = try config.renamingSlot(id, to: name)
            if next != config {
                guard commit(next) else { return false }
                invalidateUndo()
            }
            clearSlotNotice(for: id)
            statusText = String(localized: "Renamed slot to \(config.displayName(for: id))")
            return true
        } catch {
            reportSlotFailure(error.localizedDescription, for: id)
            return false
        }
    }

    func removeSlot(_ id: InputRole) {
        do {
            let result = try config.removingSlotWithReceipt(id)
            guard commit(result.config) else { return }
            invalidateUndo()
            pendingUndo = result.removed
            if activeRole == id { activeRole = nil }
            clearSlotNotice(for: id)
            boardNotice = .removed(slotName: result.removed.slot.name)
            statusText = String(localized: "Removed slot \(result.removed.slot.name). Undo available.")
        } catch {
            reportSlotFailure(error.localizedDescription, for: id)
        }
    }

    func undoRemoveSlot() {
        guard let removed = pendingUndo else { return }
        do {
            let restored = try config.restoringSlot(removed)
            guard commit(restored.config) else { return }
            invalidateUndo()
            boardNotice = nil
            statusText = String(localized: "Restored slot \(removed.slot.name)")
            if !restored.skippedBindings.isEmpty {
                let triggers = restored.skippedBindings.map { $0.binding.trigger.localizedDisplayName }.joined(separator: ", ")
                let message = String(localized: "Restored slot, but conflicting triggers were not restored: \(triggers)")
                reportSlotFailure(message, for: removed.slot.id)
                reportBoardFailure(message)
            }
        } catch {
            reportBoardFailure(error.localizedDescription)
        }
    }

    func dismissBoardNotice() {
        if case .removed = boardNotice { pendingUndo = nil }
        restoreUndoNotice()
    }

    private func invalidateUndo() {
        pendingUndo = nil
        if case .removed = boardNotice { boardNotice = nil }
    }

    func rejectSlotDrop(_ message: String) {
        reportBoardFailure(message)
    }

    private func reportBoardFailure(_ message: String) {
        statusText = message
        boardNotice = .rejected(message)
    }

    @discardableResult
    func setSlotTint(_ hex: String, for id: InputRole) -> Bool {
        do {
            let next = try config.settingSlotTint(hex, for: id)
            if next != config {
                guard commit(next, failureSlot: id) else { return false }
                invalidateUndo()
            }
            clearSlotNotice(for: id)
            statusText = String(localized: "Updated tint for \(config.displayName(for: id))")
            return true
        } catch {
            reportSlotFailure(error.localizedDescription, for: id)
            return false
        }
    }

    private func commit(_ next: SwitcherConfig, failureSlot: InputRole? = nil) -> Bool {
        commit(next) { [self] message in
            if let failureSlot {
                reportSlotFailure(message, for: failureSlot)
            } else {
                reportBoardFailure(message)
            }
        }
    }

    /// `commit` for controls outside the slot board: a failed save shows the window-wide notice,
    /// as `save()` does, since the board's own notice only appears on the Slots page.
    func commitShowingWindowFailure(_ next: SwitcherConfig) -> Bool {
        commit(next) { [self] message in
            statusText = message
            boardNotice = .failed(String(localized: "Could not save settings. \(message)"))
        }
    }

    /// Saves first and assigns `config` only on success, so a failed save changes nothing;
    /// `onFailure` gets the error text.
    private func commit(_ next: SwitcherConfig, onFailure: (String) -> Void) -> Bool {
        do {
            try refuseSaveDuringImport()
            try configStore.save(next)
            config = next
            reconcileNewSources()
            monitor?.updateConfig(next)
            refreshCurrentRole()
            refreshAppMemory()
            return true
        } catch {
            onFailure(error.localizedDescription)
            return false
        }
    }

    func setInputSourceID(_ id: String, for role: InputRole) {
        guard let source = selectableSources.first(where: { $0.id == id }) else {
            statusText = String(localized: "Input source not found: \(id)")
            return
        }

        do {
            let next = try config.selectingInputSource(source, for: role, sources: sources)
            if next != config { invalidateUndo() }
            if commitShowingWindowFailure(next) {
                clearSlotNotice(for: role)
                statusText = String(localized: "Switch slot set to \(source.localizedName)")
            }
        } catch {
            reportSlotFailure(error.localizedDescription, for: role)
        }
    }

    func inputSourceSelection(_ source: InputSourceInfo, for role: InputRole) -> SlotSourceSelection {
        config.inputSourceSelection(source, for: role, sources: sources)
    }

    func inputSourceMenuTitle(_ source: InputSourceInfo, for role: InputRole) -> String {
        switch inputSourceSelection(source, for: role) {
        case let .swap(other): String(localized: "\(source.localizedName) — swap with \(config.displayName(for: other))")
        case let .usedBy(other): String(localized: "\(source.localizedName) — used by \(config.displayName(for: other))")
        default: source.localizedName
        }
    }

    func dismissWhatsNew() {
        let previousVersion = config.lastSeenWhatsNewVersion
        config.lastSeenWhatsNewVersion = Self.currentVersion
        if !save() {
            config.lastSeenWhatsNewVersion = previousVersion
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            try refuseSaveDuringImport()
            try configStore.save(config)
            monitor?.updateConfig(config)
            refreshCurrentRole()
            refreshAppMemory()
            statusText = String(localized: "Saved \(configStore.url.path)")
            return true
        } catch {
            statusText = error.localizedDescription
            // Saving is what every control in the window ends in, so a failure has to be seen.
            boardNotice = .failed(String(localized: "Could not save settings. \(error.localizedDescription)"))
            return false
        }
    }

    func switchRole(_ role: InputRole) {
        if !hasSourceBaseline {
            scan()
        }
        guard let source = matchedSource(for: role) else {
            reportSlotFailure(String(localized: "No input source matched this slot"), for: role)
            return
        }
        settingsSwitchDeadline = Date(timeIntervalSinceNow: Self.settingsSwitchBudget)
        // Same Kana prelude as the event tap; the select is scheduled, never waited for here.
        SwitchActivationPolicy.selectWithKanaPrelude(
            target: source,
            current: { try? inputSources.currentInputSource() },
            userRecipes: activationRecipes,
            postKana: EventTapMonitor.postKanaKeyEvent,
            wait: EventTapMonitor.scheduleOnMainQueue,
            select: { [weak self] in self?.selectSwitchedSource(source, for: role) }
        )
    }

    private func selectSwitchedSource(_ source: InputSourceInfo, for role: InputRole) {
        defer { settingsSwitchDeadline = nil }
        do {
            let current = try inputSources.selectInputSourceAndConfirm(id: source.id)
            guard current?.id == source.id else {
                reportSlotFailure(InputSourceInfo.verificationMessage(requested: source, current: current), for: role)
                return
            }
            showSwitchIndicator(for: role, source: source)
            clearSlotNotice(for: role)
            statusText = String(localized: "Selected \(source.localizedName)")
        } catch {
            reportSlotFailure(error.localizedDescription, for: role)
        }
    }

    func bindingText(for role: InputRole) -> String {
        config.bindings.first { binding in
            binding.enabled
                && binding.action.type == .switchInputSource
                && binding.action.role == role
        }?.trigger.displayName ?? ""
    }

    func trigger(for role: InputRole) -> KeyTrigger? {
        config.bindings.first { binding in
            binding.enabled
                && binding.action.type == .switchInputSource
                && binding.action.role == role
        }?.trigger
    }

    func trigger(for role: InputRole, category: SlotTriggerCategory) -> KeyTrigger? {
        config.binding(for: role, category: category)?.trigger
    }

    @discardableResult
    func commitRecordedTrigger(_ trigger: KeyTrigger?, for role: InputRole,
                               category: SlotTriggerCategory) -> String? {
        if let trigger, let reason = recordedTriggerConflict(trigger, for: role, category: category) {
            reportSlotFailure(reason, for: role)
            return reason
        }
        do {
            let next = try config.replacingSwitchBinding(for: role, category: category, with: trigger)
            if next != config {
                guard commit(next) else {
                    reportSlotFailure(statusText, for: role)
                    return statusText
                }
                invalidateUndo()
            }
            clearSlotNotice(for: role)
            statusText = trigger.map { String(localized: "Saved trigger \($0.localizedDisplayName)") } ?? String(localized: "Removed trigger")
            return nil
        } catch {
            reportSlotFailure(error.localizedDescription, for: role)
            return error.localizedDescription
        }
    }

    func setBindingText(_ text: String, for role: InputRole) {
        do {
            let trigger = try ShortcutParser.parse(text)
            setBindingTrigger(trigger, for: role)
        } catch {
            reportSlotFailure(error.localizedDescription, for: role)
        }
    }

    func recordedTriggerConflict(_ trigger: KeyTrigger, for role: InputRole,
                                 category: SlotTriggerCategory) -> String? {
        if trigger.isReservedMacInputSourceShortcut {
            return String(localized: "\(trigger.localizedDisplayName) is reserved by macOS input source switching")
        }
        do {
            _ = try config.replacingSwitchBinding(for: role, category: category, with: trigger)
            return nil
        } catch SlotTriggerCategoryError.conflictingBinding(let binding) {
            return String(localized: "\(trigger.localizedDisplayName) is already used by \(config.ownerDescription(of: binding))")
        } catch {
            return error.localizedDescription
        }
    }

    func recordedTriggerConflict(_ trigger: KeyTrigger, for role: InputRole) -> String? {
        if trigger.isReservedMacInputSourceShortcut {
            return String(localized: "\(trigger.localizedDisplayName) is reserved by macOS input source switching")
        }
        if let conflictRole = config.oneShotModifierConflict(for: trigger, excluding: role) {
            return String(localized: "\(readableOneShotName(trigger.keyName)) is already bound to \(config.displayName(for: conflictRole))")
        }
        if let conflict = config.conflictingBinding(for: trigger, excluding: role) {
            return String(localized: "\(trigger.localizedDisplayName) is already used by \(config.ownerDescription(of: conflict))")
        }
        return nil
    }

    /// Recorder drafts never mutate configuration; only an explicit commit reaches here.
    @discardableResult
    func commitRecordedTrigger(_ trigger: KeyTrigger?, for role: InputRole) -> String? {
        guard config.slot(role) != nil else { return SlotError.unknownSlot(role).localizedDescription }
        if let trigger, let reason = recordedTriggerConflict(trigger, for: role) {
            reportSlotFailure(reason, for: role)
            return reason
        }
        var next = config
        if let trigger {
            next.upsertSwitchBinding(trigger: trigger, role: role)
        } else {
            next.bindings.removeAll { $0.action.type == .switchInputSource && $0.action.role == role }
        }
        if next != config {
            guard commit(next) else {
                reportSlotFailure(statusText, for: role)
                return statusText
            }
            invalidateUndo()
        }
        clearSlotNotice(for: role)
        statusText = trigger.map { String(localized: "Saved trigger \($0.localizedDisplayName)") } ?? String(localized: "Removed trigger")
        return nil
    }

    func setBindingTrigger(_ trigger: KeyTrigger, for role: InputRole) {
        commitRecordedTrigger(trigger, for: role)
    }

    func setOneShotBinding(keyCode: Int, keyName: String, gesture: TriggerGesture, for role: InputRole) {
        let trigger = KeyTrigger(
            kind: .oneShotModifier,
            keyCode: keyCode,
            keyName: keyName,
            gesture: gesture
        )
        setBindingTrigger(trigger, for: role)
    }

    func setBindingGesture(_ gesture: TriggerGesture, for role: InputRole) {
        guard var trigger = trigger(for: role) else {
            return
        }
        if gesture == .doubleTap, trigger.kind != .oneShotModifier {
            reportSlotFailure(String(localized: "Double tap requires a single modifier key"), for: role)
            return
        }
        trigger.gesture = gesture
        setBindingTrigger(trigger, for: role)
    }

    func oneShotConflictRole(forKeyCode keyCode: Int, keyName: String, excluding role: InputRole) -> InputRole? {
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: keyCode, keyName: keyName)
        return config.oneShotModifierConflict(for: trigger, excluding: role)
    }

    func oneShotConflictWarning(for role: InputRole) -> String? {
        guard let trigger = trigger(for: role),
              let conflictRole = config.oneShotModifierConflict(for: trigger, excluding: role) else {
            return nil
        }

        return String(localized: "\(readableOneShotName(trigger.keyName)) already used by \(config.displayName(for: conflictRole))")
    }

    func matchedSource(for role: InputRole) -> InputSourceInfo? {
        InputSourceMatcher.bestMatch(for: role, sources: sources, config: config)
    }

    /// Hands the user's activation recipes to the live monitor; a skipped entry is reported, not fatal.
    private func loadActivationRecipes() {
        let result = ActivationRecipeStore().load()
        activationRecipes = result.recipes
        monitor?.activationRecipes = result.recipes
        if let problem = result.problems.first {
            statusText = problem
        }
    }

    func startListening() {
        refreshRuntimeStatus()
        guard permissions.isReady else {
            isListening = false
            keyboardControlState = "Needs permission"
            statusText = String(localized: "Grant permissions, then resume keyboard control")
            return
        }

        do {
            let nextMonitor = EventTapMonitor(config: config, inputSources: inputSources)
            nextMonitor.isCapturingShortcut = recordingRole != nil
            nextMonitor.onMessage = { [weak self] message in
                DispatchQueue.main.async {
                    self?.statusText = message
                }
            }
            // Already on the main thread: the monitor reports from work it scheduled
            // there itself. Hopping again only pushed the bubble one run-loop turn
            // further from the key that asked for it.
            nextMonitor.onSwitch = { [weak self] role, source in
                MainActor.assumeIsolated {
                    self?.appMemory.switchDidConfirm(sourceID: source.id)
                    self?.showSwitchIndicator(for: role, source: source)
                }
            }
            nextMonitor.onSilentSwitch = { [weak self] source in
                MainActor.assumeIsolated {
                    _ = self?.indicatorOccasions.ownSwitchConfirmed(sourceID: source.id, reported: false)
                }
            }
            nextMonitor.onTriggeredSwitch = { [weak self] role, source, trigger in
                MainActor.assumeIsolated {
                    self?.triggeredSwitches.send(SetupTriggeredSwitch(slotID: role, sourceID: source.id, trigger: trigger))
                }
            }
            nextMonitor.onPeek = { [weak self] in
                MainActor.assumeIsolated { self?.showPeekIndicator() }
            }
            nextMonitor.onCapsLockChange = { [weak self] isOn in
                MainActor.assumeIsolated { self?.showCapsLockIndicator(isOn: isOn) }
            }
            nextMonitor.characterBeforeCaret = { CaretCharacterReader.characterBeforeCaret() }
            observeActivationsForAutoSpace()
            try nextMonitor.start()
            monitor = nextMonitor
            isListening = true
            keyboardControlState = "Active"
            statusText = String(localized: "Listener started")
            refreshAppMemory()
            // After the line above, so a skipped recipe is what the status bar ends up showing.
            loadActivationRecipes()
        } catch {
            isListening = false
            keyboardControlState = permissions.isReady ? "Failed" : "Needs permission"
            statusText = error.localizedDescription
        }
    }

    /// Another app in front: the caret auto space read belongs to the app that was left.
    private func observeActivationsForAutoSpace() {
        guard autoSpaceActivationObserver == nil else { return }
        autoSpaceActivationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.monitor?.cancelAutoSpace() }
        }
    }

    /// The listener could not start although both permissions read as granted. Kept
    /// beside the assignment above; compare raw state, not translated display copy.
    var didListenerFailToStart: Bool {
        keyboardControlState == "Failed"
    }

    func stopListening() {
        monitor?.stop()
        monitor = nil
        refreshAppMemory()
        isListening = false
        keyboardControlState = "Paused"
        statusText = String(localized: "Listener stopped")
    }

    /// `restoringSystemBadge` for Quit CmdIME on the General page: someone who stops CmdIME gets the
    /// macOS badge back. Relaunch and Update Now keep it hidden, or every restart would flash it back.
    /// The restore waits for `willTerminate`, so a quit an import holds back cannot hide it again.
    func quit(restoringSystemBadge: Bool = false) {
        if restoringSystemBadge { restoresSystemBadgeOnExit = true }
        stopListening()
        NSApp.terminate(nil)
    }

    private func showSwitchIndicator(for role: InputRole, source: InputSourceInfo) {
        let previous = activeRole
        activeRole = role
        guard indicatorOccasions.ownSwitchConfirmed(sourceID: source.id, reported: true) else {
            return
        }
        switchIndicator.show(slotID: role, previousSlotID: previous, source: source, config: config, sources: sources)
    }

    /// A change CmdIME did not make, or an app switch that left another source. Only while
    /// keyboard control runs, and only for a source that belongs to a slot: the bubble draws a slot.
    private func showExternalChangeIndicator(source: InputSourceInfo) {
        guard monitor != nil,
              let role = InputSourceMatcher.slotID(forSelectedSourceID: source.id, sources: sources, config: config) else {
            return
        }
        let previous = activeRole
        activeRole = role
        switchIndicator.show(slotID: role, previousSlotID: previous, source: source, config: config, sources: sources)
    }

    private var isOwnSwitchPending: Bool {
        if monitor?.isSwitchPending == true { return true }
        return (settingsSwitchDeadline?.timeIntervalSinceNow ?? 0) > 0
    }

    /// Covers the Settings Switch button's Kana delay plus its confirmation retries.
    private static let settingsSwitchBudget: TimeInterval = 1.0

    /// Peek asks for the bubble explicitly, so it shows even with the switch bubble turned off.
    private func showPeekIndicator() {
        guard let source = try? inputSources.currentInputSource() else {
            statusText = String(localized: "No input source is selected")
            return
        }
        guard let role = InputSourceMatcher.slotID(forSelectedSourceID: source.id, sources: sources, config: config) else {
            statusText = String(localized: "\(source.localizedName) is not in a slot")
            return
        }
        switchIndicator.show(slotID: role, previousSlotID: nil, source: source, config: config, sources: sources, isPeek: true)
    }

    private func showCapsLockIndicator(isOn: Bool) {
        guard config.showCapsLockIndicator,
              !config.switchIndicatorBehavior.isHidden(in: NSWorkspace.shared.frontmostApplication?.cmdIMEAppID) else {
            return
        }
        let source = try? inputSources.currentInputSource()
        switchIndicator.showCapsLock(isOn: isOn, slotID: activeRole, source: source, config: config, sources: sources)
    }

    private func readableOneShotName(_ keyName: String) -> String {
        switch keyName {
        case "left-command":
            return String(localized: "Left Command")
        case "right-command":
            return String(localized: "Right Command")
        case "left-option":
            return String(localized: "Left Option")
        case "right-option":
            return String(localized: "Right Option")
        case "left-control":
            return String(localized: "Left Control")
        case "right-control":
            return String(localized: "Right Control")
        case "left-shift":
            return String(localized: "Left Shift")
        case "right-shift":
            return String(localized: "Right Shift")
        default:
            return keyName
        }
    }
}

enum UpdateStatus: Equatable {
    case idle(currentVersion: String)
    case checking(currentVersion: String)
    case upToDate(UpdateCheckResult)
    case available(UpdateCheckResult)
    case failed(currentVersion: String, message: String)

    var isChecking: Bool {
        if case .checking = self {
            return true
        }
        return false
    }

    var releaseURL: URL? {
        switch self {
        case .upToDate(let result), .available(let result):
            result.releaseURL
        case .idle, .checking, .failed:
            nil
        }
    }

    var message: String {
        switch self {
        case .idle(let currentVersion):
            String(localized: "Current \(currentVersion)")
        case .checking:
            String(localized: "Checking GitHub releases")
        case .upToDate(let result):
            String(localized: "Up to date: \(result.currentVersion)")
        case .available(let result):
            String(localized: "New version \(result.latestVersion) available")
        case .failed(_, let message):
            message
        }
    }
}
