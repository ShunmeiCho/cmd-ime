import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct HerdrReplyParserTests {
    @Test("pane list selects the focused pane and preserves its IDs and agent")
    func focusedPaneIDsAndAgent() throws {
        let pane = try #require(HerdrReplyParser.focusedPane(from: Data(paneList.utf8)))

        #expect(pane.paneID == "wR:p2")
        #expect(pane.tabID == "wR:t2")
        #expect(pane.workspaceID == "wR")
        #expect(pane.agent == "claude")
    }

    @Test("shell panes have no agent", arguments: ["", #", "agent": null"#])
    func shellPaneHasNoAgent(agentField: String) throws {
        let reply = #"{"result":{"panes":[{"focused":true,"pane_id":"wR:pG","tab_id":"wR:tG","workspace_id":"wR"\#(agentField)}]}}"#
        let pane = try #require(HerdrReplyParser.focusedPane(from: Data(reply.utf8)))

        #expect(pane.paneID == "wR:pG")
        #expect(pane.agent == nil)
    }

    @Test("a pane list with no focused pane returns nil")
    func noFocusedPane() {
        let reply = paneList.replacingOccurrences(of: "true", with: "false")

        #expect(HerdrReplyParser.focusedPane(from: Data(reply.utf8)) == nil)
    }

    @Test("an ambiguous pane list returns nil")
    func multipleFocusedPanes() {
        let reply = paneList.replacingOccurrences(of: "false", with: "true")

        #expect(HerdrReplyParser.focusedPane(from: Data(reply.utf8)) == nil)
    }

    @Test("incomplete focused pane IDs are not accepted", arguments: ["pane_id", "tab_id", "workspace_id"])
    func missingPaneID(key: String) {
        let reply = paneList.replacingOccurrences(of: "\"\(key)\"", with: "\"unused\"")

        #expect(HerdrReplyParser.focusedPane(from: Data(reply.utf8)) == nil)
    }

    @Test("local Claude uses the group leader argv0, not its version name or a child")
    func localClaudeUsesLeaderArgv0() {
        #expect(HerdrReplyParser.program(from: Data(localClaude.utf8)) == "claude")
    }

    @Test("shell replies read argv0 rather than argv")
    func localShellUsesArgv0() {
        #expect(HerdrReplyParser.program(from: Data(localShell.utf8)) == "zsh")
    }

    @Test("remote replies put process info directly under result and may have null argv0")
    func remoteProcessInfoUsesName() {
        #expect(HerdrReplyParser.program(from: Data(remoteLinux.utf8)) == "claude")
    }

    @Test("name is used only when argv0 is missing or null", arguments: ["", #", "argv0": null"#])
    func missingArgv0UsesName(argv0Field: String) {
        let reply = #"{"result":{"foreground_process_group_id":42,"foreground_processes":[{"pid":42,"name":"vim"\#(argv0Field)}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == "vim")
    }

    @Test("argv0 works without a name and is returned unchanged")
    func argv0IsNotNormalized() {
        let reply = #"{"result":{"foreground_process_group_id":42,"foreground_processes":[{"pid":42,"argv0":"/usr/local/bin/Claude"}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == "/usr/local/bin/Claude")
    }

    @Test("an unusable but present argv0 never falls back to name", arguments: [#""""#, "42", "false", "[]", "{}"])
    func invalidArgv0DoesNotUseName(argv0: String) {
        let reply = #"{"result":{"foreground_process_group_id":42,"foreground_processes":[{"pid":42,"name":"claude","argv0":\#(argv0)}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("a process with neither argv0 nor name returns nil")
    func missingProgramName() {
        let reply = #"{"result":{"foreground_process_group_id":42,"foreground_processes":[{"pid":42}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("no group leader means no program, even when other processes exist")
    func noGroupLeader() {
        let reply = localClaude.replacingOccurrences(of: #""foreground_process_group_id": 64323"#, with: #""foreground_process_group_id": 7"#)

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("an empty foreground process list returns nil")
    func noForegroundProcesses() {
        let reply = #"{"result":{"foreground_process_group_id":42,"foreground_processes":[]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("duplicate group leaders are ambiguous")
    func multipleGroupLeaders() {
        let reply = #"{"result":{"foreground_process_group_id":42,"foreground_processes":[{"pid":42,"argv0":"claude"},{"pid":42,"argv0":"zsh"}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("an invalid local wrapper is not reinterpreted as a remote reply", arguments: ["null", "[]", "42"])
    func invalidLocalWrapper(info: String) {
        let reply = #"{"result":{"process_info":\#(info),"foreground_process_group_id":42,"foreground_processes":[{"pid":42,"argv0":"claude"}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("noninteger process IDs cannot select a program", arguments: ["true", "42.5", #""42""#, "null", "18446744073709551616"])
    func invalidProcessID(id: String) {
        let reply = #"{"result":{"foreground_process_group_id":\#(id),"foreground_processes":[{"pid":\#(id),"argv0":"claude"}]}}"#

        #expect(HerdrReplyParser.program(from: Data(reply.utf8)) == nil)
    }

    @Test("pane focus events carry pane and workspace IDs")
    func paneFocusedEvent() {
        let line = #"{"data":{"pane_id":"wR:pX","type":"pane_focused","workspace_id":"wR"},"event":"pane_focused"}"#

        #expect(HerdrReplyParser.event(from: line) == .paneFocused(paneID: "wR:pX", workspaceID: "wR"))
    }

    @Test("tab focus events carry tab and workspace IDs")
    func tabFocusedEvent() {
        let line = #"{"data":{"tab_id":"wR:tX","type":"tab_focused","workspace_id":"wR"},"event":"tab_focused"}"#

        #expect(HerdrReplyParser.event(from: line) == .tabFocused(tabID: "wR:tX", workspaceID: "wR"))
    }

    @Test("workspace focus events carry the workspace ID")
    func workspaceFocusedEvent() {
        let line = #"{"data":{"type":"workspace_focused","workspace_id":"wR"},"event":"workspace_focused"}"#

        #expect(HerdrReplyParser.event(from: line) == .workspaceFocused(workspaceID: "wR"))
    }

    @Test("subscription acknowledgements are not focus events")
    func subscriptionStartedEvent() {
        #expect(HerdrReplyParser.event(from: #"{"id":"sub","result":{"type":"subscription_started"}}"#) == .subscriptionStarted)
    }

    @Test("unsupported or incomplete event lines are unknown", arguments: [
        "", "not JSON", "[]", "{}", "null",
        #"{"event":"pane.agent_detected","data":{"agent":"claude"}}"#,
        #"{"event":"pane_focused","data":{"workspace_id":"wR"}}"#,
        #"{"event":"tab_focused","data":{"tab_id":"wR:tX"}}"#,
        #"{"event":"workspace_focused","data":{"workspace_id":42}}"#,
        #"{"event":"workspace_focused","data":{"workspace_id":""}}"#,
        #"{"result":{"type":"something_new"}}"#,
        #"{"event":false,"data":null}"#,
        #"{"event":"pane_focused","data":[]}"#,
        "{}\n{}",
    ])
    func unknownEvents(line: String) {
        #expect(HerdrReplyParser.event(from: line) == .unknown)
    }

    @Test("machine list returns the selected entry label and target")
    func selectedMachine() throws {
        let machine = try #require(HerdrReplyParser.selectedMachine(from: Data(machineList.utf8)))

        #expect(machine.label == "venus")
        #expect(machine.target == "venus.example")
    }

    @Test("machine selection does not require enabled to be true")
    func selectionUsesSelectedFlagOnly() {
        let reply = machineList.replacingOccurrences(of: "\"enabled\": true", with: "\"enabled\": false")

        #expect(HerdrReplyParser.selectedMachine(from: Data(reply.utf8))?.label == "venus")
    }

    @Test("a machine list without a selection returns nil")
    func noSelectedMachine() {
        let reply = machineList.replacingOccurrences(of: "\"selected\": true", with: "\"selected\": false")

        #expect(HerdrReplyParser.selectedMachine(from: Data(reply.utf8)) == nil)
    }

    @Test("unknown machine shapes and ambiguous selections return nil", arguments: [
        "[]", #"{"machines":[]}"#,
        #"[{"selected":true,"label":"venus"}]"#,
        #"[{"selected":true,"label":"venus","target":""}]"#,
        #"[{"selected":1,"label":"venus","target":"venus"}]"#,
        #"[{"selected":true,"label":"a","target":"a"},{"selected":true,"label":"b","target":"b"}]"#,
    ])
    func unknownMachineShapes(reply: String) {
        #expect(HerdrReplyParser.selectedMachine(from: Data(reply.utf8)) == nil)
    }

    @Test("reply parsers safely reject invalid UTF-8")
    func invalidUTF8() {
        let data = Data([0xFF, 0xFE, 0xFF])

        #expect(HerdrReplyParser.focusedPane(from: data) == nil)
        #expect(HerdrReplyParser.program(from: data) == nil)
        #expect(HerdrReplyParser.selectedMachine(from: data) == nil)
    }

    @Test("reply parsers safely reject malformed or unrelated JSON", arguments: [
        "", "not JSON", "null", "42", "[]", "{}", #"{"result":null}"#,
        #"{"error":{"message":"unavailable"}}"#, #"{"result":{"panes":false}}"#,
    ])
    func invalidReplies(reply: String) {
        let data = Data(reply.utf8)

        #expect(HerdrReplyParser.focusedPane(from: data) == nil)
        #expect(HerdrReplyParser.program(from: data) == nil)
        #expect(HerdrReplyParser.selectedMachine(from: data) == nil)
    }
}

// Reduced, scrubbed Herdr samples; extra fields remain to verify they are ignored.
private let paneList = #"""
{"id":"cli:pane:list","result":{"type":"pane_list","panes":[
  {"focused":false,"pane_id":"wQ:p1","tab_id":"wQ:t1","workspace_id":"wQ","agent":"claude"},
  {"focused":true,"pane_id":"wR:p2","tab_id":"wR:t2","workspace_id":"wR","agent":"claude","cwd":"<scrubbed>","agent_status":"working"},
  {"focused":false,"pane_id":"wR:pG","tab_id":"wR:tG","workspace_id":"wR","agent_status":"unknown"}
]}}
"""#

private let localClaude = #"""
{"id":"cli:pane:process_info","result":{"type":"pane_process_info","process_info":{
  "foreground_process_group_id": 64323,
  "foreground_processes":[
    {"pid":43657,"argv0":"caffeinate","name":"caffeinate"},
    {"pid":64323,"argv0":"claude","name":"2.1.286","argv":["claude"],"cmdline":"<scrubbed>"},
    {"pid":92245,"argv0":"node","name":"node"}
  ],"pane_id":"wR:p2","shell_pid":81055
}}}
"""#

private let localShell = #"""
{"id":"cli:pane:process_info","result":{"type":"pane_process_info","process_info":{
  "foreground_process_group_id":1708,
  "foreground_processes":[{"pid":1708,"argv0":"zsh","name":"zsh","argv":["-zsh"],"cmdline":"<scrubbed>"}],
  "pane_id":"wR:pG","shell_pid":1708
}}}
"""#

private let remoteLinux = #"""
{"id":"cli:pane:process-info","result":{
  "foreground_process_group_id":3450470,
  "foreground_processes":[
    {"pid":3450470,"name":"claude","argv0":null},
    {"pid":3450900,"name":"npm exec @upsta","argv0":null}
  ],"pane_id":"wD:p4","shell_pid":3450001
}}
"""#

private let machineList = #"""
[
  {"id":"other","label":"other","target":"other.example","selected": false},
  {"id":"scrubbed","label":"venus","target":"venus.example","session":"default","enabled": true,"selected": true}
]
"""#
