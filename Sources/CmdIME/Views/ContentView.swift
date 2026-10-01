import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// The settings window: a native sidebar with one page per section. The update and
/// What's New notices sit above every page.
///
/// Never give this view a `navigationTitle`: other code finds the window by its title
/// "CmdIME", and the hosting view does not bridge titles (see `AppWindowCoordinator`).
struct ContentView: View {
    @ObservedObject var model: AppModel
    @State private var triggerDrafts: [InputRole: String] = [:]
    @State private var triggerTypeDrafts: [InputRole: BindingTriggerType] = [:]
    @State private var setupSession = SetupGuideSession()
    @State private var navigation: SettingsNavigation
    /// The sidebar carries the keyboard-control status, so it never collapses.
    @State private var columns = NavigationSplitViewVisibility.all

    init(model: AppModel) {
        self.model = model
        var navigation = SettingsNavigation(isSetupPending: !model.config.hasCompletedSetup)
        #if DEBUG
        // Screenshot aid: CMDIME_SCROLL_TO=indicator opens the window on the Indicator page.
        if ProcessInfo.processInfo.environment["CMDIME_SCROLL_TO"] == "indicator" {
            navigation.select(.indicator)
        }
        #endif
        _navigation = State(initialValue: navigation)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columns) {
            SettingsSidebar(model: model, navigation: $navigation)
                .navigationSplitViewColumnWidth(DesignTokens.Layout.sidebarWidth)
        } detail: {
            detail
        }
        .onChange(of: columns) { visibility in
            if visibility != .all { columns = .all }
        }
        .followsAppearancePreference()
        .environment(\.slotLook, SlotLook(slots: model.config.slots))
        .setupGuideLifecycle(model: model, session: $setupSession)
        .onChange(of: model.boardNotice) { notice in
            // The Slots page announces its own notices.
            guard navigation.selection != .slots, case let .failed(reason)? = notice else { return }
            SetupGuideNavigation.announce(reason)
        }
        .onAppear {
            resetDrafts()
        }
    }

    private var detail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
                if case let .available(result) = model.updateStatus {
                    UpdateAvailableBar(model: model, version: result.latestVersion)
                }
                // A replayed guide hides the notice only where the two would stack.
                WhatsNewNoticeBar(model: model,
                                  isSetupGuideReopened: setupSession.isReopened && navigation.selection == .setup)
                // Saving and the login item report failures through the board notice, which
                // the Slots page shows itself; every other page shows them here.
                if navigation.selection != .slots, case let .failed(reason) = model.boardNotice {
                    WindowFailureBar(message: reason, onDismiss: model.dismissBoardNotice)
                }
                page(navigation.selection)
            }
            .padding(22)
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        // Each page starts at the top.
        .id(navigation.selection)
        // One point of padding keeps the scrolling content below the transparent title bar;
        // without it, rows slide up underneath the window title and the traffic lights.
        .padding(.top, 1)
        .background(DesignTokens.Colors.canvas)
        .background { WindowMaterial().ignoresSafeArea() }
    }

    @ViewBuilder
    private func page(_ page: SettingsPage) -> some View {
        switch page {
        case .setup:
            SetupGuideCard(model: model, session: $setupSession, resetDrafts: resetDrafts,
                           onChangeSlots: openSlotsFromSetup, onClose: { navigation.completeSetup() })
        case .slots:
            SlotBoardSection(
                model: model,
                triggerDrafts: $triggerDrafts,
                triggerTypeDrafts: $triggerTypeDrafts,
                resetDrafts: resetDrafts,
                footer: AnyView(CompactLiveKeysStrip(model: model))
            )
        case .apps:
            AppsPage(model: model)
        case .indicator:
            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
                IndicatorSettingsSection(model: model)
                IndicatorOccasionsSection(model: model)
                PeekAndCapsLockSection(model: model)
            }
            .frame(maxWidth: .infinity)
        case .general:
            GeneralPage(model: model, onShowSetupGuide: showSetupGuide)
        case .about:
            AboutPage(model: model)
        }
    }

    /// Change in the setup guide's step 2. The guide keeps its place in the sidebar.
    private func openSlotsFromSetup() {
        navigation.select(.slots)
        SetupGuideNavigation.announce(String(localized: "Slots page opened. The setup guide stays in the sidebar."))
    }

    /// General > Show Setup Guide.
    private func showSetupGuide() {
        let wasOpen = !model.setupGuideState(session: setupSession).isFinished
        SetupGuideNavigation.showGuide($setupSession, model: model)
        navigation.replaySetup()
        // A replay starts at a step, which the guide's lifecycle announces; a guide that
        // was already open only changes page.
        if wasOpen {
            SetupGuideNavigation.announce(String(localized: "Setup guide opened."))
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

/// Update, read the notes, or skip: shared by the top bar and the General page.
struct UpdateActions: View {
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

/// A failure from saving or the login item, drawn like the Slots page's failure notice.
private struct WindowFailureBar: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Label(message, systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(DesignTokens.Colors.danger)
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(ConsoleButtonStyle())
                .fixedSize()
                .accessibilityLabel("Dismiss notice: \(message)")
        }
        .font(DesignTokens.Typography.body)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            .fill(DesignTokens.Colors.surfaceInset))
        .accessibilityElement(children: .contain)
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
                    LiveStripKey(String(localized: "space"), fillsWidth: true)
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
            .accessibilityLabel("\(model.config.displayName(for: entry.slot)), \(entry.trigger.localizedDisplayName)")
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
                        .accessibilityLabel("\(model.config.displayName(for: entry.slot)), \(entry.trigger.localizedDisplayName)")
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
    static let defaultValue = String(localized: "Trigger type")
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
    /// A click (or VoiceOver's press) slides the selected background to its segment. A change
    /// from elsewhere, such as a theme that brings its own weight, lands at once: rows above can
    /// reflow in the same update, and an animation scoped to this control would leave it
    /// trailing its row. Reduce Motion lands at once too.
    private static var slide: Animation { .spring(response: 0.26, dampingFraction: 0.86) }

    @Environment(\.consoleControlLabel) private var groupLabel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionSpace
    let options: [ConsoleSegmentOption<Value>]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.element.id) { index, option in
                Button {
                    withAnimation(DesignTokens.Motion.resolved(Self.slide, reduceMotion: reduceMotion)) {
                        selection = option.value
                    }
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
                .background { selectionBackground(for: option) }

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
        .accessibilityValue(options.first { $0.value == selection }?.label ?? String(localized: "No selection"))
    }

    /// One background, drawn behind the selected segment only, so it can move between them.
    @ViewBuilder
    private func selectionBackground(for option: ConsoleSegmentOption<Value>) -> some View {
        if selection == option.value {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.Colors.overlay(0.12))
                .matchedGeometryEffect(id: "selection", in: selectionSpace)
        }
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
