import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct HerdrForwardTests {
    @Test("ssh forwards the remote socket, runs nothing there, never asks, and survives a config forward that fails")
    func sshArguments() {
        let arguments = HerdrForward.sshArguments(
            target: "venus", localSocket: "/l/a.sock", remoteSocket: "/home/me/.config/herdr/herdr.sock")

        #expect(arguments.contains("-N"))
        #expect(arguments.contains("BatchMode=yes"))
        #expect(arguments.contains("ExitOnForwardFailure=no"))
        #expect(arguments.suffix(4) == ["-L", "/l/a.sock:/home/me/.config/herdr/herdr.sock", "--", "venus"])
    }

    @Test("a host:port target becomes an ssh URL; other targets pass as saved", arguments: [
        ("venus", "venus"),
        ("me@venus.lab", "me@venus.lab"),
        ("venus:2222", "ssh://venus:2222"),
        ("me@10.0.0.2:20330", "ssh://me@10.0.0.2:20330"),
        ("ssh://venus:2222", "ssh://venus:2222"),
        ("[fe80::1]:22", "[fe80::1]:22"),
        ("fe80::1", "fe80::1"),
        ("venus:abc", "venus:abc"),
    ])
    func destination(target: String, expected: String) {
        #expect(HerdrForward.destination(ofTarget: target) == expected)
    }

    @Test("ssh -G output names the login user")
    func userInResolvedConfig() {
        let output = "hostname 10.209.1.11\nuser junming\nport 20330\n"

        #expect(HerdrForward.user(inResolvedConfig: output) == "junming")
        #expect(HerdrForward.user(inResolvedConfig: "hostname x\n") == nil)
        #expect(HerdrForward.user(inResolvedConfig: "username x\n") == nil)
    }

    @Test("the remote socket is looked for in the usual homes, Linux first")
    func remoteSocketCandidates() {
        #expect(HerdrForward.remoteSocketCandidates(user: "junming") == [
            "/home/junming/.config/herdr/herdr.sock", "/Users/junming/.config/herdr/herdr.sock",
        ])
        #expect(HerdrForward.remoteSocketCandidates(user: "root") == ["/root/.config/herdr/herdr.sock"])
        #expect(HerdrForward.remoteSocketCandidates(user: "").isEmpty)
        #expect(HerdrForward.remoteSocketCandidates(user: "../x").isEmpty)
    }

    @Test("the local socket is named by the machine id and fits sockaddr_un")
    func localSocketPath() {
        #expect(HerdrForward.localSocketPath(directory: "/Users/me/.config/cmd-ime/herdr", machineID: "1ab3578c70b9b0136573186a97adddf2")
            == "/Users/me/.config/cmd-ime/herdr/1ab3578c70b9b013.sock")
        #expect(HerdrForward.localSocketPath(directory: "/d", machineID: "../") == nil)
        #expect(HerdrForward.localSocketPath(directory: "/" + String(repeating: "x", count: 100), machineID: "abc") == nil)
    }

    @Test("a forward is tried only when on, and not again until a minute after it failed")
    func shouldTry() {
        #expect(!HerdrForward.shouldTry(isOn: false, lastFailure: nil, now: 0))
        #expect(HerdrForward.shouldTry(isOn: true, lastFailure: nil, now: 0))
        #expect(!HerdrForward.shouldTry(isOn: true, lastFailure: 100, now: 159))
        #expect(HerdrForward.shouldTry(isOn: true, lastFailure: 100, now: 160))
    }

    @Test("the setting is off by default, read when present and written only when on")
    func configKey() throws {
        let config = SwitcherConfig.default
        let encoded = try JSONEncoder().encode(config)
        let on = try JSONEncoder().encode(config.settingReadsHerdrMachinesOverSSH(true))

        #expect(!config.readsHerdrMachinesOverSSH)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("herdrMachinesOverSSH"))
        #expect(try JSONDecoder().decode(SwitcherConfig.self, from: on).readsHerdrMachinesOverSSH)
    }
}
