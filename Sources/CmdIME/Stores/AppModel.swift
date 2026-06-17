import AppKit
import Foundation
import KeyboardSwitcherCore

@MainActor
final class AppModel: ObservableObject {
    @Published var config: SwitcherConfig
    @Published var sources: [InputSourceInfo] = []
    @Published var statusText = "Ready"
    @Published var isListening = false
    @Published var keyboardControlStatus = "Starting"
    @Published var permissions = MacPermissionStatus.current()
    @Published var loginItem = LoginItemService().snapshot()
    @Published var updateStatus: UpdateStatus

    private let configStore: ConfigStore
    private let inputSources = MacInputSourceService()
    private let loginItems = LoginItemService()
    private let updates = UpdateService()
    private var monitor: EventTapMonitor?

    var menuBarIconSupported: Bool {
        Self.isMenuBarIconSupported
    }

    private static var isMenuBarIconSupported: Bool {
        ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 26
    }

    private static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore
        var initialConfig = (try? configStore.loadOrDefault()) ?? .default
        if !Self.isMenuBarIconSupported {
            initialConfig.showMenuBarIcon = false
        }
        self.config = initialConfig
        self.updateStatus = .idle(currentVersion: Self.currentVersion)
        scan()
        refreshRuntimeStatus()
        startListeningIfReady()
    }

    func scan() {
        do {
            sources = try inputSources.listInputSources()
            statusText = "Found \(sources.count) input sources"
        } catch {
            statusText = error.localizedDescription
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

    func setProtectDoubleTapShortcuts(_ enabled: Bool) {
        config.protectDoubleTapShortcuts = enabled
        save()
        statusText = enabled
            ? "Double-tap shortcut protection enabled"
            : "Single-tap modifiers switch immediately"
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

    func initializeFromScan() {
        var nextConfig = SwitcherConfig.default
        scan()

        for role in InputRole.allCases {
            if let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: nextConfig) {
                nextConfig.pinInputSourceID(source.id, for: role)
            }
        }

        config = nextConfig
        save()
    }

    func save() {
        do {
            try configStore.save(config)
            monitor?.updateConfig(config)
            statusText = "Saved \(configStore.url.path)"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func switchRole(_ role: InputRole) {
        do {
            if sources.isEmpty {
                scan()
            }
            guard let source = matchedSource(for: role) else {
                statusText = "No input source matched \(role.rawValue)"
                return
            }
            try inputSources.selectInputSource(id: source.id)
            statusText = "Selected \(source.localizedName)"
        } catch {
            statusText = error.localizedDescription
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
            statusText = error.localizedDescription
        }
    }

    func setBindingTrigger(_ trigger: KeyTrigger, for role: InputRole) {
        config.upsertSwitchBinding(trigger: trigger, role: role)
        save()
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
            statusText = "Double tap requires a single modifier key"
            return
        }
        trigger.gesture = gesture
        config.upsertSwitchBinding(trigger: trigger, role: role)
        save()
    }

    func matchedSource(for role: InputRole) -> InputSourceInfo? {
        InputSourceMatcher.bestMatch(for: role, sources: sources, config: config)
    }

    func setMenuBarIconVisible(_ visible: Bool) {
        guard menuBarIconSupported else {
            config.showMenuBarIcon = false
            save()
            statusText = "Menu bar icon is disabled on this macOS version"
            return
        }

        config.showMenuBarIcon = visible
        save()
        statusText = visible
            ? "Menu bar icon shown"
            : "Menu bar icon hidden. Reopen CmdIME.app to show settings."
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
            nextMonitor.onMessage = { [weak self] message in
                DispatchQueue.main.async {
                    self?.statusText = message
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

    func toggleListening() {
        isListening ? stopListening() : startListening()
    }

    func quit() {
        stopListening()
        NSApp.terminate(nil)
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
