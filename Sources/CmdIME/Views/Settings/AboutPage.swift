import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Version and build, release notes, the privacy statement, feedback and support links.
struct AboutPage: View {
    @ObservedObject var model: AppModel
    private static let releasesURL = "https://github.com/\(UpdatePackage.repository)/releases"
    private static let repositoryURL = "https://github.com/\(UpdatePackage.repository)"
    private static let websiteURL = "https://shunmeicho.github.io/cmd-ime/"
    private static let supportURL = "https://buymeacoffee.com/shunmeicor7"

    /// `CFBundleVersion`; a bare `swift run` binary has no Info.plist and so no build.
    private static var build: String? {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String
    }

    private static var versionText: String {
        let version = "Version \(AppModel.currentVersion)"
        return build.map { "\(version) (\($0))" } ?? version
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionGap) {
            CompactSection(title: "About") {
                VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
                    HStack(spacing: DesignTokens.Layout.panelGap) {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .frame(width: 48, height: 48)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("CmdIME")
                                .font(DesignTokens.Typography.title)
                                .foregroundStyle(DesignTokens.Colors.textPrimary)
                            Text(Self.versionText)
                                .foregroundStyle(DesignTokens.Colors.textSecondary)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    HStack(spacing: DesignTokens.Layout.rowGap) {
                        // Where a Mac user looks for it; General keeps the automatic-check settings.
                        Button(model.updateStatus.isChecking ? "Checking…" : "Check for Updates") {
                            model.checkForUpdates()
                        }
                        .disabled(model.updateStatus.isChecking)
                        Button("Release Notes…") { Self.open(Self.releasesURL) }
                        Button("Website…") { Self.open(Self.websiteURL) }
                    }
                    if case .idle = model.updateStatus {} else {
                        Text(model.updateStatus.message)
                            .font(DesignTokens.Typography.auxiliary)
                            .foregroundStyle(DesignTokens.Colors.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if case .available = model.updateStatus { UpdateActions(model: model) }
                }
            }
            CompactSection(title: "Privacy") {
                Text(SetupGuideCopy.privacy)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            CompactSection(title: "Feedback and support") {
                HStack(spacing: DesignTokens.Layout.rowGap) {
                    Button("Report an Issue…", action: Self.reportIssue)
                        .help("Opens a new GitHub issue with the CmdIME and macOS versions filled in.")
                    Button("Support CmdIME…") { Self.open(Self.supportURL) }
                    Button("Star on GitHub…") { Self.open(Self.repositoryURL) }
                }
            }
        }
        .buttonStyle(ConsoleButtonStyle())
        .font(DesignTokens.Typography.body)
    }

    private static func reportIssue() {
        guard let url = IssueReport.bugReportURL(
            appVersion: AppModel.currentVersion,
            macOSVersion: ProcessInfo.processInfo.operatingSystemVersion
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
