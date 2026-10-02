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

struct AppRuleBoardWebsiteTests {
    private func config(websites: [WebsiteRule], apps: [AppRule] = []) -> SwitcherConfig {
        var config = SwitcherConfig.default
        config.appRules = apps
        config.websiteRules = websites
        return config
    }

    @Test("a new website rule takes only a domain in stored form, never a page address")
    func dropRefusesAnAddress() {
        let empty = config(websites: [])

        for payload in ["https://user:secret@example.com/private?q=token", "Example.com", "example.com/path", "not a site"] {
            guard case .refused = AppRuleBoard.drop(websiteDomain: payload, on: .keepAsIs, in: empty) else {
                Issue.record("\(payload) was not refused")
                continue
            }
        }
        guard case .changed(let changed) = AppRuleBoard.drop(websiteDomain: "127.0.0.1", on: .keepAsIs, in: empty) else {
            Issue.record("an address in stored form was refused")
            return
        }
        #expect(changed.websiteRules.first?.includesSubdomains == false)
    }

    @Test("each lane lists its website chips beside its apps, one chip per domain")
    func lanesListWebsiteChips() {
        let board = AppRuleBoard.lanes(for: config(
            websites: [
                WebsiteRule(domain: "example.com", target: .slot(chinese)),
                WebsiteRule(domain: "bank.example", target: .keepAsIs),
                WebsiteRule(domain: "docs.example", target: .slot(english)),
                WebsiteRule(domain: "example.com", includesSubdomains: false, target: .slot(english)),
            ],
            apps: [AppRule(appID: terminal, target: .slot(english))]
        ))

        let englishLane = board.first { $0.target == .slot(english) }
        #expect(englishLane?.websiteRules.map(\.domain) == ["example.com", "docs.example"])
        #expect(englishLane?.rules.map(\.appID) == [terminal])
        #expect(board.first { $0.target == .slot(chinese) }?.websiteRules.isEmpty == true)
        #expect(board.last?.websiteRules.map(\.domain) == ["bank.example"])
    }

    @Test("each lane lists its program chips, one per name; a deleted slot keeps its lane for them")
    func lanesListProgramChips() {
        let gone = InputRole(rawValue: "korean")
        var config = SwitcherConfig.default
        config.programRules = [
            ProgramRule(name: "claude", target: .slot(chinese)),
            ProgramRule(name: "vim", target: .keepAsIs),
            ProgramRule(name: "ssh", target: .slot(gone)),
            ProgramRule(name: "claude", target: .slot(english)),
        ]

        let board = AppRuleBoard.lanes(for: config)

        #expect(board.first { $0.target == .slot(english) }?.programRules.map(\.name) == ["claude"])
        #expect(board.first { $0.target == .slot(chinese) }?.programRules.isEmpty == true)
        #expect(board.last?.programRules.map(\.name) == ["vim"])
        let deleted = board[board.count - 2]
        #expect(!deleted.slotExists)
        #expect(deleted.programRules.map(\.name) == ["ssh"])
    }

    @Test("a website rule naming a deleted slot stays visible in that slot's lane")
    func deletedSlotKeepsWebsiteChip() {
        let gone = InputRole(rawValue: "korean")
        let board = AppRuleBoard.lanes(for: config(websites: [WebsiteRule(domain: "example.com", target: .slot(gone))]))

        let lane = board[board.count - 2]
        #expect(lane.target == .slot(gone))
        #expect(!lane.slotExists)
        #expect(lane.websiteRules.map(\.domain) == ["example.com"])
    }

    @Test("dropping a new domain on a lane creates its rule, with subdomains unless told otherwise")
    func dropCreatesRule() {
        let result = AppRuleBoard.drop(websiteDomain: "example.com", on: .slot(english), in: config(websites: []))
        let exact = AppRuleBoard.drop(websiteDomain: "example.com", includesSubdomains: false, on: .keepAsIs, in: config(websites: []))

        guard case .changed(let next) = result, case .changed(let exactNext) = exact else { Issue.record("expected a change"); return }
        #expect(next.websiteRules == [WebsiteRule(domain: "example.com", includesSubdomains: true, target: .slot(english))])
        #expect(exactNext.websiteRules == [WebsiteRule(domain: "example.com", includesSubdomains: false, target: .keepAsIs)])
    }

    @Test("moving a website chip keeps its subdomain setting and its place in the list")
    func moveKeepsSubdomainsAndOrder() {
        let start = config(websites: [
            WebsiteRule(domain: "example.com", includesSubdomains: false, target: .slot(chinese)),
            WebsiteRule(domain: "docs.example", target: .slot(english)),
        ])

        let result = AppRuleBoard.drop(websiteDomain: "example.com", on: .keepAsIs, in: start)

        guard case .changed(let next) = result else { Issue.record("expected a change"); return }
        #expect(next.websiteRules == [
            WebsiteRule(domain: "example.com", includesSubdomains: false, target: .keepAsIs),
            WebsiteRule(domain: "docs.example", target: .slot(english)),
        ])
    }

    @Test("a website chip dropped on its own lane changes nothing, a deleted slot's lane included")
    func sameLaneIsUnchanged() {
        let gone = InputRole(rawValue: "korean")
        let start = config(websites: [
            WebsiteRule(domain: "example.com", target: .slot(english)),
            WebsiteRule(domain: "docs.example", target: .slot(gone)),
        ])

        #expect(AppRuleBoard.drop(websiteDomain: "example.com", on: .slot(english), in: start) == .unchanged)
        #expect(AppRuleBoard.drop(websiteDomain: "docs.example", on: .slot(gone), in: start) == .unchanged)
    }

    @Test("an empty domain and a deleted slot's lane are refused")
    func refusals() {
        let gone = InputRole(rawValue: "korean")
        let start = config(websites: [WebsiteRule(domain: "example.com", target: .slot(english))])

        for result in [
            AppRuleBoard.drop(websiteDomain: "", on: .slot(english), in: start),
            AppRuleBoard.drop(websiteDomain: "example.com", on: .slot(gone), in: start),
            AppRuleBoard.drop(websiteDomain: "new.example", on: .slot(gone), in: start),
        ] {
            guard case .refused = result else { Issue.record("expected a refusal, got \(result)"); continue }
        }
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

struct WebsiteDragPayloadTests {
    @Test("an encoded website chip decodes back to its domain, and other text is not one")
    func roundTripAndOtherText() {
        #expect(WebsiteDragPayload.decode(WebsiteDragPayload.encode(domain: "example.com")) == "example.com")
        #expect(WebsiteDragPayload.decode("example.com") == nil)
        #expect(WebsiteDragPayload.decode("cmdime-website\n") == nil)
        #expect(WebsiteDragPayload.decode(AppDragPayload.encode(appID: terminal, name: "Terminal")) == nil)
    }
}
