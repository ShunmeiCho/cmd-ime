import AppKit
import KeyboardSwitcherCore
import SwiftUI

enum SlotDragPayload: Equatable {
    case slot(InputRole)
    case source(String)
}

/// Only the overlay observes this object: pointer traffic never invalidates the board.
@MainActor
final class DragPointer: ObservableObject {
    @Published var location: CGPoint = .zero
}

@MainActor
final class SlotBoardDragController: ObservableObject {
    enum State: Equatable { case idle, dragging, settling, returning, rejecting }

    @Published private(set) var state: State = .idle
    @Published private(set) var insertionIndex: Int?
    @Published private(set) var payload: SlotDragPayload?
    @Published private(set) var rejectionReason: String?
    @Published private(set) var motionProgress: CGFloat = 0
    let pointer = DragPointer()

    // Geometry readers may update these during layout, without publishing.
    var restingFrames: [InputRole: CGRect] = [:]
    var sourceFrames: [String: CGRect] = [:]
    var columnFrame: CGRect = .zero

    private(set) var originFrame: CGRect = .zero
    private(set) var targetFrame: CGRect = .zero
    private(set) var grabOffset: CGPoint = .zero
    private(set) var placeholderHeight: CGFloat = 0
    @Published private(set) var reduceMotion = false
    private(set) var motionToken = UUID()
    private(set) var motionDuration: Double = 0
    private(set) var sourceIndex: Int?
    private(set) var slotSnapshot: SwitchSlot?
    private(set) var sourceSnapshot: InputSourceInfo?
    private(set) var isForcingCompletion = false
    var sessionID: UUID { sessionToken }
    private var frozenColumn: CGRect = .zero
    private var heights: [Double] = []
    private var fullHeights: [Double] = []
    private var top: Double = 0
    private var pendingIndex: Int?
    private var commitAction: ((SlotDragPayload, Int) -> Bool)?
    private var validateAction: ((SlotDragPayload) -> String?)?
    private var rejectAction: ((String) -> Void)?
    private var pulseAction: ((InputRole) -> Void)?
    private var sessionToken = UUID()
    nonisolated(unsafe) private var cursorPushed = false
    // AppKit tokens are only touched on the main thread, including teardown.
    nonisolated(unsafe) private var escapeMonitor: Any?
    nonisolated(unsafe) private var resignObserver: NSObjectProtocol?

    var insertionLineGap: Int? {
        guard let insertionIndex else { return nil }
        guard let sourceIndex else { return insertionIndex }
        return SlotBoardGeometry.insertionLineGap(finalIndex: insertionIndex, sourceIndex: sourceIndex)
    }

    var insertionLineY: Double? {
        guard let gap = insertionLineGap else { return nil }
        return SlotBoardGeometry.placeholderMinY(at: gap, top: top, restingHeights: fullHeights, spacing: 9)
    }

    /// Flush an old hand-off before the view reads its current model for begin().
    func prepareForBegin() -> Bool {
        guard state != .dragging else { return false }
        forceFinish()
        endResources()
        return true
    }

    @discardableResult
    func begin(payload: SlotDragPayload, startLocation: CGPoint, location: CGPoint,
               config: SwitcherConfig, sources: [InputSourceInfo], reduceMotion: Bool,
               commit: @escaping (SlotDragPayload, Int) -> Bool,
               reject: @escaping (String) -> Void, pulse: @escaping (InputRole) -> Void,
               validate: ((SlotDragPayload) -> String?)? = nil) -> Bool {
        guard state != .dragging else { return false }
        forceFinish()
        endResources()
        if case let .source(id) = payload {
            guard let source = sources.first(where: { $0.id == id }) else {
                reject("This input source is no longer available.")
                return false
            }
            switch config.sourceUsage(of: source, among: sources) {
            case .available: break
            case let .owned(owner):
                // The host emphasises its existing usage label and rubber-bands;
                // pick-up rejection must not create a board-level notice.
                pulse(owner)
                return false
            case let .resolved(owner, _):
                pulse(owner)
                return false
            }
        }
        let ids = Set(config.slots.map(\.id))
        restingFrames = restingFrames.filter { ids.contains($0.key) }
        let snapshot = restingFrames
        guard config.slots.allSatisfy({ snapshot[$0.id] != nil }), !columnFrame.isEmpty else { return false }
        sourceIndex = nil
        slotSnapshot = nil
        sourceSnapshot = nil
        switch payload {
        case let .slot(id):
            guard let index = config.slots.firstIndex(where: { $0.id == id }),
                  let frame = snapshot[id], !frame.isEmpty else { return false }
            sourceIndex = index
            slotSnapshot = config.slots[index]
            originFrame = frame
            placeholderHeight = frame.height
        case let .source(id):
            guard let frame = sourceFrames[id], !frame.isEmpty else { return false }
            sourceSnapshot = sources.first(where: { $0.id == id })
            originFrame = frame
            placeholderHeight = snapshot.values.map(\.height).min() ?? frame.height
        }
        fullHeights = config.slots.compactMap { snapshot[$0.id].map { Double($0.height) } }
        heights = config.slots.enumerated().compactMap { index, slot in
            index == sourceIndex ? nil : snapshot[slot.id].map { Double($0.height) }
        }
        top = Double(snapshot.values.map(\.minY).min() ?? columnFrame.minY)
        frozenColumn = columnFrame
        grabOffset = CGPoint(x: startLocation.x - originFrame.minX, y: startLocation.y - originFrame.minY)
        self.reduceMotion = reduceMotion
        commitAction = commit
        validateAction = validate
        rejectAction = reject
        pulseAction = pulse
        pendingIndex = nil
        motionToken = UUID()
        sessionToken = UUID()
        targetFrame = originFrame
        motionProgress = 0
        rejectionReason = nil
        self.payload = payload
        pointer.location = location
        state = .dragging
        installResources()
        move(location: location)
        return true
    }

    func ghostFrame(at location: CGPoint) -> CGRect {
        CGRect(x: location.x - grabOffset.x, y: location.y - grabOffset.y,
               width: originFrame.width, height: originFrame.height)
    }

    func move(location: CGPoint) {
        guard state == .dragging else { return }
        pointer.location = location
        let reason = payload.flatMap { validateAction?($0) }
        if rejectionReason != reason { rejectionReason = reason }
        let ghost = ghostFrame(at: location)
        let probe = CGPoint(x: ghost.midX, y: ghost.midY)
        let inY = probe.y >= frozenColumn.minY - 24 && probe.y <= frozenColumn.maxY + 24
        let inX: Bool
        if case .source = payload { inX = probe.x >= frozenColumn.minX - 7 } else { inX = true }
        let next = inY && inX && reason == nil ? SlotBoardGeometry.insertionIndex(
            probeY: Double(probe.y), top: top, restingHeights: heights,
            spacing: 9, placeholderHeight: Double(placeholderHeight)) : nil
        setInsertion(next)
    }

    func drop() {
        guard state == .dragging, payload != nil else { return }
        // Revalidate even if hover rejection previously closed the gap. Also
        // recover the index if the source became available without pointer motion.
        move(location: pointer.location)
        if let rejectionReason {
            rejectAction?(rejectionReason)
            rejectDrop()
            return
        }
        guard let index = insertionIndex else { requestCancel(); return }
        pendingIndex = index
        let y = SlotBoardGeometry.placeholderMinY(at: index, top: top, restingHeights: heights, spacing: 9)
        targetFrame = CGRect(x: frozenColumn.minX, y: y, width: originFrame.width, height: originFrame.height)
        if reduceMotion {
            guard performCommit() else { rejectDrop(); return }
        }
        startMotion(.settling)
    }

    /// The gesture sentinel is the sole normal resource-cleanup point. Deferral
    /// makes both possible orderings of onEnded and @GestureState reset safe.
    func gestureDidEnd() {
        let token = sessionToken
        DispatchQueue.main.async { [weak self] in
            guard let self, self.sessionToken == token else { return }
            if self.state == .dragging { self.requestCancel() }
            self.endResources()
        }
    }

    /// A disappearing root cannot rely on an unmounted ghost's completion.
    func tearDown() {
        forceFinish()
        sessionToken = UUID()
        endResources()
    }

    func updateReduceMotion(_ reduced: Bool) {
        guard reduceMotion != reduced else { return }
        reduceMotion = reduced
        if reduced, state == .settling {
            guard performCommit() else { rejectDrop(); return }
            startMotion(.settling)
        } else if reduced, state == .returning || state == .rejecting {
            targetFrame = originFrame
            startMotion(.returning)
        }
    }

    /// Backstops (host disappearance / app resign) cannot rely on the sentinel.
    func cancel() {
        requestCancel()
        endResources()
    }

    /// Normal Esc / outside release latch cancellation, leaving resources for
    /// the host's single sentinel cleanup point.
    private func requestCancel() {
        guard state != .idle else { return }
        if state == .settling { forceFinish(); return }
        if state == .dragging || state == .rejecting {
            pendingIndex = nil
            targetFrame = originFrame
            setInsertion(nil)
            startMotion(.returning)
        }
    }

    func finishMotion(token: UUID, phase: State) {
        guard token == motionToken, phase == state else { return }
        switch state {
        case .settling:
            guard performCommit() else { rejectDrop(); return }
            clearSession()
        case .rejecting:
            targetFrame = originFrame
            startMotion(.returning)
        case .returning: clearSession()
        case .idle, .dragging: break
        }
    }

    private func setInsertion(_ index: Int?) {
        guard insertionIndex != index else { return }
        withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
            insertionIndex = index
        }
        if index != nil { NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now) }
    }

    private func startMotion(_ phase: State) {
        motionToken = UUID()
        motionDuration = reduceMotion ? DesignTokens.Motion.fast : DesignTokens.Motion.slow
        motionProgress = 0
        state = phase
        let token = motionToken
        // Establish the zero endpoint before animating; never use a wall-clock completion.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.motionToken == token, self.state == phase else { return }
            withAnimation(.linear(duration: self.motionDuration)) { self.motionProgress = 1 }
        }
    }

    private func performCommit() -> Bool {
        guard let index = pendingIndex, let payload else { return true }
        pendingIndex = nil // consume before invoking application code (reentrancy safe)
        let result = withAnimation(nil) { commitAction?(payload, index) ?? false }
        if result, case let .slot(id) = payload, sourceIndex != index { pulseAction?(id) }
        // The commit callback owns the specific model notice. A generic ghost
        // reason must never overwrite a persistence/core error in that notice.
        if !result, rejectionReason == nil { rejectionReason = "The slot could not be changed." }
        return result
    }

    private func rejectDrop() {
        pendingIndex = nil
        targetFrame = reduceMotion ? originFrame : ghostFrame(at: pointer.location)
        setInsertion(nil)
        if reduceMotion {
            startMotion(.returning)
        } else {
            startMotion(.rejecting)
        }
    }

    private func forceFinish() {
        isForcingCompletion = true
        defer { isForcingCompletion = false }
        if state == .settling { _ = performCommit() }
        clearSession()
    }

    private func clearSession() {
        motionToken = UUID()
        pendingIndex = nil
        commitAction = nil
        validateAction = nil
        rejectAction = nil
        pulseAction = nil
        insertionIndex = nil
        rejectionReason = nil
        payload = nil
        state = .idle
    }

    private func installResources() {
        NSCursor.closedHand.push()
        cursorPushed = true
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let swallowed = MainActor.assumeIsolated {
                guard let self, self.state == .dragging, event.keyCode == 53 else { return false }
                self.requestCancel()
                return true
            }
            return swallowed ? nil : event
        }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    func endResources() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor); self.escapeMonitor = nil }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver); self.resignObserver = nil }
        if cursorPushed { NSCursor.pop(); cursorPushed = false }
    }

    deinit {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if cursorPushed {
            DispatchQueue.main.async { NSCursor.pop() }
        }
    }
}

struct SlotDragHandle: View {
    @ObservedObject var controller: SlotBoardDragController
    let enabled: Bool
    let onBegin: (DragGesture.Value) -> Bool
    @GestureState private var isDragging = false
    @State private var attempted = false
    @State private var accepted = false
    @State private var hover = false

    var body: some View {
        SlotDragHandleGlyph()
            .background(RoundedRectangle(cornerRadius: 3)
                .fill(Color.white.opacity(hover ? 0.07 : 0.035)))
            .contentShape(Rectangle())
            .onHover { hover = $0 }
            .animation(DesignTokens.Motion.stateChange, value: hover)
            .opacity(enabled ? 1 : 0)
            .allowsHitTesting(enabled)
            .gesture(DragGesture(minimumDistance: 4, coordinateSpace: .named("slotBoard"))
                .updating($isDragging) { _, active, _ in active = true }
                .onChanged { value in
                    if !attempted {
                        attempted = true
                        accepted = onBegin(value)
                    }
                    if accepted { controller.move(location: value.location) }
                }
                .onEnded { _ in controller.drop() })
            .onChange(of: isDragging) { active in
                guard !active else { return }
                controller.gestureDidEnd()
                attempted = false
                accepted = false
            }
            .onDisappear { if attempted { controller.cancel() } }
            .accessibilityHidden(true)
    }
}

struct SlotDragHandleGlyph: View {
    var body: some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(DesignTokens.Colors.textMuted)
            .frame(width: 14, height: 24)
    }
}

/// The pointer observer is deliberately confined to this overlay subtree.
struct SlotDragGhost<Content: View>: View {
    @ObservedObject var controller: SlotBoardDragController
    @ObservedObject var pointer: DragPointer
    let tint: Color
    @ViewBuilder let content: () -> Content
    @State private var appeared = false

    private var isSource: Bool {
        if case .source = controller.payload { return true }
        return false
    }
    private var isLifted: Bool { appeared && (controller.state == .dragging || controller.state == .rejecting) }
    private var frame: CGRect {
        if controller.state == .dragging || controller.reduceMotion {
            return controller.ghostFrame(at: pointer.location)
        }
        return controller.targetFrame
    }
    private var faded: Bool {
        !appeared || (controller.reduceMotion && controller.state != .dragging)
            || (isSource && controller.state == .settling)
    }
    private var flight: Animation? {
        guard !controller.reduceMotion else { return nil }
        return controller.state == .returning ? DesignTokens.Motion.dragReturn : DesignTokens.Motion.dragSettle
    }

    var body: some View {
        let phase = controller.state
        let token = controller.motionToken
        content()
            .frame(width: controller.originFrame.width, height: controller.originFrame.height)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                    .strokeBorder((controller.rejectionReason == nil ? tint : DesignTokens.Colors.warning)
                        .opacity(isLifted ? 0.60 : 0), lineWidth: 1)
                if controller.rejectionReason != nil {
                    Image(systemName: "nosign")
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(4)
                }
            }
            .shadow(color: DesignTokens.Shadow.surface.opacity(isLifted ? 1 : 0), radius: isLifted ? 22 : 0,
                    y: isLifted ? 12 : 0)
            .scaleEffect(isLifted && !controller.reduceMotion ? 1.03 : 1)
            .animation(controller.reduceMotion ? DesignTokens.Motion.quickFade : DesignTokens.Motion.dragLift, value: appeared)
            .opacity(faded ? 0 : 1)
            .animation(DesignTokens.Motion.quickFade, value: faded)
            .modifier(Shake(progress: phase == .rejecting ? controller.motionProgress : 0,
                            amplitude: controller.reduceMotion ? 0 : 7))
            .position(x: frame.midX, y: frame.midY)
            .animation(flight, value: phase)
            .modifier(MotionCompletion(progress: controller.motionProgress) {
                controller.finishMotion(token: token, phase: phase)
            })
            .onAppear { appeared = true }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
