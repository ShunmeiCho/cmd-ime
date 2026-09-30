import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// App Rules (CONTEXT.md) as a board, the way the slot board works: apps on the left, one lane per
/// slot plus "Keep as is" on the right, and dragging an app onto a lane gives it that rule. Add App,
/// the app rows' menus and each chip's menu do the same without dragging.
struct AppRulesSection: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var running = InstalledApp.running()
    @State private var installed: [InstalledApp] = []

    var body: some View {
        let lanes = AppRuleBoard.lanes(for: model.config)
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("An app with a rule gets its slot every time it comes to the front. A trigger you press afterwards still wins.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if model.config.appRules.isEmpty {
                Text("Drag an app from the list onto a slot, or use Add App.")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            HStack(alignment: .top, spacing: DesignTokens.Layout.panelGap) {
                AppPickerColumn(model: model, query: $query, apps: visibleApps, lanes: lanes)
                    .frame(width: DesignTokens.Layout.sourcePanelWidth)
                VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
                    ForEach(lanes, id: \.target) { lane in
                        AppRuleLane(model: model, lane: lane, lanes: lanes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            addMenu
        }
        .task {
            installed = await Task.detached(priority: .utility) { InstalledApp.installed() }.value
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            running = InstalledApp.running()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            running = InstalledApp.running()
        }
    }

    private var visibleApps: [InstalledApp] {
        let candidates = AppCandidateList.visible(
            running: running.map(\.candidate),
            installed: installed.map(\.candidate),
            ruledIDs: Set(model.config.appRules.map(\.appID)),
            ownAppID: Bundle.main.bundleIdentifier,
            query: query
        )
        return candidates.map { InstalledApp(id: $0.id, name: $0.name) }
    }

    private var addMenu: some View {
        let ruled = Set(model.config.appRules.map(\.appID))
        let suggestions = running.filter { !ruled.contains($0.id) }
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

    /// A new rule starts on the first slot; "keep as is" when there are none. Each chip's menu
    /// moves it from there.
    private func add(_ app: InstalledApp) {
        let target: AppRuleTarget = model.config.slots.first.map { .slot($0.id) } ?? .keepAsIs
        model.dropApp(appID: app.id, name: app.name, on: target)
    }
}
