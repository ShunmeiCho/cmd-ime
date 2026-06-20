import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var triggerDrafts: [InputRole: String] = [:]
    @State private var triggerTypeDrafts: [InputRole: BindingTriggerType] = [:]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                SettingsHeader(status: runtimeStatus, onPrimaryAction: performHeaderAction, onRefresh: refreshMethods)
                PermissionsCard(model: model, status: runtimeStatus)
                SwitchSlotsSection(
                    model: model,
                    triggerDrafts: $triggerDrafts,
                    triggerTypeDrafts: $triggerTypeDrafts,
                    resetDrafts: resetDrafts
                )
                CompactLiveKeysStrip(model: model)

                HStack(alignment: .top, spacing: 14) {
                    IndicatorSettingsCard(model: model)
                        .frame(maxWidth: .infinity)
                    RuntimeSection(model: model)
                        .frame(width: 286)
                }
            }
            .padding(22)
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DesignTokens.Colors.canvas)
        .preferredColorScheme(.dark)
        .onAppear {
            resetDrafts()
        }
    }

    private var runtimeStatus: RuntimeStatusPresentation {
        RuntimeStatusPresentation(model: model)
    }

    private func performHeaderAction() {
        if model.permissions.isReady && model.sources.isEmpty {
            refreshMethods()
        } else if model.isListening {
            model.stopListening()
        } else if model.permissions.isReady {
            model.startListeningIfReady()
        } else {
            model.requestPermissions()
        }
    }

    private func refreshMethods() {
        model.scan()
        resetDrafts()
    }

    private func resetDrafts() {
        triggerDrafts = Dictionary(
            uniqueKeysWithValues: InputRole.allCases.map { ($0, model.bindingText(for: $0)) }
        )
        triggerTypeDrafts.removeAll()
    }
}

private enum SettingsLayout {
    static let bottomCardMinHeight: CGFloat = 386
}

@MainActor
private struct RuntimeStatusPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let tone: StatusPill.Tone
    let primaryActionTitle: String
    let primaryActionProminent: Bool

    init(model: AppModel) {
        if model.permissions.isReady && model.sources.isEmpty {
            title = "No Input Sources"
            detail = "No input methods are available. Refresh methods or add an input source in System Settings."
            systemImage = "keyboard.badge.ellipsis"
            tone = .warning
            primaryActionTitle = "Refresh Methods"
            primaryActionProminent = true
        } else if model.isListening {
            title = "Active"
            detail = "Listening for your configured shortcuts."
            systemImage = "checkmark.circle.fill"
            tone = .success
            primaryActionTitle = "Pause"
            primaryActionProminent = false
        } else if !model.permissions.isReady {
            title = "Needs Permission"
            detail = "Grant Accessibility and Input Monitoring to enable global shortcuts."
            systemImage = "exclamationmark.triangle.fill"
            tone = .warning
            primaryActionTitle = "Request Permissions"
            primaryActionProminent = true
        } else if model.keyboardControlStatus == "Failed" {
            title = "Listener Failed"
            detail = "Keyboard listener could not start. Re-grant permissions, then try again."
            systemImage = "xmark.octagon.fill"
            tone = .danger
            primaryActionTitle = "Retry"
            primaryActionProminent = true
        } else {
            title = "Paused"
            detail = "Shortcuts are not being captured."
            systemImage = "pause.circle.fill"
            tone = .neutral
            primaryActionTitle = "Resume"
            primaryActionProminent = true
        }
    }
}

private struct SettingsHeader: View {
    let status: RuntimeStatusPresentation
    let onPrimaryAction: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            KeycapView("⌘")
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("CmdIME")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("A precision instrument for input switching")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 8) {
                StatusPill(text: status.title, systemImage: status.systemImage, tone: status.tone)

                HStack(spacing: 8) {
                    Button(status.primaryActionTitle, action: onPrimaryAction)
                        .buttonStyle(ConsoleButtonStyle(prominent: status.primaryActionProminent))
                    Button("Refresh Methods", action: onRefresh)
                        .buttonStyle(ConsoleButtonStyle())
                }
            }
        }
    }
}

private struct PermissionsCard: View {
    @ObservedObject var model: AppModel
    let status: RuntimeStatusPresentation

    var body: some View {
        CompactSection(title: "Keyboard control") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(status.detail)
                        .font(.callout)
                        .foregroundStyle(DesignTokens.Colors.textSecondary)
                        .lineLimit(2)
                    Spacer()
                    if !model.permissions.isReady {
                        Button("Request Permissions") {
                            model.requestPermissions()
                        }
                        .buttonStyle(ConsoleButtonStyle(prominent: true))
                    }
                }

                HStack(spacing: 10) {
                    PermissionMiniStatus(
                        title: "Accessibility",
                        granted: model.permissions.accessibilityGranted,
                        actionTitle: "Open",
                        action: model.openAccessibilitySettings
                    )

                    PermissionMiniStatus(
                        title: "Input Monitoring",
                        granted: model.permissions.inputMonitoringGranted,
                        actionTitle: "Open",
                        action: model.openInputMonitoringSettings
                    )
                }
            }
        }
    }
}

private struct PermissionMiniStatus: View {
    let title: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.caption.weight(.bold))
                .foregroundStyle(granted ? DesignTokens.Colors.success : DesignTokens.Colors.warning)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            if granted {
                Text("Ready")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.success)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(ConsoleButtonStyle())
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(granted ? "ready" : "missing")")
    }
}

private struct SwitchSlotsSection: View {
    @ObservedObject var model: AppModel
    @Binding var triggerDrafts: [InputRole: String]
    @Binding var triggerTypeDrafts: [InputRole: BindingTriggerType]
    let resetDrafts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Switch slots")
                Spacer()
                Button("Reset to Detected") {
                    model.initializeFromScan()
                    resetDrafts()
                }
                .buttonStyle(ConsoleButtonStyle())
            }

            VStack(spacing: 9) {
                ForEach(InputRole.allCases, id: \.self) { role in
                    switchSlotCard(for: role)
                }
            }
        }
    }

    private func switchSlotCard(for role: InputRole) -> some View {
        let source = model.matchedSource(for: role)
        let presentation = InputSourcePresentation(source: source, fallbackRole: role)
        let duplicate = hasDuplicateSource(source, for: role)

        return SwitchSlotCard(
            role: role,
            presentation: presentation,
            source: source,
            isActive: model.activeRole == role,
            isDuplicate: duplicate,
            triggerText: model.bindingText(for: role),
            sourceStatus: sourceStatus(source, for: role),
            bindingWarning: model.oneShotConflictWarning(for: role),
            onTest: { model.switchRole(role) },
            onFix: {
                model.initializeFromScan()
                resetDrafts()
            }
        ) {
            triggerTypePicker(for: role)
        } triggerControl: {
            triggerControl(for: role)
        } inputSourceControl: {
            inputSourcePicker(for: role, source: source)
        }
    }

    private func triggerTypePicker(for role: InputRole) -> some View {
        ConsoleSegmentedControl(
            options: BindingTriggerType.allCases.map { ConsoleSegmentOption(value: $0, label: $0.displayName) },
            selection: Binding(
                get: { triggerType(for: role) },
                set: { setTriggerType($0, for: role) }
            )
        )
        .frame(width: 158)
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
            .frame(width: 88, height: DesignTokens.Layout.fieldHeight)
        case .singleTap, .doubleTap:
            let selected = OneShotModifierChoice(trigger: model.trigger(for: role))
                ?? defaultOneShotChoice(for: role)
            Menu {
                ForEach(OneShotModifierChoice.allCases) { choice in
                    let conflictRole = model.oneShotConflictRole(
                        forKeyCode: choice.keyCode,
                        keyName: choice.rawValue,
                        excluding: role
                    )
                    Button {
                        let gesture = triggerType(for: role).gesture ?? .tap
                        model.setOneShotBinding(
                            keyCode: choice.keyCode,
                            keyName: choice.rawValue,
                            gesture: gesture,
                            for: role
                        )
                        resetDrafts()
                    } label: {
                        Label(
                            conflictRole.map { "\(choice.title) - used by \($0.displayName)" } ?? choice.title,
                            systemImage: choice.iconName
                        )
                    }
                    .disabled(conflictRole != nil)
                }
            } label: {
                OneShotMenuLabel(choice: selected, role: role)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 126)
        }
    }

    private func inputSourcePicker(for role: InputRole, source: InputSourceInfo?) -> some View {
        Menu {
            if source == nil {
                Button("Not matched") {}
                    .disabled(true)
            }
            ForEach(model.selectableSources, id: \.id) { candidate in
                Button(candidate.localizedName) {
                    model.setInputSourceID(candidate.id, for: role)
                }
            }
        } label: {
            Text("Change")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textMuted)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
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

private struct SwitchSlotCard<TriggerTypeControl: View, TriggerControl: View, InputSourceControl: View>: View {
    let role: InputRole
    let presentation: InputSourcePresentation
    let source: InputSourceInfo?
    let isActive: Bool
    let isDuplicate: Bool
    let triggerText: String
    let sourceStatus: String
    let bindingWarning: String?
    let onTest: () -> Void
    let onFix: () -> Void
    @ViewBuilder let triggerTypeControl: () -> TriggerTypeControl
    @ViewBuilder let triggerControl: () -> TriggerControl
    @ViewBuilder let inputSourceControl: () -> InputSourceControl

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoleBadge(role: role, symbol: presentation.symbol, size: 31, isActive: isActive)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(role.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    statusChip
                }

                if source == nil {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                        Text("Not matched")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(DesignTokens.Colors.warning)
                } else {
                    HStack(spacing: 6) {
                        Text(presentation.detail)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                        inputSourceControl()
                    }
                }

                if let bindingWarning {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                        Text(bindingWarning)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .foregroundStyle(DesignTokens.Colors.warning)
                }
            }
            .frame(width: 210, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if source == nil {
                    TriggerKeycapSequence(role: role, triggerText: triggerText, isActive: isActive)
                        .frame(width: 92, alignment: .leading)
                    Text(sourceStatus)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    Button("Fix", action: onFix)
                        .buttonStyle(ConsoleButtonStyle(prominent: true))
                        .frame(width: 58)
                } else {
                    triggerTypeControl()
                        .frame(width: 158)
                    triggerControl()
                        .frame(width: 126, alignment: .center)
                    Button("Test", action: onTest)
                        .buttonStyle(ConsoleButtonStyle())
                        .frame(width: 58)
                }
            }
            .frame(width: 362, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(slotStrokeColor, lineWidth: isActive ? 1.4 : 1)
                )
                .shadow(color: isActive ? DesignTokens.Colors.role(role).opacity(0.26) : .clear, radius: 14, y: 5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(role.displayName) switch slot")
        .accessibilityValue(isActive ? "Current" : (source == nil ? "Not matched" : "Configured"))
    }

    @ViewBuilder
    private var statusChip: some View {
        if bindingWarning != nil {
            Text("Conflict")
                .slotChip(color: DesignTokens.Colors.warning)
        } else if isActive {
            Text("Current")
                .slotChip(color: DesignTokens.Colors.role(role))
        } else if isDuplicate {
            Text("Duplicate")
                .slotChip(color: DesignTokens.Colors.warning)
        }
    }

    private var slotStrokeColor: Color {
        if isActive {
            return DesignTokens.Colors.role(role).opacity(0.74)
        }
        if source == nil || isDuplicate || bindingWarning != nil {
            return DesignTokens.Colors.warning.opacity(0.35)
        }
        return DesignTokens.Colors.role(role).opacity(0.22)
    }
}

private struct TriggerKeycapSequence: View {
    let role: InputRole
    let triggerText: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keycaps.enumerated()), id: \.offset) { index, keycap in
                if index > 0 {
                    Text("+")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
                KeycapView(keycap.label, detail: keycap.detail, role: role, isPressed: isActive)
                    .font(.caption)
            }
        }
    }

    private var keycaps: [LiveKeycap] {
        if triggerText.isEmpty {
            return [LiveKeycap(label: role.defaultSymbol, detail: nil)]
        }

        let parts = triggerText.split(separator: "+").map { String($0) }
        if parts.count == 1 {
            return [LiveKeycap(keyName: parts[0])]
        }
        return parts.map { LiveKeycap(keyName: $0) }
    }
}

private struct OneShotMenuLabel: View {
    let choice: OneShotModifierChoice
    let role: InputRole

    var body: some View {
        HStack(spacing: 6) {
            Text(choice.shortTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            Text(choice.keycapLabel)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(DesignTokens.Colors.role(role))
        }
        .padding(.horizontal, 8)
        .frame(width: 116, height: 26)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.keycapTop, DesignTokens.Colors.keycapBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                        .stroke(DesignTokens.Colors.role(role).opacity(0.42), lineWidth: 1)
                )
        )
        .shadow(color: DesignTokens.Shadow.keycap, radius: 4, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.title)
    }
}

private struct CompactLiveKeysStrip: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Live keys")
                Spacer()
                Text("Press a bound key - it lights up and switches")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }

            HStack(spacing: 6) {
                LiveStripKey("⌃")
                LiveStripKey("⌥", role: .japanese, isActive: model.activeRole == .japanese)
                LiveStripKey("⌘", role: .english, detail: "L", isActive: model.activeRole == .english)
                LiveStripKey("space")
                    .frame(maxWidth: .infinity)
                LiveStripKey("⌘", role: .chinese, detail: "R", isActive: model.activeRole == .chinese)
                LiveStripKey("⌥")
                LiveStripKey("⌃")
            }
        }
    }
}

private struct LiveStripKey: View {
    let label: String
    let role: InputRole?
    let detail: String?
    let isActive: Bool

    init(_ label: String, role: InputRole? = nil, detail: String? = nil, isActive: Bool = false) {
        self.label = label
        self.role = role
        self.detail = detail
        self.isActive = isActive
    }

    var body: some View {
        if label == "space" {
            Text("space")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .frame(maxWidth: .infinity, minHeight: 34)
                .background(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [DesignTokens.Colors.keycapTop, DesignTokens.Colors.keycapBottom],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                                .stroke(DesignTokens.Colors.separatorStrong, lineWidth: 1)
                        )
                )
                .shadow(color: DesignTokens.Shadow.keycap, radius: 4, y: 3)
                .accessibilityLabel("Space key")
        } else {
            KeycapView(label, detail: detail, role: role, isPressed: isActive, isBound: role != nil)
                .frame(minWidth: 46, minHeight: 34)
        }
    }
}

private struct IndicatorSettingsCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        CompactSection(title: "Switch indicator", minHeight: SettingsLayout.bottomCardMinHeight) {
            VStack(alignment: .leading, spacing: 10) {
                CompactSettingRow("Enabled") {
                    Toggle(
                        "Show switch indicator",
                        isOn: Binding(
                            get: { model.config.showSwitchIndicator },
                            set: { model.setSwitchIndicatorVisible($0) }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.success)
                    .controlSize(.small)
                    Spacer()
                }

                IndicatorPreview(model: model)
                    .opacity(model.config.showSwitchIndicator ? 1 : 0.45)

                Text("Appears near the focused caret after each switch.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)

                CompactSettingRow("Display") {
                    ConsoleSegmentedControl(
                        options: SwitchIndicatorContentStyle.allCases.map {
                            ConsoleSegmentOption(value: $0, label: $0.displayName)
                        },
                        selection: Binding(
                            get: { model.config.switchIndicatorContentStyle },
                            set: { model.setSwitchIndicatorContentStyle($0) }
                        )
                    )
                    .frame(width: 202)
                }

                CompactSettingRow("Size") {
                    ConsoleSegmentedControl(
                        options: SwitchIndicatorSize.allCases.map {
                            ConsoleSegmentOption(value: $0, label: $0.displayName)
                        },
                        selection: Binding(
                            get: { model.config.switchIndicatorSize },
                            set: { model.setSwitchIndicatorSize($0) }
                        )
                    )
                    .frame(width: 160)
                }

                CompactSettingRow("Scale \(Int((model.config.switchIndicatorScale * 100).rounded()))%") {
                    Slider(
                        value: Binding(
                            get: { model.config.switchIndicatorScale },
                            set: { model.setSwitchIndicatorScale($0) }
                        ),
                        in: SwitcherConfig.minSwitchIndicatorScale...SwitcherConfig.maxSwitchIndicatorScale,
                        step: 0.05
                    )
                    Button("Reset") {
                        model.setSwitchIndicatorScale(SwitcherConfig.defaultSwitchIndicatorScale)
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }

                CompactSettingRow("Color") {
                    IndicatorColorSwatches(
                        selection: Binding(
                            get: { model.config.switchIndicatorColorStyle },
                            set: { model.setSwitchIndicatorColorStyle($0) }
                        ),
                        customColor: Color(
                            cmdIMEHex: model.config.switchIndicatorCustomColorHex(for: model.activeRole ?? .english)
                        ) ?? DesignTokens.Colors.role(model.activeRole ?? .english)
                    )

                    Text(model.config.switchIndicatorColorStyle.settingDescription)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }

                if model.config.switchIndicatorColorStyle == .custom {
                    CompactSettingRow("Custom") {
                        CustomRoleColorControls(model: model)
                    }
                }
            }
        }
    }
}

private struct CustomRoleColorControls: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(InputRole.allCases, id: \.self) { role in
                VStack(alignment: .leading, spacing: 4) {
                    Text(role.displayName)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .lineLimit(1)

                    ColorPicker(
                        role.displayName,
                        selection: Binding(
                            get: {
                                Color(cmdIMEHex: model.config.switchIndicatorCustomColorHex(for: role))
                                    ?? DesignTokens.Colors.role(role)
                            },
                            set: { color in
                                if let hex = color.cmdIMEHexString {
                                    model.setSwitchIndicatorCustomColorHex(hex, for: role)
                                }
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 34, height: 24)
                }
                .frame(width: 58, alignment: .leading)
            }
        }
    }
}

private struct IndicatorPreview: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let role = model.activeRole ?? .english
        let source = model.matchedSource(for: role)
        let presentation = InputSourcePresentation(source: source, fallbackRole: role)
        let tint = indicatorTint(for: role, presentation: presentation)

        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(DesignTokens.Colors.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                )

            HStack(alignment: .center, spacing: 2) {
                Text("The quick brown fox")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(DesignTokens.Colors.textSecondary.opacity(0.86))
                    .frame(width: 1.5, height: 16)
                    .shadow(color: tint.opacity(0.34), radius: 5)
            }
            .padding(.top, 14)
            .padding(.leading, 14)

            HStack(spacing: 8) {
                if model.config.switchIndicatorContentStyle != .textOnly {
                    Text(presentation.symbol)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint)
                        .frame(width: 30, height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(tint.opacity(0.18))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .stroke(tint.opacity(0.45), lineWidth: 1)
                                )
                        )
                }

                if model.config.switchIndicatorContentStyle != .iconOnly {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(presentation.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                        if model.config.switchIndicatorContentStyle == .iconAndText {
                            Text(presentation.detail)
                                .font(.caption2)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.40), radius: 14, y: 8)
            .scaleEffect(previewScale, anchor: .topLeading)
            .offset(x: 154, y: 42)
            .animation(DesignTokens.Motion.stateChange, value: model.config.switchIndicatorContentStyle)
            .animation(DesignTokens.Motion.stateChange, value: model.config.switchIndicatorSize)
            .animation(DesignTokens.Motion.stateChange, value: model.config.switchIndicatorScale)
            .animation(DesignTokens.Motion.stateChange, value: model.config.switchIndicatorColorStyle)
        }
        .frame(height: 112)
        .clipped()
    }

    private var previewScale: CGFloat {
        let sizeScale: CGFloat
        switch model.config.switchIndicatorSize {
        case .small:
            sizeScale = 0.86
        case .medium:
            sizeScale = 1.0
        case .large:
            sizeScale = 1.14
        }
        return min(sizeScale * CGFloat(model.config.switchIndicatorScale), 1.08)
    }

    private func indicatorTint(for role: InputRole, presentation: InputSourcePresentation) -> Color {
        switch model.config.switchIndicatorColorStyle {
        case .accent:
            DesignTokens.Colors.accent
        case .monochrome:
            DesignTokens.Colors.textSecondary
        case .custom:
            Color(cmdIMEHex: model.config.switchIndicatorCustomColorHex(for: role)) ?? DesignTokens.Colors.role(role)
        case .role:
            presentation.tint
        }
    }
}

private struct RuntimeSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        CompactSection(title: "Runtime", minHeight: SettingsLayout.bottomCardMinHeight) {
            VStack(alignment: .leading, spacing: 0) {
                RuntimeToggleRow(
                    title: "Launch at login",
                    isOn: Binding(
                        get: { model.loginItem.isEnabled },
                        set: { model.setLaunchAtLogin($0) }
                    ),
                    isDisabled: !model.loginItem.isAvailable
                )

                Divider().overlay(DesignTokens.Colors.separator)

                menuBarIconRow

                Divider().overlay(DesignTokens.Colors.separator)

                RuntimeActionRow(title: "Updates", detail: model.updateStatus.message) {
                    if model.updateStatus.releaseURL != nil {
                        Button("Open") {
                            model.openLatestRelease()
                        }
                        .buttonStyle(ConsoleButtonStyle())
                    }
                    Button(model.updateStatus.isChecking ? "Checking" : "Check") {
                        model.checkForUpdates()
                    }
                    .disabled(model.updateStatus.isChecking)
                    .buttonStyle(ConsoleButtonStyle())
                }

                Divider().overlay(DesignTokens.Colors.separator)

                RuntimeActionRow(title: "Quit agent", detail: "Stop the background listener") {
                    Button("Quit") {
                        model.quit()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: false))
                    .foregroundStyle(DesignTokens.Colors.danger)
                }
            }
        }
    }

    @ViewBuilder
    private var menuBarIconRow: some View {
        if model.menuBarIconSupported {
            RuntimeToggleRow(
                title: "Menu bar icon",
                isOn: Binding(
                    get: { model.config.showMenuBarIcon },
                    set: { model.setMenuBarIconVisible($0) }
                )
            )
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Menu bar icon")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    Spacer()
                    StatusPill(text: "Locked Off", systemImage: "lock.fill", tone: .warning)
                }

                Text("Locked off on macOS 26+ to avoid a known status-item issue that can freeze Settings and drive CPU usage very high.")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Reopen CmdIME.app for Settings, or use keyboardctl quit to stop the agent.")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)

                Button("Copy Quit Command") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString("keyboardctl quit", forType: .string)
                    model.statusText = "Copied keyboardctl quit"
                }
                .buttonStyle(ConsoleButtonStyle())
            }
            .padding(.vertical, 8)
        }
    }
}

private struct RuntimeToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    var isDisabled = false

    var body: some View {
        HStack {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            Spacer()
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
                .disabled(isDisabled)
        }
        .padding(.vertical, 8)
    }
}

private struct RuntimeActionRow<Action: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let action: () -> Action

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .lineLimit(2)
            }
            Spacer()
            action()
        }
        .padding(.vertical, 8)
    }
}

private struct CompactSection<Content: View>: View {
    let title: String
    var minHeight: CGFloat?
    @ViewBuilder let content: () -> Content

    init(title: String, minHeight: CGFloat? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.minHeight = minHeight
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(title)
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                )
        )
    }
}

private struct CompactSettingRow<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    init(_ title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
                .frame(width: 76, alignment: .leading)
            content()
        }
    }
}

private struct ConsoleSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value {
        value
    }
}

private struct ConsoleSegmentedControl<Value: Hashable>: View {
    let options: [ConsoleSegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(selection == option.value ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textMuted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.82)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selection == option.value ? Color.white.opacity(0.12) : .clear)
                )

                if index < options.count - 1 {
                    Rectangle()
                        .fill(DesignTokens.Colors.separatorStrong)
                        .frame(width: 1, height: 14)
                        .opacity(selection == option.value || selection == options[index + 1].value ? 0 : 1)
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.Colors.surfaceInset)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
    }
}

private struct IndicatorColorSwatches: View {
    @Binding var selection: SwitchIndicatorColorStyle
    let customColor: Color

    var body: some View {
        HStack(spacing: 7) {
            ForEach(SwitchIndicatorColorStyle.allCases) { style in
                Button {
                    selection = style
                } label: {
                    swatch(for: style)
                        .frame(width: 22, height: 22)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(borderColor(for: style), lineWidth: selection == style ? 2 : 1)
                        )
                        .shadow(color: selection == style ? borderColor(for: style).opacity(0.34) : .clear, radius: 6)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.displayName)
                .accessibilityValue(selection == style ? "Selected" : "Not selected")
            }
        }
    }

    @ViewBuilder
    private func swatch(for style: SwitchIndicatorColorStyle) -> some View {
        switch style {
        case .role:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DesignTokens.Colors.role(.english),
                            DesignTokens.Colors.role(.chinese),
                            DesignTokens.Colors.role(.japanese)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .accent:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.Colors.accent)
        case .monochrome:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.80), Color.white.opacity(0.42)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        case .custom:
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(customColor)
        }
    }

    private func borderColor(for style: SwitchIndicatorColorStyle) -> Color {
        if selection == style {
            switch style {
            case .role:
                return DesignTokens.Colors.success
            case .accent:
                return DesignTokens.Colors.accent
            case .monochrome:
                return DesignTokens.Colors.textSecondary
            case .custom:
                return customColor
            }
        }
        return DesignTokens.Colors.separatorStrong
    }
}

private struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption2.weight(.bold))
            .monospaced()
            .tracking(2.2)
            .foregroundStyle(DesignTokens.Colors.textMuted)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct LiveKeycap {
    let label: String
    let detail: String?

    init(label: String, detail: String?) {
        self.label = label
        self.detail = detail
    }

    init(keyName: String) {
        switch keyName {
        case "command", "left-command":
            label = "⌘"
            detail = keyName == "left-command" ? "L" : nil
        case "right-command":
            label = "⌘"
            detail = "R"
        case "option", "left-option":
            label = "⌥"
            detail = keyName == "left-option" ? "L" : nil
        case "right-option":
            label = "⌥"
            detail = "R"
        case "control", "left-control":
            label = "⌃"
            detail = keyName == "left-control" ? "L" : nil
        case "right-control":
            label = "⌃"
            detail = "R"
        case "shift", "left-shift":
            label = "⇧"
            detail = keyName == "left-shift" ? "L" : nil
        case "right-shift":
            label = "⇧"
            detail = "R"
        default:
            label = keyName.uppercased()
            detail = nil
        }
    }
}

private extension Text {
    func slotChip(color: Color) -> some View {
        self
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }
}

private enum BindingTriggerType: CaseIterable, Hashable {
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

    var displayName: String {
        switch self {
        case .shortcut:
            "Shortcut"
        case .singleTap:
            "Single"
        case .doubleTap:
            "Double"
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

    var shortTitle: String {
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

    var keycapLabel: String {
        switch self {
        case .leftCommand, .rightCommand:
            "⌘"
        case .leftOption, .rightOption:
            "⌥"
        case .leftControl, .rightControl:
            "⌃"
        case .leftShift, .rightShift:
            "⇧"
        }
    }

    var keycapDetail: String {
        switch self {
        case .leftCommand, .leftOption, .leftControl, .leftShift:
            "L"
        case .rightCommand, .rightOption, .rightControl, .rightShift:
            "R"
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

private extension SwitchIndicatorColorStyle {
    var settingDescription: String {
        switch self {
        case .role:
            "Follows active slot"
        case .accent:
            "Accent blue"
        case .monochrome:
            "Neutral gray"
        case .custom:
            "Custom color"
        }
    }
}
