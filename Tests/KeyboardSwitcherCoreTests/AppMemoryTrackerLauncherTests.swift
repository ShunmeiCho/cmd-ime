import Testing
@testable import KeyboardSwitcherCore

private let own = "com.shunmei.cmd-ime"
private let raycast = "com.raycast.macos"
private let wechat = "com.tencent.xinWeChat"
private let ghostty = "com.mitchellh.ghostty"
private let ghosttyPID: Int32 = 701
private let chrome = "com.google.Chrome"
private let chromePID: Int32 = 802
private let abc = "com.apple.keylayout.ABC"
private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
private let quiet = AppMemoryContext()
private let ownPending = AppMemoryContext(isOwnSwitchPending: true)
private let restorePending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)
private let slots: Set<InputRole> = [.english, .chinese]
private func slotOf(_ sourceID: String) -> InputRole? {
    [abc: InputRole.english, pinyin: .chinese][sourceID]
}

/// A launcher panel is fed to the tracker as an activation of the launcher (the panel shows) and
/// then of the app underneath (the panel hides). Launchers are accessory apps; the controller
/// passes `LauncherCatalog.countsAsApp` as `isRegularApp`.
struct AppMemoryTrackerLauncherTests {
    private let launcherCounts = LauncherCatalog.countsAsApp(bundleID: raycast, isRegularApp: false)

    @Test("a panel showing applies the launcher's rule")
    func showAppliesRule() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(
            rules: [AppRule(appID: raycast, target: .slot(.english))], slotIDs: slots
        ))

        let restore = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin,
                                           context: quiet, slotOfSource: slotOf)

        #expect(restore == .selectSlot(.english))
        #expect(tracker.frontmostAppID == raycast)
    }

    @Test("Keep as is on a launcher switches nothing on show, and the hide still restores the app underneath")
    func keepAsIsLauncher() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(
            remembersPerApp: true, rules: [AppRule(appID: raycast, target: .keepAsIs)]
        ))
        tracker.sourceChanged(to: pinyin, context: quiet)

        #expect(tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet) == .none)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
    }

    @Test("a panel hiding gives the app underneath its own source, and the launcher keeps its own")
    func hideRestoresUnderneath() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(remembersPerApp: true))
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
        #expect(tracker.rememberedSourceID(for: raycast) == abc)
        #expect(tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)
            == .select(sourceID: abc))
    }

    @Test("a trigger inside the panel is the launcher's choice, not the app underneath's")
    func triggerInPanelBelongsToLauncher() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(remembersPerApp: true))
        tracker.sourceChanged(to: pinyin, context: quiet)

        tracker.triggerConfirmed(sourceID: abc, actualFrontmostAppID: raycast, isRegularApp: launcherCounts, context: ownPending)

        #expect(tracker.frontmostAppID == raycast)
        #expect(tracker.rememberedSourceID(for: raycast) == abc)
        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
    }

    @Test("notices repeating the source while the restore on hide is on its way record nothing")
    func stormDuringRestoreIsIgnored() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(remembersPerApp: true))
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
        for _ in 0..<10 {
            tracker.sourceChanged(to: abc, context: restorePending)
        }

        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
        #expect(tracker.rememberedSourceID(for: raycast) == abc)
    }

    @Test("notices repeating an unchanged source while a panel shows change no memory")
    func stormWithUnchangedSourceIsHarmless() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(remembersPerApp: true))
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)

        for _ in 0..<10 {
            tracker.sourceChanged(to: pinyin, context: quiet)
        }

        #expect(tracker.rememberedSourceID(for: wechat) == pinyin)
        #expect(tracker.appActivated(wechat, currentSourceID: pinyin, context: quiet) == .none)
    }

    @Test("a panel over a browser stops the page watch, and hiding it waits for the page again")
    func panelOverBrowser() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: chrome, frontBrowserPID: chromePID, settings: AppActivationSettings(
            rules: [AppRule(appID: chrome, target: .slot(.chinese))], slotIDs: slots,
            websiteRules: [WebsiteRule(domain: "example.jp", target: .slot(.english))]
        ))
        let generationBefore = tracker.websiteWatch?.generation

        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)
        #expect(tracker.websiteWatch == nil)

        #expect(tracker.appActivated(chrome, currentSourceID: pinyin, context: quiet, browserPID: chromePID,
                                     slotOfSource: slotOf) == .none)
        #expect(tracker.isWebsiteHoldWaiting)
        #expect(tracker.websiteWatch?.pid == chromePID)
        #expect(tracker.websiteWatch?.generation != generationBefore)
    }

    @Test("a panel over a terminal stops the pane watch, and hiding it reads the pane again")
    func panelOverTerminal() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: ghostty, frontTerminalPID: ghosttyPID, settings: AppActivationSettings(
            slotIDs: slots, programRules: [ProgramRule(name: "claude", target: .slot(.chinese))]
        ))

        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: abc, context: quiet)
        #expect(tracker.programWatch == nil)

        _ = tracker.appActivated(ghostty, currentSourceID: abc, context: quiet, terminalPID: ghosttyPID, slotOfSource: slotOf)
        #expect(tracker.programWatch?.pid == ghosttyPID)
        let reading = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 1,
                                     context: .rule("claude"), paneID: "A")
        #expect(tracker.programRead(reading, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .selectSlot(.chinese))
    }

    @Test("Cmd-Tab while a panel shows: the notice reaching main before the hide changes nothing, the hide decides")
    func cmdTabNoticeBeforeHide() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(remembersPerApp: true))
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(ghostty, currentSourceID: abc, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: abc, context: quiet)

        // The watcher has not seen the panel close: the app in front still reads as the launcher.
        #expect(tracker.appActivated(wechat, isRegularApp: launcherCounts, currentSourceID: abc, context: quiet,
                                     actualFrontmostAppID: raycast) == .none)
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
        #expect(tracker.frontmostAppID == wechat)
    }

    @Test("Cmd-Tab while a panel shows: the hide reaching main first decides, the late notice changes nothing")
    func cmdTabHideBeforeNotice() {
        var tracker = AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: AppActivationSettings(remembersPerApp: true))
        tracker.sourceChanged(to: pinyin, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: pinyin, context: quiet)
        tracker.sourceChanged(to: abc, context: quiet)
        _ = tracker.appActivated(ghostty, currentSourceID: abc, context: quiet)
        _ = tracker.appActivated(raycast, isRegularApp: launcherCounts, currentSourceID: abc, context: quiet)

        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet) == .select(sourceID: pinyin))
        #expect(tracker.appActivated(wechat, currentSourceID: abc, context: quiet, actualFrontmostAppID: wechat) == .none)
        #expect(tracker.frontmostAppID == wechat)
    }
}
