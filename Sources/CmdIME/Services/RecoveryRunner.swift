#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import Foundation
import KeyboardSwitcherCore
import os

/// Puts pinyin that came out as latin back into the Chinese input source, once, on request.
///
/// Everything destructive is gated on `RecoveryPolicy`, a pure decision made from a snapshot read
/// before anything changes. This type gathers that snapshot and, if the decision allows it,
/// performs the one edit it permits: select the run, switch, replay the letters over the selection
/// so the editor's own replacement is the only undo unit.
///
/// The main thread is treated as precious throughout. It carries the event tap, so anything that
/// blocks here delays the user's next keystroke — accessibility calls and the selection subprocess
/// both run on a background queue, and only the cheap, main-thread-only work (TIS lookups, AppKit,
/// posting events) happens here.
@MainActor
final class RecoveryRunner {
    /// Time left between the trigger's keystrokes and the switch. Measured 2026-09-20: switching
    /// 80 ms after the last key made WeType take the replayed letters as latin in 8 of 10 runs,
    /// while 200 ms passed 10 of 10.
    private static let quietBeforeSwitch: TimeInterval = 0.2
    /// Spacing between replayed letters, and between a letter's down and up. Both are the pace the
    /// real-Mac run used; a press with no time in it does not reach the input method.
    private static let replayInterval: TimeInterval = 0.09
    private static let keyHold: TimeInterval = 0.03
    /// Extra time after the first replayed key. That key does the most work — it replaces the
    /// selected run and starts the composition.
    private static let firstKeySettle: TimeInterval = 0.4
    private static let switchSettle: TimeInterval = 0.5

    private let service: MacInputSourceService
    /// Selection runs in a short-lived child, never here. Measured 2026-09-20: a process that
    /// selects and then synthesises the keys itself had every letter committed as latin, 3 of 3,
    /// while the same selection made by a separate process composed 3 of 3.
    private let keyboardctlURL: URL?
    private var isRunning = false

    var onMessage: ((String) -> Void)?
    /// A refusal the user cannot see is indistinguishable from a broken feature, and the settings
    /// window is usually closed when recovery is used. Every outcome goes to the system log too.
    private let log = Logger(subsystem: "com.shunmei.cmd-ime", category: "recovery")

    init(service: MacInputSourceService, keyboardctlURL: URL?) {
        self.service = service
        self.keyboardctlURL = keyboardctlURL
    }

    private func report(_ message: String) {
        log.notice("\(message, privacy: .public)")
        onMessage?(message)
    }

    func run(role: InputRole, config: SwitcherConfig) {
        guard !isRunning else { return }
        // Main-thread-only work first: TIS and AppKit must be asked here.
        let target = (try? service.listInputSources()).flatMap {
            InputSourceMatcher.bestMatch(for: role, sources: $0, config: config)
        }
        guard let frontmost = NSWorkspace.shared.frontmostApplication else {
            report("Recovery needs to see the text field, and it cannot.")
            return
        }
        let current = try? service.currentInputSource()
        // An outside process cannot ask another editor whether a composition is open, but a
        // keyboard layout has none to open. Under an input method the answer is unknown.
        let hasMarkedText: Bool? = current.map { service.isKeyboardLayout(id: $0.id) ? false : nil } ?? nil
        let bundleID = frontmost.bundleIdentifier ?? ""
        let pid = frontmost.processIdentifier
        let isSecure = IsSecureEventInputEnabled()

        isRunning = true
        Task { @MainActor in
            await proceed(
                target: target,
                bundleID: bundleID,
                pid: pid,
                isSecure: isSecure,
                hasMarkedText: hasMarkedText
            )
            isRunning = false
        }
    }

    private func proceed(
        target: InputSourceInfo?,
        bundleID: String,
        pid: pid_t,
        isSecure: Bool,
        hasMarkedText: Bool?
    ) async {
        guard let accessibility = await offMain({ RecoveryAccessibility.focused(in: pid) }),
              let snapshot = await offMain({ accessibility.snapshot() }) else {
            report("Recovery needs to see the text field, and it cannot.")
            return
        }

        let context = RecoveryContext(
            isSecureEventInput: isSecure,
            bundleID: bundleID,
            axRole: snapshot.axRole,
            axSubrole: snapshot.axSubrole,
            isEditable: snapshot.isEditable,
            hasSelection: snapshot.hasSelection,
            hasMarkedText: hasMarkedText,
            textBeforeCaret: snapshot.textBeforeCaret,
            targetSourceID: target?.id
        )

        switch RecoveryPolicy.decide(context) {
        case let .refuse(refusal):
            report("refused: \(refusal.message) [app \(context.bundleID), role \(context.axRole), "
                + "subrole \(context.axSubrole ?? "none"), editable \(context.isEditable), "
                + "selection \(context.hasSelection), marked \(String(describing: context.hasMarkedText)), "
                + "target \(context.targetSourceID ?? "none")]")
        case let .recover(run):
            await recover(run: run, accessibility: accessibility, caretLocation: snapshot.caretLocation, target: target)
        }
    }

    private func recover(
        run: String,
        accessibility: RecoveryAccessibility,
        caretLocation: Int,
        target: InputSourceInfo?
    ) async {
        guard let target, let keyboardctlURL else {
            report("Recovery is not set up.")
            return
        }
        let keys = run.compactMap { try? ShortcutParser.parse(String($0)) }
        guard keys.count == run.count else {
            report("Recovery cannot type \"\(run)\" on this keyboard.")
            return
        }

        guard await offMain({ accessibility.selectExactly(run, endingAt: caretLocation) }) else {
            report("Recovery stopped before changing anything: the editor did not take the selection.")
            return
        }

        await sleep(Self.quietBeforeSwitch)
        log.notice("selecting \(target.id, privacy: .public)")
        guard await offMain({ Self.runChild(executable: keyboardctlURL, arguments: ["activate", target.id]) }) else {
            await offMain { accessibility.collapseSelection(at: caretLocation) }
            report("Recovery stopped before changing anything: \(target.localizedName) would not activate.")
            return
        }
        await sleep(Self.switchSettle)

        for (index, key) in keys.enumerated() {
            EventTapMonitor.postMarkedKey(keyCode: key.keyCode, isDown: true)
            await sleep(Self.keyHold)
            EventTapMonitor.postMarkedKey(keyCode: key.keyCode, isDown: false)
            await sleep(index == 0 ? Self.firstKeySettle : Self.replayInterval)
        }
        await sleep(0.4)
        let state = await offMain { accessibility.stateDescription() }
        log.notice("after replay: \(state, privacy: .public)")
    }

    /// Runs `work` on a background queue and suspends until it answers, so a blocking
    /// accessibility call or a subprocess never holds the main thread.
    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    private func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    nonisolated private static func runChild(executable: URL, arguments: [String]) -> Bool {
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        do { try child.run() } catch { return false }
        child.waitUntilExit()
        return child.terminationStatus == 0
    }
}
#endif
