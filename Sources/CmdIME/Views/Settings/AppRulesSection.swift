import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// App Rules (CONTEXT.md) as a board, the way the slot board works: apps on the left, one lane per
/// slot plus "Keep as is" on the right, and dragging an app onto a lane gives it that rule. Add App,
/// the app rows' menus and each chip's menu do the same without dragging. Website Rules live in the
/// same lanes as globe chips, added through Add Website; Program Rules as terminal chips, added
/// through Add Program.
struct AppRulesSection: View {
    @ObservedObject var model: AppModel
    @State private var query = ""
    @State private var running = InstalledApp.running()
    @State private var installed: [InstalledApp] = []
    @State private var isScanningInstalled = true
    @State private var isAddingWebsite = false
    @State private var isAddingProgram = false
    @State private var isShowingShellIntegration = false

    var body: some View {
        let lanes = AppRuleBoard.lanes(for: model.config)
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("An app with a rule gets its slot every time it comes to the front. A trigger you press afterwards still wins.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .explanation()
            if model.config.appRules.isEmpty, model.config.websiteRules.isEmpty, model.config.programRules.isEmpty {
                Text("Drag an app from the list onto a slot, or use Add App or Add Website.")
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
            HStack(spacing: DesignTokens.Layout.rowGap) {
                addMenu
                Button("Add Website…") { isAddingWebsite = true }
                    .fixedSize()
                    .accessibilityLabel("Add a rule for a website")
                Button("Add Program…") { isAddingProgram = true }
                    .fixedSize()
                    .accessibilityLabel("Add a rule for a program in the terminal")
            }
            Text("For a website rule CmdIME reads only the site address of the page in front and keeps none of it. It is tested in Safari and Chrome; other browsers are not tested yet. A browser set to Keep as is is never read.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            programRulesRow
        }
        .sheet(isPresented: $isAddingWebsite) {
            AddWebsiteSheet(model: model, lanes: AppRuleLaneLook(config: model.config).destinations(lanes))
        }
        .sheet(isPresented: $isShowingShellIntegration) {
            ShellIntegrationSheet()
        }
        .sheet(isPresented: $isAddingProgram) {
            AddProgramSheet(model: model, lanes: AppRuleLaneLook(config: model.config).destinations(lanes))
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

    /// The switch that pauses every Program Rule, and what CmdIME reads for them. The note is
    /// always shown, in Brief too.
    private var programRulesRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Program rules")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Button("Shell Integration…") { isShowingShellIntegration = true }
                    .controlSize(.small)
                    .fixedSize()
                Toggle("Program rules", isOn: Binding(
                    get: { !model.config.programRulesPaused },
                    set: { [model] isOn in model.setProgramRulesPaused(!isOn) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
            }
            // Where it works fully and where it does not: said in Brief too, in the primary text
            // colour, because a rule that seems to do nothing in a plain tab reads as a fault.
            Label("Works best in Herdr: every pane is followed, also one you come back to. In other terminals, with shell integration, it switches only when a program starts or exits.", systemImage: "info.circle")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text("A program with a rule gets its slot while it runs in the terminal pane in focus. CmdIME reads only the name of the program running in the terminal, never what is on the screen.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Text("Terminal.app, and Ghostty from a release that reports it, can say which program runs in the tab in front: CmdIME asks them, and macOS asks you once per terminal whether CmdIME may.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
