import KeyboardSwitcherCore
import SwiftUI

/// Toggle (CONTEXT.md): one trigger that switches between two slots. Unset by default; until a
/// trigger is chosen, the two slot menus only hold a draft.
struct SlotToggleRow: View {
    @ObservedObject var model: AppModel
    @State private var draft: [InputRole]?

    private static let keys = [
        ("left-command", String(localized: "Left Command")), ("right-command", String(localized: "Right Command")),
        ("left-option", String(localized: "Left Option")), ("right-option", String(localized: "Right Option")),
        ("left-control", String(localized: "Left Control")), ("right-control", String(localized: "Right Control")),
        ("left-shift", String(localized: "Left Shift")), ("right-shift", String(localized: "Right Shift")),
    ]

    private var trigger: KeyTrigger? { model.config.toggleBinding?.trigger }

    /// The saved pair, else the draft, else the first two slots.
    private var pair: [InputRole]? {
        if let saved = model.config.toggleSlots { return [saved.0, saved.1] }
        let ids = model.config.slots.map(\.id)
        if let draft, draft.allSatisfy(ids.contains) { return draft }
        return ids.count >= 2 ? Array(ids.prefix(2)) : nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Toggle")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityHidden(true)
            HStack(spacing: DesignTokens.Layout.rowGap) {
                if let pair {
                    slotMenu(at: 0, pair: pair)
                    Image(systemName: "arrow.left.arrow.right")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .accessibilityHidden(true)
                    slotMenu(at: 1, pair: pair)
                    keyMenu(pair: pair)
                } else {
                    Text("Toggle needs two slots.")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
            }
            Text("One key switches between two slots. From any other input source it goes to the one used last.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .explanation()
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(SwitcherConfig.toggleDisplayName)
    }

    private func slotMenu(at index: Int, pair: [InputRole]) -> some View {
        let name = model.config.displayName(for: pair[index])
        return ConsoleMenuButton(title: name, tint: SlotLook(slots: model.config.slots).tint(for: pair[index])) {
            ForEach(model.config.slots, id: \.id) { slot in
                Button(model.config.displayName(for: slot.id)) { choose(slot.id, at: index, pair: pair) }
                    .accessibilityValue(slot.id == pair[index] ? String(localized: "Selected") : String(localized: "Not selected"))
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(index == 0 ? String(localized: "First Toggle slot") : String(localized: "Second Toggle slot"))
        .accessibilityValue(name)
    }

    private func keyMenu(pair: [InputRole]) -> some View {
        ConsoleMenuButton(title: shortKeyValue) {
            Button("None") { model.commitToggle(nil, slots: pair[0], pair[1]) }
                .accessibilityValue(trigger == nil ? String(localized: "Selected") : String(localized: "Not selected"))
            ForEach([TriggerGesture.tap, .doubleTap], id: \.self) { gesture in
                Divider()
                Text(gesture == .tap ? String(localized: "Single tap") : String(localized: "Double tap"))
                ForEach(Self.keys, id: \.0) { key, label in
                    let candidate = candidate(for: key, gesture: gesture)
                    let owner = candidate.flatMap { ownerName($0, pair: pair) }
                    let mover = candidate.flatMap { takenFrom($0, pair: pair) }
                    Button(owner.map { String(localized: "\(label) — used by \($0)") }
                        ?? mover.map { String(localized: "\(label) — moves from \($0)") } ?? label) {
                        model.commitToggle(candidate, slots: pair[0], pair[1])
                    }
                    .disabled(owner != nil || candidate == nil)
                    .accessibilityLabel("\(label), \(gesture == .tap ? String(localized: "single tap") : String(localized: "double tap"))")
                    .accessibilityValue(owner.map { String(localized: "Used by \($0)") } ?? (trigger == candidate ? String(localized: "Selected") : String(localized: "Not selected")))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(trigger == nil ? 0.7 : 1)
        .accessibilityLabel("Trigger for \(SwitcherConfig.toggleDisplayName)")
        .accessibilityValue(keyValue)
    }

    /// Picking the slot the other menu holds swaps the two.
    private func choose(_ id: InputRole, at index: Int, pair: [InputRole]) {
        var next = pair
        if next[1 - index] == id { next.swapAt(0, 1) } else { next[index] = id }
        guard next != pair else { return }
        draft = next
        if let trigger { model.commitToggle(trigger, slots: next[0], next[1]) }
    }

    /// Same voice as the slot cards' tap menus: glyph and side ("⌥ Right ×2"), so it fits the row.
    private var shortKeyValue: String {
        guard let trigger else { return String(localized: "None") }
        guard trigger.kind == .oneShotModifier else { return trigger.localizedDisplayName }
        let cap = LiveKeycap(keyName: trigger.keyName)
        let side = cap.detail == "L" ? String(localized: "Left") : cap.detail == "R" ? String(localized: "Right") : nil
        return [cap.label, side, trigger.gesture == .doubleTap ? "×2" : nil].compactMap { $0 }.joined(separator: " ")
    }

    private var keyValue: String {
        guard let trigger else { return String(localized: "None") }
        guard trigger.kind == .oneShotModifier,
              let label = Self.keys.first(where: { $0.0 == trigger.keyName })?.1 else { return trigger.localizedDisplayName }
        return trigger.gesture == .doubleTap ? String(localized: "Double \(label)") : label
    }

    private func candidate(for key: String, gesture: TriggerGesture) -> KeyTrigger? {
        guard var result = try? ShortcutParser.parse(key) else { return nil }
        result.gesture = gesture
        return result
    }

    /// The slot of the pair a key would be taken from, named for the menu.
    private func takenFrom(_ candidate: KeyTrigger, pair: [InputRole]) -> String? {
        model.config.toggleTakeover(of: candidate, slots: pair[0], pair[1])?.action.role.map { model.config.displayName(for: $0) }
    }

    /// Asks the same pure check the save goes through, so the menu never offers a key it would refuse.
    private func ownerName(_ candidate: KeyTrigger, pair: [InputRole]) -> String? {
        do {
            _ = try model.config.replacingToggleBinding(with: candidate, slots: pair[0], pair[1])
            return nil
        } catch .conflictingBinding(let binding) {
            return model.config.ownerDescription(of: binding)
        } catch {
            return nil
        }
    }
}
