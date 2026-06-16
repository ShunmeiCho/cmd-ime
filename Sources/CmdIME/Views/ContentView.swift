import KeyboardSwitcherCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var triggerDrafts: [InputRole: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Divider()

            inputSourcesSection

            Divider()

            bindingsSection

            Divider()

            runtimeSection

            Spacer(minLength: 0)
        }
        .padding(24)
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
            .frame(width: 156)

            Button {
                model.toggleListening()
            } label: { Text(model.isListening ? "Pause" : "Resume") }
            .frame(width: 86)
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
                .frame(width: 158)
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
                .frame(width: 112, alignment: .leading)
            Text("Matched Source")
                .frame(width: 280, alignment: .leading)
            Text("Languages")
                .frame(width: 170, alignment: .leading)
            Spacer(minLength: 0)
            Text("")
                .frame(width: 78)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
    }

    private func inputSourceRow(for role: InputRole, source: InputSourceInfo?) -> some View {
        HStack(spacing: 12) {
            Text(roleTitle(for: role))
                .frame(width: 112, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(source?.localizedName ?? "Not matched")
                    .lineLimit(1)
                Text(source?.id ?? "Run Scan or Auto Setup")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(width: 280, alignment: .leading)

            Text(source?.displayLanguages ?? "")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 170, alignment: .leading)

            Spacer(minLength: 0)

            Button("Switch") {
                model.switchRole(role)
            }
            .frame(width: 78)
        }
        .frame(height: 46)
    }

    private var bindingsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Bindings")
                .font(.headline)

            ForEach(InputRole.allCases, id: \.self) { role in
                HStack(spacing: 12) {
                    Text(roleTitle(for: role))
                        .frame(width: 120, alignment: .leading)

                    Picker(
                        "Trigger type",
                        selection: Binding(
                            get: { BindingTriggerType(trigger: model.trigger(for: role)) },
                            set: { setTriggerType($0, for: role) }
                        )
                    ) {
                        Text("Shortcut").tag(BindingTriggerType.shortcut)
                        Text("Single tap").tag(BindingTriggerType.singleTap)
                        Text("Double tap").tag(BindingTriggerType.doubleTap)
                    }
                    .labelsHidden()
                    .frame(width: 138)

                    switch BindingTriggerType(trigger: model.trigger(for: role)) {
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
                        .frame(height: 28)
                    case .singleTap, .doubleTap:
                        Picker(
                            "Modifier key",
                            selection: Binding(
                                get: {
                                    OneShotModifierChoice(trigger: model.trigger(for: role))
                                        ?? defaultOneShotChoice(for: role)
                                },
                                set: { choice in
                                    let gesture = BindingTriggerType(trigger: model.trigger(for: role)).gesture ?? .tap
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
                        .frame(width: 220)

                        Text(model.bindingText(for: role))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
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

            Toggle(
                "Start at login",
                isOn: Binding(
                    get: { model.loginItem.isEnabled },
                    set: { model.setLaunchAtLogin($0) }
                )
            )
            .disabled(!model.loginItem.isAvailable)

            HStack {
                Text("Keyboard control")
                    .frame(width: 120, alignment: .leading)
                Text(model.keyboardControlStatus)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(model.isListening ? "Pause" : "Resume") {
                    model.toggleListening()
                }
            }

            HStack {
                Text("Permissions")
                    .frame(width: 120, alignment: .leading)
                Text(model.permissions.isReady ? "Ready" : "Input Monitoring or Accessibility missing")
                    .foregroundStyle(model.permissions.isReady ? Color.secondary : Color.orange)
                Spacer()
                Button("Request Permissions") {
                    model.requestPermissions()
                }
            }

            HStack {
                Text("Application")
                    .frame(width: 120, alignment: .leading)
                Text("Stop the listener and quit the background agent")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Quit CmdIME") {
                    model.quit()
                }
                .frame(width: 100)
            }
        }
    }

    private func resetDrafts() {
        triggerDrafts = Dictionary(
            uniqueKeysWithValues: InputRole.allCases.map { ($0, model.bindingText(for: $0)) }
        )
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
            if model.trigger(for: role)?.kind == .oneShotModifier {
                model.statusText = "Record a keyboard shortcut for \(role.rawValue)"
            }
        case .singleTap:
            setOneShotType(.tap, for: role)
        case .doubleTap:
            setOneShotType(.doubleTap, for: role)
        }
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
