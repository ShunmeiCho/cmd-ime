import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct TerminalDeviceTests {
    @Test("the name a rule matches drops the directory and a login shell's dash", arguments: [
        ("claude", "claude"), ("/usr/local/bin/codex", "codex"), ("-zsh", "zsh"), ("-/bin/zsh", "zsh"),
    ])
    func programName(argv0: String, expected: String) {
        #expect(TerminalDevice.programName(fromArgv0: argv0) == expected)
    }

    @Test("a device that does not exist runs nothing")
    func missingDevice() {
        #expect(TerminalDevice.foregroundProgram(ofDevice: "ttys999") == nil)
        #expect(TerminalDevice.programName(fromArgv0: "") == nil)
    }
}
