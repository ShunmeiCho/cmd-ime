import KeyboardSwitcherCore
import SwiftUI

/// Per-app behaviour: App Rules, App Memory (CONTEXT.md), the default for apps with neither, and
/// password fields.
struct AppsPage: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
            CompactSection(title: "App Rules") { AppRulesSection(model: model) }
            CompactSection(title: "App Memory") { memoryRows }
            CompactSection(title: "Other apps") { defaultSlotRows }
            CompactSection(title: "Password fields") { passwordRows }
        }
        .buttonStyle(ConsoleButtonStyle())
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
            if model.config.rememberInputSourcePerApp || !model.rememberedSources.isEmpty {
                rememberedList
            }
        }
    }

    /// What App Memory holds right now, so a wrong memory can be dropped without turning it off.
    @ViewBuilder
    private var rememberedList: some View {
        let entries = model.rememberedSources
            .map { (app: InstalledApp(id: $0.key, fallbackName: model.config.appRule(for: $0.key)?.name), sourceID: $0.value) }
            .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
        if entries.isEmpty {
            Text(model.isListening ? "Nothing remembered yet." : "Nothing is remembered while keyboard control is paused.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
        } else {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
                HStack {
                    Text("Remembered now")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Button("Forget All") { model.forgetAllRememberedSources() }
                        .fixedSize()
                }
                ForEach(entries, id: \.app.id) { entry in
                    HStack(spacing: DesignTokens.Layout.rowGap) {
                        Image(nsImage: entry.app.icon)
                            .resizable()
                            .frame(width: 18, height: 18)
                            .accessibilityHidden(true)
                        Text(entry.app.name).lineLimit(1)
                        Spacer(minLength: DesignTokens.Layout.rowGap)
                        Text(sourceName(entry.sourceID))
                            .foregroundStyle(DesignTokens.Colors.textSecondary)
                            .lineLimit(1)
                        Button("Forget") { model.forgetRememberedSource(for: entry.app.id) }
                            .fixedSize()
                            .accessibilityLabel("Forget the input source remembered for \(entry.app.name)")
                    }
                }
            }
        }
    }

    private var defaultSlotRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text("Apps without a rule or memory")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Picker("Apps without a rule or memory", selection: Binding(
                    get: { model.config.appDefaultSlot }, set: { model.setAppDefaultSlot($0) }
                )) {
                    Text("Keep as is").tag(InputRole?.none)
                    Divider()
                    ForEach(model.config.slots, id: \.id) { slot in
                        Text(model.config.displayName(for: slot.id)).tag(Optional(slot.id))
                    }
                    if let slot = model.config.appDefaultSlot, model.config.slot(slot) == nil {
                        Text("Slot deleted").tag(Optional(slot))
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            Text("A slot here is selected every time such an app comes to the front. With App Memory on, only the first time.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var passwordRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text("Switch back after a password field")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Toggle("Switch back after a password field", isOn: Binding(
                    get: { model.config.restoreAfterPasswordField }, set: { model.setRestoreAfterPasswordField($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
            }
            Text("In a password field macOS switches to an ASCII input source such as ABC and leaves it there afterwards. This brings back the one you had.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func sourceName(_ id: String) -> String {
        model.sources.first { $0.id == id }?.localizedName ?? id
    }
}
