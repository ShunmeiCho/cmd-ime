import KeyboardSwitcherCore
import SwiftUI

struct WhatsNewNoticeBar: View {
    @ObservedObject var model: AppModel
    let isSetupGuideReopened: Bool

    var body: some View {
        if !isSetupGuideReopened, let message = WhatsNewNotice.message(for: AppModel.currentVersion),
           WhatsNewNotice.shouldShow(
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
