import KeyboardSwitcherCore
import SwiftUI

/// Direct physical-key selection; persistence and validation stay category-scoped.
struct SlotModifierMenu: View {
    @ObservedObject var model: AppModel
    let role: InputRole
    let category: SlotTriggerCategory
    let isGhost: Bool
    let onWillChange: () -> Bool
    let onUpdated: () -> Void

    private static let keys = [
        ("left-command", "Left Command"), ("right-command", "Right Command"),
        ("left-option", "Left Option"), ("right-option", "Right Option"),
        ("left-control", "Left Control"), ("right-control", "Right Control"),
        ("left-shift", "Left Shift"), ("right-shift", "Right Shift"),
    ]

    private var trigger: KeyTrigger? { model.trigger(for: role, category: category) }
    private var name: String { model.config.displayName(for: role) }
    private var title: String { category == .single ? "Single tap" : "Double tap" }
    private var value: String {
        guard let trigger else { return "None" }
        return Self.keys.first { $0.0 == trigger.keyName }?.1 ?? trigger.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(category == .single ? "Single tap" : "Double tap")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityHidden(true)
            ConsoleMenuButton(title: shortValue,
                              tint: SlotLook(slots: model.config.slots).tint(for: role)) {
                Button("None") { select(nil) }
                    .accessibilityLabel("No \(title.lowercased()) trigger for \(name)")
                    .accessibilityValue(trigger == nil ? "Selected" : "Not selected")
                Divider()
                ForEach(Self.keys, id: \.0) { key, label in
                    let candidate = candidate(for: key)
                    let owner = candidate.flatMap(ownerName)
                    let cap = LiveKeycap(keyName: key)
                    Button("\(cap.label) \(cap.detail ?? "")  \(label)\(owner.map { " — used by \($0)" } ?? "")") {
                        select(candidate)
                    }
                    .disabled(owner != nil || candidate == nil)
                    .accessibilityLabel("\(label), \(title.lowercased()) for \(name)")
                    .accessibilityValue(owner.map { "Used by \($0)" } ?? (trigger == candidate ? "Selected" : "Not selected"))
                }
                Divider()
                Text("Many Chinese input methods use Shift to switch between Chinese and English.")
                    .font(DesignTokens.Typography.auxiliary)
            }
            .frame(maxWidth: .infinity)
            .opacity(trigger == nil ? 0.7 : 1)
            .disabled(isGhost)
            .accessibilityLabel("\(title) for \(name)")
            .accessibilityValue(value)
        }
    }

    /// Same text voice as the input-source menu above it: glyph plus side, no raised keycap.
    private var shortValue: String {
        guard let trigger else { return "None" }
        let cap = LiveKeycap(keyName: trigger.keyName)
        let side = cap.detail == "L" ? "Left" : cap.detail == "R" ? "Right" : nil
        return [cap.label, side].compactMap { $0 }.joined(separator: " ")
    }

    private func candidate(for key: String) -> KeyTrigger? {
        guard var result = try? ShortcutParser.parse(key) else { return nil }
        result.gesture = category == .double ? .doubleTap : .tap
        return result
    }

    private func ownerName(_ candidate: KeyTrigger) -> String? {
        // Ask the same pure validator used at save time, rather than duplicating
        // key/gesture equivalence or treating single and double as conflicting.
        do {
            _ = try model.config.replacingSwitchBinding(for: role, category: category, with: candidate)
        } catch SlotTriggerCategoryError.conflictingBinding(let binding) {
            if let owner = binding.action.role, owner != role,
               binding.trigger.kind == .oneShotModifier,
               binding.trigger.gesture == candidate.gesture {
                return model.config.displayName(for: owner)
            }
            // A remap or disabled key owns it: saving would be rejected, so say so up front.
            if binding.action.role == nil { return "a key remap" }
        } catch {}
        return nil
    }

    private func select(_ candidate: KeyTrigger?) {
        guard !isGhost, onWillChange() else { return }
        if model.commitRecordedTrigger(candidate, for: role, category: category) == nil { onUpdated() }
    }
}
