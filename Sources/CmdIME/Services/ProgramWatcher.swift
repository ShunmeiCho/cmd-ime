import AppKit
import ApplicationServices
import KeyboardSwitcherCore

/// Asks which program is in front in the terminal's focused pane for Program Rules, off the main
/// thread, the way `WebsiteWatcher` reads a page.
///
/// The first source is the local Herdr server: focus changes are pushed over its socket, the program
/// is asked for on every new target and then once a second (Herdr pushes nothing when a program
/// starts or ends). Whether the window in front shows Herdr at all is told from the window title's
/// first word; the title stays in `read`. The second is the terminal itself where it can say which
/// program runs in its tab in front (`TerminalScriptSource`: Ghostty builds with `pid`, Terminal.app),
/// asked through `osascript` once per read. Only the name of a program with a rule, which the user
/// wrote, leaves this class. CmdIME never reads what is on the terminal's screen.
final class ProgramWatcher: NSObject, @unchecked Sendable {
    /// How often the program is asked for while nothing is pushed.
    private static let pollInterval: TimeInterval = 1
    /// A multiplexer puts the source back when its prefix mode ends and reports the new focus up
    /// to 100 ms later (measured 2026-10-02): the read waits so a rule is applied after both.
    private static let focusSettle: TimeInterval = 0.1
    private static let titleBudget: Float = 0.25

    private let onReading: @Sendable (ProgramReading) -> Void
    /// The terminal, the pane now in focus and when the notice was received, on the clock
    /// `AppMemoryController` orders triggers by.
    private let onPaneFocus: @Sendable (pid_t, String, TimeInterval) -> Void
    private let localMachine = ProgramWatcher.shortHostName()
    private var thread: Thread?

    // Touched only on the watcher thread.
    private var pid: pid_t?
    private var generation = 0
    private var rules: [ProgramRule] = []
    private var timer: Timer?
    private var sequence = 0
    private var settleUntil: TimeInterval = 0
    private var focusStream: HerdrFocusStream?
    /// Per terminal app: whether it is asked at all (an older Ghostty is not, until relaunched).
    private var scriptAvailability: [String: TerminalScriptSource.Availability] = [:]

    init(onReading: @escaping @Sendable (ProgramReading) -> Void, onPaneFocus: @escaping @Sendable (pid_t, String, TimeInterval) -> Void) {
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

    /// A focus event for `notice.paneID` came in on the subscription, read there at `notice.time`.
    /// The pane and the time go to main as they were received: asking again here could name a
    /// pane focus has moved on to since.
    @objc private func focusPushed(_ notice: FocusNotice) {
        guard let pid else { return }
        settleUntil = now + Self.focusSettle
        let send = onPaneFocus
        let paneID = notice.paneID
        let time = notice.time
        DispatchQueue.main.async { send(pid, paneID, time) }
        // A notice for the pane the tracker already knows changes nothing there, so no new
        // target follows: read anyway, once the change has settled.
        scheduleRead(after: Self.focusSettle)
    }

    private final class FocusNotice: NSObject {
        let paneID: String
        let time: TimeInterval

        init(paneID: String, time: TimeInterval) {
            self.paneID = paneID
            self.time = time
        }
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
        let herdrRunning = Self.herdr.exists
        if herdrRunning {
            openFocusStreamIfNeeded()
        }
        var answer = herdrRunning ? Self.read(pid: pid, rules: rules, localMachine: localMachine) : Answer(context: .noRule)
        // A window that is not Herdr: ask the terminal itself, where it can say.
        if answer.context == .noRule, answer.paneID == nil, let scripted = readScripted(pid: pid) {
            answer = scripted
        }
        send(answer.context, paneID: answer.paneID, pid: pid)
        // Nothing to ask (no Herdr, a terminal that cannot say): no polling until the next target
        // (an activation, a change of rules) looks again.
        guard herdrRunning || answer.paneID != nil || answer.context == .unknown else { return }
        // A pane that changed during the read is read again at once: its program is not known yet.
        scheduleRead(after: answer.paneChangedDuringRead ? Self.rereadDelay : Self.pollInterval)
    }

    /// The program in the tab in front, asked of the terminal; nil when this terminal is not asked
    /// (not one that can say, an older build, or Automation consent refused).
    private func readScripted(pid: pid_t) -> Answer? {
        guard let app = NSRunningApplication(processIdentifier: pid), let bundleID = app.bundleIdentifier,
              let kind = TerminalScriptSource.kind(forBundleID: bundleID),
              Self.dictionaryOffers(kind, appURL: app.bundleURL) else { return nil }
        var availability = scriptAvailability[bundleID] ?? TerminalScriptSource.Availability()
        guard availability.shouldAsk(appPID: pid) else { return nil }
        defer { scriptAvailability[bundleID] = availability }
        switch Self.runScript(TerminalScriptSource.script(for: kind)) {
        case .reply(let reply):
            guard let found = TerminalScriptSource.answer(kind: kind, reply: reply) else { return Answer(context: .unknown) }
            availability.answered()
            switch found {
            case .process(let paneID, let processID):
                return Answer(context: HerdrSurface.context(program: TerminalDevice.program(ofPID: processID), rules: rules),
                              paneID: "terminal:" + paneID)
            case .device(let paneID, let device):
                return Answer(context: HerdrSurface.context(program: TerminalDevice.foregroundProgram(ofDevice: device), rules: rules),
                              paneID: "terminal:" + paneID)
            }
        case .failed(let code):
            availability.failed(errorCode: code, appPID: pid)
            return availability.shouldAsk(appPID: pid) ? Answer(context: .unknown) : nil
        case .timedOut:
            return Answer(context: .unknown)
        }
    }

    /// Whether the app's own scripting dictionary has what the script asks for. Read from the
    /// bundle, so a Ghostty without `pid` (1.3.1) is never sent an Apple Event and never makes macOS
    /// ask for consent for nothing.
    private static func dictionaryOffers(_ kind: TerminalScriptSource.Kind, appURL: URL?) -> Bool {
        guard let resources = appURL?.appendingPathComponent("Contents/Resources"),
              let names = try? FileManager.default.contentsOfDirectory(atPath: resources.path),
              let sdef = names.first(where: { $0.hasSuffix(".sdef") }),
              let text = try? String(contentsOf: resources.appendingPathComponent(sdef), encoding: .utf8) else {
            // Terminal.app keeps its dictionary elsewhere; its `tty` has been there for years.
            return kind == .terminalApp
        }
        return TerminalScriptSource.dictionaryOffers(kind, sdef: text)
    }

    private enum ScriptResult {
        case reply(String)
        /// The Apple Event error number osascript printed, or 0 when it printed none.
        case failed(Int)
        case timedOut
    }

    /// osascript's own process makes the request, so macOS asks for consent on CmdIME's behalf
    /// (the responsible process) once per terminal app.
    private static let scriptBudget: TimeInterval = 1.5
    private static let scriptPoll: TimeInterval = 0.01

    private static func runScript(_ source: String) -> ScriptResult {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        guard (try? process.run()) != nil else { return .failed(0) }
        let deadline = ProcessInfo.processInfo.systemUptime + scriptBudget
        while process.isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else {
                process.terminate()
                return .timedOut
            }
            Thread.sleep(forTimeInterval: scriptPoll)
        }
        let reply = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return .failed(errorNumber(in: message))
        }
        return .reply(reply)
    }

    /// osascript ends an error with "(-1728)".
    private static func errorNumber(in message: String) -> Int {
        guard let open = message.lastIndex(of: "("), let close = message.lastIndex(of: ")"), open < close else { return 0 }
        return Int(message[message.index(after: open)..<close]) ?? 0
    }

    private static let rereadDelay: TimeInterval = 0.05

    private struct Answer {
        let context: ProgramContext
        var paneID: String?
        var paneChangedDuringRead = false
    }

    /// Every read is sent, as for a page: main may drop one, and a repeat gets it through later.
    /// It names its pane, which is how the tracker sees a focus change no event announced.
    private func send(_ context: ProgramContext, paneID: String?, pid: pid_t) {
        sequence += 1
        let reading = ProgramReading(pid: pid, generation: generation, sequence: sequence, context: context, paneID: paneID)
        let send = onReading
        DispatchQueue.main.async { send(reading) }
    }

    private func openFocusStreamIfNeeded() {
        guard focusStream == nil,
              let descriptor = Self.herdr.openSubscription(HerdrSurface.focusSubscriptionRequest) else { return }
        focusStream = HerdrFocusStream(
            descriptor: descriptor,
            onFocus: { [weak self] paneID, time in
                self?.onWatcherThread(#selector(ProgramWatcher.focusPushed(_:)), with: FocusNotice(paneID: paneID, time: time))
            },
            onClose: { [weak self] in self?.onWatcherThread(#selector(ProgramWatcher.focusStreamClosed)) }
        )
    }

    /// Called from the stream's queue. `thread` is set once, before any stream exists.
    private func onWatcherThread(_ selector: Selector, with argument: NSObject? = nil) {
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
        guard paneNow.paneID == pane.paneID else {
            return Answer(context: .unknown, paneID: paneNow.paneID, paneChangedDuringRead: true)
        }
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
