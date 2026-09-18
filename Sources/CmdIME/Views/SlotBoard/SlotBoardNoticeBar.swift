import SwiftUI

struct SlotBoardNoticeBar: View {
    let notice: BoardNotice
    let canUndo: Bool
    let onUndo: () -> Void
    let onDismiss: () -> Void
    @AccessibilityFocusState private var undoFocused: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            switch notice {
            case let .rejected(reason):
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(DesignTokens.Colors.warning)
            case let .removed(name):
                Label("Removed \(name)", systemImage: "trash")
            }
            if canUndo {
                Button("Undo", action: onUndo)
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .accessibilityFocused($undoFocused)
            }
            Spacer(minLength: 0)
            Button("Dismiss", action: onDismiss)
                .buttonStyle(ConsoleButtonStyle())
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .padding(10)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            .fill(DesignTokens.Colors.surfaceInset))
        .accessibilityElement(children: .contain)
        .onAppear { focusUndo() }
        .onChange(of: notice) { _ in focusUndo() }
    }

    private func focusUndo() {
        if case .removed = notice { undoFocused = true }
    }
}
