import Foundation
import Testing
@testable import KeyboardSwitcherCore

private let english = InputRole(rawValue: "english")
private let chinese = InputRole(rawValue: "chinese")
private let japanese = InputRole(rawValue: "japanese")
private let terminal = "com.apple.Terminal"
private let wechat = "com.tencent.xinWeChat"
private let rdp = "com.microsoft.rdc.macos"
private let own = "com.shunmei.cmd-ime"

private func config(rules: [AppRule]) -> SwitcherConfig {
    var config = SwitcherConfig.default
    config.appRules = rules
    return config
}

struct AppRuleBoardLaneTests {
    @Test("one lane per slot in slot order, then Keep as is, each holding its rules")
    func lanesFollowSlots() {
        let board = AppRuleBoard.lanes(for: config(rules: [
            AppRule(appID: wechat, target: .slot(chinese)),
            AppRule(appID: rdp, target: .keepAsIs),
            AppRule(appID: terminal, target: .slot(english)),
        ]))

        #expect(board.map(\.target) == SwitcherConfig.default.slots.map { .slot($0.id) } + [.keepAsIs])
        #expect(board.first { $0.target == .slot(english) }?.rules.map(\.appID) == [terminal])
        #expect(board.first { $0.target == .slot(chinese) }?.rules.map(\.appID) == [wechat])
        #expect(board.last?.rules.map(\.appID) == [rdp])
        #expect(board.allSatisfy { $0.slotExists })
    }

    @Test("a rule naming a deleted slot gets its own lane before Keep as is")
    func deletedSlotKeepsALane() {
        let gone = InputRole(rawValue: "korean")
        let board = AppRuleBoard.lanes(for: config(rules: [AppRule(appID: terminal, target: .slot(gone))]))

        let lane = board[board.count - 2]
        #expect(lane.target == .slot(gone))
        #expect(!lane.slotExists)
        #expect(lane.rules.map(\.appID) == [terminal])
        #expect(board.last?.target == .keepAsIs)
    }
}

struct AppRuleBoardDropTests {
    @Test("dropping a new app on a slot lane adds a rule with its name")
    func dropAddsRule() {
        let result = AppRuleBoard.drop(appID: terminal, name: "Terminal", on: .slot(english), in: config(rules: []), ownAppID: own)

        guard case .changed(let next) = result else { Issue.record("expected a change"); return }
        #expect(next.appRules == [AppRule(appID: terminal, name: "Terminal", target: .slot(english))])
    }

    @Test("moving a rule to another slot keeps Remember and its place in the list")
    func moveKeepsRememberAndOrder() {
        let start = config(rules: [
            AppRule(appID: wechat, name: "WeChat", target: .slot(chinese), rememberInstead: true),
            AppRule(appID: terminal, target: .slot(english)),
        ])

        let result = AppRuleBoard.drop(appID: wechat, name: nil, on: .slot(japanese), in: start, ownAppID: own)

        guard case .changed(let next) = result else { Issue.record("expected a change"); return }
        #expect(next.appRules.map(\.appID) == [wechat, terminal])
        #expect(next.appRules[0] == AppRule(appID: wechat, name: "WeChat", target: .slot(japanese), rememberInstead: true))
    }

    @Test("moving to Keep as is drops Remember")
    func keepAsIsNeverRemembers() {
        let start = config(rules: [AppRule(appID: wechat, target: .slot(chinese), rememberInstead: true)])

        let result = AppRuleBoard.drop(appID: wechat, name: nil, on: .keepAsIs, in: start, ownAppID: own)

        guard case .changed(let next) = result else { Issue.record("expected a change"); return }
        #expect(next.appRules == [AppRule(appID: wechat, target: .keepAsIs, rememberInstead: false)])
    }

    @Test("dropping an app on the lane it is already in changes nothing")
    func sameLaneIsUnchanged() {
        let start = config(rules: [AppRule(appID: terminal, target: .slot(english))])

        #expect(AppRuleBoard.drop(appID: terminal, name: "Terminal", on: .slot(english), in: start, ownAppID: own) == .unchanged)
    }

    @Test("a chip dropped back on its own deleted-slot lane changes nothing")
    func deletedLaneOwnChipIsUnchanged() {
        let gone = InputRole(rawValue: "korean")
        let start = config(rules: [AppRule(appID: terminal, target: .slot(gone))])

        #expect(AppRuleBoard.drop(appID: terminal, name: nil, on: .slot(gone), in: start, ownAppID: own) == .unchanged)
    }

    @Test("CmdIME itself, an empty id and a deleted slot's lane are refused")
    func refusals() {
        let start = config(rules: [])
        let gone = InputRole(rawValue: "korean")

        for result in [
            AppRuleBoard.drop(appID: own, name: "CmdIME", on: .slot(english), in: start, ownAppID: own),
            AppRuleBoard.drop(appID: "", name: nil, on: .slot(english), in: start, ownAppID: own),
            AppRuleBoard.drop(appID: terminal, name: nil, on: .slot(gone), in: start, ownAppID: own),
        ] {
            guard case .refused = result else { Issue.record("expected a refusal, got \(result)"); continue }
        }
    }

    @Test("an app's id is its bundle id, else its executable path")
    func appIDPrefersBundleID() {
        #expect(AppRuleBoard.appID(bundleIdentifier: terminal, executablePath: "/x/Terminal") == terminal)
        #expect(AppRuleBoard.appID(bundleIdentifier: "", executablePath: "/opt/tool/bin/tool") == "/opt/tool/bin/tool")
        #expect(AppRuleBoard.appID(bundleIdentifier: nil, executablePath: nil) == nil)
    }
}

struct AppCandidateListTests {
    private let running = [
        AppCandidate(id: wechat, name: "WeChat"),
        AppCandidate(id: terminal, name: "Terminal"),
        AppCandidate(id: own, name: "CmdIME"),
    ]
    private let installed = [
        AppCandidate(id: terminal, name: "Terminal"),
        AppCandidate(id: "com.apple.Notes", name: "Notes"),
        AppCandidate(id: "com.apple.TextEdit", name: "TextEdit"),
    ]

    @Test("without a query the list shows running apps by name, without CmdIME or ruled apps")
    func runningOnlyWithoutQuery() {
        let list = AppCandidateList.visible(running: running, installed: installed, ruledIDs: [wechat], ownAppID: own, query: "  ")

        #expect(list.map(\.id) == [terminal])
    }

    @Test("a query searches running and installed apps, running first, each app once")
    func querySearchesBoth() {
        let list = AppCandidateList.visible(running: running, installed: installed, ruledIDs: [], ownAppID: own, query: "te")

        #expect(list.map(\.id) == [terminal, wechat, "com.apple.Notes", "com.apple.TextEdit"])
    }

    @Test("a query ignores case and accents and also matches the bundle id")
    func queryIgnoresCaseAndAccents() {
        let apps = [AppCandidate(id: "com.example.cafe", name: "Café Notes")]

        #expect(AppCandidateList.visible(running: [], installed: apps, ruledIDs: [], ownAppID: nil, query: "CAFE").count == 1)
        #expect(AppCandidateList.visible(running: [], installed: apps, ruledIDs: [], ownAppID: nil, query: "example").count == 1)
    }
}

struct AppDragPayloadTests {
    @Test("an encoded app decodes back to its id and name")
    func roundTrip() {
        let decoded = AppDragPayload.decode(AppDragPayload.encode(appID: terminal, name: "Terminal"))

        #expect(decoded?.appID == terminal)
        #expect(decoded?.name == "Terminal")
    }

    @Test("an app without a bundle id travels by path, and a missing name stays nil")
    func pathAndEmptyName() {
        let decoded = AppDragPayload.decode(AppDragPayload.encode(appID: "/opt/tool/bin/tool", name: ""))

        #expect(decoded?.appID == "/opt/tool/bin/tool")
        #expect(decoded?.name == nil)
    }

    @Test("other text dropped on the board is not an app")
    func otherTextIsIgnored() {
        #expect(AppDragPayload.decode("com.apple.Terminal") == nil)
        #expect(AppDragPayload.decode("cmdime-app\n") == nil)
    }
}
