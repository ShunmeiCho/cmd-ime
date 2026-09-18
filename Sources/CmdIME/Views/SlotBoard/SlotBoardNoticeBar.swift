import SwiftUI

struct SlotBoardNoticeBar: View {
    let notice: BoardNotice
    let canUndo: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void
    let onAdd: (String) -> Void
    @AccessibilityFocusState private var undoFocused: Bool

    private var discardsUndo: Bool {
        if case .removed = notice { return canUndo }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            noticeRow
            if canUndo {
                Text("Undo until the next slot change")
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
        .font(DesignTokens.Typography.body)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            .fill(DesignTokens.Colors.surfaceInset))
        .accessibilityElement(children: .contain)
        .onAppear { focusUndo() }
        .onChange(of: notice) { _ in focusUndo() }
    }

    private var noticeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch notice {
            case let .rejected(reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.warning)
            case let .found(sourceID, name):
                Label("Found \(name)", systemImage: "sparkles")
                Button("Add Slot") { onAdd(sourceID) }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .accessibilityLabel("Add slot for \(name)")
            case let .removed(name):
                Label("Removed \(name)", systemImage: "trash")
            }
            if canUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .accessibilityFocused($undoFocused)
            }
            Spacer(minLength: 0)
            Button(discardsUndo ? "Discard" : "Dismiss", action: onDismiss)
                .buttonStyle(ConsoleButtonStyle())
                .help(discardsUndo ? "Discard the opportunity to restore this removed slot." : "Hide this message. Any pending Undo remains available.")
                .accessibilityLabel(discardsUndo ? "Discard removal Undo" : "Dismiss message")
        }
    }

    private func focusUndo() {
        if case .removed = notice { undoFocused = true }
    }
}
