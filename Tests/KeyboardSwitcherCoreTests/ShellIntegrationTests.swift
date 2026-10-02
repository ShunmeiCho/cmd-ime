import Testing
@testable import KeyboardSwitcherCore

private let ctl = "/Applications/CmdIME.app/Contents/MacOS/keyboardctl"

struct ShellIntegrationTests {
    @Test("the rc line loads the hook only when keyboardctl is there, and ends with the marker")
    func rcLine() {
        let line = ShellIntegration.rcLine(keyboardctlPath: ctl)

        #expect(line == "[[ -x '\(ctl)' ]] && eval \"$('\(ctl)' shell-init zsh)\" # CmdIME shell integration")
        #expect(!line.contains("\n"))
    }

    @Test("a path with a quote or a space stays one shell word")
    func quotedPath() {
        let line = ShellIntegration.rcLine(keyboardctlPath: "/Users/o'neil/My Apps/keyboardctl")

        #expect(line.contains("'/Users/o'\\''neil/My Apps/keyboardctl'"))
    }

    @Test("the hook reports both the command and the prompt, and stays silent in Herdr and tmux panes")
    func hook() {
        let hook = ShellIntegration.zshHook(keyboardctlPath: ctl)

        #expect(hook.contains("add-zsh-hook preexec _cmdime_preexec"))
        #expect(hook.contains("add-zsh-hook precmd _cmdime_precmd"))
        #expect(hook.contains("[[ -n \"$TMUX\" || -n \"$HERDR_PANE_ID\" ]] && return"))
        #expect(hook.contains("program-switch \"$1\" >/dev/null 2>&1 &!"))
    }

    @Test("installing appends one line and is refused when the line is already there")
    func install() throws {
        let line = ShellIntegration.rcLine(keyboardctlPath: ctl)

        #expect(ShellIntegration.installing(line: line, into: "") == line + "\n")
        #expect(ShellIntegration.installing(line: line, into: "export A=1") == "export A=1\n" + line + "\n")
        let installed = try #require(ShellIntegration.installing(line: line, into: "export A=1\n"))
        #expect(installed == "export A=1\n" + line + "\n")
        #expect(ShellIntegration.installing(line: line, into: installed) == nil)
    }

    @Test("uninstalling removes only the marked line and gives the file back as it was")
    func uninstall() throws {
        let before = "export A=1\n\n# a comment about CmdIME\nalias k=keyboardctl\n"
        let installed = try #require(ShellIntegration.installing(
            line: ShellIntegration.rcLine(keyboardctlPath: ctl), into: before))

        #expect(ShellIntegration.uninstalling(from: installed) == before)
        #expect(ShellIntegration.uninstalling(from: before) == nil)
    }

    @Test("the program of a command line is its first real word, without a directory",
          arguments: [
              ("claude", "claude"), ("claude --resume", "claude"), ("FOO=1 BAR=2 codex exec", "codex"),
              ("/usr/bin/vim notes.txt", "vim"), ("noglob command git status", "git"), ("sudo vim /etc/hosts", "sudo"),
              ("  pi  ", "pi"),
          ])
    func programName(line: String, expected: String) {
        #expect(ShellIntegration.programName(inCommandLine: line) == expected)
    }

    @Test("a line with no program names none", arguments: ["", "   ", "FOO=1", "noglob"])
    func noProgramName(line: String) {
        #expect(ShellIntegration.programName(inCommandLine: line) == nil)
    }
}
