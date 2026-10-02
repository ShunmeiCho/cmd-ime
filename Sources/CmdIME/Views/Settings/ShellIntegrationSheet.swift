import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Shell integration for Program Rules: shows the one line for `.zshrc`, copies it, and adds or
/// removes it when the user asks. The file work is core `ShellIntegrationInstaller`, which copies
/// the file first; CmdIME never changes an rc file on its own.
struct ShellIntegrationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isInstalled = ShellIntegrationInstaller.isInstalled(rcFile: ShellIntegrationSheet.rcFile)
    @State private var status: String?
    @State private var hasFailed = false

    private static let width: CGFloat = 460
    private static let padding: CGFloat = 16
    private static let rcFile = ShellIntegrationInstaller.defaultRCFile(environment: [:], home: NSHomeDirectory())
    private static let keyboardctlPath = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/keyboardctl").path
    private static let line = ShellIntegration.rcLine(keyboardctlPath: keyboardctlPath)

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("Shell Integration")
                .font(DesignTokens.Typography.title)
            Text("In a terminal without Herdr, zsh can tell CmdIME which program starts and when you are back at the prompt. That takes this one line in .zshrc:")
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: Self.line)
                .font(DesignTokens.Typography.auxiliary.monospaced())
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceInset))
            Text("CmdIME copies .zshrc before changing it and changes nothing else in it. A command that ends in a tab you are not looking at can still switch the input source.")
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            if let status {
                Text(status)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(hasFailed ? DesignTokens.Colors.danger : DesignTokens.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            HStack {
                Button("Copy Line", action: copy)
                Button(isInstalled ? String(localized: "Remove from .zshrc") : String(localized: "Add to .zshrc"), action: change)
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Button("Done") { dismiss() }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .buttonStyle(ConsoleButtonStyle())
        .font(DesignTokens.Typography.body)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(Self.line, forType: .string)
        report(String(localized: "Copied."))
    }

    private func change() {
        let installing = !isInstalled
        let rcFile = Self.rcFile
        let keyboardctlPath = Self.keyboardctlPath
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    installing
                        ? try ShellIntegrationInstaller.install(keyboardctlPath: keyboardctlPath, rcFile: rcFile)
                        : try ShellIntegrationInstaller.uninstall(rcFile: rcFile)
                }
            }.value
            isInstalled = ShellIntegrationInstaller.isInstalled(rcFile: rcFile)
            switch result {
            case .failure(let error):
                report(String(localized: "Could not change .zshrc: \(error.localizedDescription)"), failed: true)
            case .success(.unchanged):
                report(installing ? String(localized: "The line is already in .zshrc.") : String(localized: "The line is not in .zshrc."))
            case .success(.changed(let backup)):
                let done = installing
                    ? String(localized: "Added. Open a new terminal window to use it.")
                    : String(localized: "Removed.")
                report(backup.map { done + " " + String(localized: "The file as it was: \($0.path)") } ?? done)
            }
        }
    }

    private func report(_ text: String, failed: Bool = false) {
        status = text
        hasFailed = failed
        SetupGuideNavigation.announce(text)
    }
}
