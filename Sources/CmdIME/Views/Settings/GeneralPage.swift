import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Everything that used to sit in the General popover in the header, except the
/// support links, which are on About now.
struct GeneralPage: View {
    @ObservedObject var model: AppModel
    let onShowSetupGuide: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
            CompactSection(title: "General") { startupRows }
            CompactSection(title: "Updates") { updateRows }
            CompactSection(title: "Setup guide") { setupGuideRow }
            CompactSection(title: "Settings file") { settingsFileRows }
            CompactSection(title: "Running in the background") { quitRows }
        }
        .buttonStyle(ConsoleButtonStyle())
        .font(DesignTokens.Typography.body)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
        // The answer can change in System Settings while CmdIME keeps running.
        .onAppear { model.refreshNotificationPermission() }
    }

    private var startupRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text("Launch at login")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Toggle("Launch at login", isOn: Binding(
                    get: { model.loginItem.isEnabled }, set: { model.setLaunchAtLogin($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
                .disabled(!model.loginItem.isAvailable)
            }
            // Registering succeeds while the switch stays off: macOS waits for the user
            // to approve the login item in System Settings.
            if model.loginItemNeedsApproval {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Layout.rowGap) {
                    Label("Approve CmdIME in Login Items", systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Button("Open") { model.openLoginItemsSettings() }
                        .fixedSize()
                }
            }
            HStack {
                Text("Appearance")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                ConsoleSegmentedControl(
                    options: AppearancePreference.allCases.map { ConsoleSegmentOption(value: $0, label: $0.title) },
                    selection: $model.appearance
                )
                .fixedSize()
                .accessibilityLabel("Appearance")
            }
        }
    }

    private var updateRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text(model.updateStatus.message)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Button(model.updateStatus.isChecking ? "Checking…" : "Check") { model.checkForUpdates() }
                    .disabled(model.updateStatus.isChecking)
                    .fixedSize()
            }
            if case .available = model.updateStatus { UpdateActions(model: model) }
            HStack {
                Text("Check automatically")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Toggle("Check for updates automatically", isOn: Binding(
                    get: { model.checksForUpdatesAutomatically }, set: { model.checksForUpdatesAutomatically = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
            }
            .help("CmdIME asks GitHub for the newest release. Nothing else is sent.")
            if model.checksForUpdatesAutomatically {
                HStack {
                    Text("Every")
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    ConsoleSegmentedControl(
                        options: UpdateCheckFrequency.allCases.map { ConsoleSegmentOption(value: $0, label: $0.title) },
                        selection: Binding(
                            get: { model.updateCheckFrequency }, set: { model.updateCheckFrequency = $0 }
                        )
                    )
                    .fixedSize()
                    .accessibilityLabel("How often to check for updates")
                }
                HStack {
                    Text("Notify me about updates")
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    Toggle("Notify me about updates", isOn: Binding(
                        get: { model.notifiesAboutUpdates }, set: { model.notifiesAboutUpdates = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .tint(DesignTokens.Colors.success)
                    .controlSize(.small)
                }
                if model.notifiesAboutUpdates { notificationPermissionNote }
            }
        }
    }

    /// Says what macOS currently allows, because the switch above cannot override it.
    @ViewBuilder
    private var notificationPermissionNote: some View {
        switch model.notificationPermission {
        case .blocked:
            VStack(alignment: .leading, spacing: 6) {
                Text("Notifications for CmdIME are turned off in System Settings.")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Open Notification Settings…") { UpdateNotification.openSystemSettings() }
            }
        case .notAsked:
            Text("macOS will ask for permission the first time there is an update.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        case .allowed, .unknown:
            EmptyView()
        }
    }

    private var setupGuideRow: some View {
        HStack {
            Text("Go through the three setup steps again: keyboard access, the detected slots and trying the triggers.")
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: DesignTokens.Layout.rowGap)
            Button("Show Setup Guide", action: onShowSetupGuide)
                .fixedSize()
        }
    }

    private var settingsFileRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("Move your slots, triggers, indicator themes, imported fonts and activation recipes to another Mac, or keep a copy. An import copies your current settings to a backup folder first.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DesignTokens.Layout.rowGap) {
                Group {
                    Button("Export Settings…", action: exportSettings)
                    Button("Import Settings…", action: importSettings)
                }
                .disabled(model.settingsTransferActivity != nil)
                Button("Show Backups") { model.revealSettingsBackups() }
            }
            if let activity = model.settingsTransferActivity {
                HStack(spacing: DesignTokens.Layout.rowGap) {
                    ProgressView().controlSize(.small)
                    Text(activity.text)
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
                .accessibilityElement(children: .combine)
            } else {
                switch model.settingsTransferMessage {
                case let .done(message):
                    Text(message)
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                case let .failed(message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.warning)
                        .fixedSize(horizontal: false, vertical: true)
                case nil:
                    EmptyView()
                }
            }
        }
    }

    private func exportSettings() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = model.suggestedExportName
        panel.message = "CmdIME saves your settings in a new folder with this name."
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.exportSettings(to: url) }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder made by Export Settings."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        Task {
            guard let plan = await model.inspectSettingsImport(folder),
                  await confirmImport(plan, from: folder) else { return }
            await model.importSettings(from: folder)
        }
    }

    /// A sheet, not runModal: a modal loop started inside a Task holds the main queue, and with it
    /// every switch the event tap queues, until the alert closes.
    private func confirmImport(_ plan: SettingsImportPlan, from folder: URL) async -> Bool {
        guard let window = NSApp.windows.first(where: { $0.title == "CmdIME" && $0.isVisible }) else {
            return false
        }
        let alert = NSAlert()
        alert.messageText = "Replace your settings with the ones in \"\(folder.lastPathComponent)\"?"
        let recipes = plan.includesActivationRecipes ? ", activation recipes" : ""
        alert.informativeText = "It has \(plan.config.slots.count) slot(s), \(plan.themeFileNames.count) theme(s), "
            + "\(plan.fontFileNames.count) font(s)\(recipes). Your current settings are copied to a backup folder first "
            + "and take effect again if you import that folder."
        alert.addButton(withTitle: "Import")
        alert.addButton(withTitle: "Cancel")
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    private var quitRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("While this window is open, CmdIME is in the Dock and the app switcher. After it closes, CmdIME keeps running in the background with no menu bar icon. Open CmdIME again to return here.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            Button("Quit CmdIME", role: .destructive) { model.quit() }
                .help("Stop the background listener")
        }
    }
}
