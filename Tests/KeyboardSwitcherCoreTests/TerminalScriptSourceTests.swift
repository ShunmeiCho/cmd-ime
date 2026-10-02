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

    @Test("a terminal without the property is not asked again until it is relaunched")
    func unsupportedUntilRelaunch() {
        var availability = TerminalScriptSource.Availability()
        #expect(availability.shouldAsk(appPID: 10))

        availability.failed(errorCode: -1728, appPID: 10)

        #expect(!availability.shouldAsk(appPID: 10))
        #expect(availability.shouldAsk(appPID: 11))
    }

    @Test("a refusal stops the asking; a transient error once it has answered does not")
    func refusedAndTransient() {
        var refused = TerminalScriptSource.Availability()
        refused.failed(errorCode: -1743, appPID: 10)
        #expect(!refused.shouldAsk(appPID: 11))

        var answered = TerminalScriptSource.Availability()
        answered.answered()
        answered.failed(errorCode: -1728, appPID: 10)
        answered.failed(errorCode: -1712, appPID: 10)
        #expect(answered.shouldAsk(appPID: 10))
    }
}
