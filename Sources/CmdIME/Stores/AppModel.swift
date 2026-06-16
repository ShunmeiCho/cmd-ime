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

    private let configStore: ConfigStore
    private let inputSources = MacInputSourceService()
    private let loginItems = LoginItemService()
    private var monitor: EventTapMonitor?

    init(configStore: ConfigStore = ConfigStore()) {
        self.configStore = configStore
        self.config = (try? configStore.loadOrDefault()) ?? .default
        scan()
        refreshRuntimeStatus()
        startListening()
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
    }

    func requestPermissions() {
        MacPermissionStatus.request()
        refreshRuntimeStatus()
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
        config.showMenuBarIcon = visible
        save()
    }

    func startListening() {
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
}
