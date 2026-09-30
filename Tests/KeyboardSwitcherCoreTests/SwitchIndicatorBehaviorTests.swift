import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct SwitchIndicatorBehaviorTests {
    private let abc = "com.apple.keylayout.ABC"
    private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
    private let kotoeri = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

    private func config(_ change: (inout SwitchIndicatorBehavior) -> Void = { _ in }) -> SwitcherConfig {
        var config = SwitcherConfig.default
        change(&config.switchIndicatorBehavior)
        return config
    }

    // MARK: - Config

    @Test("a config written before the key existed reads the defaults")
    func missingKeyDecodesDefaults() throws {
        let json = Data(#"{"version": 3, "bindings": [], "inputSources": {}}"#.utf8)

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: json)

        #expect(decoded.switchIndicatorBehavior == SwitchIndicatorBehavior())
        #expect(decoded.switchIndicatorBehavior.showsExternalChanges)
        #expect(!decoded.switchIndicatorBehavior.showsOnAppSwitch)
        #expect(decoded.switchIndicatorBehavior.holdSeconds == nil)
    }

    @Test("the behavior survives a save and reload")
    func roundTrip() throws {
        let original = config {
            $0 = SwitchIndicatorBehavior(showsExternalChanges: false, showsOnAppSwitch: true,
                                         hiddenAppIDs: ["com.apple.Terminal"], holdSeconds: 2)
        }

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(original))

        #expect(decoded.switchIndicatorBehavior == original.switchIndicatorBehavior)
    }

    @Test("a partial behavior object fills the missing fields with defaults")
    func partialObject() throws {
        let json = Data(#"{"showsOnAppSwitch": true}"#.utf8)

        let decoded = try JSONDecoder().decode(SwitchIndicatorBehavior.self, from: json)

        #expect(decoded == SwitchIndicatorBehavior(showsOnAppSwitch: true))
    }

    @Test("hold is clamped, and a non-finite hold means Automatic")
    func holdClamp() {
        #expect(SwitchIndicatorBehavior(holdSeconds: 0.01).holdSeconds == SwitchIndicatorBehavior.minHoldSeconds)
        #expect(SwitchIndicatorBehavior(holdSeconds: 99).holdSeconds == SwitchIndicatorBehavior.maxHoldSeconds)
        #expect(SwitchIndicatorBehavior(holdSeconds: .nan).holdSeconds == nil)
        #expect(SwitchIndicatorBehavior().hold(automatic: 0.75) == 0.75)
        #expect(SwitchIndicatorBehavior(holdSeconds: 2).hold(automatic: 0.75) == 2)
    }

    @Test("hiding an app twice keeps one entry, and showing removes it")
    func hideAndShow() {
        let hidden = SwitchIndicatorBehavior().hiding("com.apple.Terminal").hiding("com.apple.Terminal")

        #expect(hidden.hiddenAppIDs == ["com.apple.Terminal"])
        #expect(hidden.isHidden(in: "com.apple.Terminal"))
        #expect(!hidden.isHidden(in: nil))
        #expect(hidden.showing("com.apple.Terminal").hiddenAppIDs.isEmpty)
    }

    // MARK: - External changes

    @Test("a change made outside CmdIME shows a bubble")
    func externalChangeShows() {
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        let shown1 = tracker.sourceChanged(to: pinyin, isOwnSwitchPending: false, frontmostAppID: "a", config: config())

        #expect(shown1)
        #expect(tracker.lastKnownSourceID == pinyin)
    }

    @Test("steps of CmdIME's own switch in flight (a Kana prelude, a retry) show nothing")
    func pendingOwnSwitchIsSilent() {
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        let shown2 = tracker.sourceChanged(to: "com.apple.inputmethod.Kotoeri.RomajiTyping.Roman",
                                       isOwnSwitchPending: true, frontmostAppID: "a", config: config())

        #expect(!shown2)
    }

    @Test("the system's notice of CmdIME's own confirmed switch does not show a second bubble")
    func lateNoticeOfOwnSwitchIsSilent() {
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        let shown3 = tracker.ownSwitchConfirmed(sourceID: kotoeri, reported: true, frontmostAppID: "a", config: config())

        #expect(shown3)
        let shown4 = tracker.sourceChanged(to: kotoeri, isOwnSwitchPending: false, frontmostAppID: "a", config: config())
        #expect(!shown4)
    }

    @Test("a silent own switch (App Memory putting a source back) shows nothing, now or later")
    func silentOwnSwitch() {
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        let shown5 = tracker.ownSwitchConfirmed(sourceID: pinyin, reported: false, frontmostAppID: "a", config: config())

        #expect(!shown5)
        let shown6 = tracker.sourceChanged(to: pinyin, isOwnSwitchPending: false, frontmostAppID: "a", config: config())
        #expect(!shown6)
    }

    @Test("a notice that names the source already known shows nothing")
    func unchangedSourceIsSilent() {
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        let shown7 = tracker.sourceChanged(to: abc, isOwnSwitchPending: false, frontmostAppID: "a", config: config())

        #expect(!shown7)
        let shown8 = tracker.sourceChanged(to: nil, isOwnSwitchPending: false, frontmostAppID: "a", config: config())
        #expect(!shown8)
    }

    @Test("external bubbles follow their setting and the master switch")
    func externalChangeSettings() {
        var off = IndicatorOccasionTracker(currentSourceID: abc)
        var masterOff = IndicatorOccasionTracker(currentSourceID: abc)
        var masterOffConfig = config { $0.showsExternalChanges = true }
        masterOffConfig.showSwitchIndicator = false

        let shown9 = off.sourceChanged(to: pinyin, isOwnSwitchPending: false, frontmostAppID: "a",
                                   config: config { $0.showsExternalChanges = false })

        #expect(!shown9)
        let shown10 = masterOff.sourceChanged(to: pinyin, isOwnSwitchPending: false, frontmostAppID: "a", config: masterOffConfig)
        #expect(!shown10)
        #expect(off.lastKnownSourceID == pinyin)
    }

    // MARK: - Hidden apps

    @Test("no bubble of any kind shows in a hidden app")
    func hiddenAppSuppressesEverything() {
        let hidden = config { $0.hiddenAppIDs = ["com.microsoft.rdc.macos"]; $0.showsOnAppSwitch = true }
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        let shown11 = tracker.ownSwitchConfirmed(sourceID: pinyin, reported: true, frontmostAppID: "com.microsoft.rdc.macos", config: hidden)

        #expect(!shown11)
        let shown12 = tracker.sourceChanged(to: abc, isOwnSwitchPending: false, frontmostAppID: "com.microsoft.rdc.macos", config: hidden)
        #expect(!shown12)
        tracker.appActivated("com.microsoft.rdc.macos")
        let shown13 = tracker.appSwitchSettled(appID: "com.microsoft.rdc.macos", currentSourceID: pinyin, config: hidden)
        #expect(!shown13)
        let shown14 = tracker.ownSwitchConfirmed(sourceID: kotoeri, reported: true, frontmostAppID: "other", config: hidden)
        #expect(shown14)
    }

    // MARK: - App switch

    @Test("switching apps into a different source shows a bubble after it settles")
    func appSwitchIntoDifferentSource() {
        let onSwitch = config { $0.showsOnAppSwitch = true; $0.showsExternalChanges = false }
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        tracker.appActivated("notes")
        _ = tracker.sourceChanged(to: pinyin, isOwnSwitchPending: false, frontmostAppID: "notes", config: onSwitch)

        let shown15 = tracker.appSwitchSettled(appID: "notes", currentSourceID: pinyin, config: onSwitch)

        #expect(shown15)
    }

    @Test("switching apps with the source unchanged shows nothing")
    func appSwitchSameSource() {
        let onSwitch = config { $0.showsOnAppSwitch = true }
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        tracker.appActivated("notes")

        let shown16 = tracker.appSwitchSettled(appID: "notes", currentSourceID: abc, config: onSwitch)

        #expect(!shown16)
    }

    @Test("an app switch whose change already showed a bubble shows no second one")
    func appSwitchAfterRestoreBubble() {
        let onSwitch = config { $0.showsOnAppSwitch = true }
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        tracker.appActivated("notes")
        let shown17 = tracker.ownSwitchConfirmed(sourceID: pinyin, reported: true, frontmostAppID: "notes", config: onSwitch)
        #expect(shown17)

        let shown18 = tracker.appSwitchSettled(appID: "notes", currentSourceID: pinyin, config: onSwitch)

        #expect(!shown18)
    }

    @Test("a newer activation retires the older one's settle")
    func newerActivationWins() {
        let onSwitch = config { $0.showsOnAppSwitch = true }
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        tracker.appActivated("notes")
        tracker.appActivated("mail")

        let shown19 = tracker.appSwitchSettled(appID: "notes", currentSourceID: pinyin, config: onSwitch)

        #expect(!shown19)
        let shown20 = tracker.appSwitchSettled(appID: "mail", currentSourceID: pinyin, config: onSwitch)
        #expect(shown20)
    }

    @Test("app-switch bubbles are off by default")
    func appSwitchOffByDefault() {
        var tracker = IndicatorOccasionTracker(currentSourceID: abc)

        tracker.appActivated("notes")

        let shown21 = tracker.appSwitchSettled(appID: "notes", currentSourceID: pinyin, config: config())

        #expect(!shown21)
        #expect(tracker.lastKnownSourceID == pinyin)
    }
}
