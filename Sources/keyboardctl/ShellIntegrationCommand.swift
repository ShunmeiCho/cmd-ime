import Foundation
import KeyboardSwitcherCore
#if os(macOS)
import AppKit
import Carbon
#endif

/// Shell integration for Program Rules: the hook, the rc line, and the switch the hook asks for.
extension CLI {
    private static let shellInitUsage = "Usage: keyboardctl shell-init zsh"
    private static let shellIntegrationUsage = "Usage: keyboardctl shell-integration install | uninstall [--file <rc file>]"
    private static let fileFlag = "--file"

    func printShellHook() throws {
        guard args.count == 2, args[1] == ShellIntegration.zshName else {
            throw CLIError.invalidArgument(Self.shellInitUsage + " (zsh is the only shell so far)")
        }
        print(ShellIntegration.zshHook(keyboardctlPath: Self.ownPath), terminator: "")
    }

    /// Adds the one line to the rc file, or removes it. The file is copied first; nothing else in
    /// it changes. Run only when the user asks: CmdIME never edits an rc file on its own.
    func manageShellIntegration() throws {
        let operation = try argument(at: 1, name: "install or uninstall")
        let rest = Array(args.dropFirst(2))
        guard rest.isEmpty || (rest.count == 2 && rest[0] == Self.fileFlag) else {
            throw CLIError.invalidArgument(Self.shellIntegrationUsage)
        }
        let url = rest.count == 2
            ? URL(fileURLWithPath: rest[1])
            : ShellIntegrationInstaller.defaultRCFile(environment: ProcessInfo.processInfo.environment, home: NSHomeDirectory())
        switch operation {
        case "install":
            switch try ShellIntegrationInstaller.install(keyboardctlPath: Self.ownPath, rcFile: url) {
            case .unchanged:
                print("Shell integration is already in \(url.path)")
            case .changed(let backup):
                print("Added to \(url.path):\n\(ShellIntegration.rcLine(keyboardctlPath: Self.ownPath))")
                if let backup { print("The file as it was: \(backup.path)") }
                print("Open a new terminal window to use it.")
            }
        case "uninstall":
            switch try ShellIntegrationInstaller.uninstall(rcFile: url) {
            case .unchanged:
                print("Shell integration is not in \(url.path)")
            case .changed(let backup):
                print("Removed from \(url.path)")
                if let backup { print("The file as it was: \(backup.path)") }
            }
        default:
            throw CLIError.invalidArgument(Self.shellIntegrationUsage)
        }
    }

    /// What the hook runs: the program a command line starts, looked up in the Program Rules by
    /// core `ShellIntegration.slotToSelect`. Nothing to select and an unreadable config end
    /// silently, and nothing is ever written: this runs on every command of every shell.
    func switchForProgram() throws {
        #if os(macOS)
        let line = args.dropFirst().joined(separator: " ")
        guard let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(SwitcherConfig.self, from: data),
              let slot = ShellIntegration.slotToSelect(
                  commandLine: line,
                  config: config,
                  frontmostAppID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                  isSecureInputOn: IsSecureEventInputEnabled()
              ) else { return }
        try select(slot, in: config, service: MacInputSourceService())
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    /// This executable, with links resolved, so the hook keeps pointing at the app it came from.
    private static var ownPath: String {
        let path = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }
}
