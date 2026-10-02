import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct TerminalSurfaceTests {
    @Test("a window title drawn by Herdr names its machine before the first colon and space")
    func machineInTitle() {
        #expect(HerdrSurface.machine(inWindowTitle: "junming: keyboard") == "junming")
        #expect(HerdrSurface.machine(inWindowTitle: "venus: ~") == "venus")
        #expect(HerdrSurface.machine(inWindowTitle: "venus: a: b") == "venus")
    }

    @Test("a title of another shape names no machine",
          arguments: ["", "~/workspace", "vim notes.txt", "ssh host: retry", ": x", "junming:keyboard"])
    func noMachineInOtherTitles(title: String) {
        #expect(HerdrSurface.machine(inWindowTitle: title) == nil)
    }

    @Test("a program matches its rule by exact, case-sensitive name")
    func programContext() {
        let rules = [ProgramRule(name: "claude", target: .slot(.chinese))]

        #expect(HerdrSurface.context(program: "claude", rules: rules) == .rule("claude"))
        #expect(HerdrSurface.context(program: "Claude", rules: rules) == .noRule)
        #expect(HerdrSurface.context(program: "zsh", rules: rules) == .noRule)
        #expect(HerdrSurface.context(program: nil, rules: rules) == .unknown)
    }

    @Test("requests are one JSON line each")
    func requests() throws {
        for data in [HerdrSurface.paneListRequest, HerdrSurface.processInfoRequest(paneID: "wR:pY"),
                     HerdrSurface.focusSubscriptionRequest] {
            #expect(data.last == UInt8(ascii: "\n"))
            #expect(data.filter { $0 == UInt8(ascii: "\n") }.count == 1)
        }
        let info = try #require(JSONSerialization.jsonObject(with: HerdrSurface.processInfoRequest(paneID: "wR:pY")) as? [String: Any])
        #expect(info["method"] as? String == "pane.process_info")
        #expect((info["params"] as? [String: String])?["pane_id"] == "wR:pY")
        let subscription = try #require(JSONSerialization.jsonObject(with: HerdrSurface.focusSubscriptionRequest) as? [String: Any])
        let types = ((subscription["params"] as? [String: Any])?["subscriptions"] as? [[String: String]])?.compactMap { $0["type"] }
        #expect(types == ["pane.focused", "tab.focused", "workspace.focused"])
    }

    @Test("terminals are known by bundle id")
    func terminals() {
        #expect(TerminalCatalog.isTerminal("com.mitchellh.ghostty"))
        #expect(!TerminalCatalog.isTerminal("com.apple.Safari"))
    }
}
