import KeyboardSwitcherCore
import SwiftUI

/// The slots as the bubble sees them: resolved symbol and the slot's one colour,
/// read-only. The colour is edited on the slot card; only the symbol override is
/// edited here.
struct IndicatorSlotChips: View {
    /// The settings surface the chips sit on; slot colours are lifted or tamed to
    /// stay visible against it while the stored hex stays what the user chose.
    static let settingsSurfaceHex = "#18181C"
    private static let chipMinWidth: CGFloat = 92

    @ObservedObject var model: AppModel
    @State private var editingSlot: InputRole?

    var body: some View {
        let slots = model.config.slots
        let sources = Dictionary(
            slots.compactMap { slot in model.matchedSource(for: slot.id).map { (slot.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        let symbols = SlotSymbolResolver.symbols(for: slots, sources: sources)

        VStack(alignment: .leading, spacing: 6) {
            Text("Slots")
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textSecondary)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.chipMinWidth), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(slots) { slot in
                    chip(slot, symbol: symbols[slot.id] ?? SlotSymbol(glyph: "?"))
                }
            }
            Text("Colors are edited on each slot card. Click a slot to change its symbol.")
                .font(.caption2)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func chip(_ slot: SwitchSlot, symbol: SlotSymbol) -> some View {
        let tintHex = DisplayTint.adjusted(slot.tintHex, against: Self.settingsSurfaceHex, minimum: InkLegibility.objectMinimum)
        let tint = tintHex.flatMap { Color(cmdIMEHex: $0) } ?? DesignTokens.Colors.textSecondary
        return Button {
            editingSlot = slot.id
        } label: {
            HStack(spacing: 6) {
                Text(symbol.glyph + (symbol.mark.map { " \($0)" } ?? ""))
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .fixedSize()
                Text(slot.name)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .frame(minHeight: 26)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceInset)
                    .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(tint.opacity(0.55), lineWidth: 1))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(slot.name), symbol \(symbol.glyph)")
        .accessibilityHint("Edits the symbol shown in the indicator")
        .appearancePopover(isPresented: Binding(
            get: { editingSlot == slot.id },
            set: { if !$0 { editingSlot = nil } }
        )) {
            SlotSymbolEditor(model: model, slot: slot, automaticGlyph: automaticGlyph(for: slot))
        }
    }

    /// What the rule gives this slot when it has no override: the field's placeholder.
    private func automaticGlyph(for slot: SwitchSlot) -> String {
        var cleared = model.config.slots
        if let index = cleared.firstIndex(of: slot) { cleared[index].symbol = nil }
        let sources = Dictionary(
            cleared.compactMap { member in model.matchedSource(for: member.id).map { (member.id, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return SlotSymbolResolver.symbols(for: cleared, sources: sources)[slot.id]?.glyph ?? ""
    }
}

private struct SlotSymbolEditor: View {
    @ObservedObject var model: AppModel
    let slot: SwitchSlot
    let automaticGlyph: String
    @State private var draft: String
    @State private var errorText: String?

    init(model: AppModel, slot: SwitchSlot, automaticGlyph: String) {
        self.model = model
        self.slot = slot
        self.automaticGlyph = automaticGlyph
        _draft = State(initialValue: slot.symbol ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Symbol for \(slot.name)")
                .font(DesignTokens.Typography.body.weight(.semibold))
            HStack(spacing: 8) {
                TextField(automaticGlyph, text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 72)
                    .onSubmit(apply)
                    .accessibilityLabel("Symbol")
                Button("Set", action: apply)
                Button("Reset") {
                    draft = ""
                    apply()
                }
                .disabled(slot.symbol == nil)
            }
            Text("One or two characters. Leave empty to use the automatic symbol.")
                .font(.caption2)
                .foregroundStyle(.secondary)
            if let errorText {
                IndicatorNotice(text: errorText)
            }
        }
        .padding(12)
        .frame(width: 260, alignment: .leading)
    }

    private func apply() {
        errorText = model.setSlotSymbol(draft, for: slot.id)
    }
}
