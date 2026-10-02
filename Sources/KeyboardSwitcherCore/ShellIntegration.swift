import Foundation

/// Shell integration for Program Rules: the hook a shell loads, the one line that loads it from
/// the rc file, and the edits that add and remove that line. Pure text; the caller reads and
/// writes the file, and only when the user asks.
public enum ShellIntegration {
    /// Ends the rc line, so uninstalling finds exactly that line.
    public static let marker = "# CmdIME shell integration"
    /// The name reported when the shell is back at its prompt.
    public static let zshName = "zsh"
    /// Words zsh allows before a command that are not the program.
    private static let precommandModifiers: Set<String> = ["command", "exec", "noglob", "nocorrect", "builtin"]

    /// The line for `.zshrc`. It does nothing when CmdIME is not installed at `keyboardctlPath`.
    public static func rcLine(keyboardctlPath: String) -> String {
        let path = quoted(keyboardctlPath)
        return "[[ -x \(path) ]] && eval \"$(\(path) shell-init zsh)\" \(marker)"
    }

    /// The hook `shell-init zsh` prints. The shell reports the command it is about to run and its
    /// return to the prompt; `program-switch` looks the name up in the Program Rules. Inside a
    /// Herdr or tmux pane it reports nothing: those are followed by pane, and a shell there cannot
    /// tell whether its pane is the one in focus.
    public static func zshHook(keyboardctlPath: String) -> String {
        """
        _cmdime_ctl=\(quoted(keyboardctlPath))
        _cmdime_report() {
          [[ -n "$TMUX" || -n "$HERDR_PANE_ID" ]] && return
          [[ -x "$_cmdime_ctl" ]] || return
          "$_cmdime_ctl" program-switch "$1" >/dev/null 2>&1 &!
        }
        _cmdime_preexec() { _cmdime_report "${2:-$1}" }
        _cmdime_precmd() { _cmdime_report \(zshName) }
        autoload -Uz add-zsh-hook
        add-zsh-hook preexec _cmdime_preexec
        add-zsh-hook precmd _cmdime_precmd

        """
    }

    /// `rc` with the line appended, or nil when a line with the marker is already there.
    public static func installing(line: String, into rc: String) -> String? {
        guard !isInstalled(in: rc) else { return nil }
        // A file that does not end in a line feed gets none after the line either, so removing the
        // line gives back the same bytes.
        guard rc.isEmpty || rc.hasSuffix("\n") else { return rc + "\n" + line }
        return rc + line + "\n"
    }

    /// `rc` without the lines that carry the marker, or nil when there is none. Nothing else changes.
    public static func uninstalling(from rc: String) -> String? {
        guard isInstalled(in: rc) else { return nil }
        let lines = rc.split(separator: "\n", omittingEmptySubsequences: false)
        return lines.filter { !$0.hasSuffix(marker) }.joined(separator: "\n")
    }

    public static func isInstalled(in rc: String) -> Bool {
        rc.split(separator: "\n", omittingEmptySubsequences: false).contains { $0.hasSuffix(marker) }
    }

    /// The program a command line starts: the first word after variable assignments and zsh's
    /// precommand modifiers, without its directory. Nil when there is none or it is not a name a
    /// rule can have. A wrapper such as `sudo` is the program, as it is for a pane.
    public static func programName(inCommandLine line: String) -> String? {
        let words = line.split(whereSeparator: \.isWhitespace).map(String.init)
        guard let command = words.first(where: { !isAssignment($0) && !precommandModifiers.contains($0) }) else {
            return nil
        }
        let base = command.split(separator: "/").last.map(String.init) ?? command
        return ProgramName.normalized(userInput: base)
    }

    /// The slot the hook's report selects, or nil for "leave the source alone": no rule for the
    /// program, rules paused, a Keep as is rule, a deleted slot, a password field in front (the
    /// source there is not the user's to lose), or an app in front that is not a terminal or is a
    /// terminal with a Keep as is App Rule, which nothing switches automatically.
    public static func slotToSelect(
        commandLine: String,
        config: SwitcherConfig,
        frontmostAppID: String?,
        isSecureInputOn: Bool
    ) -> InputRole? {
        guard !isSecureInputOn, !config.programRulesPaused,
              let frontmostAppID, TerminalCatalog.isTerminal(frontmostAppID),
              config.appRule(for: frontmostAppID)?.target != .keepAsIs,
              let name = programName(inCommandLine: commandLine),
              case .slot(let slot)? = config.programRule(for: name)?.target,
              config.slots.contains(where: { $0.id == slot }) else { return nil }
        return slot
    }

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// One shell word, whatever the path contains.
    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

/// The file work of shell integration, shared by `keyboardctl shell-integration` and Settings. The
/// rc file is copied beside itself before it changes, and an earlier copy is never replaced.
public enum ShellIntegrationInstaller {
    public enum Outcome: Equatable, Sendable {
        /// The file changed; `backup` is the copy of what it was (nil when there was no file).
        case changed(backup: URL?)
        /// The line was already there (install) or was not there (uninstall).
        case unchanged
    }

    public enum InstallerError: Error, Equatable {
        case tooManyBackups
    }

    private static let rcFileName = ".zshrc"
    private static let backupInfix = ".before-cmdime."
    private static let maxBackupsPerSecond = 9

    /// `$ZDOTDIR/.zshrc` when the shell uses one, else `~/.zshrc`.
    public static func defaultRCFile(environment: [String: String], home: String) -> URL {
        let directory = environment["ZDOTDIR"].flatMap { $0.isEmpty ? nil : $0 } ?? home
        return URL(fileURLWithPath: directory).appendingPathComponent(rcFileName)
    }

    public static func isInstalled(rcFile: URL) -> Bool {
        (try? String(contentsOf: rcFile, encoding: .utf8)).map(ShellIntegration.isInstalled(in:)) ?? false
    }

    public static func install(keyboardctlPath: String, rcFile: URL, now: Date = Date()) throws -> Outcome {
        let exists = FileManager.default.fileExists(atPath: rcFile.path)
        let rc = exists ? try String(contentsOf: rcFile, encoding: .utf8) : ""
        let line = ShellIntegration.rcLine(keyboardctlPath: keyboardctlPath)
        guard let next = ShellIntegration.installing(line: line, into: rc) else { return .unchanged }
        let backup = exists ? try backUp(rcFile, now: now) : nil
        try next.write(to: rcFile, atomically: true, encoding: .utf8)
        return .changed(backup: backup)
    }

    public static func uninstall(rcFile: URL, now: Date = Date()) throws -> Outcome {
        guard FileManager.default.fileExists(atPath: rcFile.path) else { return .unchanged }
        let rc = try String(contentsOf: rcFile, encoding: .utf8)
        guard let next = ShellIntegration.uninstalling(from: rc) else { return .unchanged }
        let backup = try backUp(rcFile, now: now)
        try next.write(to: rcFile, atomically: true, encoding: .utf8)
        return .changed(backup: backup)
    }

    private static func backUp(_ url: URL, now: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let stem = url.lastPathComponent + backupInfix + formatter.string(from: now)
        let directory = url.deletingLastPathComponent()
        let names = [stem] + (2...maxBackupsPerSecond).map { "\(stem)-\($0)" }
        guard let name = names.first(where: { !FileManager.default.fileExists(atPath: directory.appendingPathComponent($0).path) }) else {
            throw InstallerError.tooManyBackups
        }
        let backup = directory.appendingPathComponent(name)
        try FileManager.default.copyItem(at: url, to: backup)
        return backup
    }
}
