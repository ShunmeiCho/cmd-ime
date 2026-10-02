import Foundation
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
        #expect(ShellIntegration.installing(line: line, into: "export A=1") == "export A=1\n" + line)
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
        let unterminated = try #require(ShellIntegration.installing(
            line: ShellIntegration.rcLine(keyboardctlPath: ctl), into: "export A=1"))
        #expect(ShellIntegration.uninstalling(from: unterminated) == "export A=1")
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

struct ShellIntegrationSwitchTests {
    private let ghostty = "com.mitchellh.ghostty"

    private func config(paused: Bool = false, ghosttyRule: AppRuleTarget? = nil) -> SwitcherConfig {
        var config = SwitcherConfig.default
        config.programRules = [
            ProgramRule(name: "claude", target: .slot(.chinese)),
            ProgramRule(name: "vim", target: .keepAsIs),
            ProgramRule(name: "ssh", target: .slot(InputRole(rawValue: "korean"))),
        ]
        config.programRulesPaused = paused
        config.appRules = ghosttyRule.map { [AppRule(appID: ghostty, target: $0)] } ?? []
        return config
    }

    private func slot(_ line: String, _ config: SwitcherConfig, front: String? = "com.mitchellh.ghostty",
                      secure: Bool = false) -> InputRole? {
        ShellIntegration.slotToSelect(commandLine: line, config: config, frontmostAppID: front, isSecureInputOn: secure)
    }

    @Test("a program with a slot rule selects its slot while a terminal is in front")
    func selectsTheRuleSlot() {
        #expect(slot("claude --resume", config()) == .chinese)
        #expect(slot("claude", config(ghosttyRule: .slot(.japanese))) == .chinese)
    }

    @Test("no rule, Keep as is, a deleted slot and paused rules select nothing")
    func selectsNothingWithoutASlot() {
        #expect(slot("ls -la", config()) == nil)
        #expect(slot("vim notes", config()) == nil)
        #expect(slot("ssh host", config()) == nil)
        #expect(slot("claude", config(paused: true)) == nil)
    }

    @Test("a terminal set to Keep as is, another app in front and a password field select nothing")
    func respectsWhatNothingSwitchesAutomatically() {
        #expect(slot("claude", config(ghosttyRule: .keepAsIs)) == nil)
        #expect(slot("claude", config(), front: "com.apple.Safari") == nil)
        #expect(slot("claude", config(), front: nil) == nil)
        #expect(slot("claude", config(), secure: true) == nil)
    }
}

struct ShellIntegrationInstallerTests {
    private func scratchDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("cmdime-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("install copies the rc file and appends the line; uninstall gives the file back; both twice in a second keep every copy")
    func installAndUninstall() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rc = directory.appendingPathComponent(".zshrc")
        let before = "export A=1\n"
        try before.write(to: rc, atomically: true, encoding: .utf8)
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        guard case .changed(let firstBackup?) = try ShellIntegrationInstaller.install(keyboardctlPath: ctl, rcFile: rc, now: now) else {
            Issue.record("install changed nothing")
            return
        }
        #expect(try String(contentsOf: firstBackup, encoding: .utf8) == before)
        #expect(ShellIntegrationInstaller.isInstalled(rcFile: rc))
        #expect(try ShellIntegrationInstaller.install(keyboardctlPath: ctl, rcFile: rc, now: now) == .unchanged)

        guard case .changed(let secondBackup?) = try ShellIntegrationInstaller.uninstall(rcFile: rc, now: now) else {
            Issue.record("uninstall changed nothing")
            return
        }
        #expect(secondBackup != firstBackup)
        #expect(try String(contentsOf: rc, encoding: .utf8) == before)
        #expect(try String(contentsOf: firstBackup, encoding: .utf8) == before)
        #expect(try ShellIntegrationInstaller.uninstall(rcFile: rc, now: now) == .unchanged)
    }

    @Test("install creates the rc file when there is none, with nothing to copy")
    func installWithoutAFile() throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let rc = directory.appendingPathComponent(".zshrc")

        #expect(try ShellIntegrationInstaller.install(keyboardctlPath: ctl, rcFile: rc) == .changed(backup: nil))
        #expect(ShellIntegrationInstaller.isInstalled(rcFile: rc))
        #expect(try ShellIntegrationInstaller.uninstall(rcFile: directory.appendingPathComponent("absent")) == .unchanged)
    }

    @Test("the rc file follows ZDOTDIR when the shell uses one")
    func rcFileLocation() {
        #expect(ShellIntegrationInstaller.defaultRCFile(environment: [:], home: "/Users/a").path == "/Users/a/.zshrc")
        #expect(ShellIntegrationInstaller.defaultRCFile(environment: ["ZDOTDIR": "/Users/a/.zsh"], home: "/Users/a").path == "/Users/a/.zsh/.zshrc")
        #expect(ShellIntegrationInstaller.defaultRCFile(environment: ["ZDOTDIR": ""], home: "/Users/a").path == "/Users/a/.zshrc")
    }
}
