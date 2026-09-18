import AppKit
import KeyboardSwitcherCore
import SwiftUI

extension SlotBoardSection {
    func triggerTypePicker(for role: InputRole, isGhost: Bool = false) -> some View {
        ConsoleSegmentedControl(
            options: BindingTriggerType.allCases.map { ConsoleSegmentOption(value: $0, label: $0.displayName) },
            selection: Binding(
                get: { triggerType(for: role) },
                set: { if !isGhost { setTriggerType($0, for: role) } }
            )
        )
        .frame(width: 158)
    }

    @ViewBuilder
    func triggerControl(for role: InputRole, isGhost: Bool = false) -> some View {
        switch triggerType(for: role) {
        case .shortcut:
            ShortcutRecorderField(
                text: Binding(
                    get: { triggerDrafts[role] ?? model.bindingText(for: role) },
                    set: { if !isGhost { triggerDrafts[role] = $0 } }
                ),
                displayText: { text in
                    text.split(separator: "+").map { LiveKeycap(keyName: String($0)).label }.joined()
                },
                onCommit: { shortcut in
                    guard !isGhost, commitPendingRename() else { return }
                    model.setBindingText(shortcut, for: role)
                    resetDrafts()
                },
                onRecordingChanged: { recording in
                    guard !isGhost else { return }
                    model.setShortcutRecording(recording, for: role)
                }
            )
            .frame(width: 126, height: DesignTokens.Layout.fieldHeight)
        case .singleTap, .doubleTap:
            let selected = OneShotModifierChoice(trigger: model.trigger(for: role))
                ?? defaultOneShotChoice() ?? .leftCommand
            Menu {
                ForEach(OneShotModifierChoice.allCases) { choice in
                    let conflictRole = model.oneShotConflictRole(
                        forKeyCode: choice.keyCode,
                        keyName: choice.rawValue,
                        excluding: role
                    )
                    Button {
                        guard !isGhost, commitPendingRename() else { return }
                        let gesture = triggerType(for: role).gesture ?? .tap
                        model.setOneShotBinding(
                            keyCode: choice.keyCode,
                            keyName: choice.rawValue,
                            gesture: gesture,
                            for: role
                        )
                        resetDrafts()
                    } label: {
                        Label(
                            conflictRole.map { "\(choice.title) - used by \(model.config.displayName(for: $0))" } ?? choice.title,
                            systemImage: choice.iconName
                        )
                    }
                    .disabled(conflictRole != nil)
                }
            } label: {
                OneShotMenuLabel(choice: selected, role: role)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 126)
        }
    }

    private func setTriggerType(_ type: BindingTriggerType, for role: InputRole) {
        guard commitPendingRename() else { return }
        switch type {
        case .shortcut:
            triggerTypeDrafts[role] = .shortcut
            triggerDrafts[role] = ""
            model.statusText = "Record a keyboard shortcut for this slot"
        case .singleTap:
            triggerTypeDrafts[role] = nil
            setOneShotType(.tap, for: role)
        case .doubleTap:
            triggerTypeDrafts[role] = nil
            setOneShotType(.doubleTap, for: role)
        }
    }

    private func triggerType(for role: InputRole) -> BindingTriggerType {
        triggerTypeDrafts[role] ?? BindingTriggerType(trigger: model.trigger(for: role))
    }

    private func setOneShotType(_ gesture: TriggerGesture, for role: InputRole) {
        guard let choice = OneShotModifierChoice(trigger: model.trigger(for: role))
            ?? defaultOneShotChoice() else {
            model.statusText = "Choose a modifier key or record a keyboard shortcut for this slot"
            return
        }
        model.setOneShotBinding(
            keyCode: choice.keyCode,
            keyName: choice.rawValue,
            gesture: gesture,
            for: role
        )
        resetDrafts()
    }

    private func defaultOneShotChoice() -> OneShotModifierChoice? {
        OneShotModifierChoice(trigger: model.config.nextFreeOneShotTrigger())
    }
}

private struct OneShotMenuLabel: View {
    @Environment(\.slotLook) private var slotLook
    let choice: OneShotModifierChoice
    let role: InputRole

    var body: some View {
        HStack(spacing: 6) {
            Text(choice.shortTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 0)
            Text(choice.keycapLabel)
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .foregroundStyle(slotLook.tint(for: role))
        }
        .padding(.horizontal, 8)
        .frame(width: 116, height: 26)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [DesignTokens.Colors.keycapTop, DesignTokens.Colors.keycapBottom],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                        .stroke(slotLook.tint(for: role).opacity(0.42), lineWidth: 1)
                )
        )
        .shadow(color: DesignTokens.Shadow.keycap, radius: 4, y: 3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(choice.title)
    }
}

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

private enum OneShotModifierChoice: String, CaseIterable, Identifiable, Hashable {
    case leftCommand = "left-command"
    case rightCommand = "right-command"
    case leftOption = "left-option"
    case rightOption = "right-option"
    case leftControl = "left-control"
    case rightControl = "right-control"
    case leftShift = "left-shift"
    case rightShift = "right-shift"

    var id: String {
        rawValue
    }

    init?(trigger: KeyTrigger?) {
        guard let trigger, trigger.kind == .oneShotModifier else {
            return nil
        }
        self.init(rawValue: trigger.keyName)
    }

    var title: String {
        switch self {
        case .leftCommand:
            "Left Command"
        case .rightCommand:
            "Right Command"
        case .leftOption:
            "Left Option"
        case .rightOption:
            "Right Option"
        case .leftControl:
            "Left Control"
        case .rightControl:
            "Right Control"
        case .leftShift:
            "Left Shift"
        case .rightShift:
            "Right Shift"
        }
    }

    var shortTitle: String {
        switch self {
        case .leftCommand:
            "Left Command"
        case .rightCommand:
            "Right Command"
        case .leftOption:
            "Left Option"
        case .rightOption:
            "Right Option"
        case .leftControl:
            "Left Control"
        case .rightControl:
            "Right Control"
        case .leftShift:
            "Left Shift"
        case .rightShift:
            "Right Shift"
        }
    }

    var iconName: String {
        switch self {
        case .leftCommand, .rightCommand:
            "command"
        case .leftOption, .rightOption:
            "option"
        case .leftControl, .rightControl:
            "control"
        case .leftShift, .rightShift:
            "shift"
        }
    }

    var keycapLabel: String {
        switch self {
        case .leftCommand, .rightCommand:
            "⌘"
        case .leftOption, .rightOption:
            "⌥"
        case .leftControl, .rightControl:
            "⌃"
        case .leftShift, .rightShift:
            "⇧"
        }
    }

    var keycapDetail: String {
        switch self {
        case .leftCommand, .leftOption, .leftControl, .leftShift:
            "L"
        case .rightCommand, .rightOption, .rightControl, .rightShift:
            "R"
        }
    }

    var keyCode: Int {
        switch self {
        case .leftCommand:
            55
        case .rightCommand:
            54
        case .leftOption:
            58
        case .rightOption:
            61
        case .leftControl:
            59
        case .rightControl:
            62
        case .leftShift:
            56
        case .rightShift:
            60
        }
    }
}
