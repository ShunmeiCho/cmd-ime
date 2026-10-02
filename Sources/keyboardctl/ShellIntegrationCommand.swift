import Foundation
import KeyboardSwitcherCore
#if os(macOS)
import AppKit
#endif

/// Shell integration for Program Rules: the hook, the rc line, and the switch the hook asks for.
extension CLI {
    private static let shellInitUsage = "Usage: keyboardctl shell-init zsh"
    private static let shellIntegrationUsage = "Usage: keyboardctl shell-integration install | uninstall [--file <rc file>]"
    private static let fileFlag = "--file"
    private static let maxBackupsPerSecond = 9

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
        let url = rest.count == 2 ? URL(fileURLWithPath: rest[1]) : Self.defaultRCFile
        let existing = FileManager.default.fileExists(atPath: url.path)
        let rc = existing ? try String(contentsOf: url, encoding: .utf8) : ""
        switch operation {
        case "install":
            let line = ShellIntegration.rcLine(keyboardctlPath: Self.ownPath)
            guard let next = ShellIntegration.installing(line: line, into: rc) else {
                print("Shell integration is already in \(url.path)")
                return
            }
            let backup = existing ? try Self.backUp(url) : nil
            try next.write(to: url, atomically: true, encoding: .utf8)
            print("Added to \(url.path):\n\(line)")
            if let backup { print("The file as it was: \(backup.path)") }
            print("Open a new terminal window to use it.")
        case "uninstall":
            guard let next = ShellIntegration.uninstalling(from: rc) else {
                print("Shell integration is not in \(url.path)")
                return
            }
            let backup = try Self.backUp(url)
            try next.write(to: url, atomically: true, encoding: .utf8)
            print("Removed from \(url.path)\nThe file as it was: \(backup.path)")
        default:
            throw CLIError.invalidArgument(Self.shellIntegrationUsage)
        }
    }

    /// What the hook runs: the program a command line starts, looked up in the Program Rules. No
    /// rule, a paused feature, Keep as is, an unreadable config or a terminal that is not in front
    /// all end silently, and nothing is ever written: this runs on every command of every shell.
    func switchForProgram() throws {
        #if os(macOS)
        let line = args.dropFirst().joined(separator: " ")
        guard let name = ShellIntegration.programName(inCommandLine: line),
              let data = try? Data(contentsOf: configURL),
              let config = try? JSONDecoder().decode(SwitcherConfig.self, from: data),
              !config.programRulesPaused,
              case .slot(let slot)? = config.programRule(for: name)?.target,
              config.slots.contains(where: { $0.id == slot }),
              let frontmost = NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
              TerminalCatalog.isTerminal(frontmost) else { return }
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

    private static var defaultRCFile: URL {
        let directory = ProcessInfo.processInfo.environment["ZDOTDIR"].flatMap { $0.isEmpty ? nil : $0 }
            ?? NSHomeDirectory()
        return URL(fileURLWithPath: directory).appendingPathComponent(".zshrc")
    }

    private static func backUp(_ url: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = url.lastPathComponent + ".before-cmdime." + formatter.string(from: Date())
        let directory = url.deletingLastPathComponent()
        // Two edits within one second get two copies: an earlier copy is never replaced.
        let names = [stem] + (2...Self.maxBackupsPerSecond).map { "\(stem)-\($0)" }
        guard let name = names.first(where: { !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
            throw CLIError.invalidArgument("Too many copies of \(url.lastPathComponent) from this second; try again.")
        }
        let backup = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }
}
