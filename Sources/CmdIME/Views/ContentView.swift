import KeyboardSwitcherCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var triggerDrafts: [InputRole: String] = [:]
    @State private var triggerTypeDrafts: [InputRole: BindingTriggerType] = [:]

    fileprivate enum Metrics {
        static let contentMaxWidth: CGFloat = 680
        static let labelColumn: CGFloat = 128
        static let ruleNameColumn: CGFloat = 92
        static let ruleLabelColumn: CGFloat = 76
        static let ruleControl: CGFloat = 226
        static let triggerPicker: CGFloat = 136
        static let actionButton: CGFloat = 150
        static let compactButton: CGFloat = 88
        static let segmentedControl: CGFloat = 320
        static let rowHeight: CGFloat = 44
        static let fieldHeight: CGFloat = 28
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                GroupBox {
                    switchRulesSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                GroupBox {
                    runtimeSection
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(20)
            .frame(maxWidth: Metrics.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
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
            } label: { Text("Reset to detected") }
            .frame(width: Metrics.actionButton)

            Button {
                model.toggleListening()
            } label: { Text(model.isListening ? "Pause" : "Resume") }
            .frame(width: Metrics.compactButton)
            .buttonStyle(.borderedProminent)
        }
    }

    private var switchRulesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switch slots")
                        .font(.headline)
                    Text("Three switch slots are available. Pick the key and input method for each slot.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Refresh methods") {
                    model.scan()
                }
                .frame(width: 140)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(InputRole.allCases, id: \.self) { role in
                    switchRuleRow(for: role)
                    if role != InputRole.allCases.last {
                        Divider()
                    }
                }
            }
        }
    }

    private func switchRuleRow(for role: InputRole) -> some View {
        let source = model.matchedSource(for: role)
        let presentation = InputSourcePresentation(source: source, fallbackRole: role)

        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(presentation.tint, in: RoundedRectangle(cornerRadius: 7))

                Text(presentation.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)

                if source != nil, presentation.detail != presentation.title {
                    Text(presentation.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(width: Metrics.ruleNameColumn, alignment: .leading)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Text("Key")
                        .ruleLabel()

                    triggerTypePicker(for: role)

                    triggerControl(for: role)
                }

                HStack(spacing: 10) {
                    Text("Input method")
                        .ruleLabel()

                    inputSourcePicker(for: role, source: source)

                    Button("Test") {
                        model.switchRole(role)
                    }
                    .frame(width: Metrics.compactButton)
                }

                Text(sourceStatus(source, for: role))
                    .font(.caption)
                    .foregroundStyle(hasDuplicateSource(source, for: role) ? Color.orange : Color.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
    }

    private func triggerTypePicker(for role: InputRole) -> some View {
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
    }

    @ViewBuilder
    private func triggerControl(for role: InputRole) -> some View {
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
            .frame(width: Metrics.ruleControl, height: Metrics.fieldHeight)
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
            .frame(width: Metrics.ruleControl)
        }
    }

    private func inputSourcePicker(for role: InputRole, source: InputSourceInfo?) -> some View {
        Picker(
            "Input method",
            selection: Binding(
                get: { source?.id ?? "" },
                set: { model.setInputSourceID($0, for: role) }
            )
        ) {
            if source == nil {
                Text("Not matched").tag("")
            }
            ForEach(model.selectableSources, id: \.id) { candidate in
                Text(candidate.localizedName).tag(candidate.id)
            }
        }
        .labelsHidden()
        .frame(width: Metrics.ruleControl)
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
                "Show switch indicator",
                isOn: Binding(
                    get: { model.config.showSwitchIndicator },
                    set: { model.setSwitchIndicatorVisible($0) }
                )
            )

            if model.config.showSwitchIndicator {
                HStack {
                    Text("Indicator display")
                        .frame(width: Metrics.labelColumn, alignment: .leading)
                    Picker(
                        "Indicator display",
                        selection: Binding(
                            get: { model.config.switchIndicatorContentStyle },
                            set: { model.setSwitchIndicatorContentStyle($0) }
                        )
                    ) {
                        ForEach(SwitchIndicatorContentStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: Metrics.segmentedControl)
                    Spacer()
                }

                HStack {
                    Text("Indicator size")
                        .frame(width: Metrics.labelColumn, alignment: .leading)
                    Picker(
                        "Indicator size",
                        selection: Binding(
                            get: { model.config.switchIndicatorSize },
                            set: { model.setSwitchIndicatorSize($0) }
                        )
                    ) {
                        ForEach(SwitchIndicatorSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: Metrics.segmentedControl)
                    Spacer()
                }

                HStack {
                    Text("Indicator scale")
                        .frame(width: Metrics.labelColumn, alignment: .leading)
                    Slider(
                        value: Binding(
                            get: { model.config.switchIndicatorScale },
                            set: { model.setSwitchIndicatorScale($0) }
                        ),
                        in: SwitcherConfig.minSwitchIndicatorScale...SwitcherConfig.maxSwitchIndicatorScale,
                        step: 0.05
                    )
                    .frame(width: 220)
                    Text("\(Int((model.config.switchIndicatorScale * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                    Button("Reset") {
                        model.setSwitchIndicatorScale(SwitcherConfig.defaultSwitchIndicatorScale)
                    }
                    .frame(width: 72)
                    Spacer()
                }

                HStack {
                    Text("Indicator color")
                        .frame(width: Metrics.labelColumn, alignment: .leading)
                    Picker(
                        "Indicator color",
                        selection: Binding(
                            get: { model.config.switchIndicatorColorStyle },
                            set: { model.setSwitchIndicatorColorStyle($0) }
                        )
                    ) {
                        ForEach(SwitchIndicatorColorStyle.allCases) { style in
                            Text(style.displayName).tag(style)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: Metrics.segmentedControl)
                    Spacer()
                }

                if model.config.switchIndicatorColorStyle == .custom {
                    HStack {
                        Text("Custom color")
                            .frame(width: Metrics.labelColumn, alignment: .leading)
                        ColorPicker(
                            "Custom color",
                            selection: Binding(
                                get: {
                                    Color(cmdIMEHex: model.config.switchIndicatorCustomColorHex) ?? .accentColor
                                },
                                set: { color in
                                    if let hex = color.cmdIMEHexString {
                                        model.setSwitchIndicatorCustomColorHex(hex)
                                    }
                                }
                            ),
                            supportsOpacity: false
                        )
                        .labelsHidden()
                        Text(model.config.switchIndicatorCustomColorHex)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }

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

    private func sourceStatus(_ source: InputSourceInfo?, for role: InputRole) -> String {
        guard let source else {
            return "Choose an input method for this slot."
        }

        if hasDuplicateSource(source, for: role) {
            return "\(source.localizedName) is already used by another slot."
        }

        return "This slot activates \(source.localizedName)."
    }

    private func hasDuplicateSource(_ source: InputSourceInfo?, for role: InputRole) -> Bool {
        guard let source else {
            return false
        }

        return InputRole.allCases.contains { otherRole in
            otherRole != role && model.matchedSource(for: otherRole)?.id == source.id
        }
    }

    private func setTriggerType(_ type: BindingTriggerType, for role: InputRole) {
        switch type {
        case .shortcut:
            triggerTypeDrafts[role] = .shortcut
            triggerDrafts[role] = ""
            model.statusText = "Record a keyboard shortcut for this slot"
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

private extension Text {
    func ruleLabel() -> some View {
        self
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .frame(width: ContentView.Metrics.ruleLabelColumn, alignment: .leading)
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
        }
    }
}
