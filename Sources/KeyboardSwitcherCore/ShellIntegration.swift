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
        let separator = rc.isEmpty || rc.hasSuffix("\n") ? "" : "\n"
        return rc + separator + line + "\n"
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

    private static func isAssignment(_ word: String) -> Bool {
        guard let equals = word.firstIndex(of: "="), equals != word.startIndex else { return false }
        return word[..<equals].allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" }
    }

    /// One shell word, whatever the path contains.
    private static func quoted(_ path: String) -> String {
        "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
