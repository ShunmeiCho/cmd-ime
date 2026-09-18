import SwiftUI

extension Text {
    /// Explanatory copy inside a step. Wraps instead of truncating.
    func setupBodyText() -> some View {
        font(.callout)
            .foregroundStyle(DesignTokens.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Secondary notes inside a step. Wraps instead of truncating.
    func setupNoteText() -> some View {
        font(.caption)
            .foregroundStyle(DesignTokens.Colors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

enum SetupGuideCopy {
    /// How to get the settings window back. Launchpad is gone from macOS 26 on, so
    /// the hint names only what every supported system has.
    static let reopenHint = "To come back to this window, open CmdIME again from Spotlight or the Applications folder."
}

/// The inset surface used by permission rows and notices.
struct SetupInsetBackground: View {
    var stroke = DesignTokens.Colors.separator

    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
            .fill(DesignTokens.Colors.surfaceInset)
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
    }
}

/// An edge-state message: icon plus text (never color alone), then its actions.
struct SetupNotice<Actions: View>: View {
    let systemImage: String
    let tone: StatusPill.Tone
    let text: String
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tone.color)
                    .accessibilityHidden(true)
                Text(text)
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if Actions.self != EmptyView.self {
                HStack(spacing: 8) {
                    actions()
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SetupInsetBackground(stroke: tone.color.opacity(0.28)))
    }
}

extension SetupNotice where Actions == EmptyView {
    init(systemImage: String, tone: StatusPill.Tone, text: String) {
        self.init(systemImage: systemImage, tone: tone, text: text) { EmptyView() }
    }
}
