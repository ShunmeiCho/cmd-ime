import KeyboardSwitcherCore
import SwiftUI

/// Bubbles that are not a switch: Peek (the current input source on demand) and Caps Lock.
struct PeekAndCapsLockSection: View {
    @ObservedObject var model: AppModel

    private static let keys = [
        ("left-command", String(localized: "Left Command")), ("right-command", String(localized: "Right Command")),
        ("left-option", String(localized: "Left Option")), ("right-option", String(localized: "Right Option")),
        ("left-control", String(localized: "Left Control")), ("right-control", String(localized: "Right Control")),
        ("left-shift", String(localized: "Left Shift")), ("right-shift", String(localized: "Right Shift")),
    ]

    var body: some View {
        CompactSection(title: String(localized: "More bubbles")) {
            VStack(alignment: .leading, spacing: 10) {
                peekRow
                Text("Shows the bubble for the current input source without switching. For a shortcut such as Option+P, run keyboardctl bind option+p peek.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                    .explanation()
                capsLockRow
                Text("A bubble when Caps Lock turns on or off.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .explanation()
            }
        }
    }

    private var peekRow: some View {
        CompactSettingRow(String(localized: "Peek")) {
            ConsoleMenuButton(title: peekValue) {
                Button("None") { model.commitPeekTrigger(nil) }
                    .accessibilityValue(model.peekTrigger == nil ? String(localized: "Selected") : String(localized: "Not selected"))
                ForEach([TriggerGesture.tap, .doubleTap], id: \.self) { gesture in
                    Divider()
                    Text(gesture == .tap ? String(localized: "Single tap") : String(localized: "Double tap"))
                    ForEach(Self.keys, id: \.0) { key, label in
                        let candidate = candidate(for: key, gesture: gesture)
                        let owner = candidate.flatMap(ownerName)
                        Button(owner.map { String(localized: "\(label) — used by \($0)") } ?? label) {
                            model.commitPeekTrigger(candidate)
                        }
                        .disabled(owner != nil || candidate == nil)
                        .accessibilityLabel("\(label), \(gesture == .tap ? String(localized: "single tap") : String(localized: "double tap"))")
                        .accessibilityValue(owner.map { String(localized: "Used by \($0)") } ?? (model.peekTrigger == candidate ? String(localized: "Selected") : String(localized: "Not selected")))
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
        CompactSettingRow(String(localized: "Caps Lock")) {
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
        guard let trigger = model.peekTrigger else { return String(localized: "None") }
        guard trigger.kind == .oneShotModifier,
              let label = Self.keys.first(where: { $0.0 == trigger.keyName })?.1 else { return trigger.localizedDisplayName }
        return trigger.gesture == .doubleTap ? String(localized: "Double \(label)") : label
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
