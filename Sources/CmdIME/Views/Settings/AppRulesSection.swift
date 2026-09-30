import KeyboardSwitcherCore
import SwiftUI

/// App Rules (CONTEXT.md): one row per rule, and a menu to add one from the running apps or disk.
struct AppRulesSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("An app with a rule gets its slot every time it comes to the front. A trigger you press afterwards still wins.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(model.config.appRules, id: \.appID) { rule in
                AppRuleRow(model: model, rule: rule)
            }
            addMenu
        }
    }

    private var addMenu: some View {
        let ruled = Set(model.config.appRules.map(\.appID))
        let suggestions = InstalledApp.running().filter { !ruled.contains($0.id) }
        return Menu("Add App") {
            if !suggestions.isEmpty {
                Section("Running") {
                    ForEach(suggestions) { app in
                        Button(app.name) { add(app) }
                    }
                }
            }
            Button("Choose App…") {
                if let app = InstalledApp.choose() { add(app) }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Add a rule for an app")
    }

    /// A new rule starts on the first slot; "keep as is" when there are none.
    private func add(_ app: InstalledApp) {
        let target: AppRuleTarget = model.config.slots.first.map { .slot($0.id) } ?? .keepAsIs
        model.setAppRule(AppRule(appID: app.id, name: app.name, target: target))
    }
}

private struct AppRuleRow: View {
    @ObservedObject var model: AppModel
    let rule: AppRule

    var body: some View {
        let app = InstalledApp(id: rule.appID, fallbackName: rule.name)
        HStack(spacing: DesignTokens.Layout.rowGap) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(app.name).lineLimit(1)
                if !app.isInstalled {
                    Text("Not installed")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
            }
            Spacer(minLength: DesignTokens.Layout.rowGap)
            if case .slot = rule.target {
                Toggle("Remember", isOn: Binding(
                    get: { rule.rememberInstead },
                    set: { model.setAppRule(changing(\.rememberInstead, to: $0)) }
                ))
                .toggleStyle(.checkbox)
                .controlSize(.small)
                .help("Restore the input source you last used in this app; the rule's slot is used only the first time.")
            }
            targetPicker
            Button {
                model.removeAppRule(for: rule.appID)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
            .accessibilityLabel("Remove the rule for \(app.name)")
        }
    }

    private var targetPicker: some View {
        Picker("Input for \(rule.name ?? rule.appID)", selection: Binding(
            get: { rule.target },
            set: { model.setAppRule(changing(\.target, to: $0)) }
        )) {
            ForEach(model.config.slots, id: \.id) { slot in
                Text(model.config.displayName(for: slot.id)).tag(AppRuleTarget.slot(slot.id))
            }
            if case .slot(let slot) = rule.target, model.config.slot(slot) == nil {
                // Kept listed, never removed silently; it does nothing until changed.
                Text("Slot deleted").tag(rule.target)
            }
            Divider()
            Text("Keep as is").tag(AppRuleTarget.keepAsIs)
        }
        .labelsHidden()
        .fixedSize()
    }

    private func changing<Value>(_ keyPath: WritableKeyPath<AppRule, Value>, to value: Value) -> AppRule {
        var next = rule
        next[keyPath: keyPath] = value
        return next
    }
}
