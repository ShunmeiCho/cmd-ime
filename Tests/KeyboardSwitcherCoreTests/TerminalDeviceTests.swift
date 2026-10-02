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

    @Test("a process is named by its argv0; this test process has one")
    func programOfPID() {
        #expect(TerminalDevice.program(ofPID: getpid()) != nil)
        #expect(TerminalDevice.program(ofPID: 0) == nil)
    }

    /// A `KERN_PROCARGS2` buffer laid out as the kernel does: argc, the path padded to 8, then the strings.
    private func procArgs(argc: Int32, path: String, strings: [String]) -> [UInt8] {
        var bytes = withUnsafeBytes(of: argc.littleEndian, Array.init)
        let pathBytes = Array(path.utf8) + [0]
        bytes += pathBytes + Array(repeating: 0, count: (8 - pathBytes.count % 8) % 8)
        for string in strings { bytes += Array(string.utf8) + [0] }
        return bytes
    }

    @Test("argv0 is read where argv starts, for paths of every padding length")
    func argv0AtItsPlace() {
        for path in ["/bin/ksh", "/bin/sleep", "/usr/bin/yes", "/usr/bin/tail", "/usr/bin/caffeinate"] {
            #expect(TerminalDevice.argv0(fromProcArgs: procArgs(argc: 2, path: path, strings: ["claude", "--resume", "HOME=/x"])) == "claude")
        }
    }

    @Test("an empty argv0 or no arguments names nothing, never the next argument or the environment")
    func argv0Empty() {
        #expect(TerminalDevice.argv0(fromProcArgs: procArgs(argc: 2, path: "/bin/sleep", strings: ["", "30"])) == nil)
        #expect(TerminalDevice.argv0(fromProcArgs: procArgs(argc: 1, path: "/bin/cat", strings: ["", "I1_SYNTHETIC=x"])) == nil)
        #expect(TerminalDevice.argv0(fromProcArgs: procArgs(argc: 0, path: "/bin/cat", strings: ["HOME=/x"])) == nil)
    }

    @Test("a truncated or unexpected buffer names nothing")
    func argv0Malformed() {
        #expect(TerminalDevice.argv0(fromProcArgs: [UInt8]()) == nil)
        #expect(TerminalDevice.argv0(fromProcArgs: procArgs(argc: 1, path: "/bin/sleep", strings: []).dropLast(3)) == nil)
        let unpadded = withUnsafeBytes(of: Int32(1).littleEndian, Array.init) + Array("/bin/sleep".utf8) + [0, 65, 0]
        #expect(TerminalDevice.argv0(fromProcArgs: unpadded) == nil)
    }
}
