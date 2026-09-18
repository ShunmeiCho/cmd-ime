import KeyboardSwitcherCore
import SwiftUI

struct SlotListColumn<Card: View>: View {
    let slots: [SwitchSlot]
    let notice: BoardNotice?
    let canUndo: Bool
    let seatingID: InputRole?
    @ObservedObject var drag: SlotBoardDragController
    let insertionTint: Color
    let onUndo: () -> Void
    let onDismiss: () -> Void
    let onAdd: (String) -> Void
    @ViewBuilder let card: (SwitchSlot) -> Card
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rows: [SlotBoardRow] {
        var ordered = slots
        if !reduceMotion, case let .slot(id) = drag.payload, let destination = drag.insertionIndex,
           let source = ordered.firstIndex(where: { $0.id == id }) {
            let slot = ordered.remove(at: source)
            ordered.insert(slot, at: min(destination, ordered.count))
        }
        var rows = ordered.map(SlotBoardRow.slot)
        if !reduceMotion, case .source = drag.payload, let index = drag.insertionIndex {
            rows.insert(.well, at: min(index, rows.count))
        }
        return rows
    }

    var body: some View {
        VStack(spacing: DesignTokens.Layout.slotRowGap) {
            ForEach(rows) { row in
                switch row {
                case let .slot(slot):
                    SlotAppearingRow { card(slot) }
                        // Keep the actual gesture host mounted, including while it moves.
                        .opacity(drag.payload == .slot(slot.id) ? 0 : 1)
                        .background {
                            if drag.payload == .slot(slot.id) {
                                RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                                    .fill(DesignTokens.Colors.surfaceInset)
                                    .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                                        .stroke(DesignTokens.Colors.separatorStrong,
                                                style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
                                    .transition(.opacity.animation(DesignTokens.Motion.quickFade))
                            }
                        }
                        .animation(DesignTokens.Motion.quickFade, value: drag.payload == .slot(slot.id))
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("slotBoard")) } action: {
                            drag.restingFrames[slot.id] = $0
                        }
                        .zIndex(seatingID == slot.id ? 1 : 0)
                        .transition(SlotBoardMotion.cardTransition(reduceMotion: reduceMotion))
                case .well:
                    InsertionWell(height: drag.placeholderHeight)
                        .transition(.identity)
                }
            }
            if slots.count == 1 {
                Text("Add a second slot to switch between input sources.")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let notice {
                SlotBoardNoticeBar(notice: notice, canUndo: canUndo, onUndo: onUndo, onDismiss: onDismiss, onAdd: onAdd)
                    .id("boardNotice")
                    .transition(SlotBoardMotion.noticeTransition(reduceMotion: reduceMotion))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("slotBoard")) } action: {
            drag.columnFrame = $0
        }
        .overlay(alignment: .topLeading) {
            if reduceMotion, let y = drag.insertionLineY {
                Rectangle().fill(insertionTint)
                    .frame(height: 2)
                    .offset(y: CGFloat(y) - drag.columnFrame.minY)
                    .transition(.opacity.animation(DesignTokens.Motion.quickFade))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .onChange(of: slots.map(\.id)) { ids in
            drag.restingFrames = drag.restingFrames.filter { ids.contains($0.key) }
        }
    }
}

private enum SlotBoardRow: Identifiable {
    case slot(SwitchSlot)
    case well

    var id: String {
        switch self {
        case let .slot(slot): "slot:\(slot.id.rawValue)"
        case .well: "insertion-well"
        }
    }
}

private struct InsertionWell: View {
    let height: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            .fill(DesignTokens.Colors.surfaceInset)
            .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .stroke(DesignTokens.Colors.separatorStrong, style: StrokeStyle(lineWidth: 1, dash: [5, 4])))
            .frame(height: height)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
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
