import AppKit
import ApplicationServices
import KeyboardSwitcherCore

/// Asks which program is in front in the terminal's focused pane for Program Rules, off the main
/// thread, the way `WebsiteWatcher` reads a page.
///
/// The source is the local Herdr server: focus changes are pushed over its socket, the program is
/// asked for on every new target and then once a second (Herdr pushes nothing when a program
/// starts or ends). Whether the window in front shows Herdr at all is told from the window title's
/// first word, the only thing read from the terminal itself; the title stays in `read`. Only the
/// name of a program with a rule, which the user wrote, leaves this class. CmdIME never reads what
/// is on the terminal's screen.
final class ProgramWatcher: NSObject, @unchecked Sendable {
    /// How often the program is asked for while nothing is pushed.
    private static let pollInterval: TimeInterval = 1
    /// A multiplexer puts the source back when its prefix mode ends and reports the new focus up
    /// to 100 ms later (measured 2026-10-02): the read waits so a rule is applied after both.
    private static let focusSettle: TimeInterval = 0.1
    private static let titleBudget: Float = 0.25

    private let onReading: @Sendable (ProgramReading) -> Void
    /// The terminal and when focus moved, on the clock `AppMemoryController` orders choices by.
    private let onPaneFocus: @Sendable (pid_t, TimeInterval) -> Void
    private let localMachine = ProgramWatcher.shortHostName()
    private var thread: Thread?

    // Touched only on the watcher thread.
    private var pid: pid_t?
    private var generation = 0
    private var rules: [ProgramRule] = []
    private var timer: Timer?
    private var sequence = 0
    private var settleUntil: TimeInterval = 0
    /// The pane the last read found in focus, to notice a focus change no event announced.
    private var lastPaneID: String?
    private var focusStream: HerdrFocusStream?

    init(onReading: @escaping @Sendable (ProgramReading) -> Void, onPaneFocus: @escaping @Sendable (pid_t, TimeInterval) -> Void) {
        self.onReading = onReading
        self.onPaneFocus = onPaneFocus
        super.init()
    }

    /// Points the watcher at the terminal in front (or at nothing). Called on main; returns at once.
    func retarget(pid: pid_t?, generation: Int, rules: [ProgramRule]) {
        if thread == nil {
            guard pid != nil else { return }
            let thread = Thread { [weak self] in self?.runThread() }
            thread.name = "CmdIME program watcher"
            thread.qualityOfService = .userInitiated
            self.thread = thread
            thread.start()
        }
        guard let thread else { return }
        perform(#selector(apply(_:)), on: thread, with: Target(pid: pid, generation: generation, rules: rules),
                waitUntilDone: false)
    }

    /// Asks again though nothing was pushed. Called on main; returns at once.
    func refresh() {
        guard let thread else { return }
        perform(#selector(readNow), on: thread, with: nil, waitUntilDone: false)
    }

    private final class Target: NSObject {
        let pid: pid_t?
        let generation: Int
        let rules: [ProgramRule]

        init(pid: pid_t?, generation: Int, rules: [ProgramRule]) {
            self.pid = pid
            self.generation = generation
            self.rules = rules
        }
    }

    private func runThread() {
        // A port keeps the run loop alive between targets.
        RunLoop.current.add(Port(), forMode: .default)
        while !Thread.current.isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }

    @objc private func apply(_ target: Target) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        timer?.invalidate()
        timer = nil
        if target.pid != pid {
            lastPaneID = nil
        }
        pid = target.pid
        generation = target.generation
        rules = target.rules
        guard target.pid != nil else {
            focusStream?.cancel()
            focusStream = nil
            return
        }
        // A new generation is read at once (the tracker may be waiting for it), but not before a
        // focus change just pushed has settled.
        scheduleRead(after: max(0, settleUntil - now))
    }

    @objc private func readNow() {
        guard pid != nil else { return }
        scheduleRead(after: 0)
    }

    /// A focus event came in on the subscription, read there at `time`.
    @objc private func focusPushed(_ time: NSNumber) {
        guard let pid else { return }
        settleUntil = now + Self.focusSettle
        // The read that follows finds the new pane; that is not a second focus change.
        lastPaneID = nil
        let send = onPaneFocus
        let at = time.doubleValue
        DispatchQueue.main.async { send(pid, at) }
    }

    @objc private func focusStreamClosed() {
        focusStream = nil
    }

    private func scheduleRead(after delay: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in self?.read() }
        RunLoop.current.add(timer, forMode: .default)
        self.timer = timer
    }

    private func read() {
        guard let pid else { return }
        // Without a server there is nothing to ask and nothing to poll for; the next target
        // (an activation, a change of rules) looks again.
        guard Self.herdr.exists else {
            send(.noRule, pid: pid)
            return
        }
        openFocusStreamIfNeeded()
        let answer = Self.read(pid: pid, rules: rules, localMachine: localMachine)
        defer { scheduleRead(after: Self.pollInterval) }
        if let paneID = answer.paneID, let lastPaneID, paneID != lastPaneID {
            // Another pane is in focus than at the last read that named one, and no event said so
            // (the subscription was down, or focus moved during this read): report it as a focus
            // change. The tracker starts a new generation and this watcher is pointed at it, so
            // this read is not sent.
            self.lastPaneID = paneID
            let send = onPaneFocus
            let at = now
            DispatchQueue.main.async { send(pid, at) }
            return
        }
        // A read that names no pane (the window or the server did not answer, or the window is
        // not Herdr) keeps the last one known, so a focus change missed meanwhile still shows.
        lastPaneID = answer.paneID ?? lastPaneID
        send(answer.context, pid: pid)
    }

    private struct Answer {
        let context: ProgramContext
        var paneID: String?
    }

    /// Every read is sent, as for a page: main may drop one, and a repeat gets it through later.
    private func send(_ context: ProgramContext, pid: pid_t) {
        sequence += 1
        let reading = ProgramReading(pid: pid, generation: generation, sequence: sequence, context: context)
        let send = onReading
        DispatchQueue.main.async { send(reading) }
    }

    private func openFocusStreamIfNeeded() {
        guard focusStream == nil,
              let descriptor = Self.herdr.openSubscription(HerdrSurface.focusSubscriptionRequest) else { return }
        focusStream = HerdrFocusStream(
            descriptor: descriptor,
            onFocus: { [weak self] time in
                self?.onWatcherThread(#selector(ProgramWatcher.focusPushed(_:)), with: NSNumber(value: time))
            },
            onClose: { [weak self] in self?.onWatcherThread(#selector(ProgramWatcher.focusStreamClosed)) }
        )
    }

    /// Called from the stream's queue. `thread` is set once, before any stream exists.
    private func onWatcherThread(_ selector: Selector, with argument: NSNumber? = nil) {
        guard let thread else { return }
        perform(selector, on: thread, with: argument, waitUntilDone: false)
    }

    private static let herdr = HerdrSocket.default

    /// The program in the focused pane against the rules, and that pane's id. A window that does
    /// not show the local Herdr (a plain tab, or another machine's panes) has nothing to ask:
    /// `noRule`, so nothing waits for it. A window or a server that does not answer is `unknown`.
    /// The focused pane is asked for again after its program: a pane switch between the two
    /// questions would pair one pane's program with the other pane.
    private static func read(pid: pid_t, rules: [ProgramRule], localMachine: String?) -> Answer {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let title = focusedWindowTitle(pid: pid) else { return Answer(context: .unknown) }
        guard let machine = HerdrSurface.machine(inWindowTitle: title), machine == localMachine else {
            return Answer(context: .noRule)
        }
        guard let pane = focusedPane() else { return Answer(context: .unknown) }
        let program = herdr.reply(to: HerdrSurface.processInfoRequest(paneID: pane.paneID))
            .flatMap(HerdrReplyParser.program(from:))
        // Only a pane read again says whose program this is: a second answer that fails is
        // "cannot tell", and one that names another pane is that pane with its program unread.
        guard let paneNow = focusedPane() else { return Answer(context: .unknown) }
        guard paneNow.paneID == pane.paneID else { return Answer(context: .unknown, paneID: paneNow.paneID) }
        return Answer(context: HerdrSurface.context(program: program, rules: rules), paneID: pane.paneID)
    }

    private static func focusedPane() -> HerdrReplyParser.FocusedPane? {
        herdr.reply(to: HerdrSurface.paneListRequest).flatMap(HerdrReplyParser.focusedPane(from:))
    }

    /// This Mac's name as Herdr writes it in the window title: the host name up to its first dot.
    private static func shortHostName() -> String? {
        var name = [CChar](repeating: 0, count: Int(MAXHOSTNAMELEN) + 1)
        guard gethostname(&name, name.count - 1) == 0 else { return nil }
        let bytes = name.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self).split(separator: ".").first.map(String.init)
    }

    private static func focusedWindowTitle(pid: pid_t) -> String? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, titleBudget)
        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window, CFGetTypeID(window) == AXUIElementGetTypeID() else { return nil }
        let element = window as! AXUIElement
        AXUIElementSetMessagingTimeout(element, titleBudget)
        var title: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &title) == .success else { return nil }
        return title as? String
    }
}
