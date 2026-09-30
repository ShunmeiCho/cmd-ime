import Foundation
import Testing
@testable import KeyboardSwitcherCore

private let own = "com.shunmei.cmd-ime"
private let terminal = "com.apple.Terminal"
private let wechat = "com.tencent.xinWeChat"
private let rdp = "com.microsoft.rdc.macos"
private let abc = "com.apple.keylayout.ABC"
private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
private let chineseSlot = InputRole.chinese
private let englishSlot = InputRole.english
private let quiet = AppMemoryContext()
private let secure = AppMemoryContext(isSecureInputInFrontmostApp: true)
private let slots: Set<InputRole> = [.english, .chinese]

private func slotOf(_ sourceID: String) -> InputRole? {
    switch sourceID {
    case abc: englishSlot
    case pinyin: chineseSlot
    default: nil
    }
}

struct AppActivationSettingsTests {
    @Test("an app rule beats a remembered source")
    func ruleBeatsMemory() {
        let settings = AppActivationSettings(
            remembersPerApp: true,
            rules: [AppRule(appID: terminal, target: .slot(englishSlot))],
            slotIDs: slots
        )

        #expect(settings.target(for: terminal, rememberedSourceID: pinyin) == .slot(englishSlot))
        #expect(!settings.usesMemory(for: terminal))
    }

    @Test("remember instead restores memory and uses the rule only on a first visit, even with App Memory off")
    func rememberInsteadOverride() {
        let settings = AppActivationSettings(
            remembersPerApp: false,
            rules: [AppRule(appID: wechat, target: .slot(chineseSlot), rememberInstead: true)],
            slotIDs: slots
        )

        #expect(settings.usesMemory(for: wechat))
        #expect(settings.target(for: wechat, rememberedSourceID: abc) == .source(abc))
        #expect(settings.target(for: wechat, rememberedSourceID: nil) == .slot(chineseSlot))
    }

    @Test("keep as is selects nothing and keeps the app out of memory")
    func keepAsIs() {
        let settings = AppActivationSettings(
            remembersPerApp: true,
            rules: [AppRule(appID: rdp, target: .keepAsIs, rememberInstead: true)],
            defaultSlot: englishSlot,
            slotIDs: slots
        )

        #expect(settings.target(for: rdp, rememberedSourceID: pinyin) == .none)
        #expect(!settings.usesMemory(for: rdp))
    }

    @Test("a rule or default naming a deleted slot does nothing")
    func deletedSlotIsInert() {
        let gone = InputRole(rawValue: "korean")
        let settings = AppActivationSettings(
            rules: [AppRule(appID: terminal, target: .slot(gone))],
            defaultSlot: gone,
            slotIDs: slots
        )

        #expect(settings.target(for: terminal, rememberedSourceID: nil) == .none)
        #expect(settings.target(for: wechat, rememberedSourceID: nil) == .none)
    }

    @Test("the default slot covers an app with no rule and nothing remembered")
    func defaultSlot() {
        let settings = AppActivationSettings(remembersPerApp: true, defaultSlot: englishSlot, slotIDs: slots)

        #expect(settings.target(for: wechat, rememberedSourceID: nil) == .slot(englishSlot))
        #expect(settings.target(for: wechat, rememberedSourceID: pinyin) == .source(pinyin))
    }

    @Test("nothing on means nothing needs to follow apps")
    func anythingOn() {
        #expect(!AppActivationSettings().isAnythingOn)
        #expect(AppActivationSettings(restoresAfterPasswordField: true).isAnythingOn)
        #expect(AppActivationSettings(rules: [AppRule(appID: rdp, target: .keepAsIs)]).isAnythingOn)
    }
}

struct AppRuleConfigTests {
    @Test("a config from before App Rules reads no rules, no default, and password put-back on")
    func missingKeysDecodeDefaults() throws {
        let json = Data(#"{"version": 3, "bindings": [], "inputSources": {}}"#.utf8)

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: json)

        #expect(config.appRules.isEmpty)
        #expect(config.appDefaultSlot == nil)
        #expect(config.restoreAfterPasswordField)
    }

    @Test("rules, the default slot and the password setting survive a save and reload")
    func roundTrip() throws {
        var config = SwitcherConfig.default
        config.appRules = [
            AppRule(appID: terminal, name: "Terminal", target: .slot(englishSlot)),
            AppRule(appID: rdp, target: .keepAsIs),
            AppRule(appID: wechat, target: .slot(chineseSlot), rememberInstead: true),
        ]
        config.appDefaultSlot = englishSlot
        config.restoreAfterPasswordField = false

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.appRules == config.appRules)
        #expect(decoded.appDefaultSlot == englishSlot)
        #expect(!decoded.restoreAfterPasswordField)
    }

    @Test("a rule this build cannot read is dropped, not the whole file")
    func unreadableRuleIsDropped() throws {
        let json = Data(#"""
        {"version": 3, "bindings": [], "inputSources": {},
         "appRules": [{"app": "a", "kind": "website"}, {"app": "b", "kind": "keepAsIs"}]}
        """#.utf8)

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: json)

        #expect(config.appRules == [AppRule(appID: "b", target: .keepAsIs)])
    }

    @Test("setting a rule for an app that has one replaces it in place")
    func settingReplaces() {
        var config = SwitcherConfig.default
        config.appRules = [AppRule(appID: terminal, target: .keepAsIs), AppRule(appID: rdp, target: .keepAsIs)]

        let next = config.setting(AppRule(appID: terminal, target: .slot(englishSlot)))

        #expect(next.appRules.map(\.appID) == [terminal, rdp])
        #expect(next.appRule(for: terminal)?.target == .slot(englishSlot))
        #expect(next.removingAppRule(for: terminal).appRules.map(\.appID) == [rdp])
    }
}

struct AppRuleTrackerTests {
    private func tracker(_ settings: AppActivationSettings) -> AppMemoryTracker {
        AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: settings)
    }

    @Test("an app with a slot rule gets its slot unless it arrives in it")
    func ruleSelectsSlot() {
        var tracker = tracker(AppActivationSettings(
            rules: [AppRule(appID: terminal, target: .slot(englishSlot))], slotIDs: slots
        ))

        #expect(tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet, slotOfSource: slotOf) == .selectSlot(englishSlot))
        _ = tracker.appActivated(wechat, currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        #expect(tracker.appActivated(terminal, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("apps whose rule does not remember are never recorded")
    func ruledAppsAreNotRecorded() {
        var tracker = tracker(AppActivationSettings(
            remembersPerApp: true,
            rules: [AppRule(appID: rdp, target: .keepAsIs)],
            slotIDs: slots
        ))
        _ = tracker.appActivated(rdp, currentSourceID: pinyin, context: quiet)

        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: abc, context: quiet)

        #expect(tracker.rememberedSourceID(for: rdp) == nil)
        #expect(tracker.rememberedSources == [wechat: pinyin])
    }

    @Test("adding a rule drops that app's memory, and forget removes one app")
    func settingsAndForget() {
        var tracker = tracker(AppActivationSettings(remembersPerApp: true, slotIDs: slots))
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(rdp, currentSourceID: abc, context: quiet)

        tracker.update(settings: AppActivationSettings(
            remembersPerApp: true, rules: [AppRule(appID: wechat, target: .keepAsIs)], slotIDs: slots
        ))
        tracker.forget(terminal)

        #expect(tracker.rememberedSources.isEmpty)
    }

    @Test("a rule switch still pending when its app is left is put back")
    func pendingRuleSwitchIsPutBack() {
        var tracker = tracker(AppActivationSettings(
            rules: [AppRule(appID: terminal, target: .slot(englishSlot))], slotIDs: slots
        ))
        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)

        let pending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)
        #expect(tracker.appActivated(wechat, currentSourceID: pinyin, context: pending, slotOfSource: slotOf) == .putBack(sourceID: pinyin))
    }
}

struct PasswordFieldPutBackTests {
    private func trackerInWeChatTypingPinyin(putBack: Bool = true) -> AppMemoryTracker {
        var tracker = AppMemoryTracker(
            ownAppID: own,
            frontmostAppID: wechat,
            settings: AppActivationSettings(restoresAfterPasswordField: putBack)
        )
        tracker.sourceChanged(to: pinyin, context: quiet)
        return tracker
    }

    @Test("after a password field forced ABC, the source it replaced comes back")
    func putsBackTheReplacedSource() {
        var tracker = trackerInWeChatTypingPinyin()

        tracker.sourceChanged(to: abc, context: secure)
        tracker.sourceChanged(to: abc, context: secure)

        #expect(tracker.isAwaitingSecureInputEnd)
        #expect(tracker.secureInputEnded(currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
        #expect(!tracker.isAwaitingSecureInputEnd)
    }

    @Test("a source the user chose after the field is left alone")
    func userChoiceWins() {
        var tracker = trackerInWeChatTypingPinyin()
        tracker.sourceChanged(to: abc, context: secure)

        #expect(tracker.secureInputEnded(currentSourceID: "com.apple.keylayout.US", context: quiet) == .none)
    }

    @Test("with the setting off nothing waits and nothing comes back")
    func settingOff() {
        var tracker = trackerInWeChatTypingPinyin(putBack: false)
        tracker.sourceChanged(to: abc, context: secure)

        #expect(!tracker.isAwaitingSecureInputEnd)
        #expect(tracker.secureInputEnded(currentSourceID: abc, context: quiet) == .none)
    }

    @Test("switching apps drops the put-back")
    func appSwitchDrops() {
        var tracker = trackerInWeChatTypingPinyin()
        tracker.sourceChanged(to: abc, context: secure)

        _ = tracker.appActivated(terminal, currentSourceID: abc, context: quiet)

        #expect(!tracker.isAwaitingSecureInputEnd)
    }

    @Test("nothing waits when the source was already ASCII")
    func alreadyASCII() {
        var tracker = trackerInWeChatTypingPinyin()
        tracker.sourceChanged(to: abc, context: quiet)

        tracker.sourceChanged(to: abc, context: secure)

        #expect(!tracker.isAwaitingSecureInputEnd)
    }
}
