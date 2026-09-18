import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var triggerDrafts: [InputRole: String] = [:]
    @State private var triggerTypeDrafts: [InputRole: BindingTriggerType] = [:]
    @State private var setupSession = SetupGuideSession()

    var body: some View {
        ScrollViewReader { scroll in
            page(scroll: scroll)
                .environment(\.setupFolds, SetupFolds(session: $setupSession, isActive: !model.config.hasCompletedSetup))
        }
    }

    private func page(scroll: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
                SettingsHeader(model: model, status: runtimeStatus, onPrimaryAction: performHeaderAction)
                WhatsNewNoticeBar(model: model, isSetupGuideReopened: setupSession.isReopened)
                SetupGuideCard(model: model, session: $setupSession, scroll: scroll, resetDrafts: resetDrafts)
                SlotBoardSection(
                    model: model,
                    triggerDrafts: $triggerDrafts,
                    triggerTypeDrafts: $triggerTypeDrafts,
                    resetDrafts: resetDrafts,
                    footer: AnyView(CompactLiveKeysStrip(model: model).setupFold(.liveKeys))
                )
                .setupFold(.slotBoard)

                IndicatorSettingsCard(model: model)
                    .setupFold(.indicator)
                    .frame(maxWidth: .infinity)
                RuntimeSection(model: model) {
                    SetupGuideNavigation.showGuide($setupSession, model: model, scroll: scroll)
                }
                .setupFold(.runtime)
                .frame(maxWidth: .infinity)
            }
            .padding(22)
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(DesignTokens.Colors.canvas)
        .preferredColorScheme(.dark)
        .environment(\.slotLook, SlotLook(slots: model.config.slots))
        .onAppear {
            resetDrafts()
        }
    }

    private var runtimeStatus: RuntimeStatusPresentation {
        RuntimeStatusPresentation(model: model)
    }

    private func performHeaderAction() {
        if model.isListening {
            model.stopListening()
        } else if model.permissions.isReady {
            model.startListeningIfReady()
        } else {
            model.requestPermissions()
        }
    }

    private func resetDrafts() {
        triggerDrafts = Dictionary(
            model.config.slots.map { ($0.id, model.bindingText(for: $0.id)) },
            uniquingKeysWith: { first, _ in first }
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
            primaryActionTitle = model.isListening ? "Pause" : "Resume"
            primaryActionProminent = !model.isListening
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
        } else if model.didListenerFailToStart {
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
    @ObservedObject var model: AppModel
    let status: RuntimeStatusPresentation
    let onPrimaryAction: () -> Void
    @State private var showsPermissionDetails = false

    private var needsAttention: Bool {
        !model.permissions.isReady || model.keyboardControlStatus == "Failed"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack(spacing: DesignTokens.Layout.rowGap) {
                Text("CmdIME")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                StatusPill(text: status.title, systemImage: status.systemImage, tone: status.tone)
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Button {
                    showsPermissionDetails.toggle()
                } label: {
                    Label(needsAttention ? "Keyboard access needs attention" : "Keyboard access ready",
                          systemImage: needsAttention ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .font(DesignTokens.Typography.auxiliary)
                }
                .buttonStyle(ConsoleButtonStyle())
                .disabled(needsAttention)
                .help(needsAttention ? status.detail : "Show or hide keyboard permission details")
                .accessibilityValue(needsAttention || showsPermissionDetails ? "Expanded" : "Collapsed")
                Button(status.primaryActionTitle, action: onPrimaryAction)
                    .buttonStyle(ConsoleButtonStyle(prominent: status.primaryActionProminent))
                    .fixedSize(horizontal: true, vertical: false)
            }
            if needsAttention || showsPermissionDetails {
                Divider()
                if needsAttention {
                    PermissionsCard(model: model, status: status)
                        .id(SetupFoldSection.keyboardControl)
                } else {
                    PermissionsCard(model: model, status: status)
                        .setupFold(.keyboardControl)
                }
            }
        }
        .padding(DesignTokens.Layout.panelInset)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
            .fill(DesignTokens.Colors.surface))
    }
}

private struct PermissionsCard: View {
    @ObservedObject var model: AppModel
    let status: RuntimeStatusPresentation
    var body: some View { details }

    private var details: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text(status.detail)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                if !model.permissions.isReady {
                    Button("Request Permissions") {
                        model.requestPermissions()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                }
            }

            HStack(spacing: DesignTokens.Layout.panelGap) {
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

private struct PermissionMiniStatus: View {
    let title: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Layout.rowGap) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(granted ? DesignTokens.Colors.success : DesignTokens.Colors.warning)

            Text(title)
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            if granted {
                Text("Ready")
                    .font(DesignTokens.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.success)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(ConsoleButtonStyle())
            }
        }
        .padding(.vertical, DesignTokens.Layout.rowGap)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(granted ? "ready" : "missing")")
    }
}

private struct CompactLiveKeysStrip: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            Text("Live keys · Bound keys light up for the current slot")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)

            // Laid out like the bottom of a keyboard: Shift on the upper row, the
            // other modifiers around the space bar, shortcuts where the letter keys sit.
            VStack(spacing: DesignTokens.Layout.rowGap) {
                HStack(alignment: .top, spacing: DesignTokens.Layout.rowGap) {
                    modifierKey("left-shift").frame(width: Self.shiftWidth)
                    HStack(spacing: DesignTokens.Layout.rowGap) { chordKeys }
                        .frame(maxWidth: .infinity, alignment: .center)
                    modifierKey("right-shift").frame(width: Self.shiftWidth)
                }
                HStack(alignment: .top, spacing: DesignTokens.Layout.rowGap) {
                    ForEach(Self.leftModifierKeys, id: \.self) { modifierKey($0).frame(width: Self.modifierWidth) }
                    LiveStripKey("space")
                    ForEach(Self.rightModifierKeys, id: \.self) { modifierKey($0).frame(width: Self.modifierWidth) }
                }
            }
        }
    }

    private static let shiftWidth: CGFloat = 96
    private static let modifierWidth: CGFloat = 58

    private var chordKeys: some View {
        ForEach(Array(model.config.chordTriggers.enumerated()), id: \.offset) { _, entry in
            LiveStripKey(
                Self.symbols(for: entry.trigger),
                role: entry.slot,
                isActive: model.activeRole == entry.slot
            )
            .accessibilityLabel("\(model.config.displayName(for: entry.slot)), \(entry.trigger.displayName)")
        }
    }

    // Physical one-shot modifier keys, ordered like the bottom row of a keyboard.
    private static let leftModifierKeys = ["left-control", "left-option", "left-command"]
    private static let rightModifierKeys = ["right-command", "right-option", "right-control"]

    @ViewBuilder
    private func modifierKey(_ keyName: String) -> some View {
        let keycap = LiveKeycap(keyName: keyName)
        let entries = model.config.slots.flatMap { slot in
            model.config.bindings.filter {
                $0.enabled && $0.action.type == .switchInputSource && $0.action.role == slot.id
                    && $0.trigger.kind == .oneShotModifier && $0.trigger.keyName == keyName
            }.map { (slot: slot.id, trigger: $0.trigger) }
        }
        if entries.isEmpty {
            LiveStripKey(keycap.label, fillsWidth: true)
        } else {
            // Multiple bindings keep the same physical key column. Gesture text
            // distinguishes them even when their slot colors are identical.
            VStack(spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    let gesture = entry.trigger.gesture == .doubleTap ? "×2" : (entries.count > 1 ? "x1" : nil)
                    LiveStripKey(keycap.label, role: entry.slot,
                                 detail: [keycap.detail, gesture].compactMap { $0 }.joined(separator: " "),
                                 isActive: model.activeRole == entry.slot, fillsWidth: true)
                        .accessibilityLabel("\(model.config.displayName(for: entry.slot)), \(entry.trigger.displayName)")
                }
            }
        }
    }

    private static func symbols(for trigger: KeyTrigger) -> String {
        trigger.displayName.split(separator: "+").map { LiveKeycap(keyName: String($0)).label }.joined()
    }
}

/// Keeps the physical keyboard row separate from a variable number of chords.
private struct LiveKeyFlowLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        metrics(for: subviews, width: proposal.width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let metrics = metrics(for: subviews, width: bounds.width)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + metrics.origins[index].x,
                                     y: bounds.minY + metrics.origins[index].y),
                          anchor: .topLeading, proposal: ProposedViewSize(metrics.sizes[index]))
        }
    }

    private func metrics(for subviews: Subviews, width: CGFloat?) -> LiveKeyFlowMetrics {
        LiveKeyFlowMetrics(sizes: subviews.map { $0.sizeThatFits(.unspecified) },
                           availableWidth: width, spacing: spacing)
    }
}

private struct LiveKeyFlowMetrics {
    let sizes: [CGSize]
    let origins: [CGPoint]
    let size: CGSize

    init(sizes: [CGSize], availableWidth: CGFloat?, spacing: CGFloat) {
        self.sizes = sizes
        let idealWidth = sizes.reduce(0) { $0 + $1.width } + CGFloat(max(0, sizes.count - 1)) * spacing
        let proposedWidth = availableWidth.flatMap { $0.isFinite ? max(0, $0) : nil } ?? idealWidth
        // Expand before wrapping so measurement and placement use the same width.
        let width = max(proposedWidth, sizes.map(\.width).max() ?? 0)
        var origins: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0
        for item in sizes {
            if x > 0 && x + item.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            usedWidth = max(usedWidth, x + item.width)
            rowHeight = max(rowHeight, item.height)
            x += item.width + spacing
        }
        self.origins = origins
        size = CGSize(width: max(width, usedWidth), height: sizes.isEmpty ? 0 : y + rowHeight)
    }
}

private struct LiveStripKey: View {
    let label: String
    let role: InputRole?
    let detail: String?
    let isActive: Bool

    var fillsWidth = false

    init(_ label: String, role: InputRole? = nil, detail: String? = nil, isActive: Bool = false, fillsWidth: Bool = false) {
        self.fillsWidth = fillsWidth
        self.label = label
        self.role = role
        self.detail = detail
        self.isActive = isActive
    }

    var body: some View {
        KeycapView(label, detail: detail, role: role, isPressed: isActive, isBound: role != nil,
                   appearance: .display, expandsHorizontally: fillsWidth || label == "space")
            .frame(minWidth: 46, minHeight: 34)
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
                        customColor: model.previewSlot.map { slot in
                            Color(cmdIMEHex: model.config.switchIndicatorCustomColorHex(for: slot.id))
                                ?? Color(cmdIMEHex: slot.tintHex) ?? DesignTokens.Colors.accent
                        } ?? DesignTokens.Colors.accent
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
    @Environment(\.slotLook) private var slotLook
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.config.slots) { slot in
                let role = slot.id
                VStack(alignment: .leading, spacing: 4) {
                    Text(slotLook.name(for: role))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .lineLimit(1)

                    ColorPicker(
                        slotLook.name(for: role),
                        selection: Binding(
                            get: {
                                Color(cmdIMEHex: model.config.switchIndicatorCustomColorHex(for: role))
                                    ?? slotLook.tint(for: role)
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
    @Environment(\.slotLook) private var slotLook
    @ObservedObject var model: AppModel

    var body: some View {
        if let slot = model.previewSlot {
            preview(for: slot)
        }
    }

    private func preview(for slot: SwitchSlot) -> some View {
        let role = slot.id
        let source = model.matchedSource(for: role)
        let presentation = InputSourcePresentation(source: source, slot: slot)
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
            Color(cmdIMEHex: model.config.switchIndicatorCustomColorHex(for: role)) ?? slotLook.tint(for: role)
        case .role:
            presentation.tint
        }
    }
}

private struct RuntimeSection: View {
    @ObservedObject var model: AppModel
    let onShowSetupGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            SectionLabel("General")
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: DesignTokens.Layout.panelGap,
                                        alignment: .topLeading)],
                      alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
                group("Launch at login") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.loginItem.isEnabled }, set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.success)
                    .controlSize(.small)
                    .disabled(!model.loginItem.isAvailable)
                    .frame(minHeight: DesignTokens.Layout.fieldHeight, alignment: .leading)
                }
                group("Updates") {
                    HStack(spacing: DesignTokens.Layout.rowGap) {
                        if model.updateStatus.releaseURL != nil {
                            Button("Open") { model.openLatestRelease() }
                                .buttonStyle(ConsoleButtonStyle())
                        }
                        Button(model.updateStatus.isChecking ? "Checking" : "Check") {
                            model.checkForUpdates()
                        }
                        .disabled(model.updateStatus.isChecking)
                        .buttonStyle(ConsoleButtonStyle())
                    }
                    Text(model.updateStatus.message)
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                group("Setup guide") {
                    Button("Show", action: onShowSetupGuide)
                        .buttonStyle(ConsoleButtonStyle())
                        .help("Walk through the first-run steps again")
                        .accessibilityLabel("Show setup guide")
                }
                group("Quit CmdIME") {
                    Button("Quit", role: .destructive) { model.quit() }
                        .buttonStyle(ConsoleButtonStyle())
                        .help("Stop the background listener")
                        .accessibilityLabel("Quit CmdIME")
                }
            }
            Text("CmdIME keeps running after this window closes. Open CmdIME again to return here.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignTokens.Layout.panelInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
            .fill(DesignTokens.Colors.surface))
    }

    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            Text(title)
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
    }
}

struct CompactSection<Content: View>: View {
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
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(width: 76, alignment: .leading)
            content()
                .environment(\.consoleControlLabel, title)
        }
    }
}

private struct ConsoleControlLabelKey: EnvironmentKey {
    static let defaultValue = "Trigger type"
}

private extension EnvironmentValues {
    var consoleControlLabel: String {
        get { self[ConsoleControlLabelKey.self] }
        set { self[ConsoleControlLabelKey.self] = newValue }
    }
}

struct ConsoleSegmentOption<Value: Hashable>: Identifiable {
    let value: Value
    let label: String

    var id: Value {
        value
    }
}

struct ConsoleSegmentedControl<Value: Hashable>: View {
    @Environment(\.consoleControlLabel) private var groupLabel
    let options: [ConsoleSegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    selection = option.value
                } label: {
                    Text(option.label)
                        .font(DesignTokens.Typography.body.weight(.semibold))
                        .foregroundStyle(selection == option.value ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
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
        .accessibilityLabel(groupLabel)
        .accessibilityValue(options.first { $0.value == selection }?.label ?? "No selection")
    }
}

private struct IndicatorColorSwatches: View {
    @Environment(\.slotLook) private var slotLook
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
                        colors: slotLook.slots.map { slotLook.tint(for: $0.id) },
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

struct SectionLabel: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(DesignTokens.Typography.auxiliary.weight(.semibold))
            .tracking(1.4)
            .foregroundStyle(DesignTokens.Colors.textMuted)
            .accessibilityAddTraits(.isHeader)
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
