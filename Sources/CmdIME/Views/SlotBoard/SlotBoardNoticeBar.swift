import SwiftUI

struct SlotBoardNoticeBar: View {
    let notice: BoardNotice
    let canUndo: Bool
    let undoSlotName: String?
    let onUndo: () -> Void
    let onDismiss: () -> Void
    let onAdd: (String) -> Void
    @AccessibilityFocusState private var undoFocused: Bool

    private var removalName: String? {
        if case let .removed(name) = notice { return name }
        return undoSlotName
    }

    private var noticeSummary: String {
        switch notice {
        case let .removed(name): "Removed slot \(name)"
        case let .found(_, name): "Found input source \(name)"
        case let .rejected(reason): reason
        case let .failed(reason): reason
        }
    }

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
            case let .failed(reason):
                Label(reason, systemImage: "exclamationmark.octagon.fill")
                    .foregroundStyle(DesignTokens.Colors.danger)
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
                    .accessibilityLabel(removalName.map { "Undo removal of \($0) slot" } ?? "Undo last slot removal")
            }
            Spacer(minLength: 0)
            Button(discardsUndo ? "Discard" : "Dismiss", action: onDismiss)
                .buttonStyle(ConsoleButtonStyle())
                .help(discardsUndo ? "Discard the opportunity to restore this removed slot." : "Hide this message. Any pending Undo remains available.")
                .accessibilityLabel(discardsUndo
                    ? removalName.map { "Discard Undo for removed \($0) slot" } ?? "Discard last slot removal Undo"
                    : "Dismiss notice: \(noticeSummary)")
        }
    }

    private func focusUndo() {
        if case .removed = notice { undoFocused = true }
    }
}
