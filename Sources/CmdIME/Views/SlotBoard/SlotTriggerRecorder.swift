import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SlotTriggerRecorder: View {
    @ObservedObject var model: AppModel
    let role: InputRole
    let isGhost: Bool
    let onWillOpen: () -> Bool
    let onUpdated: () -> Void
    @StateObject private var session = TriggerRecordingSession()
    @State private var presented = false
    @Environment(\.slotLook) private var slotLook

    private var trigger: KeyTrigger? { model.trigger(for: role) }
    private var presentation: Binding<Bool> {
        Binding(get: { presented }, set: { visible in
            presented = visible
            if !visible { session.end(reason: .explicitClose) }
        })
    }

    var body: some View {
        HStack(spacing: 6) {
            TriggerRecorderAnchor(title: session.isRecording ? "Recording…" : trigger.map(TriggerKeycapText.summary) ?? "Record Hotkey",
                                  accessibilityTitle: "Record trigger for \(slotLook.name(for: role))",
                                  accessibilityValue: trigger?.displayName ?? "No trigger",
                                  tint: NSColor(slotLook.tint(for: role)), hasTrigger: trigger != nil,
                                  isGhost: isGhost, onOpen: open)
                .frame(width: 180, height: 28)
                .popover(isPresented: presentation, arrowEdge: .bottom) {
                    let generation = session.sessionID
                    TriggerRecorderPopover(session: session, role: role, name: slotLook.name(for: role))
                        .environment(\.slotLook, slotLook)
                        .id(generation)
                        .onDisappear { session.end(reason: .disappeared, sessionID: generation) }
                }
            if trigger != nil {
                Button {
                    guard !isGhost, onWillOpen() else { return }
                    if model.commitRecordedTrigger(nil, for: role) == nil { onUpdated() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
                .buttonStyle(.borderless)
                .help("Immediately remove this slot’s trigger")
                .accessibilityLabel("Immediately remove trigger for \(slotLook.name(for: role))")
            }
        }
        .allowsHitTesting(!isGhost)
        .accessibilityHidden(isGhost)
        .onDisappear { session.end(reason: .disappeared) }
    }

    private func open(in window: NSWindow) {
        guard !isGhost, onWillOpen() else { return }
        session.begin(in: window, existingTrigger: trigger,
                      onCaptureChanged: { model.setShortcutRecording($0, for: role) },
                      onValidate: { model.recordedTriggerConflict($0, for: role) },
                      onCommit: { draft in
                          let error = model.commitRecordedTrigger(draft, for: role)
                          if error == nil { onUpdated() }
                          return error
                      }, onDismiss: { presented = false })
        presented = true
    }
}

private struct TriggerRecorderPopover: View {
    @ObservedObject var session: TriggerRecordingSession
    let role: InputRole
    let name: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var shake: CGFloat = 0
    @State private var rejectionGeneration = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Press a key combination or tap a modifier")
                .font(DesignTokens.Typography.title)
            HStack(spacing: 5) {
                if session.liveKeyNames.isEmpty {
                    Text("Waiting for keys…")
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                } else {
                    ForEach(Array(session.liveKeyNames.enumerated()), id: \.offset) { _, key in
                        let cap = TriggerKeycapText.keycap(key)
                        KeycapView(cap.label, detail: cap.detail, role: role,
                                   isPressed: session.heldKeys.contains { $0.keyName == key }, appearance: .display)
                    }
                    if session.draft?.gesture == .doubleTap {
                        Text("×2").font(DesignTokens.Typography.body.weight(.bold))
                    }
                }
            }
            .frame(minHeight: 36)
            .id(session.captureRevision)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.96).combined(with: .opacity))
            .animation(reduceMotion ? DesignTokens.Motion.quickFade : DesignTokens.Motion.keyRelease,
                       value: session.captureRevision)
            Text("Tap a modifier twice for a double tap.\nReturn saves · Esc cancels · Delete clears the draft.")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textMuted)
            if let warning = session.warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            HStack(spacing: 8) {
                RoleBadge(role: role, symbol: role.defaultSymbol, size: 24, isActive: false)
                Text(name).font(DesignTokens.Typography.body.weight(.semibold))
                Spacer()
                Button("Cancel · Esc", action: session.cancel)
                    .buttonStyle(ConsoleButtonStyle())
                    .accessibilityLabel("Cancel recording")
                Button("Save · Return", action: session.save)
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .disabled(!session.canSave)
                    .accessibilityLabel("Save trigger")
            }
        }
        .padding(16)
        .frame(width: 350)
        .background(DesignTokens.Colors.surfaceRaised)
        .preferredColorScheme(.dark)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.98)
        .opacity(appeared ? 1 : 0)
        .animation(reduceMotion ? DesignTokens.Motion.quickFade : DesignTokens.Motion.expandCollapse, value: appeared)
        .modifier(Shake(progress: shake, amplitude: reduceMotion ? 0 : 5))
        .onAppear { appeared = true }
        .onChange(of: session.rejectionRevision) { _ in
            rejectionGeneration += 1
            let generation = rejectionGeneration
            shake = 0
            DispatchQueue.main.async {
                guard generation == rejectionGeneration, !reduceMotion else { return }
                withAnimation(DesignTokens.Motion.rejectShake) { shake = 1 }
            }
        }
    }
}

private enum TriggerKeycapText {
    static func keycap(_ key: String) -> (label: String, detail: String?) {
        switch key {
        case "left": return ("←", nil)
        case "right": return ("→", nil)
        case "up": return ("↑", nil)
        case "down": return ("↓", nil)
        case "return": return ("↩", nil)
        case "tab": return ("⇥", nil)
        case "space": return ("Space", nil)
        case "delete": return ("⌫", nil)
        case "forward-delete": return ("⌦", nil)
        default:
            let cap = LiveKeycap(keyName: key)
            return (cap.label, cap.detail)
        }
    }

    static func summary(_ trigger: KeyTrigger) -> String {
        let keys = trigger.modifiers.map(\.rawValue) + [trigger.keyName]
        let text = keys.map { key in
            let cap = keycap(key)
            return (cap.detail ?? "") + cap.label
        }.joined(separator: " ")
        return text + (trigger.gesture == .doubleTap ? " ×2" : "")
    }
}

/// The actual anchor supplies its own window; it never discovers a key window.
/// NSButton preserves native focus/activation while supporting focused Return.
private struct TriggerRecorderAnchor: NSViewRepresentable {
    let title: String
    let accessibilityTitle: String
    let accessibilityValue: String
    let tint: NSColor
    let hasTrigger: Bool
    let isGhost: Bool
    let onOpen: (NSWindow) -> Void

    func makeNSView(context: Context) -> AnchorButton {
        let button = AnchorButton()
        button.setButtonType(.momentaryPushIn)
        button.bezelStyle = .rounded
        button.isBordered = false
        button.focusRingType = .exterior
        button.alignment = .left
        button.font = DesignTokens.Typography.bodyKeyNSFont
        button.target = button
        button.action = #selector(AnchorButton.openRecorder)
        return button
    }

    func updateNSView(_ button: AnchorButton, context: Context) {
        button.title = title
        button.contentTintColor = hasTrigger ? NSColor(DesignTokens.Colors.textPrimary) : NSColor(DesignTokens.Colors.textMuted)
        button.outlineTint = tint
        button.onOpen = isGhost ? nil : onOpen
        button.setAccessibilityLabel(accessibilityTitle)
        button.setAccessibilityValue(accessibilityValue)
        button.setAccessibilityHidden(isGhost)
        button.needsDisplay = true
    }

    final class AnchorButton: NSButton {
        var onOpen: ((NSWindow) -> Void)?
        var outlineTint = NSColor.controlAccentColor
        private var tracking: NSTrackingArea?
        private var hovered = false
        override var acceptsFirstResponder: Bool { onOpen != nil }
        override var focusRingMaskBounds: NSRect { bounds }
        override func drawFocusRingMask() { NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill() }

        @objc func openRecorder() {
            guard let window else { return }
            onOpen?(window)
        }
        override func keyDown(with event: NSEvent) {
            if event.keyCode == 36 || event.keyCode == 49 {
                performClick(nil)
            } else { super.keyDown(with: event) }
        }
        override func becomeFirstResponder() -> Bool {
            let result = super.becomeFirstResponder()
            needsDisplay = true
            return result
        }
        override func resignFirstResponder() -> Bool {
            let result = super.resignFirstResponder()
            needsDisplay = true
            return result
        }
        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let tracking { removeTrackingArea(tracking) }
            let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                     owner: self, userInfo: nil)
            addTrackingArea(area)
            tracking = area
        }
        override func mouseEntered(with event: NSEvent) { hovered = true; needsDisplay = true }
        override func mouseExited(with event: NSEvent) { hovered = false; needsDisplay = true }
        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)
            if hovered || window?.firstResponder === self {
                outlineTint.setStroke()
                NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6, yRadius: 6).stroke()
            }
        }
    }
}
