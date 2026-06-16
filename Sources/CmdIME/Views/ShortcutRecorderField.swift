import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var text: String
    var onCommit: (String) -> Void

    func makeNSView(context: Context) -> RecorderTextField {
        let field = RecorderTextField()
        field.isEditable = false
        field.isSelectable = false
        field.focusRingType = .default
        field.bezelStyle = .roundedBezel
        field.delegate = context.coordinator
        field.onShortcut = { shortcut in
            text = shortcut
            onCommit(shortcut)
        }
        return field
    }

    func updateNSView(_ nsView: RecorderTextField, context: Context) {
        nsView.stringValue = text
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {}
}

final class RecorderTextField: NSTextField {
    var onShortcut: ((String) -> Void)?

    override var acceptsFirstResponder: Bool {
        true
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            placeholderString = "Press shortcut"
        }
        return became
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            window?.makeFirstResponder(nil)
            return
        }

        guard let shortcut = shortcutString(from: event) else {
            NSSound.beep()
            return
        }

        stringValue = shortcut
        onShortcut?(shortcut)
        window?.makeFirstResponder(nil)
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
