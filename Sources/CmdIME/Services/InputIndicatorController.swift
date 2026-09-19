import AppKit
import ApplicationServices
import KeyboardSwitcherCore
import SwiftUI

extension IndicatorRenderContext {
    /// What the system says about its surroundings right now. `auto` themes follow
    /// the system appearance: sampling the pixels behind the bubble would need
    /// Screen Recording permission.
    @MainActor
    static func current(isDarkAppearance: Bool? = nil) -> IndicatorRenderContext {
        let workspace = NSWorkspace.shared
        let isDark = isDarkAppearance
            ?? (NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        return IndicatorRenderContext(
            isDarkAppearance: isDark,
            accentHex: Color(nsColor: .controlAccentColor).cmdIMEHexString ?? "#357AE6",
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

/// Shows the switch indicator near the caret. The bubble is measured from its
/// content, placed by core's `BubblePlacement`, and moved through four phases; a
/// re-trigger while it is visible never touches its opacity.
@MainActor
final class InputIndicatorController {
    private enum Phase {
        case hidden, appearing, holding, dismissing
    }

    let library: IndicatorLibrary

    private let state = BubbleState()
    private lazy var panel = BubblePanel()
    private lazy var container = BubbleContainerView(state: state)
    private lazy var measuringController = NSHostingController(rootView: AnyView(EmptyView()))
    private var phase = Phase.hidden
    /// Superseded animation groups still call their completion; this tells them apart.
    private var generation = 0
    private var hideTask: Task<Void, Never>?
    private var bubbleFrame = CGRect.zero
    private var anchor = BubblePlacement.Anchor.bottomLeading
    private var target = CGPoint.zero
    private var reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    private var displayOptionsObserver: NSObjectProtocol?

    init(configStore: ConfigStore) {
        library = IndicatorLibrary(configStore: configStore)
        displayOptionsObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            }
        }
    }

    func show(
        slotID: InputRole,
        previousSlotID: InputRole?,
        source: InputSourceInfo,
        config: SwitcherConfig,
        sources: [InputSourceInfo]
    ) {
        guard let model = IndicatorBubbleResolver.model(
            config: config,
            themes: library.themes,
            sources: sources,
            slotID: slotID,
            previousSlotID: previousSlotID,
            source: source,
            context: .current()
        ) else { return }

        let size = measure(model)
        // An app that reports a caret outside every display (some launchers do) gets the pointer instead.
        let caret = focusedCaretRect().flatMap { rect in
            NSScreen.screens.contains { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ? rect : nil
        }
        let pointer = NSEvent.mouseLocation
        let newTarget = caret.map { CGPoint(x: $0.midX, y: $0.maxY) } ?? pointer
        let visible = screen(containing: newTarget).visibleFrame
        let visibleRect = BubblePlacement.Rect(x: visible.minX, y: visible.minY, width: visible.width, height: visible.height)
        let placement = BubblePlacement.resolve(
            caret: caret.map { BubblePlacement.Rect(x: $0.minX, y: $0.minY, width: $0.width, height: $0.height) },
            pointerX: pointer.x,
            pointerY: pointer.y,
            bubbleWidth: size.width,
            bubbleHeight: size.height,
            visible: visibleRect
        )
        let placed = CGRect(x: placement.originX, y: placement.originY, width: size.width, height: size.height)

        generation += 1
        let wasVisible = phase == .appearing || phase == .holding
        let movedFar = hypot(newTarget.x - target.x, newTarget.y - target.y) > BubbleMotion.repositionThreshold
        let frame = wasVisible && !movedFar ? keepingAnchorCorner(of: bubbleFrame, size: size, visible: visibleRect) : placed
        if !wasVisible || movedFar {
            anchor = placement.anchor
            target = newTarget
        }
        bubbleFrame = frame

        configurePanel(for: model, bubbleSize: size)
        state.present(
            model,
            fresh: phase == .hidden,
            anchor: anchor == .bottomLeading ? .bottomLeading : .topLeading,
            fixedSize: size,
            reduceMotion: reduceMotion
        )

        switch phase {
        case .hidden:
            panel.alphaValue = 0
            panel.setFrame(panelFrame(for: frame, travel: reduceMotion ? 0 : BubbleMotion.riseDistance), display: true)
            panel.orderFrontRegardless()
            appear(to: frame)
        case .dismissing:
            appear(to: frame)
        case .appearing:
            // Alpha keeps rising from where it is; only the destination changes.
            appear(to: frame)
        case .holding:
            panel.setFrame(panelFrame(for: frame, travel: 0), display: true)
            scheduleHide(for: model, after: 0)
        }
    }

    // MARK: - Phases

    private func appear(to frame: CGRect) {
        phase = .appearing
        hideTask?.cancel()
        let current = generation
        let duration = reduceMotion ? BubbleMotion.reducedFadeIn : BubbleMotion.appearDuration
        let model = state.model
        resizePanelAtOnce(to: panelFrame(for: frame, travel: 0).size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = BubbleMotion.easeOutTimingFunction
            panel.animator().alphaValue = 1
            panel.animator().setFrame(panelFrame(for: frame, travel: 0), display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.phase == .appearing else { return }
                self.phase = .holding
            }
        }
        if let model { scheduleHide(for: model, after: duration) }
    }

    /// The hold is measured from the end of the appear.
    private func scheduleHide(for model: BubbleRenderModel, after appearDuration: Double) {
        hideTask?.cancel()
        let hold = model.archetype == .switcher ? BubbleMotion.holdSwitcher : BubbleMotion.holdStandard
        let current = generation
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64((appearDuration + hold) * 1_000_000_000))
            guard !Task.isCancelled, let self, self.generation == current else { return }
            self.dismiss()
        }
    }

    /// Leaves the way it came: fading, a little back toward the caret.
    private func dismiss() {
        phase = .dismissing
        let current = generation
        let travel = reduceMotion ? 0 : BubbleMotion.dismissTravel
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduceMotion ? BubbleMotion.reducedFadeOut : BubbleMotion.dismissDuration
            context.timingFunction = BubbleMotion.easeOutTimingFunction
            panel.animator().alphaValue = 0
            panel.animator().setFrame(panelFrame(for: bubbleFrame, travel: travel), display: true)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current, self.phase == .dismissing else { return }
                self.panel.orderOut(nil)
                self.state.clear()
                self.phase = .hidden
            }
        }
    }

    // MARK: - Geometry

    /// Laid out exactly as the panel will show it, so larger text never clips.
    private func measure(_ model: BubbleRenderModel) -> CGSize {
        measuringController.rootView = AnyView(SwitchBubbleView(model: model, mode: .live))
        let fitted = measuringController.sizeThatFits(
            in: CGSize(width: model.metrics.maxBubbleWidth, height: .greatestFiniteMagnitude)
        )
        return CGSize(width: fitted.width.rounded(.up), height: fitted.height.rounded(.up))
    }

    private func configurePanel(for model: BubbleRenderModel, bubbleSize: CGSize) {
        if panel.contentView !== container { panel.contentView = container }
        let margin = model.metrics.shadowMargin.points
        let glass: (isDark: Bool, isLiquid: Bool)? = switch model.substrate {
        case let .glass(isDark, _): (isDark, false)
        case let .liquidGlass(isDark): (isDark, true)
        default: nil
        }
        if let glass {
            container.setGlass(.init(
                isDark: glass.isDark,
                isLiquid: glass.isLiquid,
                frame: CGRect(origin: CGPoint(x: margin, y: margin), size: bubbleSize),
                cornerRadius: model.metrics.bubbleRadius.points
            ))
        } else {
            container.setGlass(nil)
        }
    }

    /// The panel is the bubble plus a transparent, click-through margin for the shadow.
    /// `travel` moves it toward the caret along the line through the anchor corner.
    private func panelFrame(for bubble: CGRect, travel: CGFloat) -> CGRect {
        let margin = (state.model?.metrics.shadowMargin ?? 0).points
        let towardCaret = anchor == .bottomLeading ? -travel : travel
        return bubble.insetBy(dx: -margin, dy: -margin).offsetBy(dx: 0, dy: towardCaret)
    }

    /// The glass takes its new size at once, so the panel must too: animating the size
    /// would slide the centred SwiftUI edges away from the glass. Only origin and
    /// alpha are animated.
    private func resizePanelAtOnce(to size: CGSize) {
        let current = panel.frame
        guard current.size != size else { return }
        let y = anchor == .bottomLeading ? current.minY : current.maxY - size.height
        panel.setFrame(CGRect(x: current.minX, y: y, width: size.width, height: size.height), display: true)
    }

    /// A larger bubble grows from the corner nearest the caret and stays on screen.
    private func keepingAnchorCorner(of old: CGRect, size: CGSize, visible: BubblePlacement.Rect) -> CGRect {
        let resized = BubblePlacement.resized(
            from: BubblePlacement.Rect(x: old.minX, y: old.minY, width: old.width, height: old.height),
            anchor: anchor,
            width: size.width,
            height: size.height,
            visible: visible
        )
        return CGRect(x: resized.x, y: resized.y, width: resized.width, height: resized.height)
    }

    private func screen(containing point: NSPoint) -> NSScreen {
        NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    // MARK: - Caret

    private func focusedCaretRect() -> CGRect? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedElement = focusedValue as! AXUIElement

        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let bounds = boundsValue as! AXValue
        var rect = CGRect.zero
        // An insertion point is a zero-width rect, which `isEmpty` would throw away: only the
        // height says whether the app reported a real caret.
        guard AXValueGetType(bounds) == .cgRect, AXValueGetValue(bounds, .cgRect, &rect), rect.height > 0 else {
            return nil
        }
        return convertAccessibilityRect(rect)
    }

    /// Accessibility rects have a top-left origin; AppKit's is bottom-left.
    private func convertAccessibilityRect(_ rect: CGRect) -> CGRect {
        // screens[0] is always the primary display, the one both coordinate systems hang off.
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        let flipped = BubblePlacement.appKitRect(
            fromAccessibility: .init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
            primaryDisplayHeight: primaryHeight
        )
        return CGRect(x: flipped.x, y: flipped.y, width: flipped.width, height: flipped.height)
    }
}
