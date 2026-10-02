import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct TerminalTitleMarkerTests {
    @Test("a device's mark reads back as that device, alone or inside any title", arguments: ["ttys000", "ttys009", "ttys123", "/dev/ttys016"])
    func roundTrip(device: String) throws {
        let mark = try #require(TerminalTitleMarker.mark(forDevice: device))
        let expected = device.replacingOccurrences(of: "/dev/", with: "")

        #expect(TerminalTitleMarker.device(inTitle: mark) == expected)
        #expect(TerminalTitleMarker.device(inTitle: "~/workspace " + mark) == expected)
        #expect(TerminalTitleMarker.device(inTitle: mark + " zsh") == expected)
    }

    @Test("the mark is invisible: only the two measured zero-width characters")
    func invisible() throws {
        let mark = try #require(TerminalTitleMarker.mark(forDevice: "ttys009"))

        #expect(mark.unicodeScalars.allSatisfy { $0.value == 0x200B || $0.value == 0x200C })
    }

    @Test("a title with two marks names the last one")
    func lastMarkWins() throws {
        let first = try #require(TerminalTitleMarker.mark(forDevice: "ttys001"))
        let second = try #require(TerminalTitleMarker.mark(forDevice: "ttys002"))

        #expect(TerminalTitleMarker.device(inTitle: first + "x" + second) == "ttys002")
    }

    @Test("a title without a complete mark names no device", arguments: [
        "", "~/workspace", "mark\u{200B}\u{200C}\u{200B}", "\u{200C}\u{200C}\u{200C}\u{200B}",
    ])
    func noMark(title: String) {
        #expect(TerminalTitleMarker.device(inTitle: title) == nil)
    }

    @Test("a cut-off mark names no device")
    func truncated() throws {
        let mark = try #require(TerminalTitleMarker.mark(forDevice: "ttys009"))

        #expect(TerminalTitleMarker.device(inTitle: String(mark.dropLast())) == nil)
        #expect(TerminalTitleMarker.device(inTitle: String(mark.dropFirst())) == nil)
    }

    @Test("only terminal devices get a mark", arguments: ["console", "tty", "ttys", "ttysx1", "pts/1", "ttys99999"])
    func onlyDevices(name: String) {
        #expect(TerminalTitleMarker.mark(forDevice: name) == nil)
    }
}

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
