import KeyboardSwitcherCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var triggerDrafts: [InputRole: String] = [:]
    @State private var triggerTypeDrafts: [InputRole: BindingTriggerType] = [:]

    private enum Metrics {
        static let labelColumn: CGFloat = 140
        static let matchedColumn: CGFloat = 280
        static let languagesColumn: CGFloat = 170
        static let triggerPicker: CGFloat = 140
        static let modifierPicker: CGFloat = 220
        static let actionButton: CGFloat = 170
        static let compactButton: CGFloat = 96
        static let rowHeight: CGFloat = 44
        static let fieldHeight: CGFloat = 28
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header

                Divider()

                inputSourcesSection

                Divider()

                bindingsSection

                Divider()

                runtimeSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            resetDrafts()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Text("⌘")
                .font(.system(size: 30, weight: .semibold))
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 4) {
                Text("CmdIME")
                    .font(.title2.weight(.semibold))
                Text(model.statusText)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                model.initializeFromScan()
                resetDrafts()
            } label: { Text("Use detected sources") }
            .frame(width: Metrics.actionButton)

            Button {
                model.toggleListening()
            } label: { Text(model.isListening ? "Pause" : "Resume") }
            .frame(width: Metrics.compactButton)
            .buttonStyle(.borderedProminent)
        }
    }

    private var inputSourcesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Input Sources")
                .font(.headline)

            HStack {
                Text("Matched from your macOS input sources")
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    model.scan()
                } label: { Text("Refresh input sources") }
                .frame(width: Metrics.actionButton)
            }

            VStack(alignment: .leading, spacing: 8) {
                inputSourceHeaderRow

                ForEach(InputRole.allCases, id: \.self) { role in
                    inputSourceRow(for: role, source: model.matchedSource(for: role))
                }
            }
        }
    }

    private var inputSourceHeaderRow: some View {
        HStack(spacing: 12) {
            Text("Role")
                .frame(width: Metrics.labelColumn, alignment: .leading)
            Text("Matched Source")
                .frame(width: Metrics.matchedColumn, alignment: .leading)
            Text("Languages")
                .frame(width: Metrics.languagesColumn, alignment: .leading)
            Spacer(minLength: 0)
            Text("")
                .frame(width: Metrics.compactButton)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func inputSourceRow(for role: InputRole, source: InputSourceInfo?) -> some View {
        HStack(spacing: 12) {
            Text(roleTitle(for: role))
                .frame(width: Metrics.labelColumn, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(source?.localizedName ?? "Not matched")
                    .lineLimit(1)
                Text(source?.id ?? "Run Scan or Auto Setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: Metrics.matchedColumn, alignment: .leading)

            Text(source?.displayLanguages ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Metrics.languagesColumn, alignment: .leading)

            Spacer(minLength: 0)

            Button("Switch") {
                model.switchRole(role)
            }
            .frame(width: Metrics.compactButton)
        }
        .frame(height: Metrics.rowHeight)
    }

    private var bindingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bindings")
                .font(.headline)

            ForEach(InputRole.allCases, id: \.self) { role in
                HStack(spacing: 12) {
                    Text(roleTitle(for: role))
                        .frame(width: Metrics.labelColumn, alignment: .leading)

                    Picker(
                        "Trigger type",
                        selection: Binding(
                            get: { triggerType(for: role) },
                            set: { setTriggerType($0, for: role) }
                        )
                    ) {
                        Text("Shortcut").tag(BindingTriggerType.shortcut)
                        Text("Single tap").tag(BindingTriggerType.singleTap)
                        Text("Double tap").tag(BindingTriggerType.doubleTap)
                    }
                    .labelsHidden()
                    .frame(width: Metrics.triggerPicker)

                    switch triggerType(for: role) {
                    case .shortcut:
                        ShortcutRecorderField(
                            text: Binding(
                                get: { triggerDrafts[role] ?? model.bindingText(for: role) },
                                set: { triggerDrafts[role] = $0 }
                            ),
                            onCommit: { shortcut in
                                model.setBindingText(shortcut, for: role)
                                resetDrafts()
                            }
                        )
                        .frame(width: Metrics.modifierPicker, height: Metrics.fieldHeight)
                        Spacer(minLength: 0)
                    case .singleTap, .doubleTap:
                        Picker(
                            "Modifier key",
                            selection: Binding(
                                get: {
                                    OneShotModifierChoice(trigger: model.trigger(for: role))
                                        ?? defaultOneShotChoice(for: role)
                                },
                                set: { choice in
                                    let gesture = triggerType(for: role).gesture ?? .tap
                                    model.setOneShotBinding(
                                        keyCode: choice.keyCode,
                                        keyName: choice.rawValue,
                                        gesture: gesture,
                                        for: role
                                    )
                                    resetDrafts()
                                }
                            )
                        ) {
                            ForEach(OneShotModifierChoice.allCases) { choice in
                                Label(choice.title, systemImage: choice.iconName)
                                    .tag(choice)
                            }
                        }
                        .labelsHidden()
                        .frame(width: Metrics.modifierPicker)

                        Text(model.bindingText(for: role))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .frame(minHeight: Metrics.rowHeight)
            }
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Runtime")
                .font(.headline)

            Toggle(
                "Show menu bar icon",
                isOn: Binding(
                    get: { model.config.showMenuBarIcon },
                    set: { model.setMenuBarIconVisible($0) }
                )
            )
            .disabled(!model.menuBarIconSupported)

            if !model.menuBarIconSupported {
                Text("Menu bar icon is disabled on this macOS version. Reopen CmdIME.app to show settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Toggle(
                "Start at login",
                isOn: Binding(
                    get: { model.loginItem.isEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .disabled(!model.loginItem.isAvailable)

            Toggle(
                "Protect double-tap shortcuts",
                isOn: Binding(
                    get: { model.config.protectDoubleTapShortcuts },
                    set: { model.setProtectDoubleTapShortcuts($0) }
                )
            )
            .help("Delay single-tap modifier bindings briefly so double-tap shortcuts can take precedence.")

            HStack {
                Text("Updates")
                    .frame(width: Metrics.labelColumn, alignment: .leading)
                Text(model.updateStatus.message)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                if model.updateStatus.releaseURL != nil {
                    Button("Open Release") {
                        model.openLatestRelease()
                    }
                    .frame(width: 120)
                }
                Button(model.updateStatus.isChecking ? "Checking" : "Check") {
                    model.checkForUpdates()
                }
                .disabled(model.updateStatus.isChecking)
                .frame(width: Metrics.actionButton)
            }

            HStack {
                Text("Keyboard control")
                    .frame(width: Metrics.labelColumn, alignment: .leading)
                Text(model.keyboardControlStatus)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.isListening ? "Pause" : "Resume") {
                    model.toggleListening()
                }
                .frame(width: Metrics.actionButton)
            }

            HStack {
                Text("Permissions")
                    .frame(width: Metrics.labelColumn, alignment: .leading)
                Text(model.permissions.isReady ? "Ready" : "Grant both permissions")
                    .foregroundStyle(model.permissions.isReady ? Color.secondary : Color.orange)
                Spacer()
                Button("Request All") {
                    model.requestPermissions()
                }
                .frame(width: Metrics.actionButton)
            }

            permissionRow(
                title: "Accessibility",
                granted: model.permissions.accessibilityGranted,
                buttonTitle: "Open Accessibility"
            ) {
                model.openAccessibilitySettings()
            }

            permissionRow(
                title: "Input Monitoring",
                granted: model.permissions.inputMonitoringGranted,
                buttonTitle: "Open Input Monitoring"
            ) {
                model.openInputMonitoringSettings()
            }

            HStack {
                Text("Application")
                    .frame(width: Metrics.labelColumn, alignment: .leading)
                Text("Stop the listener and quit the background agent")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit CmdIME") {
                    model.quit()
                }
                .frame(width: Metrics.actionButton)
            }
        }
    }

    private func permissionRow(
        title: String,
        granted: Bool,
        buttonTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
                .frame(width: Metrics.labelColumn, alignment: .leading)
            Text(granted ? "Ready" : "Missing")
                .foregroundStyle(granted ? Color.secondary : Color.orange)
            Spacer()
            Button(buttonTitle, action: action)
                .frame(width: Metrics.actionButton)
        }
        .font(.caption)
    }

    private func resetDrafts() {
        triggerDrafts = Dictionary(
            uniqueKeysWithValues: InputRole.allCases.map { ($0, model.bindingText(for: $0)) }
        )
        triggerTypeDrafts.removeAll()
    }

    private func roleTitle(for role: InputRole) -> String {
        switch role {
        case .english:
            "English"
        case .chinese:
            "Chinese"
        case .japanese:
            "Japanese"
        }
    }

    private func setTriggerType(_ type: BindingTriggerType, for role: InputRole) {
        switch type {
        case .shortcut:
            triggerTypeDrafts[role] = .shortcut
            triggerDrafts[role] = ""
            model.statusText = "Record a keyboard shortcut for \(role.rawValue)"
        case .singleTap:
            triggerTypeDrafts[role] = nil
            setOneShotType(.tap, for: role)
        case .doubleTap:
            triggerTypeDrafts[role] = nil
            setOneShotType(.doubleTap, for: role)
        }
    }

    private func triggerType(for role: InputRole) -> BindingTriggerType {
        triggerTypeDrafts[role] ?? BindingTriggerType(trigger: model.trigger(for: role))
    }

    private func setOneShotType(_ gesture: TriggerGesture, for role: InputRole) {
        let choice = OneShotModifierChoice(trigger: model.trigger(for: role))
            ?? defaultOneShotChoice(for: role)
        model.setOneShotBinding(
            keyCode: choice.keyCode,
            keyName: choice.rawValue,
            gesture: gesture,
            for: role
        )
        resetDrafts()
    }

    private func defaultOneShotChoice(for role: InputRole) -> OneShotModifierChoice {
        switch role {
        case .english:
            .leftCommand
        case .chinese:
            .rightCommand
        case .japanese:
            .leftOption
        }
    }
}

private enum BindingTriggerType: Hashable {
    case shortcut
    case singleTap
    case doubleTap

    init(trigger: KeyTrigger?) {
        guard let trigger else {
            self = .shortcut
            return
        }

        switch (trigger.kind, trigger.gesture) {
        case (.oneShotModifier, .doubleTap):
            self = .doubleTap
        case (.oneShotModifier, .tap):
            self = .singleTap
        case (.keyPress, _):
            self = .shortcut
        }
    }

    var gesture: TriggerGesture? {
        switch self {
        case .shortcut:
            return nil
        case .singleTap:
            return .tap
        case .doubleTap:
            return .doubleTap
        }
    }
}

private enum OneShotModifierChoice: String, CaseIterable, Identifiable, Hashable {
    case leftCommand = "left-command"
    case rightCommand = "right-command"
    case leftOption = "left-option"
    case rightOption = "right-option"
    case leftControl = "left-control"
    case rightControl = "right-control"
    case leftShift = "left-shift"
    case rightShift = "right-shift"
    case capsLock = "caps-lock"

    var id: String {
        rawValue
    }

    init?(trigger: KeyTrigger?) {
        guard let trigger, trigger.kind == .oneShotModifier else {
            return nil
        }
        self.init(rawValue: trigger.keyName)
    }

    var title: String {
        switch self {
        case .leftCommand:
            "Left Command"
        case .rightCommand:
            "Right Command"
        case .leftOption:
            "Left Option"
        case .rightOption:
            "Right Option"
        case .leftControl:
            "Left Control"
        case .rightControl:
            "Right Control"
        case .leftShift:
            "Left Shift"
        case .rightShift:
            "Right Shift"
        case .capsLock:
            "Caps Lock"
        }
    }

    var iconName: String {
        switch self {
        case .leftCommand, .rightCommand:
            "command"
        case .leftOption, .rightOption:
            "option"
        case .leftControl, .rightControl:
            "control"
        case .leftShift, .rightShift:
            "shift"
        case .capsLock:
            "capslock"
        }
    }

    var keyCode: Int {
        switch self {
        case .leftCommand:
            55
        case .rightCommand:
            54
        case .leftOption:
            58
        case .rightOption:
            61
        case .leftControl:
            59
        case .rightControl:
            62
        case .leftShift:
            56
        case .rightShift:
            60
        case .capsLock:
            57
        }
    }
}
