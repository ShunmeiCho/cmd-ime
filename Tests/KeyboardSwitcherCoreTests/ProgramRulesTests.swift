import Foundation
import Testing
@testable import KeyboardSwitcherCore

private func programConfig(_ rules: String, paused: String = "false") throws -> SwitcherConfig {
    let json = #"{"version":3,"bindings":[],"inputSources":{},"programRules":\#(rules),"programRulesPaused":\#(paused)}"#
    return try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))
}

struct ProgramRuleCodingTests {
    @Test("program rule keys survive decoding and encoding")
    func configPreservesProgramKeys() throws {
        let config = try programConfig(#"[{"name":"claude","kind":"slot","slot":"chinese"}]"#, paused: "true")
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect((object["programRules"] as? [[String: Any]])?.first?["name"] as? String == "claude")
        #expect(object["programRulesPaused"] as? Bool == true)
    }

    @Test("slot and keep rules round-trip with the specified JSON keys")
    func ruleRoundTrip() throws {
        let rules = [
            ProgramRule(name: "claude", target: .slot(.chinese)),
            ProgramRule(name: "vim", target: .keepAsIs),
        ]
        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode([ProgramRule].self, from: data) == rules)
        let objects = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: String]])
        #expect(objects == [
            ["name": "claude", "kind": "slot", "slot": "chinese"],
            ["name": "vim", "kind": "keep"],
        ])
    }

    @Test("unreadable elements are dropped without losing adjacent rules")
    func dropsOnlyUnreadableRules() throws {
        let config = try programConfig(#"""
        [{"name":"claude","kind":"slot","slot":"chinese"},
         {"name":"future","kind":"unknown"}, {"name":"missing-slot","kind":"slot"},
         {"kind":"keep"}, {"name":12,"kind":"keep"}, null, 7, "bad",
         {"name":"vim","kind":"keep"}]
        """#)
        #expect(config.programRules == [
            ProgramRule(name: "claude", target: .slot(.chinese)),
            ProgramRule(name: "vim", target: .keepAsIs),
        ])
    }

    @Test("the later duplicate name replaces the first in place while case stays distinct")
    func duplicateNames() throws {
        let config = try programConfig(#"""
        [{"name":"claude","kind":"keep"}, {"name":"Claude","kind":"keep"},
         {"name":"claude","kind":"slot","slot":"chinese"}]
        """#)
        #expect(config.programRules == [
            ProgramRule(name: "claude", target: .slot(.chinese)),
            ProgramRule(name: "Claude", target: .keepAsIs),
        ])
    }

    @Test("missing or null keys default to no rules and not paused", arguments: [
        #"{"bindings":[],"inputSources":{}}"#,
        #"{"bindings":[],"inputSources":{},"programRules":null,"programRulesPaused":null}"#,
    ])
    func missingKeys(json: String) throws {
        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))
        #expect(config.programRules.isEmpty)
        #expect(!config.programRulesPaused)
    }

    @Test("empty rules and an unpaused flag are omitted without a version bump")
    func omitsDefaults() throws {
        let config = SwitcherConfig.default
        let object = try #require(try JSONSerialization.jsonObject(with: JSONEncoder().encode(config)) as? [String: Any])
        #expect(object["programRules"] == nil)
        #expect(object["programRulesPaused"] == nil)
        #expect(SwitcherConfig.currentVersion == 3)
        #expect(config.version == 3)
    }

    @Test("a canonical config from a0b63a3 without program keys round-trips byte-identically")
    func baselineBytesUnchanged() throws {
        // ConfigStore output captured on a0b63a3, before Program Rules existed.
        let original = Data(#"""
        {
          "appRules" : [

          ],
          "bindings" : [

          ],
          "hasCompletedSetup" : true,
          "inputSources" : {

          },
          "rememberInputSourcePerApp" : false,
          "restoreAfterPasswordField" : true,
          "showCapsLockIndicator" : false,
          "showSwitchIndicator" : true,
          "slots" : [
            {
              "id" : "english",
              "name" : "English",
              "tintHex" : "#4D8CFF"
            },
            {
              "id" : "chinese",
              "name" : "Chinese",
              "tintHex" : "#33A854"
            },
            {
              "id" : "japanese",
              "name" : "Japanese",
              "tintHex" : "#E3574A"
            }
          ],
          "switchIndicatorBehavior" : {
            "hiddenAppIDs" : [

            ],
            "showsExternalChanges" : true,
            "showsOnAppSwitch" : false
          },
          "switchIndicatorColorStyle" : "role",
          "switchIndicatorContentStyle" : "iconAndText",
          "switchIndicatorCustomColorHex" : "#2F7CF6",
          "switchIndicatorCustomRoleColorHexes" : {

          },
          "switchIndicatorScale" : 1,
          "switchIndicatorSize" : "medium",
          "switchIndicatorSizeFactor" : 1,
          "version" : 3,
          "websiteRules" : [

          ]
        }
        """#.utf8)
        let config = try JSONDecoder().decode(SwitcherConfig.self, from: original)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        #expect(try encoder.encode(config) == original)
    }

    @Test("program rules and pause survive a whole config round trip")
    func configRoundTrip() throws {
        let config = SwitcherConfig.default
            .setting(ProgramRule(name: "claude", target: .slot(.chinese)))
            .setting(ProgramRule(name: "vim", target: .keepAsIs))
            .settingProgramRulesPaused(true)
        #expect(try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config)) == config)
    }
}

struct ProgramRuleConfigTests {
    @Test("setting replaces the same name in place without mutating the original")
    func settingReplacesByName() {
        let config = SwitcherConfig.default
            .setting(ProgramRule(name: "claude", target: .keepAsIs))
            .setting(ProgramRule(name: "zsh", target: .slot(.english)))
        let next = config.setting(ProgramRule(name: "claude", target: .slot(.chinese)))
        #expect(next.programRules.map(\.name) == ["claude", "zsh"])
        #expect(next.programRule(for: "claude")?.target == .slot(.chinese))
        #expect(config.programRule(for: "claude")?.target == .keepAsIs)
    }

    @Test("setting appends a new exact name")
    func settingAppends() {
        let config = SwitcherConfig.default
            .setting(ProgramRule(name: "claude", target: .keepAsIs))
            .setting(ProgramRule(name: "Claude", target: .slot(.chinese)))
        #expect(config.programRules.map(\.name) == ["claude", "Claude"])
    }

    @Test("removing affects only the exact name and an absent name changes nothing")
    func removingExactName() {
        let config = SwitcherConfig.default
            .setting(ProgramRule(name: "claude", target: .keepAsIs))
            .setting(ProgramRule(name: "Claude", target: .slot(.chinese)))
        #expect(config.removingProgramRule(for: "claude").programRules.map(\.name) == ["Claude"])
        #expect(config.removingProgramRule(for: "missing") == config)
        #expect(config.programRule(for: "CLAUDE") == nil)
    }

    @Test("pausing and resuming preserve the rules and other settings")
    func settingPaused() {
        let config = SwitcherConfig.default.setting(ProgramRule(name: "claude", target: .slot(.chinese)))
        let paused = config.settingProgramRulesPaused(true)
        #expect(paused.programRulesPaused)
        #expect(paused.programRules == config.programRules)
        #expect(paused.settingProgramRulesPaused(false) == config)
    }
}

struct ProgramNameTests {
    @Test("names are trimmed without changing case")
    func trimsAndKeepsCase() {
        #expect(ProgramName.normalized(userInput: " \tClaude\n") == "Claude")
        #expect(ProgramName.normalized(userInput: "zsh") == "zsh")
    }

    @Test("empty names, paths and embedded whitespace are refused", arguments: [
        "", " \t\n", "/bin/zsh", "bin/zsh", "claude --help", "cl\taude", "cl\naude", "cl\u{00A0}aude",
    ])
    func rejectsInvalidNames(input: String) {
        #expect(ProgramName.normalized(userInput: input) == nil)
    }

    @Test("the limit is 64 characters after trimming")
    func lengthBoundary() {
        #expect(ProgramName.normalized(userInput: " \(String(repeating: "a", count: 64)) ") != nil)
        #expect(ProgramName.normalized(userInput: String(repeating: "a", count: 65)) == nil)
    }
}

struct ProgramRuleMatcherTests {
    @Test("program matching is exact and case sensitive")
    func exactCaseSensitiveMatch() {
        let rule = ProgramRule(name: "claude", target: .slot(.chinese))
        #expect(ProgramRuleMatcher.match(name: "claude", in: [rule]) == rule)
        #expect(ProgramRuleMatcher.match(name: "Claude", in: [rule]) == nil)
        #expect(ProgramRuleMatcher.match(name: "claude-code", in: [rule]) == nil)
        #expect(ProgramRuleMatcher.match(name: "/bin/claude", in: [rule]) == nil)
        #expect(ProgramRuleMatcher.match(name: "claude", in: []) == nil)
    }
}

struct ProgramActivationSettingsTests {
    @Test("config supplies program rules and pause state")
    func settingsFromConfig() {
        let config = SwitcherConfig.default
            .setting(ProgramRule(name: "claude", target: .slot(.chinese)))
            .settingProgramRulesPaused(true)
        let settings = AppActivationSettings(config: config)
        #expect(settings.programRules == config.programRules)
        #expect(settings.programRulesPaused)
        #expect(settings.programTargets == ["claude": .slot(.chinese)])
    }

    @Test("program targets keep the later duplicate")
    func laterTargetWins() {
        let settings = AppActivationSettings(programRules: [
            ProgramRule(name: "claude", target: .keepAsIs),
            ProgramRule(name: "claude", target: .slot(.chinese)),
        ])
        #expect(settings.programTargets == ["claude": .slot(.chinese)])
    }

    @Test("watching requires rules, not paused, and an app that is not Keep as is")
    func watchingConditions() {
        var settings = AppActivationSettings()
        #expect(!settings.watchesPrograms(in: "terminal"))
        settings.programRules = [ProgramRule(name: "claude", target: .slot(.chinese))]
        #expect(settings.watchesPrograms(in: "terminal"))
        settings.programRulesPaused = true
        #expect(!settings.watchesPrograms(in: "terminal"))
        settings.programRulesPaused = false
        settings.rules["terminal"] = AppRule(appID: "terminal", target: .keepAsIs)
        #expect(!settings.watchesPrograms(in: "terminal"))
        #expect(settings.watchesPrograms(in: "other-terminal"))
        settings.rules["terminal"] = AppRule(appID: "terminal", target: .slot(.english))
        #expect(settings.watchesPrograms(in: "terminal"))
    }

    @Test("active program rules alone enable activation tracking")
    func isAnythingOnRespectsPause() {
        var settings = AppActivationSettings()
        #expect(!settings.isAnythingOn)
        settings.programRules = [ProgramRule(name: "vim", target: .keepAsIs)]
        #expect(settings.isAnythingOn)
        settings.programRulesPaused = true
        #expect(!settings.isAnythingOn)
        settings.remembersPerApp = true
        #expect(settings.isAnythingOn)
    }

    @Test("program targets distinguish no rule, Keep as is, a deleted slot and a live slot")
    func resolvesTargets() {
        let settings = AppActivationSettings(slotIDs: [.chinese], programRules: [
            ProgramRule(name: "claude", target: .slot(.chinese)),
            ProgramRule(name: "zsh", target: .slot(.english)),
            ProgramRule(name: "vim", target: .keepAsIs),
        ])
        #expect(settings.programTarget(forRule: "claude") == .slot(.chinese))
        #expect(settings.programTarget(forRule: "zsh") == AppActivationTarget.none)
        #expect(settings.programTarget(forRule: "vim") == AppActivationTarget.none)
        #expect(settings.programTarget(forRule: "Claude") == nil)
        #expect(settings.programTarget(forRule: "unknown") == nil)
    }

    @Test("paused rules do not resolve to a program target")
    func pausedHasNoTarget() {
        let settings = AppActivationSettings(slotIDs: [.chinese], programRules: [
            ProgramRule(name: "claude", target: .slot(.chinese)),
        ], programRulesPaused: true)
        #expect(settings.programTarget(forRule: "claude") == nil)
    }
}
