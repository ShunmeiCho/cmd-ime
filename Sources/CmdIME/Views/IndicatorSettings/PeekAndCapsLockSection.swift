import KeyboardSwitcherCore
import SwiftUI

/// Bubbles that are not a switch: Peek (the current input source on demand) and Caps Lock.
struct PeekAndCapsLockSection: View {
    @ObservedObject var model: AppModel

    private static let keys = [
        ("left-command", "Left Command"), ("right-command", "Right Command"),
        ("left-option", "Left Option"), ("right-option", "Right Option"),
        ("left-control", "Left Control"), ("right-control", "Right Control"),
        ("left-shift", "Left Shift"), ("right-shift", "Right Shift"),
    ]

    var body: some View {
        CompactSection(title: "More bubbles") {
            VStack(alignment: .leading, spacing: 10) {
                peekRow
                Text("Shows the bubble for the current input source without switching. For a shortcut such as Option+P, run keyboardctl bind option+p peek.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                capsLockRow
                Text("A bubble when Caps Lock turns on or off.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
        }
    }

    private var peekRow: some View {
        CompactSettingRow("Peek") {
            ConsoleMenuButton(title: peekValue) {
                Button("None") { model.commitPeekTrigger(nil) }
                    .accessibilityValue(model.peekTrigger == nil ? "Selected" : "Not selected")
                ForEach([TriggerGesture.tap, .doubleTap], id: \.self) { gesture in
                    Divider()
                    Text(gesture == .tap ? "Single tap" : "Double tap")
                    ForEach(Self.keys, id: \.0) { key, label in
                        let candidate = candidate(for: key, gesture: gesture)
                        let owner = candidate.flatMap(ownerName)
                        Button("\(label)\(owner.map { " — used by \($0)" } ?? "")") {
                            model.commitPeekTrigger(candidate)
                        }
                        .disabled(owner != nil || candidate == nil)
                        .accessibilityLabel("\(label), \(gesture == .tap ? "single tap" : "double tap")")
                        .accessibilityValue(owner.map { "Used by \($0)" } ?? (model.peekTrigger == candidate ? "Selected" : "Not selected"))
                    }
                }
            }
            .frame(maxWidth: 220)
            .accessibilityLabel("Trigger for \(SwitcherConfig.peekDisplayName)")
            .accessibilityValue(peekValue)
            Spacer()
        }
    }

    private var capsLockRow: some View {
        CompactSettingRow("Caps Lock") {
            Toggle(
                "Show a bubble when Caps Lock changes",
                isOn: Binding(
                    get: { model.config.showCapsLockIndicator },
                    set: { model.setCapsLockIndicatorVisible($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(DesignTokens.Colors.success)
            .controlSize(.small)
            Spacer()
        }
    }

    private var peekValue: String {
        guard let trigger = model.peekTrigger else { return "None" }
        guard trigger.kind == .oneShotModifier,
              let label = Self.keys.first(where: { $0.0 == trigger.keyName })?.1 else { return trigger.displayName }
        return trigger.gesture == .doubleTap ? "Double \(label)" : label
    }

    private func candidate(for key: String, gesture: TriggerGesture) -> KeyTrigger? {
        guard var result = try? ShortcutParser.parse(key) else { return nil }
        result.gesture = gesture
        return result
    }

    /// Asks the same pure check the save goes through, so the menu never offers a key it would refuse.
    private func ownerName(_ candidate: KeyTrigger) -> String? {
        do {
            _ = try model.config.replacingPeekBinding(with: candidate)
            return nil
        } catch .conflictingBinding(let binding) {
            return model.config.ownerDescription(of: binding)
        } catch {
            return nil
        }
    }
}
