import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct HerdrRemoteTests {
    private static func machine(_ label: String, target: String? = nil, enabled: Bool = true, selected: Bool = false) -> HerdrMachine {
        HerdrMachine(id: "id-" + label, label: label, target: target ?? label, isEnabled: enabled, isSelected: selected)
    }

    @Test("machine list returns every saved machine with its id and flags")
    func parsesMachineList() throws {
        let machines = try #require(HerdrReplyParser.machines(from: Data(remoteMachineList.utf8)))

        #expect(machines == [
            HerdrMachine(id: "1ab3", label: "venus", target: "venus", isEnabled: true, isSelected: true),
            HerdrMachine(id: "2cd4", label: "lab", target: "me@gpu01.lab.example:2222", isEnabled: false, isSelected: false),
        ])
    }

    @Test("a malformed machine list is nil", arguments: ["", "{}", "null", #"[{"label":"venus"}]"#])
    func malformedMachineList(reply: String) {
        #expect(HerdrReplyParser.machines(from: Data(reply.utf8)) == nil)
    }

    @Test("a remote reply without argv0 is read by its process name")
    func remoteProgramUsesName() {
        #expect(HerdrReplyParser.program(from: Data(remoteProcessInfo.utf8)) == "nvitop")
    }

    @Test("the title names a machine by its label or by the host of its ssh target")
    func titleMatchesLabelOrHost() {
        let machines = [Self.machine("venus"), Self.machine("box", target: "me@gpu01.lab.example:2222")]

        #expect(HerdrRemote.machine(titleMachine: "venus", localMachine: "junming", machines: machines)?.label == "venus")
        #expect(HerdrRemote.machine(titleMachine: "gpu01", localMachine: "junming", machines: machines)?.label == "box")
    }

    @Test("this Mac's own title is never a remote machine")
    func localTitleIsNotRemote() {
        let machines = [Self.machine("junming", selected: true)]

        #expect(HerdrRemote.machine(titleMachine: "junming", localMachine: "junming", machines: machines) == nil)
    }

    @Test("a host name no machine is saved under falls back to the one selected machine")
    func unnamedHostUsesSelection() {
        let selected = [Self.machine("venus"), Self.machine("lab", selected: true)]
        let none = [Self.machine("venus"), Self.machine("lab")]

        #expect(HerdrRemote.machine(titleMachine: "node-7", localMachine: "junming", machines: selected)?.label == "lab")
        #expect(HerdrRemote.machine(titleMachine: "node-7", localMachine: "junming", machines: none) == nil)
    }

    @Test("a disabled machine is never asked, even when named or selected")
    func disabledMachineIsSkipped() {
        let machines = [Self.machine("venus", enabled: false, selected: true)]

        #expect(HerdrRemote.machine(titleMachine: "venus", localMachine: "junming", machines: machines) == nil)
        #expect(HerdrRemote.machine(titleMachine: "other", localMachine: "junming", machines: machines) == nil)
    }

    @Test("two machines answering to one name are not guessed between")
    func ambiguousNameIsNil() {
        let machines = [Self.machine("venus", selected: true), Self.machine("venus2", target: "venus")]

        #expect(HerdrRemote.machine(titleMachine: "venus", localMachine: "junming", machines: machines) == nil)
    }

    @Test("a remote pane id names its machine, so it never equals a local pane id")
    func paneIDIsNamespaced() {
        #expect(HerdrRemote.paneID(machineID: "1ab3", paneID: "w1:p1") == "machine:1ab3/w1:p1")
        #expect(HerdrRemote.paneID(machineID: "1ab3", paneID: "w1:p1") != "w1:p1")
    }

    @Test("CLI arguments ask the machine by id")
    func arguments() {
        #expect(HerdrRemote.paneListArguments(machineID: "1ab3") == ["--machine", "1ab3", "pane", "list"])
        #expect(HerdrRemote.processInfoArguments(machineID: "1ab3", paneID: "w6:p2")
            == ["--machine", "1ab3", "pane", "process-info", "--pane", "w6:p2"])
    }

    @Test("failed reads wait longer each time up to the last interval, and a success resets")
    func backoff() {
        var backoff = HerdrRemote.Backoff()

        let waits = (0..<6).map { _ in backoff.failed() }
        backoff.succeeded()

        #expect(waits == [2, 5, 10, 30, 30, 30])
        #expect(backoff.failed() == 2)
    }

    @Test("an extended wait ends only on the longer expiry")
    func extendedHold() {
        var hold = SurfaceHoldExtension()

        let extended = hold.extend(generation: 4, waitingGeneration: 4)

        #expect(extended)
        #expect(!hold.counts(generation: 4, isExtended: false))
        #expect(hold.counts(generation: 4, isExtended: true))
    }

    @Test("a wait already over, or of another generation, is not extended")
    func lateExtension() {
        var hold = SurfaceHoldExtension()

        let afterExpiry = hold.extend(generation: 4, waitingGeneration: nil)
        let otherGeneration = hold.extend(generation: 4, waitingGeneration: 5)

        #expect(!afterExpiry)
        #expect(!otherGeneration)
        #expect(hold.counts(generation: 5, isExtended: false))
    }

    @Test("a wait is extended once; a later generation's short expiry still counts")
    func extensionIsPerGeneration() {
        var hold = SurfaceHoldExtension()

        let first = hold.extend(generation: 4, waitingGeneration: 4)
        let second = hold.extend(generation: 4, waitingGeneration: 4)

        #expect(first)
        #expect(!second)
        #expect(hold.counts(generation: 5, isExtended: false))
    }
}

// Reduced from `herdr machine list --json` and `herdr --machine venus pane process-info` (2026-10-04).
private let remoteMachineList = #"""
[
  {"id":"1ab3","label":"venus","target":"venus","session":"default","enabled":true,"selected":true},
  {"id":"2cd4","label":"lab","target":"me@gpu01.lab.example:2222","session":"default","enabled":false,"selected":false}
]
"""#

private let remoteProcessInfo = #"""
{"id":"cli:pane:process_info","result":{"process_info":{"foreground_process_group_id":24092,
  "foreground_processes":[{"argv":["/usr/bin/python3","/home/user/.local/bin/nvitop"],"cmdline":"<scrubbed>","name":"nvitop","pid":24092}],
  "pane_id":"w6:p1","shell_pid":23110},"type":"pane_process_info"}}
"""#
