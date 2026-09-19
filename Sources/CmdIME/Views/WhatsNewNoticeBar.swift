import KeyboardSwitcherCore
import SwiftUI

struct WhatsNewNoticeBar: View {
    @ObservedObject var model: AppModel
    let isSetupGuideReopened: Bool

    private let message = "New in 0.6: updates install from here with Update Now, and CmdIME checks for them once a day (General > Check automatically)."

    var body: some View {
        if !isSetupGuideReopened && WhatsNewNotice.shouldShow(
            lastSeen: model.config.lastSeenWhatsNewVersion,
            current: AppModel.currentVersion,
            hasCompletedSetup: model.config.hasCompletedSetup,
            isFreshConfig: model.isFreshConfig
        ) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(message)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer(minLength: 0)
                Button("Dismiss", action: model.dismissWhatsNew)
                    .buttonStyle(ConsoleButtonStyle())
                    .fixedSize()
                    .accessibilityLabel("Dismiss what's new notice")
            }
            .font(DesignTokens.Typography.body)
            .fixedSize(horizontal: false, vertical: true)
            .padding(10)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
                .fill(DesignTokens.Colors.surfaceInset))
            .accessibilityElement(children: .contain)
            .accessibilityLabel("What's new")
        }
    }
}
