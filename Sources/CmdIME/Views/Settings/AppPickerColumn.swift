import KeyboardSwitcherCore
import SwiftUI

/// The rule board's app list: running apps, or installed ones matching the search. Drag a row onto
/// a lane; drop a rule chip back here to remove its rule. Each row's menu adds it without dragging.
struct AppPickerColumn: View {
    @ObservedObject var model: AppModel
    @Binding var query: String
    let apps: [InstalledApp]
    let lanes: [AppRuleBoard.Lane]
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            TextField("Search apps", text: $query)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search installed apps")
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(apps) { app in
                        AppPickerRow(model: model, app: app, lanes: AppRuleLaneLook(config: model.config).destinations(lanes))
                    }
                }
            }
            .frame(minHeight: 120, maxHeight: 280)
            if let note {
                Text(note)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(isTargeted ? DesignTokens.Colors.danger.opacity(0.08) : DesignTokens.Colors.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .strokeBorder(isTargeted ? DesignTokens.Colors.danger.opacity(0.5) : DesignTokens.Colors.separator, lineWidth: 1)
        )
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion), value: isTargeted)
        .onDrop(of: [.utf8PlainText], isTargeted: $isTargeted) { providers in
            AppDropReader.read(providers, acceptsFiles: false) { [model] id, _ in
                // Only a rule chip dragged back removes something; an app row dropped here is a no-op.
                if model.config.appRule(for: id) != nil { model.removeAppRule(for: id) }
            }
        }
    }

    private var note: String? {
        if !query.trimmingCharacters(in: .whitespaces).isEmpty {
            return apps.isEmpty ? "No app matches." : nil
        }
        return apps.isEmpty ? "Every running app has a rule. Search to find others." : "Running apps. Search to find others."
    }
}

private struct AppPickerRow: View {
    @ObservedObject var model: AppModel
    let app: InstalledApp
    let lanes: [AppRuleBoard.Lane]
    @State private var hover = false

    var body: some View {
        let look = AppRuleLaneLook(config: model.config)
        HStack(spacing: 6) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(app.name).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 5).fill(DesignTokens.Colors.overlay(hover ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .help("Drag onto a slot to give \(app.name) a rule")
        .onDrag { AppDropReader.provider(appID: app.id, name: app.name) }
        .contextMenu {
            ForEach(lanes, id: \.target) { lane in
                Button("Add to \(look.title(lane))") { model.dropApp(appID: app.id, name: app.name, on: lane.target) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(app.name)
        .accessibilityActions {
            ForEach(lanes, id: \.target) { lane in
                Button("Add to \(look.title(lane))") { model.dropApp(appID: app.id, name: app.name, on: lane.target) }
            }
        }
    }
}
