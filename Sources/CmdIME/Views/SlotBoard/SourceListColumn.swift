import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SourceListColumn: View {
    @ObservedObject var model: AppModel
    @ObservedObject var drag: SlotBoardDragController
    let onBeginDrag: (String, DragGesture.Value) -> Bool
    let onAdd: (String) -> Void
    let onRefresh: () -> Void
    let onOpenSettings: () -> Void
    let onLocate: (InputRole) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack(spacing: DesignTokens.Layout.rowGap) {
                SectionLabel("Input sources")
                Spacer(minLength: 0)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise").frame(width: 22, height: 24)
                }
                .buttonStyle(ConsoleControlButtonStyle())
                .accessibilityLabel("Refresh input sources")
                .help("Refresh installed input sources")
            }
            .frame(height: DesignTokens.Layout.panelHeaderHeight)
            if model.selectableSources.isEmpty {
                Label("No input sources", systemImage: "keyboard").font(DesignTokens.Typography.body)
                keyboardSettingsButton
            } else {
                VStack(spacing: 0) {
                    ForEach(model.selectableSources, id: \.id) { source in
                        if source.id != model.selectableSources.first?.id {
                            Divider().overlay(DesignTokens.Colors.separator)
                        }
                        SourceRow(source: source, usage: model.sourceUsage(of: source), model: model,
                                  drag: drag, onBeginDrag: { onBeginDrag(source.id, $0) },
                                  onAdd: { onAdd(source.id) }, onLocate: onLocate)
                    }
                }
                if model.unassignedSources.isEmpty {
                    Text("All input sources are in slots. Add more in System Settings.")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    keyboardSettingsButton
                }
            }
            if let message = model.sourceRefreshMessage {
                Text(message)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
        }
        .padding(DesignTokens.Layout.panelInset)
        .frame(width: DesignTokens.Layout.sourcePanelWidth, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
            .fill(DesignTokens.Colors.surfaceInset))
        .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
            .stroke(DesignTokens.Colors.separator, lineWidth: 1))
    }

    private var keyboardSettingsButton: some View {
        // One line at the narrow column width; the long title used to wrap into a two-line slab.
        Button(action: onOpenSettings) {
            Label("Keyboard Settings…", systemImage: "arrow.up.forward.app")
                .lineLimit(1)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(ConsoleButtonStyle())
        .accessibilityLabel("Open Keyboard Settings")
    }
}

struct SourceRow: View {
    let source: InputSourceInfo
    let usage: SlotSourceUsage
    @ObservedObject var model: AppModel
    @ObservedObject var drag: SlotBoardDragController
    let onBeginDrag: (DragGesture.Value) -> Bool
    let onAdd: () -> Void
    var isGhost = false
    var onLocate: (InputRole) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false
    @State private var attempted = false
    @State private var hostSessionID: UUID?
    @State private var suppressClick = false
    @State private var gestureGeneration = 0
    @State private var rejected = false
    @State private var hover = false
    @State private var offset = CGSize.zero

    private var isAvailable: Bool { usage == .available }
    private var isNew: Bool { isAvailable && model.newSourceIDs.contains(source.id) }
    private var name: String {
        switch usage {
        case .available: "Available"
        case let .owned(id): "\(rejected ? "Already in slot" : "In use ·") \(model.config.displayName(for: id))"
        case let .resolved(id, _): "Fallback for \(model.config.displayName(for: id))"
        }
    }
    private var icon: String {
        switch usage {
        case .available: "plus.circle"
        case .owned: "checkmark.circle.fill"
        case .resolved: "arrow.triangle.branch"
        }
    }
    private var tint: Color {
        switch usage {
        case .available:
            let slot = try? model.config.addingSlot(for: source).slot
            return SlotLook(slots: slot.map { [$0] } ?? []).tint(for: slot?.id ?? .english)
        case let .owned(id), let .resolved(id, _):
            return SlotLook(slots: model.config.slots).tint(for: id)
        }
    }

    private var rowContent: some View {
        HStack(spacing: DesignTokens.Layout.rowGap) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            Button(action: activateRow) {
                sourceDetails
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(source.localizedName)
            .accessibilityValue(accessibilityUsage)
            .accessibilityHint(isAvailable ? "Add as a slot" : "Show the slot using this input source")
            Spacer(minLength: 0)
            if case let .resolved(owner, _) = usage {
                Button {
                    guard !isGhost, !suppressClick, !isDragging, !attempted else { return }
                    onLocate(owner)
                } label: {
                    Image(systemName: "arrow.right").frame(width: 22, height: 24)
                        .accessibilityHidden(true)
                }
                .buttonStyle(ConsoleButtonStyle())
                .help("Show \(model.config.displayName(for: owner)) slot")
                .accessibilityLabel("Show \(model.config.displayName(for: owner)) slot using \(source.localizedName)")
            }
            if isAvailable {
                Button(action: activateRow) {
                    Image(systemName: "plus").frame(width: 22, height: 24)
                        .accessibilityHidden(true)
                }
                .buttonStyle(ConsoleButtonStyle())
                .help("Add \(source.localizedName) as a slot")
                .accessibilityLabel("Add \(source.localizedName) as a slot")
                .accessibilityValue(accessibilityUsage)
            }
        }
    }

    private var sourceDetails: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            Text(source.localizedName)
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(2)
            if isNew {
                Label("New", systemImage: "sparkles")
                    .font(DesignTokens.Typography.auxiliary.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
            }
            Label(name, systemImage: icon)
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(rejected ? DesignTokens.Colors.warning : (isAvailable ? DesignTokens.Colors.textMuted : tint))
                .id(name).transition(.opacity)
        }
        .accessibilityHidden(true)
    }

    private func activateRow() {
        guard !isGhost, !suppressClick, !isDragging, !attempted else { return }
        switch usage {
        case .available: onAdd()
        case let .owned(owner), let .resolved(owner, _): onLocate(owner)
        }
    }

    private var accessibilityUsage: String {
        let state: String
        switch usage {
        case .available: state = "Available"
        case let .owned(owner): state = "Used by \(model.config.displayName(for: owner))"
        case let .resolved(owner, _): state = "Used by \(model.config.displayName(for: owner)) as a fallback"
        }
        return isNew ? "New, \(state)" : state
    }

    var body: some View {
        rowContent
        .padding(.vertical, DesignTokens.Layout.rowGap)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Rectangle().fill(DesignTokens.Colors.overlay(hover && isAvailable ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { if !isGhost { hover = $0 } }
        .animation(DesignTokens.Motion.stateChange, value: hover)
        .animation(DesignTokens.Motion.stateChange, value: usage)
        .animation(DesignTokens.Motion.stateChange, value: rejected)
        .offset(reduceMotion ? .zero : offset)
        .onChange(of: reduceMotion) { reduced in
            guard reduced else { return }
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) { offset = .zero }
        }
        .opacity(!isGhost && drag.payload == .source(source.id) ? 0.35 : 1)
        .animation(DesignTokens.Motion.quickFade, value: drag.payload == .source(source.id))
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("slotBoard")) } action: {
            if !isGhost { drag.sourceFrames[source.id] = $0 }
        }
        .simultaneousGesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("slotBoard"))
            .updating($isDragging) { _, active, _ in active = true }
            .onChanged { value in
                if !attempted {
                    attempted = true
                    suppressClick = true
                    gestureGeneration += 1
                    rejected = !onBeginDrag(value)
                    hostSessionID = rejected ? nil : drag.sessionID
                }
                if rejected {
                    if !reduceMotion {
                        offset = CGSize(width: min(max(value.translation.width * 0.25, -6), 6),
                                        height: min(max(value.translation.height * 0.25, -6), 6))
                    }
                } else {
                    drag.move(location: value.location, sessionID: hostSessionID)
                }
            }
            .onEnded { _ in drag.drop(sessionID: hostSessionID) }, including: isGhost ? .none : .all)
        .onChange(of: isDragging) { active in
            guard !active, !isGhost else { return }
            drag.gestureDidEnd(sessionID: hostSessionID)
            attempted = false
            rejected = false
            // Keep the release event from also activating the nested + button.
            let generation = gestureGeneration
            DispatchQueue.main.async {
                if generation == gestureGeneration { suppressClick = false }
            }
            withAnimation(reduceMotion ? nil : DesignTokens.Motion.keyRelease) { offset = .zero }
        }
        .onDisappear { if !isGhost { drag.cancel(sessionID: hostSessionID) } }
        .accessibilityElement(children: .contain)
        .accessibilityAction { activateRow() }
        .allowsHitTesting(!isGhost)
        .accessibilityHidden(isGhost)
    }
}

@MainActor
func openKeyboardSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
}
