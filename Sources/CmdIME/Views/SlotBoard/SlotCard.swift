import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SlotCard: View {
    @Environment(\.slotLook) private var slotLook
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var nameFocused: Bool
    @State private var showingColor = false
    @StateObject private var renameSession = SlotRenameSession()
    let slot: SwitchSlot
    let source: InputSourceInfo?
    let isActive: Bool
    let sourceStatus: SwitcherConfig.SourceStatus
    /// Zero-based position in the slot list.
    let position: Int
    let count: Int
    let triggerText: String
    let hasTrigger: Bool
    let warning: String?
    let isRenaming: Bool
    let onRename: () -> Void
    let onCommitRename: (String) -> Bool
    let onCancelRename: () -> Void
    let onRenameDraftChanged: () -> Void
    let onRenameCommitChanged: ((() -> Bool)?) -> Void
    let onTest: () -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void
    let onColorSelect: (String) -> Void
    let triggerControls: AnyView
    let inputSourceControl: AnyView
    let matchNotice: AnyView
    var seatProgress: CGFloat = 1
    var focusName: Bool = false
    var isGhost: Bool = false
    var dragHandle: AnyView = AnyView(Color.clear.frame(width: 14, height: 14))

    private var presentation: InputSourcePresentation { InputSourcePresentation(source: source, slot: slot) }
    private var tint: Color { slotLook.tint(for: slot.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                dragHandle.accessibilityHidden(true)
                Button { openColor() } label: {
                    RoleBadge(role: slot.id, symbol: presentation.symbol, size: 31, isActive: isActive)
                        .accessibilityValue(isActive ? "Current" : "Available")
                }
                // The badge tile is the control; a second chrome box around it read as a nested frame.
                .buttonStyle(SlotBadgeButtonStyle())
                .help("Change slot color")
                .accessibilityLabel("Color for \(slot.name)")
                .popover(isPresented: $showingColor) {
                    SlotColorPopover(slot: slot, onSelect: { hex in
                        guard !isGhost else { return }
                        onColorSelect(hex)
                    }, onClose: { showingColor = false }, warning: warning)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        name
                        Spacer(minLength: 0)
                        statusChip
                    }
                    inputSourceControl
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(-1)
                Button("Switch") { perform(onTest) }
                    .help("Switch to this input source now. This does not test the trigger.")
                    .accessibilityLabel("Switch to this input source now. This does not test the trigger.")
                    .buttonStyle(ConsoleButtonStyle())
                    .frame(width: 68)
                    .disabled(source == nil)
                SlotOverflowMenu(position: position, count: count,
                                 onRename: { perform(onRename) },
                                 onColor: openColor, tint: tint,
                                 onMove: { offset in perform { onMove(offset) } },
                                 onRemove: { perform(onRemove) })
                    .frame(width: 32)
            }
            triggerControls
                .padding(.leading, 22)
            if !hasTrigger {
                Label("No trigger yet - record one", systemImage: "keyboard")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 22)
            }
            matchNotice.padding(.leading, 22)
            if let warning {
                Label {
                    Text(warning).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .font(DesignTokens.Typography.auxiliary.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.warning)
                .padding(.leading, 22)
                .help(warning)
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background {
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.surfaceRaised)
        }
        .modifier(SlotCardOutline(progress: seatProgress, tint: tint, reduceMotion: reduceMotion,
                                  stroke: strokeColor, isActive: isActive))
        .onAppear { if !isGhost { nameFocused = focusName } }
        .onChange(of: focusName) { if !isGhost { nameFocused = $0 } }
        .contextMenu { menuItems }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(slot.name) slot, position \(position + 1) of \(count)")
        .accessibilityValue(accessibilityStatus)
        .allowsHitTesting(!isGhost)
        .accessibilityHidden(isGhost)
    }

    private var name: some View {
        Group {
            if isRenaming {
                SlotNameField(name: slot.name, tint: tint, session: renameSession,
                              onCommit: onCommitRename, onCancel: onCancelRename, onEdit: onRenameDraftChanged,
                              onCommitChanged: onRenameCommitChanged)
                    .transition(.opacity)
            } else {
                Text(slot.name)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .help(slot.name)
                    .accessibilityFocused($nameFocused)
                    .onTapGesture(count: 2, perform: onRename)
                    .accessibilityActions {
                        Button("Rename", action: onRename)
                        Button("Color…", action: openColor)
                        if position > 0 { Button("Move Up") { perform { onMove(-1) } } }
                        if position + 1 < count { Button("Move Down") { perform { onMove(1) } } }
                        if count > 1 { Button("Remove Slot") { perform(onRemove) } }
                    }
                    .transition(.opacity)
            }
        }
        .font(DesignTokens.Typography.title)
        .animation(DesignTokens.Motion.stateChange, value: isRenaming)
    }

    private var menuItems: some View {
        SlotMenuItems(position: position, count: count, onRename: { perform(onRename) }, onColor: openColor,
                      onMove: { offset in perform { onMove(offset) } }, onRemove: { perform(onRemove) })
    }

    private func openColor() {
        guard !isGhost else { return }
        perform { showingColor = true }
    }

    private func perform(_ action: () -> Void) {
        guard renameSession.commit?() ?? true else { return }
        action()
    }

    private var accessibilityStatus: String {
        var values = [isActive ? "Current" : "Not current"]
        if source == nil { values.append("Not matched") }
        if sourceStatus == .duplicate { values.append("Duplicate") }
        if sourceStatus == .sourceMissing { values.append("Source missing") }
        if !hasTrigger { values.append("No trigger yet - record one") }
        if let warning { values.append(warning) }
        return values.joined(separator: ", ")
    }

    private var statusChip: some View {
        HStack(spacing: 4) {
            if isActive {
                Label("Current", systemImage: "checkmark.circle.fill").slotChip(color: tint)
            }
            if warning != nil {
                Label("Warning", systemImage: "exclamationmark.triangle.fill").slotChip(color: DesignTokens.Colors.warning)
            }
            if sourceStatus == .duplicate {
                Label("Duplicate", systemImage: "square.on.square").slotChip(color: DesignTokens.Colors.warning)
            }
            if sourceStatus == .sourceMissing {
                Label("Source missing", systemImage: "questionmark.circle").slotChip(color: DesignTokens.Colors.warning)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var strokeColor: Color {
        if isActive { return tint.opacity(0.74) }
        if source == nil || sourceStatus != .ok || warning != nil { return DesignTokens.Colors.warning.opacity(0.35) }
        return tint.opacity(0.22)
    }
}

/// Keeping the branch inside an animatable modifier lets the pulse finish before
/// restoring the resting outline, even though the parent's target is already one.
private struct SlotCardOutline: ViewModifier, @preconcurrency Animatable {
    var progress: CGFloat
    let tint: Color
    let reduceMotion: Bool
    let stroke: Color
    let isActive: Bool

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        content.overlay {
            Group {
                if progress < 1 {
                    Color.clear
                        .modifier(SeatPulse(progress: progress, tint: tint, reduceMotion: reduceMotion))
                } else {
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(stroke, lineWidth: isActive ? 1.4 : 1)
                        .shadow(color: isActive ? tint.opacity(0.26) : .clear, radius: 14, y: 5)
                }
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct SlotMenuItems: View {
    let position: Int
    let count: Int
    let onRename: () -> Void
    let onColor: () -> Void
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        Button("Rename", action: onRename)
        Button("Color…", action: onColor)
        if position > 0 { Button("Move Up") { onMove(-1) } }
        if position + 1 < count { Button("Move Down") { onMove(1) } }
        Divider()
        Button("Remove Slot", role: .destructive, action: onRemove)
            .disabled(count <= 1)
            .help(count <= 1 ? (SlotError.lastSlot.errorDescription ?? "Keep at least one slot.") : "Remove this slot")
    }
}

struct SlotOverflowMenu: View {
    let position: Int
    let count: Int
    let onRename: () -> Void
    let onColor: () -> Void
    let tint: Color
    let onMove: (Int) -> Void
    let onRemove: () -> Void

    var body: some View {
        ConsoleMenuButton(title: "", systemImage: "ellipsis", tint: tint, showsChevron: false) {
            SlotMenuItems(position: position, count: count, onRename: onRename,
                          onColor: onColor, onMove: onMove, onRemove: onRemove)
        }
        .accessibilityLabel("Slot actions")
        .help("Slot actions")
    }
}

@MainActor
final class SlotRenameSession: ObservableObject {
    var commit: (() -> Bool)?
}

struct SlotNameField: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focused: Bool
    @State private var draft = ""
    @State private var invalid = false
    @State private var shakeProgress: CGFloat = 0
    @State private var shakeGeneration = 0
    @State private var appeared = false
    @State private var finished = false
    @State private var rejectedInCurrentEvent = false
    let name: String
    let tint: Color
    let session: SlotRenameSession
    let onCommit: (String) -> Bool
    let onCancel: () -> Void
    let onEdit: () -> Void
    let onCommitChanged: ((() -> Bool)?) -> Void

    var body: some View {
        TextField("Slot name", text: $draft)
            .textFieldStyle(.plain)
            .focused($focused)
            .accessibilityLabel("Slot name")
            .onSubmit { if !isComposing { _ = commit() } }
            .onExitCommand {
                guard !isComposing else { return }
                finished = true
                session.commit = nil
                onCommitChanged(nil)
                onCancel()
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(invalid ? DesignTokens.Colors.warning : tint)
                    .frame(height: 1)
                    .scaleEffect(x: appeared || reduceMotion ? 1 : 0, y: 1, anchor: .leading)
                    .animation(reduceMotion ? nil : DesignTokens.Motion.expandCollapse, value: appeared)
                    .animation(DesignTokens.Motion.stateChange, value: invalid)
            }
            .modifier(Shake(progress: shakeProgress, amplitude: reduceMotion ? 0 : 5))
            .background(SlotRenameOutsideMonitor(onOutside: { _ = commit() }))
            .onAppear {
                draft = name
                session.commit = commit
                onCommitChanged(commit)
                focused = true
                appeared = true
            }
            .onChange(of: draft) { _ in
                if invalid { invalid = false; onEdit() }
                session.commit = commit
                onCommitChanged(commit)
            }
            .onDisappear {
                session.commit = nil
                onCommitChanged(nil)
            }
    }

    private var isComposing: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.hasMarkedText() == true
    }

    @discardableResult private func commit() -> Bool {
        guard !finished else { return true }
        guard !isComposing, !rejectedInCurrentEvent else { return false }
        if onCommit(draft) {
            finished = true
            session.commit = nil
            onCommitChanged(nil)
            return true
        }
        // The outside-click monitor returns the event; its menu/button action
        // must not immediately retry the rejected draft and repeat this reason.
        rejectedInCurrentEvent = true
        DispatchQueue.main.async { rejectedInCurrentEvent = false }
        invalid = true
        focused = true
        shakeGeneration += 1
        shakeProgress = 0
        let generation = shakeGeneration
        if !reduceMotion {
            DispatchQueue.main.async {
                guard generation == shakeGeneration, !finished else { return }
                withAnimation(DesignTokens.Motion.rejectShake) { shakeProgress = 1 }
            }
        }
        return false
    }
}

private struct SlotRenameOutsideMonitor: NSViewRepresentable {
    let onOutside: () -> Void

    func makeNSView(context: Context) -> MonitorView {
        let view = MonitorView()
        view.onOutside = onOutside
        return view
    }

    func updateNSView(_ view: MonitorView, context: Context) { view.onOutside = onOutside }
    static func dismantleNSView(_ view: MonitorView, coordinator: ()) { view.stop() }

    final class MonitorView: NSView {
        var onOutside: (() -> Void)?
        private var monitor: Any?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            stop()
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
                MainActor.assumeIsolated {
                    guard let self, let window = self.window else { return }
                    if event.window !== window || !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) {
                        self.onOutside?()
                    }
                }
                return event
            }
        }

        func stop() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }
    }
}

private extension View {
    func slotChip(color: Color) -> some View {
        self
            .font(DesignTokens.Typography.auxiliary.weight(.bold))
            .foregroundStyle(color)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color.opacity(0.16)))
    }
}

extension SlotBoardSection {
    func inputSourcePicker(for role: InputRole, source: InputSourceInfo?, isGhost: Bool = false) -> some View {
        ConsoleMenuButton(title: source?.localizedName ?? "Choose input source",
                          tint: SlotLook(slots: model.config.slots).tint(for: role),
                          warning: source == nil) {
            if source == nil {
                Button("Not matched") {}
                    .disabled(true)
            }
            ForEach(model.selectableSources, id: \.id) { candidate in
                Button(model.inputSourceMenuTitle(candidate, for: role)) {
                    guard !isGhost, commitPendingRename() else { return }
                    model.setInputSourceID(candidate.id, for: role)
                    if let notice = model.slotNotices[role] { announce(notice) }
                }
                .disabled(!model.inputSourceSelection(candidate, for: role).isEnabled)
            }
        }
        .disabled(isGhost)
        .help(source?.localizedName ?? "Choose input source")
    }
}

private struct SlotBadgeButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}
