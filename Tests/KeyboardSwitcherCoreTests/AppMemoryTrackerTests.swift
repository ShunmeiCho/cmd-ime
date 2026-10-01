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

// MARK: - Website rules

private let chrome = "com.google.Chrome"
private let chromePID: Int32 = 501
private let jaSite = "example.jp"
private let quietSite = "bank.example"
private let slots: Set<InputRole> = [.english, .chinese, .japanese]
private func slotOf(_ sourceID: String) -> InputRole? {
    [abc: InputRole.english, pinyin: .chinese, kotoeri: .japanese][sourceID]
}

struct AppMemoryTrackerWebsiteTests {
    /// Chrome has the slot rule `chinese`; example.jp is `japanese`; bank.example is "Keep as is".
    private func makeTracker(
        remembersPerApp: Bool = false,
        chromeRule: AppRule? = AppRule(appID: chrome, target: .slot(.chinese))
    ) -> AppMemoryTracker {
        AppMemoryTracker(ownAppID: own, frontmostAppID: terminal, settings: AppActivationSettings(
            remembersPerApp: remembersPerApp,
            rules: chromeRule.map { [$0] } ?? [],
            restoresAfterPasswordField: true,
            slotIDs: slots,
            websiteRules: [WebsiteRule(domain: jaSite, target: .slot(.japanese)), WebsiteRule(domain: quietSite, target: .keepAsIs)]
        ))
    }

    /// Chrome comes to the front on ABC; its own target waits for the page.
    private func activateChrome(_ tracker: inout AppMemoryTracker, context: AppMemoryContext = quiet) -> AppMemoryTracker.Restore {
        tracker.appActivated(chrome, currentSourceID: abc, context: context, browserPID: chromePID, slotOfSource: slotOf)
    }

    private func reading(_ tracker: AppMemoryTracker, _ sequence: Int, _ context: WebsiteContext) -> WebsiteReading {
        WebsiteReading(pid: chromePID, generation: tracker.activationGeneration, sequence: sequence, context: context)
    }

    @Test("a browser with website rules waits for its page, then the page's rule decides once")
    func holdDecidesOnce() {
        var tracker = makeTracker()

        #expect(activateChrome(&tracker) == .none)
        #expect(tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.japanese))
        #expect(!tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(reading(tracker, 2, .rule(jaSite)), currentSourceID: kotoeri, context: quiet, slotOfSource: slotOf)
            == .none)
    }

    @Test("a page without a rule, an unread page or an expired wait gives the browser's own target")
    func holdFallsBackToTheBrowser() {
        for page in [WebsiteContext.noRule, .unknown] {
            var tracker = makeTracker()
            _ = activateChrome(&tracker)
            #expect(tracker.websiteRead(reading(tracker, 1, page), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
                == .selectSlot(.chinese))
        }
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        #expect(tracker.websiteHoldExpired(generation: tracker.activationGeneration, currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.chinese))
        #expect(tracker.websiteHoldExpired(generation: tracker.activationGeneration, currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .none)
    }

    @Test("a result with another pid, an older generation or an older read is dropped")
    func staleResultsAreDropped() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        let generation = tracker.activationGeneration

        let otherPID = WebsiteReading(pid: 9, generation: generation, sequence: 1, context: .rule(jaSite))
        #expect(tracker.websiteRead(otherPID, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
        #expect(tracker.isWebsiteHoldWaiting)

        _ = tracker.websiteRead(reading(tracker, 5, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        #expect(tracker.websiteRead(reading(tracker, 4, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)
            == .none)

        _ = tracker.appActivated(terminal, currentSourceID: pinyin, context: quiet)
        _ = activateChrome(&tracker)
        let old = WebsiteReading(pid: chromePID, generation: generation, sequence: 6, context: .rule(jaSite))
        #expect(tracker.websiteRead(old, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
        #expect(tracker.isWebsiteHoldWaiting)
    }

    @Test("a result for a browser that is no longer in front is dropped")
    func resultForAnAppAlreadyLeftIsDropped() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), actualFrontmostAppID: terminal,
                                    currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a trigger confirmed while waiting for the page wins, and the next read switches nothing")
    func triggerDuringTheHoldWins() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        tracker.triggerConfirmed(sourceID: pinyin, actualFrontmostAppID: chrome, context: ownPending, browserPID: chromePID)

        #expect(!tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)
            == .none)
        // The page is known now, so moving to a page without a rule gives the browser's target again.
        #expect(tracker.websiteRead(reading(tracker, 2, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.chinese))
    }

    @Test("a source chosen by hand while waiting for the page stands")
    func manualChangeDuringTheHoldStands() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        tracker.sourceChanged(to: pinyin, context: quiet)

        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)
            == .none)
    }

    @Test("a trigger in flight at activation gives no wait, and the first read after it switches nothing")
    func triggerPendingAtActivation() {
        var tracker = makeTracker()

        #expect(activateChrome(&tracker, context: ownPending) == .none)
        #expect(!tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: ownPending, slotOfSource: slotOf)
            == .none)
        #expect(tracker.websiteRead(reading(tracker, 2, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .none)
    }

    @Test("moving between pages switches only when the rule changes")
    func laterReads() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)

        #expect(tracker.websiteRead(reading(tracker, 2, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.japanese))
        // The address bar keeps the page's context.
        #expect(tracker.websiteRead(reading(tracker, 3, .unknown), currentSourceID: kotoeri, context: quiet, slotOfSource: slotOf)
            == .none)
        #expect(tracker.websiteRead(reading(tracker, 4, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .none)
        #expect(tracker.websiteRead(reading(tracker, 5, .noRule), currentSourceID: kotoeri, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.chinese))
    }

    @Test("an unread page that turns out to have no rule switches nothing after the wait expired")
    func notReadToNoRule() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteHoldExpired(generation: tracker.activationGeneration, currentSourceID: abc, context: quiet, slotOfSource: slotOf)

        #expect(tracker.websiteRead(reading(tracker, 1, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a website switch is not remembered for the browser, even after the page left the rule")
    func websiteSwitchIsNotRemembered() {
        var tracker = makeTracker(remembersPerApp: true, chromeRule: nil)
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        _ = tracker.websiteRead(reading(tracker, 2, .noRule), currentSourceID: abc, context: ownPending, slotOfSource: slotOf)

        tracker.switchConfirmed(sourceID: kotoeri, context: quiet)

        #expect(tracker.rememberedSourceID(for: chrome) == nil)
    }

    @Test("on a ruled page neither a manual change nor a trigger is remembered; on an unruled page both are")
    func rememberPathsFollowThePage() {
        var tracker = makeTracker(remembersPerApp: true, chromeRule: nil)
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        tracker.switchConfirmed(sourceID: kotoeri, context: quiet)

        tracker.sourceChanged(to: pinyin, context: quiet)
        tracker.triggerConfirmed(sourceID: abc, actualFrontmostAppID: chrome, context: ownPending, browserPID: chromePID)
        #expect(tracker.rememberedSourceID(for: chrome) == nil)

        _ = tracker.websiteRead(reading(tracker, 2, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        tracker.sourceChanged(to: pinyin, context: quiet)
        #expect(tracker.rememberedSourceID(for: chrome) == pinyin)
    }

    @Test("leaving the browser from a ruled page leaves its memory as it was")
    func leavingFromARuledPage() {
        var tracker = makeTracker(remembersPerApp: true, chromeRule: nil)
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.websiteRead(reading(tracker, 2, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)
        tracker.switchConfirmed(sourceID: kotoeri, context: quiet)

        _ = tracker.appActivated(terminal, currentSourceID: kotoeri, context: quiet)

        #expect(tracker.rememberedSourceID(for: chrome) == pinyin)
    }

    @Test("a website switch still on its way when the browser is left is put back")
    func pendingWebsiteSwitchIsPutBack() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)

        #expect(tracker.appActivated(terminal, currentSourceID: kotoeri, context: restorePending) == .putBack(sourceID: abc))
    }

    @Test("a Keep as is site switches nothing and gets no Password Put-back")
    func keepAsIsSite() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        #expect(tracker.websiteRead(reading(tracker, 1, .rule(quietSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .none)
        tracker.sourceChanged(to: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: secure)
        #expect(!tracker.isAwaitingSecureInputEnd)
    }

    @Test("a Keep as is browser is never watched")
    func keepAsIsBrowserIsNotWatched() {
        var tracker = makeTracker(chromeRule: AppRule(appID: chrome, target: .keepAsIs))

        #expect(activateChrome(&tracker) == .none)
        #expect(tracker.websiteWatch == nil)
        #expect(!tracker.isWebsiteHoldWaiting)
    }

    @Test("without website rules a browser behaves like any app")
    func noRulesNoHold() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: terminal, settings: AppActivationSettings(
            rules: [AppRule(appID: chrome, target: .slot(.chinese))], slotIDs: slots
        ))

        #expect(activateChrome(&tracker) == .selectSlot(.chinese))
        #expect(tracker.websiteWatch == nil)
    }

    @Test("macOS repeating the current source while waiting for the page is not a choice")
    func repeatedSourceDoesNotCancelTheHold() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.japanese))
    }

    @Test("a wait that expires after the user moved on selects nothing in the other app")
    func expiryForAnAppAlreadyLeft() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        #expect(tracker.websiteHoldExpired(generation: tracker.activationGeneration, actualFrontmostAppID: terminal,
                                           currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
        #expect(!tracker.isWebsiteHoldWaiting)
    }

    @Test("the source put back after a second website switch is the one in place before that switch")
    func putBackUsesTheLatestSource() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        tracker.switchConfirmed(sourceID: kotoeri, context: quiet)
        _ = tracker.websiteRead(reading(tracker, 2, .noRule), currentSourceID: kotoeri, context: quiet, slotOfSource: slotOf)
        tracker.switchConfirmed(sourceID: pinyin, context: quiet)

        _ = tracker.websiteRead(reading(tracker, 3, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)

        #expect(tracker.appActivated(terminal, currentSourceID: kotoeri, context: restorePending) == .putBack(sourceID: pinyin))
    }

    @Test("a browser already in front when following starts is read, without a wait")
    func browserInFrontAtStart() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: chrome, frontBrowserPID: chromePID, settings: AppActivationSettings(
            slotIDs: slots, websiteRules: [WebsiteRule(domain: jaSite, target: .slot(.japanese))]
        ))

        #expect(tracker.websiteWatch?.pid == chromePID)
        #expect(!tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.japanese))
    }

    @Test("a trigger confirmed after the wait ended, with the page still unread, still wins")
    func triggerConfirmedAfterTheWaitEnded() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        #expect(tracker.websiteHoldExpired(generation: tracker.activationGeneration, currentSourceID: abc,
                                           context: ownPending, slotOfSource: slotOf) == .none)

        tracker.triggerConfirmed(sourceID: pinyin, actualFrontmostAppID: chrome, context: ownPending, browserPID: chromePID)

        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: pinyin, context: quiet, slotOfSource: slotOf)
            == .none)
    }

    @Test("a website switch still on its way is put back when the next page needs nothing")
    func pendingWebsiteSwitchIsRetiredByTheNextPage() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)

        #expect(tracker.websiteRead(reading(tracker, 2, .rule(quietSite)), currentSourceID: kotoeri,
                                    context: restorePending, slotOfSource: slotOf) == .putBack(sourceID: abc))
    }

    @Test("a read matched against rules since replaced is dropped")
    func readFromOldRulesIsDropped() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        let old = reading(tracker, 1, .rule(jaSite))

        var settings = tracker.settings
        settings.websiteRules.append(WebsiteRule(domain: "sub.example.jp", target: .keepAsIs))
        tracker.update(settings: settings)

        #expect(tracker.websiteRead(old, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
        #expect(tracker.websiteRead(reading(tracker, 2, .rule("sub.example.jp")), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
            == .none)
    }

    @Test("a source a password field replaced is not put back once the page is a Keep as is site")
    func noPutBackAfterMovingToAKeepAsIsSite() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)
        tracker.switchConfirmed(sourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: secure)
        #expect(tracker.isAwaitingSecureInputEnd)

        _ = tracker.websiteRead(reading(tracker, 2, .rule(quietSite)), currentSourceID: abc, context: secure, slotOfSource: slotOf)

        #expect(tracker.secureInputEnded(currentSourceID: abc, context: quiet) == .none)
    }

    @Test("a new tracker counts on from the generation it is given")
    func generationBase() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: terminal, activationGeneration: 7)

        _ = tracker.appActivated(chrome, currentSourceID: abc, context: quiet)

        #expect(tracker.activationGeneration == 8)
    }

    @Test("another process of the same browser is an activation of its own: a new wait, old results dropped")
    func sameBrowserOtherProcess() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        let first = reading(tracker, 1, .rule(jaSite))
        let otherPID: Int32 = 777

        #expect(tracker.appActivated(chrome, currentSourceID: abc, context: quiet, browserPID: otherPID, slotOfSource: slotOf) == .none)

        #expect(tracker.websiteWatch?.pid == otherPID)
        #expect(tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(first, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a website switch on its way is put back when another process of the browser comes forward")
    func pendingSwitchIsRetiredForAnotherProcess() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), currentSourceID: abc, context: quiet, slotOfSource: slotOf)

        #expect(tracker.appActivated(chrome, currentSourceID: kotoeri, context: restorePending, browserPID: 777, slotOfSource: slotOf)
            == .putBack(sourceID: abc))
    }

    @Test("a trigger confirmed in another process of the browser registers it, and the late notice changes nothing")
    func triggerInAnotherProcess() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)
        _ = tracker.websiteRead(reading(tracker, 1, .noRule), currentSourceID: abc, context: quiet, slotOfSource: slotOf)

        tracker.triggerConfirmed(sourceID: abc, actualFrontmostAppID: chrome, context: ownPending, browserPID: 777)
        #expect(tracker.appActivated(chrome, currentSourceID: abc, context: quiet, browserPID: 777, slotOfSource: slotOf) == .none)

        #expect(!tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteRead(WebsiteReading(pid: 777, generation: tracker.activationGeneration, sequence: 2, context: .rule(jaSite)),
                                    currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a wait that expires after another process of the browser came forward selects nothing")
    func expiryForAnotherProcess() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        #expect(tracker.websiteHoldExpired(generation: tracker.activationGeneration, actualFrontmostAppID: chrome, actualBrowserPID: 777,
                                           currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a read for a browser process that is not the one in front is dropped")
    func readForAnotherProcessInFront() {
        var tracker = makeTracker()
        _ = activateChrome(&tracker)

        #expect(tracker.websiteRead(reading(tracker, 1, .rule(jaSite)), actualFrontmostAppID: chrome, actualBrowserPID: 777,
                                    currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
        #expect(tracker.isWebsiteHoldWaiting)
    }
}
