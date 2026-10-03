import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Everything that used to sit in the General popover in the header, except the
/// support links, which are on About now.
struct GeneralPage: View {
    @ObservedObject var model: AppModel
    let onShowSetupGuide: () -> Void
    @State private var relaunchFailed = false

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
            CompactSection(title: String(localized: "General")) { startupRows }
            CompactSection(title: String(localized: "Typing")) { typingRows }
            CompactSection(title: String(localized: "Updates")) { updateRows }
            CompactSection(title: String(localized: "Setup guide")) { setupGuideRow }
            CompactSection(title: String(localized: "Settings file")) { settingsFileRows }
            CompactSection(title: String(localized: "Running in the background")) { quitRows }
        }
        .buttonStyle(ConsoleButtonStyle())
        .font(DesignTokens.Typography.body)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
        // The answer can change in System Settings while CmdIME keeps running.
        .onAppear { model.refreshNotificationPermission() }
    }

    private var typingRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            HStack {
                Text("Space between Chinese and English")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Toggle("Space between Chinese and English", isOn: Binding(
                    get: { model.config.autoSpaceBetweenChineseAndEnglish }, set: { model.setAutoSpaceBetweenChineseAndEnglish($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
            }
            // New in 0.16: shown in Brief too while the feature is new (owner rule, issue #7). It also
            // says what is read, which the user must know before turning it on.
            Text("After a trigger switches input source, CmdIME reads the one character before the caret. Into English after Chinese, it types a space before your first letter or digit; into Chinese after English or a digit, before your first pinyin letter. The character is not stored. Terminals and password fields are left alone.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
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
            if InterfaceLanguage.isChoosable { languageRows }
        }
    }

    private var languageRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            HStack {
                Text("Language")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Picker("Language", selection: $model.interfaceLanguage) {
                    ForEach(InterfaceLanguage.allCases, id: \.self) { language in
                        Text(verbatim: language.nativeName ?? String(localized: "System")).tag(language)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            if model.interfaceLanguage != model.launchedInterfaceLanguage {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Layout.rowGap) {
                    Text("The new language takes effect when CmdIME relaunches.")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: DesignTokens.Layout.rowGap)
                    RelaunchButton(model: model, failed: $relaunchFailed)
                        .fixedSize()
                }
                if relaunchFailed || !AppRelauncher.canRelaunch {
                    Text("After quitting, open CmdIME again from Spotlight or the Applications folder.")
                        .font(DesignTokens.Typography.auxiliary)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
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
                Button(model.updateStatus.isChecking ? String(localized: "Checking…") : String(localized: "Check")) { model.checkForUpdates() }
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
        // Stacked like the sections below it, so the button keeps its place when Brief hides the text.
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("Go through the three setup steps again: keyboard access, the detected slots and trying the triggers.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .explanation()
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
                .explanation()
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
        panel.message = String(localized: "CmdIME saves your settings in a new folder with this name.")
        panel.prompt = String(localized: "Export")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await model.exportSettings(to: url) }
    }

    private func importSettings() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose a folder made by Export Settings.")
        panel.prompt = String(localized: "Import")
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
        alert.messageText = String(localized: "Replace your settings with the ones in \"\(folder.lastPathComponent)\"?")
        let recipes = plan.includesActivationRecipes ? String(localized: ", activation recipes") : ""
        alert.informativeText = String(localized: "It has \(plan.config.slots.count) slot(s), \(plan.themeFileNames.count) theme(s), \(plan.fontFileNames.count) font(s)\(recipes). Your current settings are copied to a backup folder first and take effect again if you import that folder.")
        alert.addButton(withTitle: String(localized: "Import"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        return await alert.beginSheetModal(for: window) == .alertFirstButtonReturn
    }

    private var quitRows: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("While this window is open, CmdIME is in the Dock and the app switcher. After it closes, CmdIME keeps running in the background with no menu bar icon. Open CmdIME again to return here.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
                .explanation()
            Button("Quit CmdIME", role: .destructive) { model.quit(restoringSystemBadge: true) }
                .help("Stop the background listener")
        }
    }
}
