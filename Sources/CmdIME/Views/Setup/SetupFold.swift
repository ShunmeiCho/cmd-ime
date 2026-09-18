import SwiftUI

/// Sections of the settings page that stay folded while the first-run guide is open.
/// The raw value is also the scroll id of the section.
enum SetupFoldSection: String, Hashable, Sendable {
    case keyboardControl
    case slotBoard
    case liveKeys
    case indicator
    case runtime

    var title: String {
        switch self {
        case .keyboardControl: "Keyboard control"
        case .slotBoard: "Switch slots"
        case .liveKeys: "Live keys"
        case .indicator: "Switch indicator"
        case .runtime: "General"
        }
    }
}

/// Folding context for the settings page. Returning users never fold: `isActive`
/// is true only while the stored `hasCompletedSetup` is still false.
struct SetupFolds {
    var session: Binding<SetupGuideSession>
    var isActive: Bool

    func isFolded(_ section: SetupFoldSection) -> Bool {
        isActive && !session.wrappedValue.unfoldedSections.contains(section)
    }

    func unfold(_ section: SetupFoldSection) {
        session.wrappedValue.unfoldedSections.insert(section)
    }
}

private struct SetupFoldsKey: EnvironmentKey {
    static var defaultValue: SetupFolds {
        SetupFolds(session: .constant(SetupGuideSession()), isActive: false)
    }
}

extension EnvironmentValues {
    var setupFolds: SetupFolds {
        get { self[SetupFoldsKey.self] }
        set { self[SetupFoldsKey.self] = newValue }
    }
}

extension View {
    /// Replaces the section with a one-line bar while the first-run guide folds it.
    /// The bar stays a button, so nothing (Quit included) is ever out of reach.
    func setupFold(_ section: SetupFoldSection) -> some View {
        modifier(SetupFoldModifier(section: section))
    }
}

private struct SetupFoldModifier: ViewModifier {
    @Environment(\.setupFolds) private var folds
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let section: SetupFoldSection

    func body(content: Content) -> some View {
        Group {
            if folds.isFolded(section) {
                SetupFoldedBar(title: section.title) {
                    withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                        folds.unfold(section)
                    }
                    SetupGuideNavigation.announce("\(section.title) section shown.")
                }
                .transition(.opacity)
            } else {
                content
                    .transition(.opacity)
            }
        }
        .id(section)
    }
}

private struct SetupFoldedBar: View {
    let title: String
    let onUnfold: () -> Void

    var body: some View {
        Button(action: onUnfold) {
            HStack(spacing: 8) {
                SectionLabel(title)
                Spacer(minLength: 8)
                Text("Show")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                            .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show \(title) section")
        .accessibilityHint("Folded while the setup guide is open")
    }
}
