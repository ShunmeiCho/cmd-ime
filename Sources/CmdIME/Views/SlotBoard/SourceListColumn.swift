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

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                SectionLabel("Input sources")
                Spacer(minLength: 0)
                Button(action: onRefresh) {
                    Image(systemName: "arrow.clockwise").frame(width: 22, height: 24)
                }
                .buttonStyle(ConsoleControlButtonStyle())
                .accessibilityLabel("Refresh input sources")
                .help("Refresh installed input sources")
            }
            if let message = model.sourceRefreshMessage {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            if model.selectableSources.isEmpty {
                Label("No input sources", systemImage: "keyboard").font(.caption)
                keyboardSettingsButton
            } else {
                ForEach(model.selectableSources, id: \.id) { source in
                    SourceRow(source: source, usage: model.sourceUsage(of: source), model: model,
                              drag: drag, onBeginDrag: { onBeginDrag(source.id, $0) }) { onAdd(source.id) }
                }
                if model.unassignedSources.isEmpty {
                    Text("All input sources are in slots.")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                    keyboardSettingsButton
                }
            }
        }
        .frame(width: 196, alignment: .leading)
        .background(SourceWindowCloseHook(model: model).frame(width: 0, height: 0))
    }

    private var keyboardSettingsButton: some View {
        Button("Open Keyboard Settings…", action: onOpenSettings).buttonStyle(ConsoleButtonStyle())
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @GestureState private var isDragging = false
    @State private var attempted = false
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

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                if isNew {
                    Label("New", systemImage: "sparkles")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                }
                Label(name, systemImage: icon)
                    .font(.caption2)
                    .foregroundStyle(rejected ? DesignTokens.Colors.warning : (isAvailable ? DesignTokens.Colors.textMuted : tint))
                    .id(name).transition(.opacity)
            }
            Spacer(minLength: 0)
            if isAvailable {
                Button {
                    guard !isGhost, !suppressClick else { return }
                    onAdd()
                } label: {
                    Image(systemName: "plus").frame(width: 22, height: 24)
                }
                .buttonStyle(ConsoleButtonStyle())
                .help("Add \(source.localizedName) as a slot")
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            .fill(DesignTokens.Colors.surfaceRaised)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(Color.white.opacity(hover && isAvailable ? 0.07 : 0.035))))
        .contentShape(Rectangle())
        .onHover { if !isGhost { hover = $0 } }
        .animation(DesignTokens.Motion.stateChange, value: hover)
        .animation(DesignTokens.Motion.stateChange, value: usage)
        .animation(DesignTokens.Motion.stateChange, value: rejected)
        .offset(offset)
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
                }
                if rejected {
                    if !reduceMotion {
                        offset = CGSize(width: min(max(value.translation.width * 0.25, -6), 6),
                                        height: min(max(value.translation.height * 0.25, -6), 6))
                    }
                } else {
                    drag.move(location: value.location)
                }
            }
            .onEnded { _ in drag.drop() }, including: isGhost ? .none : .all)
        .onChange(of: isDragging) { active in
            guard !active, !isGhost else { return }
            drag.gestureDidEnd()
            attempted = false
            rejected = false
            // Keep the release event from also activating the nested + button.
            let generation = gestureGeneration
            DispatchQueue.main.async {
                if generation == gestureGeneration { suppressClick = false }
            }
            withAnimation(reduceMotion ? nil : DesignTokens.Motion.keyRelease) { offset = .zero }
        }
        .onDisappear { if attempted && !isGhost { drag.cancel() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.localizedName)
        .accessibilityValue(isNew ? "New, \(name)" : name)
        .accessibilityAddTraits(isAvailable ? .isButton : [])
        .accessibilityAction { if isAvailable && !isGhost { onAdd() } }
        .allowsHitTesting(!isGhost)
        .accessibilityHidden(isGhost)
    }
}

@MainActor
func openKeyboardSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
}

/// Observe only this view's window closing; activation never triggers a scan.
private struct SourceWindowCloseHook: NSViewRepresentable {
    let model: AppModel

    func makeNSView(context: Context) -> SourceWindowCloseView {
        let view = SourceWindowCloseView()
        view.model = model
        return view
    }

    func updateNSView(_ nsView: SourceWindowCloseView, context: Context) {
        nsView.model = model
    }

    static func dismantleNSView(_ nsView: SourceWindowCloseView, coordinator: ()) {
        nsView.stopObserving()
    }
}

private final class SourceWindowCloseView: NSView {
    weak var model: AppModel?
    private var closeObserver: SourceWindowCloseObservation?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }
        let token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak model] _ in
            Task { @MainActor [weak model] in
                model?.clearNewSourceMarkers()
            }
        }
        closeObserver = SourceWindowCloseObservation(token: token)
    }

    func stopObserving() {
        closeObserver = nil
    }
}

/// Immutable token ownership; NotificationCenter permits removal from any thread.
/// Keeping cleanup here avoids accessing non-Sendable state in NSView's deinit.
private final class SourceWindowCloseObservation: @unchecked Sendable {
    private let token: NSObjectProtocol

    init(token: NSObjectProtocol) {
        self.token = token
    }

    deinit {
        NotificationCenter.default.removeObserver(token)
    }
}
