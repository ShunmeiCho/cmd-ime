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
    @State private var isScanningInstalled = true

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
                AppPickerColumn(model: model, query: $query, apps: visibleApps, lanes: lanes,
                                isScanningInstalled: isScanningInstalled)
                    .frame(width: DesignTokens.Layout.sourcePanelWidth)
                VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
                    ForEach(lanes, id: \.target) { lane in
                        AppRuleLane(model: model, lane: lane, lanes: lanes)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            if let notice = model.appRuleNotice {
                AppRuleNoticeRow(notice: notice) { model.dismissAppRuleNotice() }
            }
            addMenu
        }
        .onAppear { AppMetadataCache.shared.removeAll() }
        .onDisappear { model.dismissAppRuleNotice() }
        .task {
            installed = await Task.detached(priority: .utility) { InstalledApp.installed() }.value
            isScanningInstalled = false
        }
        .task(id: model.appRuleNotice) {
            guard let notice = model.appRuleNotice else { return }
            SetupGuideNavigation.announce(notice.text)
            // A confirmation clears itself; a refusal or a failed save stays until dismissed or replaced.
            guard case .done = notice else { return }
            try? await Task.sleep(for: Self.confirmationLifetime)
            model.dismissAppRuleNotice(notice)
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didLaunchApplicationNotification)) { _ in
            refreshRunning()
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didTerminateApplicationNotification)) { _ in
            refreshRunning()
        }
    }

    private static let confirmationLifetime: Duration = .seconds(4)

    /// An app that launched or quit may have been installed or removed too, so names, icons and
    /// install states are looked up again.
    private func refreshRunning() {
        AppMetadataCache.shared.removeAll()
        running = InstalledApp.running()
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

/// The Apps page's answer to the last rule edit: what changed, why a drop was refused, or that the
/// change could not be saved.
private struct AppRuleNoticeRow: View {
    let notice: AppRuleNotice
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            Text(notice.text)
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DesignTokens.Layout.rowGap)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .accessibilityElement(children: .contain)
    }

    private var symbol: String {
        switch notice {
        case .done: "checkmark.circle.fill"
        case .refused: "hand.raised.fill"
        case .failed: "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch notice {
        case .done: DesignTokens.Colors.success
        case .refused: DesignTokens.Colors.textSecondary
        case .failed: DesignTokens.Colors.danger
        }
    }
}
