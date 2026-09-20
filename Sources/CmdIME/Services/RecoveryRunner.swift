#if os(macOS)
import AppKit
import ApplicationServices
import Carbon
import Foundation
import KeyboardSwitcherCore
import os

/// Puts pinyin that came out as latin back into the Chinese input source, once, on request.
///
/// Everything destructive is gated on `RecoveryPolicy`, which is a pure decision made from a
/// snapshot read before anything changes. This type only gathers that snapshot, and — if the
/// decision says so — performs the one edit it allows: select the run, switch, replay the letters
/// over the selection so the editor's own replacement is the only undo unit.
@MainActor
final class RecoveryRunner {
    /// Time left between the trigger's keystrokes and the switch. Measured 2026-09-20: switching
    /// 80 ms after the last key made WeType take the replayed letters as latin in 8 of 10 runs,
    /// while 200 ms passed 10 of 10.
    private static let quietBeforeSwitch: TimeInterval = 0.2
    /// Spacing between replayed letters, and between a letter's down and up. Both are the pace
    /// the real-Mac run used; a press with no time in it does not reach the input method.
    private static let replayInterval: TimeInterval = 0.09
    private static let keyHold: TimeInterval = 0.03
    /// Extra time after the first replayed key. That key does the most work — it replaces the
    /// selected run and starts the composition — and the measured runs that composed all left
    /// this much room after it.
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

    private func report(_ message: String) {
        log.notice("\(message, privacy: .public)")
        onMessage?(message)
    }

    init(service: MacInputSourceService, keyboardctlURL: URL?) {
        self.service = service
        self.keyboardctlURL = keyboardctlURL
    }

    func run(role: InputRole, config: SwitcherConfig) {
        guard !isRunning else { return }
        let target = (try? service.listInputSources()).flatMap {
            InputSourceMatcher.bestMatch(for: role, sources: $0, config: config)
        }
        guard let element = focusedElement(), let caret = selectedRange(element) else {
            report("Recovery needs to see the text field, and it cannot.")
            return
        }

        let value = stringAttribute(element, kAXValueAttribute as String) ?? ""
        let before = String(value.utf16Prefix(caret.location))
        let current = try? service.currentInputSource()
        let context = RecoveryContext(
            isSecureEventInput: IsSecureEventInputEnabled(),
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
            axRole: stringAttribute(element, kAXRoleAttribute as String) ?? "",
            axSubrole: stringAttribute(element, kAXSubroleAttribute as String),
            isEditable: isEditable(element),
            hasSelection: caret.length > 0,
            // An outside process cannot ask another editor whether a composition is open, but a
            // keyboard layout has none to open. Under an input method the answer is unknown.
            hasMarkedText: current.map { service.isKeyboardLayout(id: $0.id) ? false : nil } ?? nil,
            textBeforeCaret: before,
            targetSourceID: target?.id
        )

        switch RecoveryPolicy.decide(context) {
        case let .refuse(refusal):
            report("refused: \(refusal.message) [app \(context.bundleID), role \(context.axRole), "
                + "subrole \(context.axSubrole ?? "none"), editable \(context.isEditable), "
                + "selection \(context.hasSelection), marked \(String(describing: context.hasMarkedText)), "
                + "target \(context.targetSourceID ?? "none")]")
        case let .recover(run):
            isRunning = true
            // The whole thing takes about a second of waiting, and none of it may block the
            // main thread: the indicator and the event tap live there too.
            Task { @MainActor in
                await recover(run: run, element: element, caret: caret, target: target)
                isRunning = false
            }
        }
    }

    private func recover(run: String, element: AXUIElement, caret: CFRange, target: InputSourceInfo?) async {
        guard let target, let keyboardctlURL else {
            report("Recovery is not set up.")
            return
        }
        let keys = run.compactMap { try? ShortcutParser.parse(String($0)) }
        guard keys.count == run.count else {
            report("Recovery cannot type \"\(run)\" on this keyboard.")
            return
        }

        // Select exactly the run, and prove it is selected before anything replaces it.
        let range = CFRange(location: caret.location - run.utf16.count, length: run.utf16.count)
        guard setSelectedRange(element, range) == .success,
              let readBack = selectedRange(element),
              readBack.location == range.location, readBack.length == range.length,
              stringAttribute(element, kAXSelectedTextAttribute as String) == run else {
            report("Recovery stopped before changing anything: the editor did not take the selection.")
            return
        }

        await sleep(Self.quietBeforeSwitch)
        log.notice("selecting \(target.id, privacy: .public) through \(keyboardctlURL.path, privacy: .public)")
        guard selectThroughChildProcess(id: target.id, executable: keyboardctlURL) else {
            _ = setSelectedRange(element, CFRange(location: caret.location, length: 0))
            report("Recovery stopped before changing anything: \(target.localizedName) would not activate.")
            return
        }
        await sleep(Self.switchSettle)
        log.notice("""
            before replay: current \((try? self.service.currentInputSource())?.id ?? "unknown", privacy: .public),             selection \(String(describing: self.selectedRange(element)), privacy: .public),             selected text \(self.stringAttribute(element, kAXSelectedTextAttribute as String) ?? "nil", privacy: .public)
            """)

        for (index, key) in keys.enumerated() {
            EventTapMonitor.postMarkedKey(keyCode: key.keyCode, isDown: true)
            await sleep(Self.keyHold)
            EventTapMonitor.postMarkedKey(keyCode: key.keyCode, isDown: false)
            await sleep(index == 0 ? Self.firstKeySettle : Self.replayInterval)
        }
        await sleep(0.4)
        log.notice("""
            after replay: text \(self.stringAttribute(element, kAXValueAttribute as String) ?? "nil", privacy: .public),             selection \(String(describing: self.selectedRange(element)), privacy: .public),             trusted \(AXIsProcessTrusted(), privacy: .public),             keyCodes \(keys.map(\.keyCode).map(String.init).joined(separator: ","), privacy: .public)
            """)
    }

    private func sleep(_ seconds: TimeInterval) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // MARK: - Selection, in a process of its own

    private func selectThroughChildProcess(id: String, executable: URL) -> Bool {
        runChild(executable: executable, arguments: ["activate", id])
    }

    @discardableResult
    private func runChild(executable: URL, arguments: [String]) -> Bool {
        let child = Process()
        child.executableURL = executable
        child.arguments = arguments
        do { try child.run() } catch { return false }
        child.waitUntilExit()
        return child.terminationStatus == 0
    }

    // MARK: - Accessibility

    private func focusedElement() -> AXUIElement? {
        guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let application = AXUIElementCreateApplication(app.processIdentifier)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        return (focused as! AXUIElement)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func isEditable(_ element: AXUIElement) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

    private func selectedRange(_ element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func setSelectedRange(_ element: AXUIElement, _ range: CFRange) -> AXError {
        var mutable = range
        guard let value = AXValueCreate(.cfRange, &mutable) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }
}

private extension String {
    /// The accessibility API counts in UTF-16, so the caret offset has to be applied there.
    func utf16Prefix(_ length: Int) -> String {
        guard length > 0 else { return "" }
        let units = Array(utf16.prefix(length))
        return String(decoding: units, as: UTF16.self)
    }
}
#endif
