import AppKit
import ApplicationServices
import KeyboardSwitcherCore

/// Notices a launcher panel (Raycast, Spotlight, Alfred) taking the keyboard, off the main thread.
///
/// A panel never changes the frontmost app or the menu bar owner, and macOS posts nothing when it
/// opens or closes; the system-wide focused application is the one place it shows (2026-10-04 probe,
/// `.claude/work/launcher-probe/results.md`). So this polls that attribute on its own thread while
/// it runs, and posts to main only when the panel in front changes. Main never waits on it.
final class LauncherWatcher: NSObject, @unchecked Sendable {
    /// A panel is noticed at most this late; the probe saw one poll at this rate catch every open.
    private static let pollInterval: TimeInterval = 0.1
    /// One read must not hold the next poll for long.
    private static let readBudget: Float = 0.1

    private let onChange: @Sendable (pid_t?) -> Void
    private var thread: Thread?

    // Touched only on the watcher thread.
    private var timer: Timer?
    private var systemWide: AXUIElement?
    private var presence = LauncherPresence()
    private var lastFocusedPID: pid_t?
    private var lastFocusedIsLauncher = false

    /// `onChange` gets the pid of the launcher whose panel now has the keyboard, or nil, on main.
    init(onChange: @escaping @Sendable (pid_t?) -> Void) {
        self.onChange = onChange
        super.init()
    }

    /// Starts or stops polling. Called on main; returns at once.
    func setRunning(_ running: Bool) {
        if thread == nil {
            guard running else { return }
            let thread = Thread { [weak self] in self?.runThread() }
            thread.name = "CmdIME launcher watcher"
            thread.qualityOfService = .userInitiated
            self.thread = thread
            thread.start()
        }
        guard let thread else { return }
        perform(#selector(apply(_:)), on: thread, with: NSNumber(value: running), waitUntilDone: false)
    }

    private func runThread() {
        // A port keeps the run loop alive while stopped.
        RunLoop.current.add(Port(), forMode: .default)
        while !Thread.current.isCancelled {
            RunLoop.current.run(mode: .default, before: .distantFuture)
        }
    }

    @objc private func apply(_ running: NSNumber) {
        dispatchPrecondition(condition: .notOnQueue(.main))
        timer?.invalidate()
        timer = nil
        guard running.boolValue else {
            // Stopping ends any panel: main hears nothing more until polling starts again.
            presence = LauncherPresence()
            systemWide = nil
            return
        }
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, Self.readBudget)
        self.systemWide = systemWide
        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in self?.poll() }
        RunLoop.current.add(timer, forMode: .default)
        self.timer = timer
    }

    private func poll() {
        guard let systemWide else { return }
        guard presence.record(read(systemWide)) else { return }
        let pid = presence.launcherPID
        DispatchQueue.main.async { [onChange] in onChange(pid) }
    }

    private func read(_ systemWide: AXUIElement) -> LauncherPresence.Read {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(systemWide, kAXFocusedApplicationAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else {
            return .failed
        }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success else { return .failed }
        // The bundle id is looked up only when the focused process changes.
        if pid != lastFocusedPID {
            lastFocusedPID = pid
            let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier
            lastFocusedIsLauncher = bundleID.map(LauncherCatalog.isLauncher) ?? false
        }
        return lastFocusedIsLauncher ? .launcher(pid) : .other
    }
}
