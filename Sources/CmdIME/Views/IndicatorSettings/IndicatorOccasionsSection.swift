import AppKit
import KeyboardSwitcherCore
import SwiftUI
import UniformTypeIdentifiers

/// "When it shows": which changes bring the indicator up beyond CmdIME's own switches, how
/// long it stays, and the apps it never shows in.
struct IndicatorOccasionsSection: View {
    @ObservedObject var model: AppModel

    private var behavior: SwitchIndicatorBehavior { model.config.switchIndicatorBehavior }

    var body: some View {
        CompactSection(title: "When it shows") {
            VStack(alignment: .leading, spacing: 10) {
                externalRow
                appSwitchRow
                holdRow
                hiddenAppsRow
            }
            .disabled(!model.config.showSwitchIndicator)
            .opacity(model.config.showSwitchIndicator ? 1 : IndicatorSettingsSection.unavailableRowOpacity)
        }
    }

    private var externalRow: some View {
        CompactSettingRow("Other switches") {
            VStack(alignment: .leading, spacing: 2) {
                toggle("Show when the input source changes without CmdIME", isOn: Binding(
                    get: { behavior.showsExternalChanges },
                    set: { isOn in
                        model.editSwitchIndicatorBehavior(
                            status: isOn ? "Indicator shows every input source change" : "Indicator shows CmdIME switches only"
                        ) { $0.showsExternalChanges = isOn }
                    }
                ))
                caption("Control+Space, the Globe key, the menu bar or another app.")
            }
        }
    }

    private var appSwitchRow: some View {
        CompactSettingRow("App switch") {
            VStack(alignment: .leading, spacing: 2) {
                toggle("Show when switching apps changes the input source", isOn: Binding(
                    get: { behavior.showsOnAppSwitch },
                    set: { isOn in
                        model.editSwitchIndicatorBehavior(
                            status: isOn ? "Indicator shows after an app switch" : "Indicator no longer shows after an app switch"
                        ) { $0.showsOnAppSwitch = isOn }
                    }
                ))
                caption("Once the new app has settled, and only if nothing else showed the change.")
            }
        }
    }

    private var holdRow: some View {
        CompactSettingRow("Stays") {
            Picker("How long the indicator stays", selection: Binding(
                get: { behavior.holdSeconds },
                set: { seconds in
                    model.editSwitchIndicatorBehavior(
                        status: seconds.map { "Indicator stays \(Self.secondsText($0))" } ?? "Indicator stays as long as its theme sets"
                    ) { $0.holdSeconds = seconds.flatMap { SwitchIndicatorBehavior.clampedHold($0) } }
                }
            )) {
                Text("Automatic").tag(Double?.none)
                ForEach(Self.holdOptions(current: behavior.holdSeconds), id: \.self) { seconds in
                    Text(Self.secondsText(seconds)).tag(Double?.some(seconds))
                }
            }
            .labelsHidden()
            .fixedSize()
            .controlSize(.small)
            Spacer()
        }
    }

    private var hiddenAppsRow: some View {
        CompactSettingRow("Hidden in") {
            VStack(alignment: .leading, spacing: 6) {
                if behavior.hiddenAppIDs.isEmpty {
                    caption("Shows in every app.")
                }
                ForEach(behavior.hiddenAppIDs, id: \.self) { appID in
                    HiddenAppRow(appID: appID) {
                        model.editSwitchIndicatorBehavior(status: "Indicator shows in \(HiddenAppRow.name(for: appID)) again") {
                            $0 = $0.showing(appID)
                        }
                    }
                }
                addAppMenu
            }
        }
    }

    private var addAppMenu: some View {
        Menu("Add App") {
            ForEach(Self.runningApps(excluding: behavior.hiddenAppIDs), id: \.id) { app in
                Button(app.name) { hide(app.id) }
            }
            Divider()
            Button("Choose…") { chooseApp() }
        }
        .menuStyle(.button)
        .fixedSize()
        .controlSize(.small)
    }

    private func hide(_ appID: String) {
        model.editSwitchIndicatorBehavior(status: "Indicator hidden in \(HiddenAppRow.name(for: appID))") {
            $0 = $0.hiding(appID)
        }
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Hide Indicator"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let appID = Bundle(url: url)?.bundleIdentifier else {
            model.statusText = "\(url.lastPathComponent) has no bundle identifier"
            return
        }
        hide(appID)
    }

    private func toggle(_ label: String, isOn: Binding<Bool>) -> some View {
        Toggle(label, isOn: isOn)
            .toggleStyle(.checkbox)
            .controlSize(.small)
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DesignTokens.Colors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The offered choices, plus a stored value that is not one of them (a hand-edited file),
    /// so the picker can show what is really in effect.
    static func holdOptions(current: Double?) -> [Double] {
        var options = SwitchIndicatorBehavior.holdChoices
        if let current, !options.contains(current) {
            options.append(current)
            options.sort()
        }
        return options
    }

    static func secondsText(_ seconds: Double) -> String {
        seconds.formatted(.number.precision(.fractionLength(0...1))) + " s"
    }

    struct RunningApp {
        let id: String
        let name: String
    }

    /// Regular apps that are running now, by name, other than CmdIME and those already hidden.
    static func runningApps(excluding hidden: [String]) -> [RunningApp] {
        let ownID = NSRunningApplication.current.cmdIMEAppID
        var seen = Set(hidden)
        if let ownID { seen.insert(ownID) }
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.cmdIMEAppID, seen.insert(id).inserted else { return nil }
                return RunningApp(id: id, name: app.localizedName ?? HiddenAppRow.name(for: id))
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// One hidden app: icon, name and a remove button.
private struct HiddenAppRow: View {
    let appID: String
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(nsImage: Self.icon(for: appID))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(Self.name(for: appID))
                .lineLimit(1)
                .help(appID)
            Button {
                onRemove()
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Show the indicator in this app again")
            .accessibilityLabel("Show the indicator in \(Self.name(for: appID)) again")
        }
    }

    private static func url(for appID: String) -> URL? {
        if appID.hasPrefix("/") { return URL(fileURLWithPath: appID) }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: appID)
    }

    /// The app's display name when it is installed; otherwise the stored id as is.
    static func name(for appID: String) -> String {
        guard let url = url(for: appID) else { return appID }
        if appID.hasPrefix("/") { return url.lastPathComponent }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    static func icon(for appID: String) -> NSImage {
        guard let url = url(for: appID) else { return NSWorkspace.shared.icon(for: .application) }
        return NSWorkspace.shared.icon(forFile: url.path)
    }
}
