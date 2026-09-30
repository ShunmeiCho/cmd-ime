import Testing
@testable import KeyboardSwitcherCore

private let own = "com.shunmei.cmd-ime"
private let terminal = "com.apple.Terminal"
private let wechat = "com.tencent.xinWeChat"
private let safari = "com.apple.Safari"
private let abc = "com.apple.keylayout.ABC"
private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
private let kotoeri = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
private let quiet = AppMemoryContext()
private let ownPending = AppMemoryContext(isOwnSwitchPending: true)
private let restorePending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)
private let secure = AppMemoryContext(isSecureInputInFrontmostApp: true)

struct AppMemoryTrackerTests {
    @Test("returning to an app restores the source last used there")
    func restoresOnReturn() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        #expect(tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet) == .none)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
    }

    @Test("an app seen for the first time is left as it is")
    func firstVisitKeepsSource() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)

        #expect(tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet) == .none)
    }

    @Test("no selection when the remembered source is already current")
    func noSelectWhenAlreadyCurrent() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: pinyin, context: quiet) == .none)
    }

    @Test("leaving an app remembers the current source even without a change notification")
    func activationSnapshotsTheAppBeingLeft() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)

        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet)

        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("changes while CmdIME's own switch is pending are not remembered")
    func pendingOwnSwitchIsIgnored() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        tracker.sourceChanged(to: kotoeri, context: ownPending)

        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("leaving an app while CmdIME's own switch is pending keeps its memory")
    func pendingOwnSwitchIsNotSnapshotted() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        _ = tracker.appActivated(terminal, currentSourceID: kotoeri, context: ownPending)

        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("a confirmed switch is remembered for the app in front")
    func confirmedSwitchIsRemembered() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)

        tracker.switchConfirmed(sourceID: pinyin, context: quiet)

        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("an app holding secure input is neither remembered nor restored")
    func secureInputAppIsNeitherRecordedNorRestored() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: safari)
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.appActivated(safari, currentSourceID: abc, context: secure) == .none)
        tracker.sourceChanged(to: abc, context: secure)
        #expect(tracker.rememberedSourceID(for: safari) == pinyin)
    }

    @Test("the source forced by a password field is not remembered when the app is left later")
    func forcedSourceIsNotSnapshottedAfterSecureInputEnds() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: safari)
        tracker.sourceChanged(to: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: secure)

        // The password field lost focus, secure input ended, macOS repeated the current source.
        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: abc, context: quiet)

        #expect(tracker.rememberedSourceID(for: safari) == pinyin)
    }

    @Test("a real change after a password field replaces the forced source")
    func changeAfterForcedSourceIsRemembered() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: safari)
        tracker.sourceChanged(to: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: secure)

        tracker.sourceChanged(to: kotoeri, context: quiet)

        #expect(tracker.rememberedSourceID(for: safari) == kotoeri)
    }

    @Test("arriving at an app that already holds secure input does not make the forced source its memory")
    func forcedArrivalIsNotSnapshotted() {
        let passwords = "com.1password.1password"
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: safari)
        tracker.sourceChanged(to: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: secure)
        _ = tracker.appActivated(passwords, currentSourceID: abc, context: quiet)

        // Back in the browser with the password field still focused, then on to another app.
        _ = tracker.appActivated(safari, currentSourceID: abc, context: secure)
        _ = tracker.appActivated(terminal, currentSourceID: abc, context: quiet)

        #expect(tracker.rememberedSourceID(for: safari) == pinyin)
    }

    @Test("a source forced while CmdIME's own restore is pending is still marked as forced")
    func forcedDuringPendingRestoreIsMarked() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: safari)
        tracker.sourceChanged(to: pinyin, context: quiet)

        tracker.sourceChanged(to: abc, context: AppMemoryContext(isOwnSwitchPending: true, isSecureInputInFrontmostApp: true))
        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: abc, context: quiet)

        #expect(tracker.rememberedSourceID(for: safari) == pinyin)
    }

    @Test("a confirmed switch is not remembered for an app holding secure input")
    func confirmedSwitchUnderSecureInputIsNotRemembered() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: safari)
        tracker.sourceChanged(to: pinyin, context: quiet)

        tracker.switchConfirmed(sourceID: abc, context: secure)

        #expect(tracker.rememberedSourceID(for: safari) == pinyin)
    }

    @Test("CmdIME's own settings window is never remembered or restored")
    func ownAppIsSkipped() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        #expect(tracker.appActivated(own, currentSourceID: pinyin, context: quiet) == .none)
        tracker.sourceChanged(to: abc, context: quiet)
        tracker.switchConfirmed(sourceID: abc, context: quiet)

        #expect(tracker.rememberedSourceID(for: own) == nil)
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
    }

    @Test("a system agent that comes to the front is not remembered and a change there stays with the app underneath")
    func nonRegularAppIsIgnored() {
        let notificationCenter = "com.apple.UserNotificationCenter"
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        #expect(tracker.appActivated(notificationCenter, isRegularApp: false, currentSourceID: pinyin, context: quiet) == .none)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.frontmostAppID == wechat)
        #expect(tracker.rememberedSourceID(for: notificationCenter) == nil)
        #expect(tracker.rememberedSourceID(for: wechat) == abc)
    }

    @Test("CmdIME counts as the app in front even while it is not a regular app")
    func ownAppCountsWhateverItsPolicy() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        _ = tracker.appActivated(own, isRegularApp: false, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.frontmostAppID == own)
        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("reactivating the app already in front changes nothing")
    func sameAppActivationIsIgnored() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .none)
        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("a restore still on its way when its app is left is put back for an app with no memory")
    func pendingRestoreIsPutBackForAnAppWithoutMemory() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: kotoeri, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: kotoeri))

        #expect(tracker.appActivated(safari, currentSourceID: abc, context: restorePending) == .putBack(sourceID: abc))
    }

    @Test("a restore still on its way gives way to the next app's own memory")
    func pendingRestoreGivesWayToTheNextAppsMemory() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        _ = tracker.appActivated(safari, currentSourceID: kotoeri, context: quiet)
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: kotoeri))

        #expect(tracker.appActivated(safari, currentSourceID: abc, context: restorePending) == .select(sourceID: pinyin))
    }

    @Test("while a restore is pending, the next app's memory is compared with the source the user arrived with")
    func pendingRestoreComparesWithTheArrivalSource() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        _ = tracker.appActivated(safari, currentSourceID: kotoeri, context: quiet)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: kotoeri, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: kotoeri))

        // The Kana key already brought in the restore's target before Safari came to the front.
        #expect(tracker.appActivated(safari, currentSourceID: kotoeri, context: restorePending) == .select(sourceID: kotoeri))
    }

    @Test("a pending restore is put back even when the next app holds secure input or is CmdIME")
    func pendingRestoreIsPutBackForSecureAndOwnApps() {
        let secureAndPending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true, isSecureInputInFrontmostApp: true)
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: kotoeri, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: kotoeri))

        #expect(tracker.appActivated(safari, currentSourceID: abc, context: secureAndPending) == .putBack(sourceID: abc))
        #expect(tracker.appActivated(own, currentSourceID: abc, context: restorePending) == .putBack(sourceID: abc))
    }

    @Test("a trigger in flight is never put back")
    func pendingTriggerIsNotPutBack() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        _ = tracker.appActivated(terminal, currentSourceID: kotoeri, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(wechat, currentSourceID: abc, context: quiet)

        #expect(tracker.appActivated(safari, currentSourceID: abc, context: ownPending) == .none)
    }

    @Test("forgetting clears every app")
    func forgetAllClears() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat)
        tracker.sourceChanged(to: pinyin, context: quiet)

        tracker.forgetAll()

        #expect(tracker.rememberedSourceID(for: wechat) == nil)
    }
}
