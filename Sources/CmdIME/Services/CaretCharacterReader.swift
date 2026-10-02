import AppKit
import ApplicationServices
import KeyboardSwitcherCore

/// Auto space (issue #10): the one character before the caret in the focused text element. Called off the
/// main thread by the event tap monitor after a trigger switch. Reads only that character and returns it to
/// the caller, which keeps only whether it is Han; nothing is stored or sent anywhere.
enum CaretCharacterReader {
    /// The whole lookup; an app that answers later loses this switch's space, never the typing.
    private static let budget: Float = 0.25

    static func characterBeforeCaret() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, budget)
        guard let focused = element(systemWide, kAXFocusedUIElementAttribute) else { return nil }
        AXUIElementSetMessagingTimeout(focused, budget)
        // Terminals and password fields are left alone, as Settings says.
        guard !isTerminal(focused), !isSecure(focused) else { return nil }
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focused, kAXSelectedTextRangeAttribute as CFString, &rangeValue) == .success,
              let rangeValue, CFGetTypeID(rangeValue) == AXValueGetTypeID() else { return nil }
        var selection = CFRange()
        // A selection is replaced by the next key, so the character before it is not what the key follows.
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &selection), selection.location > 0, selection.length == 0 else {
            return nil
        }
        return stringForRange(focused, location: selection.location - 1) ?? valueCharacter(focused, at: selection.location - 1)
    }

    private static func isTerminal(_ element: AXUIElement) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier else { return false }
        return TerminalCatalog.isTerminal(bundleID)
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value) == .success else { return false }
        return (value as? String) == (kAXSecureTextFieldSubrole as String)
    }

    private static func element(_ parent: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(parent, attribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    /// The parameterized attribute most text views answer. AX ranges count UTF-16 units, so the unit before
    /// the caret can be the low half of a surrogate pair: then the pair is asked for.
    private static func stringForRange(_ element: AXUIElement, location: Int) -> String? {
        for length in [1, 2] where location - length + 1 >= 0 {
            var range = CFRange(location: location - length + 1, length: length)
            guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
            var out: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(
                element, kAXStringForRangeParameterizedAttribute as CFString, parameter, &out
            ) == .success, let text = out as? String, !text.isEmpty else { return nil }
            if text.unicodeScalars.count == 1 { return text }
        }
        return nil
    }

    /// Fallback for elements that only expose their whole value (some web fields).
    private static func valueCharacter(_ element: AXUIElement, at location: Int) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        let units = Array(text.utf16)
        guard location < units.count else { return nil }
        let start = location > 0 && UTF16.isTrailSurrogate(units[location]) ? location - 1 : location
        return String(utf16CodeUnits: Array(units[start...location]), count: location - start + 1)
    }
}
