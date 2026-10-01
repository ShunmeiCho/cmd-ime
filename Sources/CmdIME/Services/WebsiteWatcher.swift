import AppKit
import ApplicationServices
import KeyboardSwitcherCore

/// Reads the page in front of one browser for website rules, off the main thread.
///
/// Everything that talks to Accessibility lives on this watcher's own thread: the observer, its
/// run-loop source, the read and its timer. Main only posts a new target to that thread and never
/// waits on it; results come back through `DispatchQueue.main.async`. CmdIME only reads: it writes no
/// accessibility attribute to any browser (the 2026-10-01 probe found Safari and Chrome expose the
/// page address on a plain read). The page address stays inside `readContext`: only the domain of
/// the matching rule, which the user wrote, leaves it.
final class WebsiteWatcher: NSObject, @unchecked Sendable {
    /// The whole read, the same budget as the caret lookup.
    private static let readBudget: TimeInterval = 0.25
    private static let notifications = [
        kAXFocusedUIElementChangedNotification, kAXFocusedWindowChangedNotification, kAXTitleChangedNotification,
    ]

    private let onReading: @Sendable (WebsiteReading) -> Void
    private var thread: Thread?

    // Touched only on the watcher thread.
    private var pid: pid_t?
    private var generation = 0
    private var rules: [WebsiteRule] = []
    private var app: AXUIElement?
    private var observer: AXObserver?
    private var scheduler = WebsiteReadScheduler()
    private var timer: Timer?
    private var sequence = 0
    private var lastSent: WebsiteContext?

    init(onReading: @escaping @Sendable (WebsiteReading) -> Void) {
        self.onReading = onReading
        super.init()
    }

    /// Points the watcher at the browser in front (or at nothing). Called on main; returns at once.
    func retarget(pid: pid_t?, generation: Int, rules: [WebsiteRule]) {
        if thread == nil {
            guard pid != nil else { return }
            let thread = Thread { [weak self] in self?.runThread() }
            thread.name = "CmdIME website watcher"
            thread.qualityOfService = .userInitiated
            self.thread = thread
            thread.start()
        }
        guard let thread else { return }
        perform(#selector(apply(_:)), on: thread, with: Target(pid: pid, generation: generation, rules: rules),
                waitUntilDone: false)
    }

    private final class Target: NSObject {
        let pid: pid_t?
        let generation: Int
        let rules: [WebsiteRule]

        init(pid: pid_t?, generation: Int, rules: [WebsiteRule]) {
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
        removeObserver()
        timer?.invalidate()
        timer = nil
        pid = target.pid
        generation = target.generation
        rules = target.rules
        lastSent = nil
        guard let pid = target.pid else {
            app = nil
            scheduler.stopped()
            return
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, Float(Self.readBudget))
        self.app = app
        addObserver(pid: pid, app: app)
        scheduler.activated(at: now)
        scheduleNextRead()
    }

    private func addObserver(pid: pid_t, app: AXUIElement) {
        var created: AXObserver?
        let callback: AXObserverCallback = { _, _, _, refcon in
            guard let refcon else { return }
            Unmanaged<WebsiteWatcher>.fromOpaque(refcon).takeUnretainedValue().notified()
        }
        guard AXObserverCreate(pid, callback, &created) == .success, let created else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.notifications {
            AXObserverAddNotification(created, app, name as CFString, refcon)
        }
        CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(created), .defaultMode)
        observer = created
    }

    private func removeObserver() {
        guard let observer else { return }
        CFRunLoopRemoveSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
        self.observer = nil
    }

    private func notified() {
        scheduler.notified(at: now)
        scheduleNextRead()
    }

    private func scheduleNextRead() {
        timer?.invalidate()
        timer = nil
        guard let due = scheduler.nextReadDue else { return }
        let timer = Timer(timeInterval: max(0, due - now), repeats: false) { [weak self] _ in self?.readIfDue() }
        RunLoop.current.add(timer, forMode: .default)
        self.timer = timer
    }

    private func readIfDue() {
        guard let app, let pid, scheduler.beginRead(at: now) else {
            scheduleNextRead()
            return
        }
        let context = Self.readContext(app: app, rules: rules)
        scheduler.readFinished(at: now, outcome: context == .unknown ? .unknown : .answered)
        sequence += 1
        if context != lastSent {
            lastSent = context
            let reading = WebsiteReading(pid: pid, generation: generation, sequence: sequence, context: context)
            let send = onReading
            DispatchQueue.main.async { send(reading) }
        }
        scheduleNextRead()
    }

    /// Spec §5: the focused element, its ancestors up to the window, the outermost web area's
    /// address. Focus outside a page (the address bar), no address or a spent budget is `.unknown`.
    private static func readContext(app: AXUIElement, rules: [WebsiteRule]) -> WebsiteContext {
        dispatchPrecondition(condition: .notOnQueue(.main))
        let deadline = ProcessInfo.processInfo.systemUptime + readBudget
        guard let focused = value(app, kAXFocusedUIElementAttribute, deadline: deadline) else { return .unknown }
        var element = focused as! AXUIElement
        var chain: [AXUIElement] = []
        var roles: [String] = []
        var reachedTop = false
        while roles.count < WebAreaPath.maxSteps {
            let role = value(element, kAXRoleAttribute, deadline: deadline) as? String ?? ""
            chain.append(element)
            roles.append(role)
            if role == kAXWindowRole || role == kAXApplicationRole {
                reachedTop = true
                break
            }
            guard let parent = value(element, kAXParentAttribute, deadline: deadline) else { break }
            element = parent as! AXUIElement
        }
        guard let index = WebAreaPath.outermostWebArea(rolesFromFocus: roles, reachedTop: reachedTop),
              let url = value(chain[index], "AXURL", deadline: deadline) as? URL else {
            return .unknown
        }
        // A page that is not a website (a new tab page, a local file) has no rule.
        guard let host = WebsiteHost.host(of: url) else { return .noRule }
        return WebsiteRuleMatcher.match(host: host, in: rules).map { .rule($0.domain) } ?? .noRule
    }

    /// One AX read that may take only what is left of the read's budget.
    private static func value(_ element: AXUIElement, _ attribute: String, deadline: TimeInterval) -> CFTypeRef? {
        let remaining = deadline - ProcessInfo.processInfo.systemUptime
        guard remaining > 0 else { return nil }
        AXUIElementSetMessagingTimeout(element, Float(remaining))
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }
}
