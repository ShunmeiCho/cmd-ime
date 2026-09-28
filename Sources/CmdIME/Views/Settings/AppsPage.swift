import KeyboardSwitcherCore
import SwiftUI

/// Per-app behaviour. App Memory (CONTEXT.md) today; App Rules join it here.
struct AppsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
            CompactSection(title: "App Memory") { memoryRows }
        }
        .font(DesignTokens.Typography.body)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
    }

    private var memoryRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text("Remember input source per app")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Toggle("Remember input source per app", isOn: Binding(
                    get: { model.config.rememberInputSourcePerApp }, set: { model.setRememberInputSourcePerApp($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
            }
            Text("Coming back to an app selects the input source you last used there. Nothing is saved to disk, and nothing happens while keyboard control is paused.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            // macOS's own per-document switching re-selects sources on every focus change.
            if model.config.rememberInputSourcePerApp, model.isSystemPerDocumentSwitchingOn {
                Label("Turn off \"Automatically switch to a document's input source\" in Keyboard settings; it fights this.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
