import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var text: String
    var displayText: (String) -> String
    var onCommit: (String) -> Void
    var onRecordingChanged: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderTextField {
        let field = RecorderTextField()
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .default
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.setAccessibilityElement(true)
        field.setAccessibilityRole(.textField)
        field.setAccessibilityLabel("Trigger shortcut")
        field.setAccessibilityHelp("Press a key combination. Escape cancels. Tab moves to the next control.")
        updateField(field)
        return field
    }

    private func updateField(_ field: RecorderTextField) {
        field.onRecordingChanged = onRecordingChanged
        field.onShortcut = { [weak field] shortcut in
            text = shortcut
            onCommit(shortcut)
            field?.setCommittedText(text, displayText: displayText(text))
        }
        field.setCommittedText(text, displayText: displayText(text))
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        updateField(nsView)
    }

    static func dismantleNSView(_ nsView: RecorderTextField, coordinator: Coordinator) {
        nsView.endRecording()
        NotificationCenter.default.removeObserver(nsView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {}
}

final class RecorderTextField: NSTextField {
    var onShortcut: ((String) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var isRecording = false
    private var committedText = ""
    private var committedDisplayText = ""

    func setCommittedText(_ text: String, displayText: String) {
        committedText = text
        committedDisplayText = displayText
        updatePresentation()
    }

    private func updatePresentation() {
        stringValue = isRecording ? "" : committedDisplayText
        placeholderString = isRecording ? "Press shortcut" : "Click to record"
    }

    override func accessibilityValue() -> String? {
        isRecording ? "Press shortcut" : committedText
    }

    private func setRecording(_ recording: Bool) {
        guard recording != isRecording else { return }
        isRecording = recording
        updatePresentation()
        onRecordingChanged?(recording)
    }

    func endRecording() {
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        setRecording(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow !== window {
            endRecording()
            NotificationCenter.default.removeObserver(self)
        }
        super.viewWillMove(toWindow: newWindow)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        NotificationCenter.default.removeObserver(self)
        if let window {
            let center = NotificationCenter.default
            center.addObserver(self, selector: #selector(windowBecameKey), name: NSWindow.didBecomeKeyNotification, object: window)
            center.addObserver(self, selector: #selector(windowEndedRecording), name: NSWindow.didResignKeyNotification, object: window)
            center.addObserver(self, selector: #selector(windowEndedRecording), name: NSWindow.willCloseNotification, object: window)
        }
        setRecording(window?.isKeyWindow == true && window?.firstResponder === self)
    }

    @objc private func windowBecameKey(_ notification: Notification) {
        setRecording(window?.isKeyWindow == true && window?.firstResponder === self)
    }

    @objc private func windowEndedRecording(_ notification: Notification) {
        endRecording()
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            // AppKit installs the first responder after this method returns.
            setRecording(window?.isKeyWindow == true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            setRecording(false)
        }
        return resigned
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard isRecording, window?.isKeyWindow == true, window?.firstResponder === self else {
            return super.performKeyEquivalent(with: event)
        }
        keyDown(with: event)
        return true
    }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }
        if event.keyCode == 48,
           event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            if event.modifierFlags.contains(.shift) {
                window?.selectPreviousKeyView(self)
            } else {
                window?.selectNextKeyView(self)
            }
            if window?.firstResponder === self {
                endRecording()
            }
            return
        }
        if event.keyCode == 53 {
            endRecording()
            return
        }

        guard let shortcut = shortcutString(from: event) else {
            NSSound.beep()
            return
        }

        onShortcut?(shortcut)
        endRecording()
    }

    private func shortcutString(from event: NSEvent) -> String? {
        let modifiers = normalizedModifiers(event.modifierFlags)
        guard !modifiers.isEmpty else {
            return nil
        }
        guard let keyName = keyName(forKeyCode: Int(event.keyCode), characters: event.charactersIgnoringModifiers) else {
            return nil
        }
        return (modifiers + [keyName]).joined(separator: "+")
    }

    private func normalizedModifiers(_ flags: NSEvent.ModifierFlags) -> [String] {
        var modifiers: [String] = []
        if flags.contains(.command) {
            modifiers.append("command")
        }
        if flags.contains(.option) {
            modifiers.append("option")
        }
        if flags.contains(.control) {
            modifiers.append("control")
        }
        if flags.contains(.shift) {
            modifiers.append("shift")
        }
        return modifiers
    }

    private func keyName(forKeyCode keyCode: Int, characters: String?) -> String? {
        switch keyCode {
        case 36:
            return "return"
        case 48:
            return "tab"
        case 49:
            return "space"
        case 51:
            return "delete"
        case 53:
            return "escape"
        case 123:
            return "left"
        case 124:
            return "right"
        case 125:
            return "down"
        case 126:
            return "up"
        default:
            if let first = characters?.lowercased().first {
                return String(first)
            }
            return nil
        }
    }
}
