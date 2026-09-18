import KeyboardSwitcherCore
import SwiftUI

struct SlotListColumn<Card: View>: View {
    let slots: [SwitchSlot]
    let notice: BoardNotice?
    let canUndo: Bool
    let seatingID: InputRole?
    let onUndo: () -> Void
    let onDismiss: () -> Void
    @ViewBuilder let card: (SwitchSlot) -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 9) {
            ForEach(slots) { slot in
                SlotAppearingRow { card(slot) }
                    .id(slot.id)
                    .zIndex(seatingID == slot.id ? 1 : 0)
                    .transition(SlotBoardMotion.cardTransition(reduceMotion: reduceMotion))
            }
            if slots.count == 1 {
                Text("Add a second slot to switch between input sources.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let notice {
                SlotBoardNoticeBar(notice: notice, canUndo: canUndo, onUndo: onUndo, onDismiss: onDismiss)
                    .id("boardNotice")
                    .transition(SlotBoardMotion.noticeTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SlotAppearingRow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        content()
            .opacity(reduceMotion && !appeared ? 0 : 1)
            .animation(reduceMotion ? DesignTokens.Motion.quickFade : nil, value: appeared)
            .onAppear { appeared = true }
    }
}
