import Testing
@testable import KeyboardSwitcherCore

struct TerminalScriptSourceTests {
    @Test("only Ghostty and Terminal.app are asked")
    func kinds() {
        #expect(TerminalScriptSource.kind(forBundleID: "com.mitchellh.ghostty") == .ghostty)
        #expect(TerminalScriptSource.kind(forBundleID: "com.apple.Terminal") == .terminalApp)
        #expect(TerminalScriptSource.kind(forBundleID: "com.googlecode.iterm2") == nil)
    }

    @Test("the scripts ask only for the pane and the process, never a title or the screen")
    func scriptsAskLittle() {
        let ghostty = TerminalScriptSource.script(for: .ghostty)
        let terminal = TerminalScriptSource.script(for: .terminalApp)

        #expect(ghostty.contains("pid of t") && ghostty.contains("id of t"))
        #expect(terminal.contains("tty of selected tab"))
        for script in [ghostty, terminal] {
            #expect(!script.contains("name") && !script.contains("contents") && !script.contains("working directory"))
        }
    }

    @Test("a Ghostty reply names the terminal and its foreground pid")
    func ghosttyReply() {
        #expect(TerminalScriptSource.answer(kind: .ghostty, reply: "ABC-123\t4242\n") == .process(paneID: "ABC-123", pid: 4242))
        #expect(TerminalScriptSource.answer(kind: .ghostty, reply: "ABC-123") == nil)
        #expect(TerminalScriptSource.answer(kind: .ghostty, reply: "ABC-123\t0") == nil)
        #expect(TerminalScriptSource.answer(kind: .ghostty, reply: "\t4242") == nil)
    }

    @Test("a Terminal.app reply is the tab's device")
    func terminalReply() {
        #expect(TerminalScriptSource.answer(kind: .terminalApp, reply: "/dev/ttys012\n") == .device(paneID: "/dev/ttys012", device: "/dev/ttys012"))
        #expect(TerminalScriptSource.answer(kind: .terminalApp, reply: "") == nil)
        #expect(TerminalScriptSource.answer(kind: .terminalApp, reply: "/dev/ttys") == nil)
        #expect(TerminalScriptSource.answer(kind: .terminalApp, reply: "missing value") == nil)
    }

    @Test("a failed query is only 'cannot tell': the terminal is asked again")
    func failuresDoNotStopTheAsking() {
        var availability = TerminalScriptSource.Availability()

        availability.failed(errorCode: -1728, appPID: 10)
        availability.failed(errorCode: -1712, appPID: 10)

        #expect(availability.shouldAsk(appPID: 10))
    }

    @Test("a refused consent stops the asking")
    func refused() {
        var availability = TerminalScriptSource.Availability()
        availability.answered()

        availability.failed(errorCode: -1743, appPID: 10)

        #expect(!availability.shouldAsk(appPID: 11))
    }

    @Test("a Ghostty whose dictionary lacks pid is not asked; one that has it is")
    func dictionary() {
        let old = #"<property name="focused terminal" code="x"/><property name="working directory" code="y"/>"#
        let new = old + #"<property name="pid" code="Gpid" type="integer"/>"#

        #expect(!TerminalScriptSource.dictionaryOffers(.ghostty, sdef: old))
        #expect(TerminalScriptSource.dictionaryOffers(.ghostty, sdef: new))
        #expect(TerminalScriptSource.dictionaryOffers(.terminalApp, sdef: #"<property name="tty" code="ttty"/>"#))
    }

    @Test("a program is kept only when both reads name the same tab and the same program")
    func confirmation() {
        let tab = TerminalScriptSource.Answer.process(paneID: "7", pid: 100)
        let sameTabNewProcess = TerminalScriptSource.Answer.process(paneID: "7", pid: 200)
        let otherTab = TerminalScriptSource.Answer.device(paneID: "/dev/ttys002", device: "/dev/ttys002")

        #expect(TerminalScriptSource.confirm(first: tab, firstProgram: "claude", second: tab, secondProgram: "claude")
            == .program(paneID: "7", name: "claude"))
        #expect(TerminalScriptSource.confirm(first: tab, firstProgram: "claude", second: sameTabNewProcess, secondProgram: "zsh")
            == .changed(paneID: "7"))
        #expect(TerminalScriptSource.confirm(first: tab, firstProgram: "claude", second: otherTab, secondProgram: "claude")
            == .changed(paneID: "/dev/ttys002"))
    }
}
