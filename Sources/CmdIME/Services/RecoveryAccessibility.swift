#if os(macOS)
import AppKit
import ApplicationServices
import Foundation

/// The accessibility half of recovery, deliberately kept off the main thread.
///
/// Every one of these calls blocks until the other application answers, and the default messaging
/// timeout is measured in seconds. CmdIME's main thread carries the event tap, so one unresponsive
/// editor would not merely delay the bubble: it would delay the user's own keystrokes. Each element
/// therefore gets an explicit short timeout, and the whole type runs on a background queue.
///
/// Marked `@unchecked Sendable` because `AXUIElement` is a CoreFoundation type Swift cannot reason
/// about; it is used from one queue at a time, never shared between concurrent calls.
struct RecoveryAccessibility: @unchecked Sendable {
    /// Long enough for an editor that is merely busy, short enough that a hung one costs a blink.
    static let messagingTimeout: Float = 0.25

    struct Snapshot: Sendable {
        let axRole: String
        let axSubrole: String?
        let isEditable: Bool
        let caretLocation: Int
        let hasSelection: Bool
        let textBeforeCaret: String
    }

    /// The focused element, held across the read and the edit so both act on the same target.
    private let element: AXUIElement

    private init(element: AXUIElement) {
        self.element = element
    }

    /// Resolves the focused element of `pid`, or nil when there is nothing to work with.
    static func focused(in pid: pid_t) -> RecoveryAccessibility? {
        let application = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(application, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focused else { return nil }
        let element = focused as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)
        return RecoveryAccessibility(element: element)
    }

    func snapshot() -> Snapshot? {
        guard let caret = selectedRange() else { return nil }
        let value = string(kAXValueAttribute as String) ?? ""
        return Snapshot(
            axRole: string(kAXRoleAttribute as String) ?? "",
            axSubrole: string(kAXSubroleAttribute as String),
            isEditable: isEditable(),
            caretLocation: caret.location,
            hasSelection: caret.length > 0,
            textBeforeCaret: value.utf16Prefix(caret.location)
        )
    }

    /// Selects exactly `run`, and proves it: the range read back and the selected text must both
    /// match before anything is allowed to replace it.
    func selectExactly(_ run: String, endingAt caretLocation: Int) -> Bool {
        let range = CFRange(location: caretLocation - run.utf16.count, length: run.utf16.count)
        guard setSelectedRange(range) == .success,
              let readBack = selectedRange(),
              readBack.location == range.location, readBack.length == range.length,
              string(kAXSelectedTextAttribute as String) == run else { return false }
        return true
    }

    func collapseSelection(at location: Int) {
        _ = setSelectedRange(CFRange(location: location, length: 0))
    }

    /// For the log after a replay: what the client holds now, and where its caret sits.
    func stateDescription() -> String {
        let text = string(kAXValueAttribute as String) ?? "nil"
        let range = selectedRange().map { "{\($0.location), \($0.length)}" } ?? "nil"
        return "text \(text), selection \(range)"
    }

    // MARK: - Attributes

    private func string(_ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func isEditable() -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success
        else { return false }
        return settable.boolValue
    }

    private func selectedRange() -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value) == .success,
              let value else { return nil }
        var range = CFRange()
        guard AXValueGetValue(value as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private func setSelectedRange(_ range: CFRange) -> AXError {
        var mutable = range
        guard let value = AXValueCreate(.cfRange, &mutable) else { return .failure }
        return AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
    }
}

private extension String {
    /// The accessibility API counts in UTF-16, so a caret offset has to be applied there.
    func utf16Prefix(_ length: Int) -> String {
        guard length > 0 else { return "" }
        return String(decoding: Array(utf16.prefix(length)), as: UTF16.self)
    }
}
#endif
