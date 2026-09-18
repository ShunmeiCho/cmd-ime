import AppKit
import Foundation
import KeyboardSwitcherCore

enum BoardNotice: Equatable {
    case rejected(String)
    case removed(slotName: String)
}

@MainActor
final class AppModel: ObservableObject {
    @Published var config: SwitcherConfig
    @Published var sources: [InputSourceInfo] = []
    @Published var statusText = "Ready"
    @Published var isListening = false
    @Published var activeRole: InputRole?
    @Published var keyboardControlStatus = "Starting"
    @Published var permissions = MacPermissionStatus.current()
    @Published var loginItem = LoginItemService().snapshot()
    @Published var updateStatus: UpdateStatus
    @Published private(set) var slotNotices: [InputRole: String] = [:]

    @Published private(set) var boardNotice: BoardNotice?
    @Published private(set) var canUndoRemoval = false
    private var pendingUndo: RemovedSlot? {
        didSet { canUndoRemoval = pendingUndo != nil }
    }

    private let configStore: ConfigStore
    private let inputSources = MacInputSourceService()
    private let loginItems = LoginItemService()
    private let switchIndicator = InputIndicatorController()
    private let updates = UpdateService()
    private var monitor: EventTapMonitor?
    private var recordingRole: InputRole?

    func setShortcutRecording(_ recording: Bool, for role: InputRole) {
        if recording {
            recordingRole = role
            clearSlotNotice(for: role)
        } else if recordingRole == role {
            recordingRole = nil
        }
        monitor?.isCapturingShortcut = recordingRole != nil
    }

    private func clearSlotNotice(for role: InputRole) {
        if slotNotices[role] != nil {
            slotNotices[role] = nil
        }
    }

    private func reportSlotFailure(_ message: String, for role: InputRole) {
        statusText = message
        slotNotices[role] = message
    }

    private static var currentVersion: String {
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
                recoveryMessage = "Config was unreadable; backed it up to \(backupURL.lastPathComponent) and reset to defaults."
            }
        } catch {
            initialConfig = .default
            recoveryMessage = "Could not read config: \(error.localizedDescription). Using defaults."
        }

        self.config = initialConfig
        self.updateStatus = .idle(currentVersion: Self.currentVersion)
        let scanSucceeded = scan()
        if isFirstRun {
            if scanSucceeded {
                config = SwitcherConfig.detected(from: sources)
                do {
                    try configStore.save(config)
                } catch {
                    recoveryMessage = "Could not save detected slots: \(error.localizedDescription)"
                }
            } else {
                recoveryMessage = statusText
            }
        }
        refreshRuntimeStatus()
        startListeningIfReady()
        if let recoveryMessage {
            statusText = recoveryMessage
        }
    }

    @discardableResult
    func scan() -> Bool {
        do {
            sources = try inputSources.listInputSources()
            monitor?.updateConfig(config)
            statusText = "Found \(sources.count) input sources"
            return true
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func refreshRuntimeStatus() {
        permissions = MacPermissionStatus.current()
        loginItem = loginItems.snapshot()
        if !isListening, permissions.isReady, keyboardControlStatus == "Needs permission" {
            keyboardControlStatus = "Paused"
            statusText = "Permissions ready. Click Resume to start keyboard control."
        }
    }

    func requestPermissions() {
        MacPermissionStatus.request()
        refreshRuntimeStatus()
    }

    func openAccessibilitySettings() {
        openPrivacySettings(anchor: "Privacy_Accessibility")
        statusText = "Opened Accessibility settings"
    }

    func openInputMonitoringSettings() {
        openPrivacySettings(anchor: "Privacy_ListenEvent")
        statusText = "Opened Input Monitoring settings"
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
            keyboardControlStatus = "Needs permission"
            statusText = "Grant permissions, then resume keyboard control"
            return
        }
        startListening()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try loginItems.setEnabled(enabled)
            refreshRuntimeStatus()
            statusText = enabled ? "Login item enabled" : "Login item disabled"
        } catch {
            refreshRuntimeStatus()
            statusText = error.localizedDescription
        }
    }

    func setSwitchIndicatorVisible(_ visible: Bool) {
        config.showSwitchIndicator = visible
        save()
        statusText = visible ? "Switch indicator enabled" : "Switch indicator disabled"
    }

    func setSwitchIndicatorSize(_ size: SwitchIndicatorSize) {
        config.switchIndicatorSize = size
        save()
        statusText = "Switch indicator size set to \(size.displayName)"
    }

    func setSwitchIndicatorScale(_ scale: Double) {
        let clampedScale = SwitcherConfig.clampedSwitchIndicatorScale(scale)
        config.switchIndicatorScale = clampedScale
        save()
        statusText = "Switch indicator scale set to \(Int((clampedScale * 100).rounded()))%"
    }

    func setSwitchIndicatorColorStyle(_ style: SwitchIndicatorColorStyle) {
        config.switchIndicatorColorStyle = style
        save()
        statusText = "Switch indicator color set to \(style.displayName)"
    }

    func setSwitchIndicatorContentStyle(_ style: SwitchIndicatorContentStyle) {
        config.switchIndicatorContentStyle = style
        save()
        statusText = "Switch indicator display set to \(style.displayName)"
    }

    func setSwitchIndicatorCustomColorHex(_ hex: String) {
        config.switchIndicatorCustomColorHex = hex
        save()
        statusText = "Switch indicator custom color set to \(hex)"
    }

    func setSwitchIndicatorCustomColorHex(_ hex: String, for role: InputRole) {
        config.setSwitchIndicatorCustomColorHex(hex, for: role)
        save()
        statusText = "\(config.displayName(for: role)) indicator custom color set to \(hex)"
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
        statusText = "Checking for updates"

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

    func openLatestRelease() {
        guard let url = updateStatus.releaseURL else {
            checkForUpdates()
            return
        }
        NSWorkspace.shared.open(url)
        statusText = "Opened CmdIME release page"
    }

    func resetSlotsFromDetectedSources() {
        guard scan() else { return }
        do {
            let rebuilt = try configStore.resettingSlots(in: config, from: sources)
            invalidateUndo()
            config = rebuilt
            activeRole = nil
            monitor?.updateConfig(rebuilt)
            statusText = "Rebuilt \(rebuilt.slots.count) slots from installed input sources"
        } catch {
            // Keep the live config and monitor untouched if backup or save fails.
            statusText = "Could not rebuild slots: \(error.localizedDescription)"
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
            reportBoardFailure("Already in slot \(config.displayName(for: owner))")
            return nil
        case let .resolved(owner, _):
            reportBoardFailure("Fallback for \(config.displayName(for: owner))")
            return nil
        }
        do {
            let added = try config.addingSlot(for: source, at: index)
            guard commit(added.config) else { return nil }
            invalidateUndo()
            boardNotice = nil
            statusText = "Added slot \(added.slot.name)"
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
        statusText = "Moved slot \(config.displayName(for: id))"
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
            statusText = "Renamed slot to \(config.displayName(for: id))"
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
            statusText = "Removed slot \(result.removed.slot.name). Undo available."
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
            statusText = "Restored slot \(removed.slot.name)"
            if !restored.skippedBindings.isEmpty {
                let triggers = restored.skippedBindings.map { $0.binding.trigger.displayName }.joined(separator: ", ")
                let message = "Restored slot, but conflicting triggers were not restored: \(triggers)"
                reportSlotFailure(message, for: removed.slot.id)
                reportBoardFailure(message)
            }
        } catch {
            reportBoardFailure(error.localizedDescription)
        }
    }

    func dismissBoardNotice() {
        pendingUndo = nil
        boardNotice = nil
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

    private func commit(_ next: SwitcherConfig) -> Bool {
        do {
            try configStore.save(next)
            config = next
            monitor?.updateConfig(next)
            return true
        } catch {
            reportBoardFailure(error.localizedDescription)
            return false
        }
    }

    func setInputSourceID(_ id: String, for role: InputRole) {
        guard let source = selectableSources.first(where: { $0.id == id }) else {
            statusText = "Input source not found: \(id)"
            return
        }

        do {
            let next = try config.selectingInputSource(source, for: role, sources: sources)
            if next != config { invalidateUndo() }
            config = next
            if save() {
                clearSlotNotice(for: role)
                statusText = "Switch slot set to \(source.localizedName)"
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
        case let .swap(other): "\(source.localizedName) — swap with \(config.displayName(for: other))"
        case let .usedBy(other): "\(source.localizedName) — used by \(config.displayName(for: other))"
        default: source.localizedName
        }
    }

    @discardableResult
    func save() -> Bool {
        do {
            try configStore.save(config)
            monitor?.updateConfig(config)
            statusText = "Saved \(configStore.url.path)"
            return true
        } catch {
            statusText = error.localizedDescription
            return false
        }
    }

    func switchRole(_ role: InputRole) {
        do {
            if sources.isEmpty {
                scan()
            }
            guard let source = matchedSource(for: role) else {
                reportSlotFailure("No input source matched this slot", for: role)
                return
            }
            let current = try inputSources.selectInputSourceAndConfirm(id: source.id)
            guard current?.id == source.id else {
                reportSlotFailure(InputSourceInfo.verificationMessage(requested: source, current: current), for: role)
                return
            }
            showSwitchIndicator(for: role, source: source)
            clearSlotNotice(for: role)
            statusText = "Selected \(source.localizedName)"
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

    func setBindingText(_ text: String, for role: InputRole) {
        do {
            let trigger = try ShortcutParser.parse(text)
            setBindingTrigger(trigger, for: role)
        } catch {
            reportSlotFailure(error.localizedDescription, for: role)
        }
    }

    func setBindingTrigger(_ trigger: KeyTrigger, for role: InputRole) {
        guard !trigger.isReservedMacInputSourceShortcut else {
            reportSlotFailure("\(trigger.displayName) is reserved by macOS input source switching", for: role)
            return
        }
        if let conflictRole = config.oneShotModifierConflict(for: trigger, excluding: role) {
            reportSlotFailure("\(readableOneShotName(trigger.keyName)) is already bound to \(config.displayName(for: conflictRole))", for: role)
            return
        }
        if let conflict = config.conflictingBinding(for: trigger, excluding: role) {
            let owner: String
            if conflict.action.type == .switchInputSource, let otherRole = conflict.action.role {
                owner = config.displayName(for: otherRole)
            } else if conflict.action.type == .sendKey {
                owner = "a key remap"
            } else {
                owner = "another binding"
            }
            reportSlotFailure("\(trigger.displayName) is already used by \(owner)", for: role)
            return
        }

        // Validate before upsert: its replacement semantics also serve the CLI.
        var next = config
        next.upsertSwitchBinding(trigger: trigger, role: role)
        guard next != config else {
            clearSlotNotice(for: role)
            return
        }
        invalidateUndo()
        config = next
        if save() {
            clearSlotNotice(for: role)
        } else {
            reportSlotFailure(statusText, for: role)
        }
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
            reportSlotFailure("Double tap requires a single modifier key", for: role)
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

        return "\(readableOneShotName(trigger.keyName)) already used by \(config.displayName(for: conflictRole))"
    }

    func matchedSource(for role: InputRole) -> InputSourceInfo? {
        InputSourceMatcher.bestMatch(for: role, sources: sources, config: config)
    }

    func startListening() {
        refreshRuntimeStatus()
        guard permissions.isReady else {
            isListening = false
            keyboardControlStatus = "Needs permission"
            statusText = "Grant permissions, then resume keyboard control"
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
            nextMonitor.onSwitch = { [weak self] role, source in
                DispatchQueue.main.async {
                    self?.showSwitchIndicator(for: role, source: source)
                }
            }
            try nextMonitor.start()
            monitor = nextMonitor
            isListening = true
            keyboardControlStatus = "Active"
            statusText = "Listener started"
        } catch {
            isListening = false
            keyboardControlStatus = permissions.isReady ? "Failed" : "Needs permission"
            statusText = error.localizedDescription
        }
    }

    func stopListening() {
        monitor?.stop()
        monitor = nil
        isListening = false
        keyboardControlStatus = "Paused"
        statusText = "Listener stopped"
    }

    func quit() {
        stopListening()
        NSApp.terminate(nil)
    }

    private func showSwitchIndicator(for role: InputRole, source: InputSourceInfo) {
        activeRole = role
        guard config.showSwitchIndicator, let slot = config.slot(role) else {
            return
        }
        switchIndicator.show(
            slot: slot,
            source: source,
            size: config.switchIndicatorSize,
            scale: config.switchIndicatorScale,
            colorStyle: config.switchIndicatorColorStyle,
            contentStyle: config.switchIndicatorContentStyle,
            customColorHex: config.switchIndicatorCustomColorHex(for: role)
        )
    }

    private func readableOneShotName(_ keyName: String) -> String {
        switch keyName {
        case "left-command":
            return "Left Command"
        case "right-command":
            return "Right Command"
        case "left-option":
            return "Left Option"
        case "right-option":
            return "Right Option"
        case "left-control":
            return "Left Control"
        case "right-control":
            return "Right Control"
        case "left-shift":
            return "Left Shift"
        case "right-shift":
            return "Right Shift"
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
            "Current \(currentVersion)"
        case .checking:
            "Checking GitHub releases"
        case .upToDate(let result):
            "Up to date: \(result.currentVersion)"
        case .available(let result):
            "New version \(result.latestVersion) available"
        case .failed(_, let message):
            message
        }
    }
}
