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
    /// Each switch asks for the caret off the main thread. An answer for an older switch is dropped
    /// and that lookup skips its remaining steps; a request it has already sent still runs to its
    /// answer or timeout.
    private var caretRequest = 0
    private var caretLookup: Task<Void, Never>?
    /// From the config of the latest show; only its hold is read here.
    private var behavior = SwitchIndicatorBehavior()
    /// A show waiting for its caret lookup. A second switch in that gap is continuing the
    /// first, so an adaptive theme expands for it as if the bubble were already up.
    private var isPresentPending = false
    /// Whether the pending show, and the bubble on screen, came from a switch or Peek. A
    /// Caps Lock bubble is not switching, so a switch right after one starts from the Mark.
    private var isPendingSwitch = false
    private var isShowingSwitch = false
    /// The adaptive bubble on screen: its two layouts, how far its pill has grown from the
    /// Mark (0) to the row (1), and the clock driving that growth. Nil for other themes.
    private var adaptive: AdaptiveLayouts?
    private var pillProgress = 0.0
    private var growth: (clock: BubbleGrowthClock, originIndex: Int?)?
    /// Seconds into the running growth at its latest frame; nil when nothing grows.
    private var growthTime: Double?

    /// An adaptive switch's two layouts, resolved and measured when the switch arrives;
    /// which one is drawn is decided when the bubble is placed.
    private struct AdaptiveLayouts {
        let compact: BubbleRenderModel
        let expanded: BubbleRenderModel
        let compactSize: CGSize
        let expandedSize: CGSize
        /// Always expanded: Peek, or a switch in the gap before an earlier one was placed.
        let isExpandedAlready: Bool

        var reserved: CGSize {
            let size = AdaptiveExpansion.reservedSize(compact: .init(compactSize), expanded: .init(expandedSize))
            return CGSize(width: size.width, height: size.height)
        }
    }

    private enum Content {
        case fixed(BubbleRenderModel, CGSize)
        case adaptive(AdaptiveLayouts)
    }

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
        sources: [InputSourceInfo],
        isPeek: Bool = false
    ) {
        let context = IndicatorRenderContext.current()
        func resolve(_ occasion: AdaptiveBubbleLayout.Occasion) -> BubbleRenderModel? {
            IndicatorBubbleResolver.model(
                config: config, themes: library.themes, sources: sources, slotID: slotID,
                previousSlotID: previousSlotID, source: source, context: context, occasion: occasion
            )
        }
        behavior = config.switchIndicatorBehavior
        guard AdaptiveBubbleLayout.isAdaptive(themeID: config.switchIndicatorThemeID, in: library.themes) else {
            guard let model = resolve(isPeek ? .peek : .switched(whileVisible: false)) else { return }
            show(.fixed(model, measure(model)), isSwitch: true)
            return
        }
        guard let compact = resolve(.switched(whileVisible: false)), let expanded = resolve(.peek) else { return }
        let layouts = AdaptiveLayouts(
            compact: compact,
            expanded: expanded,
            compactSize: measure(compact),
            expandedSize: measure(expanded),
            isExpandedAlready: isPeek || (isPresentPending && isPendingSwitch)
        )
        show(.adaptive(layouts), isSwitch: true)
    }

    /// Caps Lock turned on or off: the bubble in the colours of `slotID`, or of the first slot.
    func showCapsLock(
        isOn: Bool,
        slotID: InputRole?,
        source: InputSourceInfo?,
        config: SwitcherConfig,
        sources: [InputSourceInfo]
    ) {
        guard let model = IndicatorBubbleResolver.capsLockModel(
            isOn: isOn,
            config: config,
            themes: library.themes,
            sources: sources,
            slotID: slotID,
            source: source,
            context: .current()
        ) else { return }
        behavior = config.switchIndicatorBehavior
        show(.fixed(model, measure(model)), isSwitch: false)
    }

    private func show(_ content: Content, isSwitch: Bool) {
        let pointer = NSEvent.mouseLocation
        caretRequest += 1
        let request = caretRequest
        isPresentPending = true
        isPendingSwitch = isSwitch
        caretLookup?.cancel()
        // The bubble on screen keeps its opacity until present() re-times it: without this, its
        // hold could run out while the lookup is still waiting and fade it out and back in.
        if phase == .appearing || phase == .holding { hideTask?.cancel() }
        // Detached so the lookup starts at once on the concurrent pool instead of queueing
        // behind the main thread; only the answer comes back to the main actor.
        caretLookup = Task.detached(priority: .userInitiated) { [weak self] in
            let axCaret = await Self.focusedCaretAccessibilityRect()
            await MainActor.run { [weak self] in
                guard let self, self.caretRequest == request else { return }
                self.isPresentPending = false
                self.present(content, isSwitch: isSwitch, pointer: pointer, accessibilityCaret: axCaret)
            }
        }
    }

    /// Chooses the adaptive layout from what is on screen now, not when the switch arrived:
    /// the caret lookup may have outlasted the bubble that was up then.
    private func present(_ content: Content, isSwitch: Bool, pointer: NSPoint, accessibilityCaret: CGRect?) {
        switch content {
        case let .fixed(model, size):
            present(model, size: size, layouts: nil, isSwitch: isSwitch, pointer: pointer, accessibilityCaret: accessibilityCaret)
        case let .adaptive(layouts):
            let isUp = layouts.isExpandedAlready || (phase != .hidden && isShowingSwitch)
            present(
                isUp ? layouts.expanded : layouts.compact,
                size: isUp ? layouts.expandedSize : layouts.compactSize,
                layouts: layouts,
                isSwitch: isSwitch,
                pointer: pointer,
                accessibilityCaret: accessibilityCaret
            )
        }
    }

    /// Places and animates the bubble once the caret lookup has answered (or given up). An
    /// adaptive bubble is placed at the size of its row, whichever layout it draws now.
    private func present(
        _ model: BubbleRenderModel,
        size drawnSize: CGSize,
        layouts: AdaptiveLayouts?,
        isSwitch: Bool,
        pointer: NSPoint,
        accessibilityCaret: CGRect?
    ) {
        let size = layouts?.reserved ?? drawnSize
        // An app that reports a caret outside every display (some launchers do) gets the pointer instead.
        let caret = accessibilityCaret.map(convertAccessibilityRect).flatMap { rect in
            NSScreen.screens.contains { $0.frame.contains(CGPoint(x: rect.midX, y: rect.midY)) } ? rect : nil
        }
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

        let grows = updatePill(for: model, layouts: layouts)
        isShowingSwitch = isSwitch
        let pill = pillRect(for: model, drawnSize: drawnSize)
        configurePanel(for: model, bubbleRect: pill, isAdaptive: layouts != nil)
        state.present(
            model,
            fresh: phase == .hidden,
            anchor: anchor == .bottomLeading ? .bottomLeading : .topLeading,
            fixedSize: pill.size,
            reduceMotion: reduceMotion,
            expansion: layouts == nil ? nil : expansion(
                for: model,
                time: growthTime ?? (grows ? 0 : nil),
                originIndex: growth?.originIndex ?? model.previousIndex
            )
        )
        if grows { startGrowth(for: model) }

        switch phase {
        case .hidden:
            panel.alphaValue = 0
            // No travel on the way in. A window origin lands on whole points, so four
            // points of rise had five reachable positions: three moves and then five
            // frames standing still, read as a catch. The direction is carried by the
            // content settling out of the corner nearest the caret instead.
            panel.setFrame(panelFrame(for: frame, travel: 0), display: true)
            panel.orderFrontRegardless()
            appear(to: frame)
        case .dismissing:
            appear(to: frame)
        case .appearing:
            // Alpha keeps rising from where it is; only the destination changes.
            appear(to: frame)
        case .holding:
            reposition(to: frame)
            scheduleHide(for: model, after: 0)
        }
    }

    // MARK: - Phases

    /// A re-trigger while the bubble is up. It travels to the new caret instead of
    /// being teleported there in one frame. The size is taken at once, as on the way
    /// in, so the glass underneath and the edges drawn over it stay together; only the
    /// origin is animated.
    private func reposition(to frame: CGRect) {
        let destination = panelFrame(for: frame, travel: 0)
        resizePanelAtOnce(to: destination.size)
        guard !reduceMotion, panel.frame.origin != destination.origin else {
            panel.setFrame(destination, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = BubbleMotion.repositionDuration
            context.timingFunction = BubbleMotion.appearTimingFunction
            panel.animator().setFrame(destination, display: true)
        }
    }

    private func appear(to frame: CGRect) {
        phase = .appearing
        hideTask?.cancel()
        let current = generation
        let duration = reduceMotion ? BubbleMotion.reducedFadeIn : BubbleMotion.appearDuration
        let model = state.model
        resizePanelAtOnce(to: panelFrame(for: frame, travel: 0).size)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = BubbleMotion.appearTimingFunction
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
        // Exhaustive, with no default: how long a new archetype stays is a decision,
        // not an inherited value.
        let themeHold: Double = switch model.archetype {
        case .switcher: BubbleMotion.holdSwitcher
        case .badge: BubbleMotion.holdBadge
        case .tileTwoLine, .lineWithBar, .stackedText, .tileOnly, .mark: BubbleMotion.holdStandard
        }
        let hold = behavior.hold(automatic: themeHold)
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
                self.stopGrowth()
                self.adaptive = nil
                self.pillProgress = 0
                self.isShowingSwitch = false
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

    /// `bubbleRect` is the bubble in the panel's content coordinates: for every theme but an
    /// adaptive one, the whole panel less its shadow margin.
    private func configurePanel(for model: BubbleRenderModel, bubbleRect: CGRect, isAdaptive: Bool) {
        if panel.contentView !== container { panel.contentView = container }
        container.setPill(isAdaptive ? bubbleRect : nil, shadowMargin: model.metrics.shadowMargin.points)
        configureGlass(for: model, frame: bubbleRect)
    }

    private func configureGlass(for model: BubbleRenderModel, frame: CGRect) {
        let glass: (isDark: Bool, isLiquid: Bool)? = switch model.substrate {
        case let .glass(isDark, _): (isDark, false)
        case let .liquidGlass(isDark): (isDark, true)
        default: nil
        }
        if let glass {
            container.setGlass(.init(
                isDark: glass.isDark,
                isLiquid: glass.isLiquid,
                frame: frame,
                cornerRadius: model.metrics.bubbleRadius.points
            ))
        } else {
            container.setGlass(nil)
        }
    }

    // MARK: - Adaptive growth

    /// Records the adaptive layouts now on screen and settles how far the pill has grown.
    /// True when the pill should grow from the Mark it is showing into the row.
    private func updatePill(for model: BubbleRenderModel, layouts: AdaptiveLayouts?) -> Bool {
        let previous = adaptive
        adaptive = layouts
        guard let layouts else {
            stopGrowth()
            pillProgress = 0
            return false
        }
        let wantsRow = model.archetype == layouts.expanded.archetype
        // Already growing toward the row: a further switch retargets the thumb, not the pill.
        if wantsRow, growth != nil { return false }
        let growsFromMark = wantsRow && !reduceMotion && phase != .hidden && pillProgress == 0
            && previous.map { $0.reserved == layouts.reserved } == true
        stopGrowth()
        pillProgress = wantsRow && !growsFromMark ? 1 : 0
        return growsFromMark
    }

    /// The pill in the panel's content coordinates. An adaptive pill keeps the leading edge
    /// and the edge nearest the caret of the area kept for the row, on whole device pixels
    /// so the glass under it and the edges over it land on the same ones.
    private func pillRect(for model: BubbleRenderModel, drawnSize: CGSize) -> CGRect {
        let margin = model.metrics.shadowMargin.points
        guard let adaptive else { return CGRect(origin: CGPoint(x: margin, y: margin), size: drawnSize) }
        let pill = AdaptiveExpansion.pillSize(
            compact: .init(adaptive.compactSize), expanded: .init(adaptive.expandedSize), progress: pillProgress
        )
        let origin = AdaptiveExpansion.pillOrigin(pill: pill, reserved: .init(adaptive.reserved), anchor: anchor)
        let scale = max(panel.backingScaleFactor, 1)
        func snapped(_ value: Double) -> CGFloat { CGFloat((value * scale).rounded() / scale) }
        return CGRect(x: margin + snapped(origin.x), y: margin + snapped(origin.y),
                      width: snapped(pill.width), height: snapped(pill.height))
    }

    /// The row's frame of the growth `time` seconds in; at rest (nil) or for the Mark, nothing moves.
    private func expansion(for model: BubbleRenderModel, time: Double?, originIndex: Int?) -> BubbleExpansion {
        guard let time, let adaptive, let originIndex, model.archetype == adaptive.expanded.archetype else {
            return BubbleExpansion()
        }
        let progress = AdaptiveExpansion.progress(at: time)
        let offset = AdaptiveExpansion.badgeCellCenter(BadgeMetrics(model: model), slotIndex: originIndex).map {
            AdaptiveExpansion.rowOffset(progress: progress, markGlyphCenter: adaptive.compactSize.width / 2, cellCenter: $0)
        } ?? 0
        let reveal = Dictionary(uniqueKeysWithValues: model.cells.indices.map { index in
            (index, AdaptiveExpansion.reveal(at: time, distance: abs(index - originIndex)))
        })
        return BubbleExpansion(rowOffset: CGFloat(offset), reveal: reveal)
    }

    private func startGrowth(for model: BubbleRenderModel) {
        let origin = model.previousIndex
        let maxDistance = origin.map { origin in model.cells.indices.map { abs($0 - origin) }.max() ?? 0 } ?? 0
        let clock = BubbleGrowthClock(view: container) { [weak self] time in
            self?.advanceGrowth(to: time, maxDistance: maxDistance)
        }
        growth = (clock, origin)
        growthTime = 0
    }

    /// One display frame: the pill, the glass under it and the row inside it, together.
    private func advanceGrowth(to time: Double, maxDistance: Int) {
        guard let running = growth, let model = state.model else { return }
        let origin = running.originIndex
        let finished = AdaptiveExpansion.isFinished(at: time, maxDistance: maxDistance)
        pillProgress = finished ? 1 : AdaptiveExpansion.progress(at: time)
        if finished { stopGrowth() } else { growthTime = time }
        let rect = pillRect(for: model, drawnSize: .zero)
        container.setPill(rect, shadowMargin: model.metrics.shadowMargin.points)
        configureGlass(for: model, frame: rect)
        state.updateGrowth(
            fixedSize: rect.size,
            expansion: expansion(for: model, time: finished ? nil : time, originIndex: origin)
        )
    }

    private func stopGrowth() {
        growth?.clock.stop()
        growth = nil
        growthTime = nil
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

    /// An accessibility reply is served on the focused application's own main thread,
    /// and this asks for one right after that application was handed an input source
    /// change. Without a cap the wait is unbounded: measured idle, every application
    /// answered in well under two milliseconds at the ninetieth percentile but produced
    /// outliers from seventy milliseconds to nearly a quarter of a second. Measured on
    /// macOS 27.0 with TextEdit, 51 switches with typing between them: a 50 ms cap timed
    /// out on 16 lookups (the 35 that answered took 13 ms at the median, 49 ms at most)
    /// and held typing for up to 76 ms; with this budget all 51 answered. The lookup runs
    /// off the main thread, which services the event tap, so the wait never holds the
    /// user's typing; the budget covers the whole lookup, and past it the bubble falls
    /// back to the pointer, the same path as an application that reports no caret.
    private nonisolated static let caretLookupBudget: TimeInterval = 0.25
    /// A step started with less time left than this would only time out.
    private nonisolated static let minimumStepTimeout: TimeInterval = 0.005

    /// The focused caret in accessibility coordinates (top-left origin), or nil when the app
    /// reports none within the budget. Runs on the concurrent pool: no AppKit in here.
    @concurrent
    private nonisolated static func focusedCaretAccessibilityRect() async -> CGRect? {
        // Uptime, not the wall clock, so a clock correction cannot stretch or empty the budget.
        let deadline = ProcessInfo.processInfo.systemUptime + caretLookupBudget
        // Each element carries its own timeout (the system-wide one does not reach an element it
        // returns), so every step gets what is left of the budget. A newer switch cancels this one.
        func withRemainingBudget(_ element: AXUIElement) -> Bool {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard !Task.isCancelled, remaining > minimumStepTimeout else { return false }
            AXUIElementSetMessagingTimeout(element, Float(remaining))
            return true
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard withRemainingBudget(systemWide),
              AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focusedValue, CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedElement = focusedValue as! AXUIElement

        var rangeValue: CFTypeRef?
        guard withRemainingBudget(focusedElement),
              AXUIElementCopyAttributeValue(focusedElement, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue else {
            return nil
        }

        if let rect = bounds(of: rangeValue, in: focusedElement, budget: withRemainingBudget) {
            return rect
        }
        // Many web fields (Chromium) answer an empty rect for a zero-length range. The character next to the
        // caret has a real rect: its trailing edge (before the caret) or leading edge (after it) is the caret.
        var selection = CFRange()
        guard CFGetTypeID(rangeValue) == AXValueGetTypeID(),
              AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection), selection.length == 0 else { return nil }
        // The length says whether a side has no character (start or end of the text) or just did not answer.
        var lengthValue: CFTypeRef?
        let length = withRemainingBudget(focusedElement)
            && AXUIElementCopyAttributeValue(focusedElement, kAXNumberOfCharactersAttribute as CFString, &lengthValue) == .success
            ? (lengthValue as? Int) : nil
        var found: [CaretNeighbor.Side: CaretNeighbor.Lookup] = [
            .before: selection.location == 0 ? .none : .unknown,
            .after: length.map { selection.location >= $0 } == true ? .none : .unknown,
        ]
        for candidate in CaretNeighbor.candidates(caretLocation: selection.location) where found[candidate.side] == .unknown {
            var range = CFRange(location: candidate.location, length: 1)
            guard let parameter = AXValueCreate(.cfRange, &range) else { continue }
            var boundsValue: CFTypeRef?
            guard withRemainingBudget(focusedElement) else { break }
            let error = AXUIElementCopyParameterizedAttributeValue(
                focusedElement, kAXBoundsForRangeParameterizedAttribute as CFString, parameter, &boundsValue)
            guard error == .success, let rect = Self.realRect(boundsValue) else {
                // An answer that there is nothing there (a range past the end) means no character on that side;
                // a timeout or a failure says nothing, and stays unknown.
                // Only without a known length: with one, the character exists and its missing rect stays unknown.
                if length == nil, [.illegalArgument, .noValue].contains(error) { found[candidate.side] = CaretNeighbor.Lookup.none }
                continue
            }
            // The character itself only says which way the text runs; it is not kept.
            var text: CFTypeRef?
            if withRemainingBudget(focusedElement) {
                _ = AXUIElementCopyParameterizedAttributeValue(
                    focusedElement, kAXStringForRangeParameterizedAttribute as CFString, parameter, &text)
            }
            found[candidate.side] = .found(.init(rect: .init(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height),
                                                 text: text as? String))
        }
        // An empty field has no character to measure: its leading edge is where typing starts. A field with text
        // whose caret cannot be told is left to the pointer (review A3: wrapped, right-to-left or partial evidence).
        // Without a length, an empty field shows as nothing before the start and nothing after it.
        let isEmpty = length == 0 || (length == nil && selection.location == 0 && found[.after] == CaretNeighbor.Lookup.none)
        if isEmpty {
            return fieldCaret(focusedElement, budget: withRemainingBudget)
        }
        guard let caret = CaretNeighbor.caret(before: found[.before] ?? .unknown, after: found[.after] ?? .unknown) else {
            return nil
        }
        return CGRect(x: caret.x, y: caret.y, width: caret.width, height: caret.height)
    }

    /// For an empty field only: the field itself, when it is short enough that its leading edge is where typing
    /// starts. Assumes left-to-right; a field scrolled out of its viewport is not detected (accepted, rare).
    private nonisolated static func fieldCaret(_ element: AXUIElement, budget: (AXUIElement) -> Bool) -> CGRect? {
        var positionValue: CFTypeRef?, sizeValue: CFTypeRef?
        guard budget(element),
              AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              budget(element),
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(), CFGetTypeID(sizeValue) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(positionValue as! AXValue, .cgPoint, &origin),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size),
              let caret = CaretNeighbor.caret(inField: .init(x: origin.x, y: origin.y, width: size.width, height: size.height)) else {
            return nil
        }
        return CGRect(x: caret.x, y: caret.y, width: caret.width, height: caret.height)
    }

    /// The screen rect the element gives for a range, when it gives a real one.
    private nonisolated static func bounds(of range: CFTypeRef, in element: AXUIElement, budget: (AXUIElement) -> Bool) -> CGRect? {
        var boundsValue: CFTypeRef?
        guard budget(element),
              AXUIElementCopyParameterizedAttributeValue(
                  element, kAXBoundsForRangeParameterizedAttribute as CFString, range, &boundsValue
              ) == .success else {
            return nil
        }
        return realRect(boundsValue)
    }

    /// An insertion point is a zero-width rect, which `isEmpty` would throw away: only the height says
    /// whether the app reported a real one.
    private nonisolated static func realRect(_ boundsValue: CFTypeRef?) -> CGRect? {
        guard let boundsValue, CFGetTypeID(boundsValue) == AXValueGetTypeID() else { return nil }
        let bounds = boundsValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(bounds) == .cgRect, AXValueGetValue(bounds, .cgRect, &rect), rect.height > 0 else {
            return nil
        }
        return rect
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

private extension AdaptiveExpansion.Size {
    init(_ size: CGSize) {
        self.init(width: Double(size.width), height: Double(size.height))
    }
}
