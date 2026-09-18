import AppKit
import SwiftUI

/// Place in a card's background with `.frame(maxWidth: .infinity, maxHeight: .infinity)`.
/// The parent owns request IDs and disables delivery while a drag is active.
@MainActor
struct SlotRevealAnchor: NSViewRepresentable {
    let requestID: UUID?
    let isEnabled: Bool
    let canReveal: () -> Bool
    let onReveal: () -> Void

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.setAccessibilityElement(false)
        view.setAccessibilityHidden(true)
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        view.update(requestID: requestID, isEnabled: isEnabled, canReveal: canReveal, onReveal: onReveal)
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: ()) {
        view.update(requestID: nil, isEnabled: false, canReveal: { false }, onReveal: {})
    }

    @MainActor
    final class AnchorView: NSView {
        private var requestID: UUID?
        private var isEnabled = false
        private var canReveal: () -> Bool = { false }
        private var onReveal: (() -> Void)?
        private var deliveredRequestID: UUID?
        private var scheduledToken: UUID?

        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override var acceptsFirstResponder: Bool { false }

        func update(requestID: UUID?, isEnabled: Bool, canReveal: @escaping () -> Bool,
                    onReveal: @escaping () -> Void) {
            if self.requestID != requestID || self.isEnabled != isEnabled {
                // Invalidate queued work even if a drag ends before that work runs.
                scheduledToken = nil
            }
            self.requestID = requestID
            self.isEnabled = isEnabled
            self.canReveal = canReveal
            self.onReveal = onReveal
            scheduleReveal()
        }

        override func layout() {
            super.layout()
            scheduleReveal()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            scheduledToken = nil
            scheduleReveal()
        }

        private func scheduleReveal() {
            guard isEnabled, window != nil,
                  let requestID, requestID != deliveredRequestID,
                  scheduledToken == nil else { return }

            let token = UUID()
            scheduledToken = token
            DispatchQueue.main.async { [weak self] in
                guard let self, self.scheduledToken == token else { return }
                defer {
                    if self.scheduledToken == token { self.scheduledToken = nil }
                }
                guard self.isEnabled, self.canReveal(), self.requestID == requestID,
                      self.deliveredRequestID != requestID,
                      self.window != nil, self.enclosingScrollView != nil,
                      !self.bounds.isEmpty else { return }

                // Scrolling can cause synchronous layout; consume first so that
                // neither layout nor the parent's pulse can deliver this twice.
                self.deliveredRequestID = requestID
                if !self.visibleRect.contains(self.bounds) {
                    self.scrollToVisible(self.bounds)
                }
                guard self.scheduledToken == token, self.isEnabled,
                      self.requestID == requestID, self.window != nil else { return }
                self.onReveal?()
            }
        }
    }
}
