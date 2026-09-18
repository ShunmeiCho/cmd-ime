import KeyboardSwitcherCore
import SwiftUI

/// One detected slot as a plain sentence: "Tap Left Command alone -> English (ABC)".
/// Built from the real bindings, never from default assumptions.
struct SetupSlotSentenceRow: View {
    let slot: SwitchSlot
    let triggers: [KeyTrigger]
    let source: InputSourceInfo?
    /// The slot that switched most recently lights up, like the live keys strip.
    var isActive = false
    /// Nil outside "Try it"; otherwise whether the slot was fired once.
    var isTried: Bool?

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 4) {
                if triggers.isEmpty {
                    KeycapView("-", isBound: false)
                } else {
                    ForEach(triggers, id: \.self) { trigger in
                        KeycapView(Self.symbols(for: trigger), detail: Self.detail(for: trigger),
                                   role: slot.id, isPressed: isActive)
                    }
                }
            }
            .accessibilityHidden(true)

            Text(instruction)
                .font(.callout.weight(.semibold))
                .foregroundStyle(triggers.isEmpty ? DesignTokens.Colors.textMuted : DesignTokens.Colors.textPrimary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.bold))
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .accessibilityHidden(true)

            RoleBadge(role: slot.id, symbol: InputSourcePresentation(source: source, slot: slot).symbol,
                      size: 24, isActive: isActive)
                .accessibilityHidden(true)

            Text(target)
                .font(.callout)
                .foregroundStyle(source == nil ? DesignTokens.Colors.warning : DesignTokens.Colors.textSecondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            if let isTried {
                Image(systemName: isTried ? "checkmark.circle.fill" : "circle")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isTried ? DesignTokens.Colors.success : DesignTokens.Colors.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(triggers.isEmpty ? "\(target) has no key yet" : "\(instruction) to switch to \(target)")
        .accessibilityValue(isTried.map { $0 ? "Tried" : "Not tried yet" } ?? "")
    }

    private var instruction: String {
        guard !triggers.isEmpty else { return "No key yet" }
        return triggers.map { SetupTriggerPhrase(trigger: $0).instruction }.joined(separator: ", or ")
    }

    /// "English (ABC)", or just the slot name when the source carries the same name.
    private var target: String {
        guard let source else { return "\(slot.name) (no input source matched)" }
        return source.localizedName == slot.name ? slot.name : "\(slot.name) (\(source.localizedName))"
    }

    private static func symbols(for trigger: KeyTrigger) -> String {
        let names = trigger.kind == .oneShotModifier
            ? [trigger.keyName]
            : trigger.modifiers.map(\.rawValue) + [trigger.keyName]
        let label = names.map { LiveKeycap(keyName: $0).label }.joined()
        return trigger.gesture == .doubleTap ? "\(label)\(label)" : label
    }

    private static func detail(for trigger: KeyTrigger) -> String? {
        trigger.kind == .oneShotModifier ? LiveKeycap(keyName: trigger.keyName).detail : nil
    }
}
