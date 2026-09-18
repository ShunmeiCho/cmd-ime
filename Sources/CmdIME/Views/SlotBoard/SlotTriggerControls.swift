import KeyboardSwitcherCore
import SwiftUI

extension SlotBoardSection {
    // Preserve the existing section wiring without editing its drag/layout code.
    // The old three-way selector is no longer rendered.
    func triggerTypePicker(for role: InputRole, isGhost: Bool = false) -> some View {
        EmptyView()
    }

    func triggerControl(for role: InputRole, isGhost: Bool = false) -> some View {
        TriggerKeycapFlow(spacing: 8) {
            ForEach([SlotTriggerCategory.single, .double], id: \.self) { category in
                SlotModifierMenu(model: model, role: role, category: category, isGhost: isGhost,
                                 onWillChange: commitPendingRename, onUpdated: resetDrafts)
            }
            SlotTriggerRecorder(model: model, role: role, isGhost: isGhost,
                                onWillOpen: commitPendingRename, onUpdated: resetDrafts)
        }
    }
}

// Also used by LiveKeys; keep its existing presentation unchanged.
struct LiveKeycap {
    let label: String
    let detail: String?

    init(keyName: String) {
        switch keyName {
        case "command", "left-command":
            label = "⌘"
            detail = keyName == "left-command" ? "L" : nil
        case "right-command":
            label = "⌘"
            detail = "R"
        case "option", "left-option":
            label = "⌥"
            detail = keyName == "left-option" ? "L" : nil
        case "right-option":
            label = "⌥"
            detail = "R"
        case "control", "left-control":
            label = "⌃"
            detail = keyName == "left-control" ? "L" : nil
        case "right-control":
            label = "⌃"
            detail = "R"
        case "shift", "left-shift":
            label = "⇧"
            detail = keyName == "left-shift" ? "L" : nil
        case "right-shift":
            label = "⇧"
            detail = "R"
        default:
            label = keyName.uppercased()
            detail = nil
        }
    }
}

enum BindingTriggerType: CaseIterable, Hashable {
    case shortcut
    case singleTap
    case doubleTap

    init(trigger: KeyTrigger?) {
        guard let trigger else {
            self = .shortcut
            return
        }

        switch (trigger.kind, trigger.gesture) {
        case (.oneShotModifier, .doubleTap):
            self = .doubleTap
        case (.oneShotModifier, .tap):
            self = .singleTap
        case (.keyPress, _):
            self = .shortcut
        }
    }

    var gesture: TriggerGesture? {
        switch self {
        case .shortcut:
            return nil
        case .singleTap:
            return .tap
        case .doubleTap:
            return .doubleTap
        }
    }

    var displayName: String {
        switch self {
        case .shortcut:
            "Shortcut"
        case .singleTap:
            "Single"
        case .doubleTap:
            "Double"
        }
    }
}
