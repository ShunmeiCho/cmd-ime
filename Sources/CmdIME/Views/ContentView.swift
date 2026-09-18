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
            VStack(alignment: .leading, spacing: 14) {
                SettingsHeader(status: runtimeStatus, onPrimaryAction: performHeaderAction, onRefresh: refreshMethods)
                SetupGuideCard(model: model, session: $setupSession, scroll: scroll, resetDrafts: resetDrafts)
                PermissionsCard(model: model, status: runtimeStatus)
                    .setupFold(.keyboardControl)
                SlotBoardSection(
                    model: model,
                    triggerDrafts: $triggerDrafts,
                    triggerTypeDrafts: $triggerTypeDrafts,
                    resetDrafts: resetDrafts
                )
                .setupFold(.slotBoard)
                CompactLiveKeysStrip(model: model)
                    .setupFold(.liveKeys)

                HStack(alignment: .top, spacing: 14) {
                    IndicatorSettingsSection(model: model)
                        .setupFold(.indicator)
                        .frame(maxWidth: .infinity)
                    RuntimeSection(model: model) {
                        SetupGuideNavigation.showGuide($setupSession, model: model, scroll: scroll)
                    }
                    .setupFold(.runtime)
                    .frame(width: 286)
                }
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
            model.config.slots.map { ($0.id, model.bindingText(for: $0.id)) },
            uniquingKeysWith: { first, _ in first }
        )
        triggerTypeDrafts.removeAll()
    }
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
    let status: RuntimeStatusPresentation
    let onPrimaryAction: () -> Void
    let onRefresh: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            KeycapView("⌘", appearance: .display)
                .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("CmdIME")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text("A precision instrument for input switching")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
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
    @State private var showsDetails = false

    private var needsAttention: Bool {
        !model.permissions.isReady || model.keyboardControlStatus == "Failed"
    }

    var body: some View {
        Group {
            if needsAttention {
                CompactSection(title: "Keyboard control") { details }
            } else {
                DisclosureGroup(isExpanded: $showsDetails) {
                    details.padding(.top, 10)
                } label: {
                    Label("Keyboard access ready", systemImage: "checkmark.circle.fill")
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                .padding(12)
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
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 10) {
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

private struct PermissionMiniStatus: View {
    let title: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 9) {
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

private struct CompactLiveKeysStrip: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Live keys")
                Spacer()
                Text("Bound keys take their slot's color - the active slot's key lights up")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }

            HStack(alignment: .top, spacing: 6) {
                ForEach(Self.leftModifierKeys, id: \.self) { modifierKey($0) }
                LiveStripKey("space")
                    .frame(maxWidth: .infinity)
                ForEach(Self.rightModifierKeys, id: \.self) { modifierKey($0) }
            }

            if !model.config.chordTriggers.isEmpty {
                LiveKeyFlowLayout(spacing: 6) {
                    ForEach(Array(model.config.chordTriggers.enumerated()), id: \.offset) { _, entry in
                        LiveStripKey(
                            Self.symbols(for: entry.trigger),
                            role: entry.slot,
                            isActive: model.activeRole == entry.slot
                        )
                        .accessibilityLabel("\(model.config.displayName(for: entry.slot)), \(entry.trigger.displayName)")
                    }
                }
            }
        }
    }

    // Physical one-shot modifier keys, ordered like the bottom row of a keyboard.
    private static let leftModifierKeys = ["left-shift", "left-control", "left-option", "left-command"]
    private static let rightModifierKeys = ["right-command", "right-option", "right-control", "right-shift"]

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
            LiveStripKey(keycap.label)
        } else {
            // Multiple bindings keep the same physical key column. Gesture text
            // distinguishes them even when their slot colors are identical.
            VStack(spacing: 4) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                    let gesture = entry.trigger.gesture == .doubleTap ? "x2" : (entries.count > 1 ? "x1" : nil)
                    LiveStripKey(keycap.label, role: entry.slot,
                                 detail: [keycap.detail, gesture].compactMap { $0 }.joined(separator: " "),
                                 isActive: model.activeRole == entry.slot)
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

    init(_ label: String, role: InputRole? = nil, detail: String? = nil, isActive: Bool = false) {
        self.label = label
        self.role = role
        self.detail = detail
        self.isActive = isActive
    }

    var body: some View {
        KeycapView(label, detail: detail, role: role, isPressed: isActive, isBound: role != nil,
                   appearance: .display, expandsHorizontally: label == "space")
            .frame(minWidth: 46, minHeight: 34)
    }
}

private struct RuntimeSection: View {
    @ObservedObject var model: AppModel
    let onShowSetupGuide: () -> Void

    var body: some View {
        CompactSection(title: "General") {
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

                RuntimeActionRow(title: "Setup guide", detail: "Walk through the first-run steps again") {
                    Button("Show", action: onShowSetupGuide)
                        .buttonStyle(ConsoleButtonStyle())
                        .accessibilityLabel("Show setup guide")
                }

                Divider().overlay(DesignTokens.Colors.separator)

                RuntimeActionRow(title: "Quit CmdIME", detail: "Stop the background listener") {
                    Button("Quit", role: .destructive) {
                        model.quit()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: false))
                }

                Text("CmdIME keeps running after this window closes. Open CmdIME again to return here.")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }
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
                .font(DesignTokens.Typography.body.weight(.semibold))
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
                    .font(DesignTokens.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(detail)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            action()
        }
        .padding(.vertical, 8)
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

struct CompactSettingRow<Content: View>: View {
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
