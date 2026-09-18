import KeyboardSwitcherCore
import SwiftUI

struct SlotMatchNotice: View {
    let explanation: SlotMatchExplanation
    let preferredName: String?
    let pinUnavailableReason: String?
    let onPin: () -> Void

    var body: some View {
        switch explanation {
        case let .unavailablePreferred(id, source):
            Label("Using \(source.localizedName) because \(preferredName ?? id) is unavailable",
                  systemImage: "arrow.triangle.branch")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case let .automatic(source):
            VStack(alignment: .leading, spacing: 4) {
                Label("Matched \(source.localizedName) automatically - not pinned",
                      systemImage: "arrow.triangle.branch")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Pin", action: onPin)
                    .buttonStyle(ConsoleButtonStyle())
                    .disabled(pinUnavailableReason != nil)
                    .help(pinUnavailableReason ?? "Make this input source the slot’s preferred source.")
                    .accessibilityLabel("Pin \(source.localizedName) as the preferred input source")
                if let pinUnavailableReason {
                    Text(pinUnavailableReason).fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(DesignTokens.Typography.auxiliary)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
        case .pinned, .unmatched:
            EmptyView()
        }
    }
}
