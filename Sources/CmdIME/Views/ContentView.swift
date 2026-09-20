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
                SettingsHeader(model: model, status: runtimeStatus, onPrimaryAction: performHeaderAction) {
                    SetupGuideNavigation.showGuide($setupSession, model: model, scroll: scroll)
                }
                if case let .available(result) = model.updateStatus {
                    UpdateAvailableBar(model: model, version: result.latestVersion)
                }
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

                IndicatorSettingsSection(model: model)
                    .setupFold(.indicator)
                    .frame(maxWidth: .infinity)
                    .id("indicator-section")
                #if DEBUG
                // Screenshot aid: CMDIME_SCROLL_TO=indicator opens the window on the lower half.
                Color.clear.frame(height: 0).onAppear {
                    guard ProcessInfo.processInfo.environment["CMDIME_SCROLL_TO"] == "indicator" else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { scroll.scrollTo("indicator-section", anchor: .top) }
                }
                #endif
            }
            .padding(22)
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // One point of padding keeps the scrolling content below the transparent title bar;
        // without it, rows slide up underneath the window title and the traffic lights.
        .padding(.top, 1)
        .background(DesignTokens.Colors.canvas)
        .background { WindowMaterial().ignoresSafeArea() }
        .followsAppearancePreference()
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
    let onShowSetupGuide: () -> Void
    @State private var showsPermissionDetails = false
    @State private var showsGeneral = false

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
                generalMenu
            }
            Text("CmdIME keeps running after this window closes. Open CmdIME again to return here.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
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
        .floatingBarSurface()
    }
}

private extension SettingsHeader {
    /// Every action row spans the panel, so the left and right edges line up.
    /// Says what macOS currently allows, because the switch above cannot override it.
    @ViewBuilder
    var notificationPermissionNote: some View {
        switch model.notificationPermission {
        case .blocked:
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications for CmdIME are turned off in System Settings.")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Notification Settings…") { UpdateNotification.openSystemSettings() }
            }
        case .notAsked:
            Text("macOS will ask for permission the first time there is an update.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        case .allowed, .unknown:
            EmptyView()
        }
    }

    func generalRow(_ title: String, prominent: Bool = false, destructive: Bool = false,
                    action: @escaping () -> Void) -> some View {
        Button(role: destructive ? .destructive : nil, action: action) {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(ConsoleButtonStyle(prominent: prominent))
    }

    static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Everything that used to sit in a General section at the bottom of the page. A popover
    /// rather than a menu: the toggle, the update result and every button stay visible while
    /// they act, which a closing menu cannot show.
    var generalMenu: some View {
        Button { showsGeneral.toggle() } label: {
            Label("General", systemImage: "gearshape")
        }
        .buttonStyle(ConsoleButtonStyle())
        .fixedSize()
        .accessibilityLabel("General")
        .onChange(of: showsGeneral) { isShown in
            // The answer can change in System Settings while CmdIME keeps running.
            if isShown { model.refreshNotificationPermission() }
        }
        .appearancePopover(isPresented: $showsGeneral, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
                HStack {
                    Text("Launch at login")
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Toggle("Launch at login", isOn: Binding(
                        get: { model.loginItem.isEnabled }, set: { model.setLaunchAtLogin($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.success)
                    .controlSize(.small)
                    .disabled(!model.loginItem.isAvailable)
                }
                // Registering succeeds while the switch stays off: macOS waits for the user
                // to approve the login item in System Settings.
                if model.loginItemNeedsApproval {
                    HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Layout.rowGap) {
                        Label("Approve CmdIME in Login Items", systemImage: "exclamationmark.triangle.fill")
                            .font(DesignTokens.Typography.auxiliary)
                            .foregroundStyle(DesignTokens.Colors.warning)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: DesignTokens.Layout.rowGap)
                        Button("Open") { model.openLoginItemsSettings() }
                            .fixedSize()
                    }
                }
                HStack {
                    Text("Appearance")
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Picker("Appearance", selection: $model.appearance) {
                        ForEach(AppearancePreference.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                }
                Divider()
                HStack {
                    Text(model.updateStatus.message)
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Button(model.updateStatus.isChecking ? "Checking…" : "Check") { model.checkForUpdates() }
                        .disabled(model.updateStatus.isChecking)
                        .fixedSize()
                }
                if case .available = model.updateStatus { UpdateActions(model: model) }
                HStack {
                    Text("Check automatically")
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Toggle("Check for updates automatically", isOn: Binding(
                        get: { model.checksForUpdatesAutomatically }, set: { model.checksForUpdatesAutomatically = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.success)
                    .controlSize(.small)
                }
                .help("CmdIME asks GitHub for the newest release. Nothing else is sent.")
                if model.checksForUpdatesAutomatically {
                    HStack {
                        Text("Every")
                        Spacer(minLength: DesignTokens.Layout.rowGap)
                        Picker("Check every", selection: Binding(
                            get: { model.updateCheckFrequency }, set: { model.updateCheckFrequency = $0 }
                        )) {
                            ForEach(UpdateCheckFrequency.allCases, id: \.self) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .controlSize(.small)
                        .fixedSize()
                        .accessibilityLabel("How often to check for updates")
                    }
                    HStack {
                        Text("Notify me about updates")
                        Spacer(minLength: DesignTokens.Layout.rowGap)
                        Toggle("Notify me about updates", isOn: Binding(
                            get: { model.notifiesAboutUpdates }, set: { model.notifiesAboutUpdates = $0 }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(DesignTokens.Colors.success)
                        .controlSize(.small)
                    }
                    if model.notifiesAboutUpdates { notificationPermissionNote }
                }
                Divider()
                generalRow("Show Setup Guide") {
                    showsGeneral = false
                    onShowSetupGuide()
                }
                generalRow("Support CmdIME…") { Self.open("https://buymeacoffee.com/shunmeicor7") }
                generalRow("Star on GitHub…") { Self.open("https://github.com/ShunmeiCho/cmd-ime") }
                Divider()
                generalRow("Quit CmdIME", destructive: true) { model.quit() }
                    .help("Stop the background listener")
            }
            .buttonStyle(ConsoleButtonStyle())
            .font(DesignTokens.Typography.body)
            .foregroundStyle(DesignTokens.Colors.textPrimary)
            .padding(16)
            .frame(width: 300)
            .background(DesignTokens.Colors.surfaceRaised)
        }
    }
}

/// Update, read the notes, or skip: shared by the top bar and the General panel.
private struct UpdateActions: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            if let stage = model.updateInstallStage {
                HStack(spacing: DesignTokens.Layout.rowGap) {
                    ProgressView().controlSize(.small)
                    Text(stage).font(DesignTokens.Typography.body)
                }
            } else {
                HStack(spacing: DesignTokens.Layout.rowGap) {
                    if SelfUpdater.canUpdateInPlace {
                        Button("Update Now") { model.installAvailableUpdate() }
                            .buttonStyle(ConsoleButtonStyle(prominent: true))
                    }
                    Button("Release Notes") { model.openLatestRelease() }
                        .buttonStyle(ConsoleButtonStyle())
                    Button("Skip") { model.skipAvailableUpdate() }
                        .buttonStyle(ConsoleButtonStyle())
                        .help("Do not remind me about this version again")
                }
                .fixedSize()
            }
            if let error = model.updateInstallError {
                Text(error)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// What the update changes, so deciding on it does not take a trip to the browser.
private struct ReleaseNotesSummaryView: View {
    let notes: ReleaseNotesSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let headline = notes.headline {
                Text(headline)
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            ForEach(notes.items, id: \.self) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•")
                    Text(item)
                }
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}

private struct UpdateAvailableBar: View {
    @ObservedObject var model: AppModel
    let version: String

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            HStack(alignment: .top, spacing: DesignTokens.Layout.rowGap) {
                Label("CmdIME \(version) is available", systemImage: "arrow.down.circle.fill")
                    .font(DesignTokens.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .padding(.top, 5)
                Spacer(minLength: DesignTokens.Layout.rowGap)
                UpdateActions(model: model)
            }
            if case let .available(result) = model.updateStatus, !result.notes.isEmpty {
                ReleaseNotesSummaryView(notes: result.notes)
            }
        }
        .padding(DesignTokens.Layout.panelInset)
        .floatingBarSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Update available")
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
    /// A segment the current context cannot offer. It stays in place, so the choice on
    /// offer does not move around, but it is dimmed and does not answer a click.
    var isEnabled = true

    var id: Value {
        value
    }
}

struct ConsoleSegmentedControl<Value: Hashable>: View {
    static var unavailableOpacity: Double { 0.4 }

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
                        .opacity(option.isEnabled ? 1 : Self.unavailableOpacity)
                        .lineLimit(1)
                        .fixedSize()
                        // A label never touches its segment's edge, whatever width the row gives it.
                        .padding(.horizontal, 12)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!option.isEnabled)
                .accessibilityLabel(option.label)
                .accessibilityAddTraits(selection == option.value ? .isSelected : [])
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selection == option.value ? DesignTokens.Colors.overlay(0.12) : .clear)
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
