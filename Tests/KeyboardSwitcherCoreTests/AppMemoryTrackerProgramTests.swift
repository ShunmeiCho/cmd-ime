import Testing
@testable import KeyboardSwitcherCore

private let own = "com.shunmei.cmd-ime"
private let wechat = "com.tencent.xinWeChat"
private let ghostty = "com.mitchellh.ghostty"
private let ghosttyPID: Int32 = 701
private let abc = "com.apple.keylayout.ABC"
private let pinyin = "com.apple.inputmethod.SCIM.ITABC"
private let kotoeri = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
private let quiet = AppMemoryContext()
private let ownPending = AppMemoryContext(isOwnSwitchPending: true)
private let restorePending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)
private let slots: Set<InputRole> = [.english, .chinese, .japanese]
private func slotOf(_ sourceID: String) -> InputRole? {
    [abc: InputRole.english, pinyin: .chinese, kotoeri: .japanese][sourceID]
}

struct AppMemoryTrackerProgramTests {
    /// claude is `chinese`, zsh is `english`, vim is "Keep as is"; node has no rule. Ghostty itself
    /// has the slot rule `japanese` unless a test takes it away.
    private func settings(
        ghosttyRule: AppRule? = AppRule(appID: ghostty, target: .slot(.japanese)),
        remembersPerApp: Bool = false,
        paused: Bool = false
    ) -> AppActivationSettings {
        AppActivationSettings(
            remembersPerApp: remembersPerApp,
            rules: ghosttyRule.map { [$0] } ?? [],
            restoresAfterPasswordField: true,
            slotIDs: slots,
            programRules: [
                ProgramRule(name: "claude", target: .slot(.chinese)),
                ProgramRule(name: "zsh", target: .slot(.english)),
                ProgramRule(name: "vim", target: .keepAsIs),
            ],
            programRulesPaused: paused
        )
    }

    private func makeTracker(_ settings: AppActivationSettings? = nil) -> AppMemoryTracker {
        AppMemoryTracker(ownAppID: own, frontmostAppID: wechat, settings: settings ?? self.settings())
    }

    /// Ghostty comes to the front on `source`; its own target waits for the program.
    private func activateGhostty(_ tracker: inout AppMemoryTracker, on source: String = abc) -> AppMemoryTracker.Restore {
        tracker.appActivated(ghostty, currentSourceID: source, context: quiet, terminalPID: ghosttyPID, slotOfSource: slotOf)
    }

    private func read(
        _ tracker: inout AppMemoryTracker,
        _ sequence: Int,
        _ program: ProgramContext,
        on source: String,
        context: AppMemoryContext = quiet
    ) -> AppMemoryTracker.Restore {
        let reading = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: sequence, context: program)
        return tracker.programRead(reading, currentSourceID: source, context: context, slotOfSource: slotOf)
    }

    @Test("a terminal with Program Rules waits for its program, then the program's rule decides")
    func activationAppliesTheRule() {
        var tracker = makeTracker()

        #expect(activateGhostty(&tracker) == .none)
        #expect(tracker.isWebsiteHoldWaiting)
        #expect(tracker.programWatch?.pid == ghosttyPID)
        #expect(tracker.websiteWatch == nil)

        #expect(read(&tracker, 1, .rule("claude"), on: abc) == .selectSlot(.chinese))
        #expect(!tracker.isWebsiteHoldWaiting)
    }

    @Test("on activation, a program without a rule or a plain tab gets the terminal's own target at once",
          arguments: [ProgramContext.noRule, .rule("node")])
    func activationFallsBackToTheTerminal(program: ProgramContext) {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)

        #expect(read(&tracker, 1, program, on: abc) == .selectSlot(.japanese))
    }

    @Test("when no read arrives in time, the terminal's own target applies; a later rule still switches")
    func expiryFallsBackToTheTerminal() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)

        #expect(tracker.programHoldExpired(generation: tracker.activationGeneration, currentSourceID: abc,
                                           context: quiet, slotOfSource: slotOf) == .selectSlot(.japanese))
        #expect(read(&tracker, 1, .rule("claude"), on: kotoeri) == .selectSlot(.chinese))
    }

    @Test("a browser's expiry does not end a terminal's wait")
    func websiteExpiryIsNotForATerminal() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)

        #expect(tracker.websiteHoldExpired(generation: tracker.activationGeneration, currentSourceID: abc,
                                           context: quiet, slotOfSource: slotOf) == .none)
        #expect(tracker.isWebsiteHoldWaiting)
    }

    @Test("a rule is applied again every time a pane comes into focus")
    func paneFocusReapplies() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

        tracker.paneFocused(pid: ghosttyPID)
        #expect(read(&tracker, 2, .rule("zsh"), on: pinyin) == .selectSlot(.english))
        tracker.switchConfirmed(sourceID: abc, context: restorePending)

        tracker.paneFocused(pid: ghosttyPID)
        #expect(read(&tracker, 3, .rule("claude"), on: abc) == .selectSlot(.chinese))
    }

    @Test("another pane running the same program gets the rule again after a switch by hand")
    func sameProgramInAnotherPaneReapplies() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        tracker.sourceChanged(to: abc, context: quiet)
        // The read that follows the user's choice only records the program.
        #expect(read(&tracker, 2, .rule("claude"), on: abc) == .none)

        tracker.paneFocused(pid: ghosttyPID)

        #expect(read(&tracker, 3, .rule("claude"), on: abc) == .selectSlot(.chinese))
    }

    @Test("a program started in the pane in focus gets its rule; one without a rule changes nothing")
    func programChangeInOnePane() {
        // Ghostty has its own rule (japanese): a fallback to it would show.
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        #expect(read(&tracker, 1, .rule("zsh"), on: abc) == .none)

        #expect(read(&tracker, 2, .rule("claude"), on: abc) == .selectSlot(.chinese))
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

        #expect(read(&tracker, 3, .rule("node"), on: pinyin) == .none)
        #expect(read(&tracker, 4, .noRule, on: pinyin) == .none)
        #expect(read(&tracker, 5, .rule("zsh"), on: pinyin) == .selectSlot(.english))
    }

    @Test("focus moving to a pane whose program has no rule changes nothing")
    func paneFocusWithoutARule() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

        tracker.paneFocused(pid: ghosttyPID)

        #expect(read(&tracker, 2, .noRule, on: pinyin) == .none)
    }

    @Test("a Keep as is program is left alone and nothing is remembered there")
    func keepAsIsProgram() {
        var tracker = makeTracker(settings(ghosttyRule: nil, remembersPerApp: true))
        _ = activateGhostty(&tracker)

        #expect(read(&tracker, 1, .rule("vim"), on: abc) == .none)
        tracker.sourceChanged(to: kotoeri, context: quiet)

        #expect(tracker.rememberedSourceID(for: ghostty) == nil)
    }

    @Test("the prefix key's two source changes before the focus notice do not stop the rule")
    func prefixKeyThenFocus() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

        // The multiplexer selects ASCII for its prefix mode, then puts the source back.
        tracker.sourceChanged(to: abc, context: quiet)
        #expect(read(&tracker, 2, .rule("claude"), on: abc) == .none)
        tracker.sourceChanged(to: pinyin, context: quiet)
        tracker.paneFocused(pid: ghosttyPID)

        #expect(read(&tracker, 3, .rule("zsh"), on: pinyin) == .selectSlot(.english))
    }

    @Test("a read stamped before the focus notice is dropped")
    func readFromBeforeTheFocusNoticeIsStale() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        let old = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 2, context: .rule("zsh"))

        tracker.paneFocused(pid: ghosttyPID)

        #expect(tracker.programRead(old, currentSourceID: pinyin, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a trigger pressed after the focus notice wins: the next read only records the program")
    func triggerAfterFocusWins() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        tracker.paneFocused(pid: ghosttyPID)

        tracker.triggerConfirmed(sourceID: kotoeri, actualFrontmostAppID: ghostty, context: ownPending, terminalPID: ghosttyPID)

        #expect(read(&tracker, 2, .rule("zsh"), on: kotoeri) == .none)
        #expect(read(&tracker, 3, .rule("zsh"), on: kotoeri) == .none)
    }

    @Test("a source selected by a Program Rule does not become the terminal's memory")
    func ruleSwitchIsNotRemembered() {
        var tracker = makeTracker(settings(ghosttyRule: nil, remembersPerApp: true))
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)

        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

        #expect(tracker.rememberedSourceID(for: ghostty) == nil)
    }

    @Test("pausing Program Rules while a rule's switch is on its way puts the source back")
    func pausingRetiresASwitchInFlight() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)

        #expect(tracker.update(settings: settings(paused: true), context: restorePending) == .putBack(sourceID: abc))
        #expect(tracker.programWatch == nil)
    }

    @Test("changed Program Rules are matched afresh: a read stamped under the old ones is dropped")
    func rulesChangeStartsANewGeneration() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        let old = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 2, context: .rule("zsh"))
        var changed = settings()
        changed.programRules = [ProgramRule(name: "claude", target: .slot(.japanese))]

        _ = tracker.update(settings: changed, context: quiet)

        #expect(tracker.programRead(old, currentSourceID: pinyin, context: quiet, slotOfSource: slotOf) == .none)
        #expect(read(&tracker, 3, .rule("claude"), on: pinyin) == .selectSlot(.japanese))
    }

    @Test("a terminal that is Keep as is, or with rules paused, is not read")
    func notWatchedWhenKeptOrPaused() {
        var kept = makeTracker(settings(ghosttyRule: AppRule(appID: ghostty, target: .keepAsIs)))
        _ = activateGhostty(&kept)
        var paused = makeTracker(settings(paused: true))

        #expect(kept.programWatch == nil)
        #expect(!kept.isWebsiteHoldWaiting)
        #expect(activateGhostty(&paused) == .selectSlot(.japanese))
        #expect(paused.programWatch == nil)
    }

    @Test("a focus notice or a read for a terminal that is not in front is dropped")
    func noticesForAnotherTerminalAreDropped() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        let generation = tracker.activationGeneration

        tracker.paneFocused(pid: 9)
        tracker.paneFocused(pid: ghosttyPID, actualFrontmostAppID: wechat)

        #expect(tracker.activationGeneration == generation)
        let reading = ProgramReading(pid: ghosttyPID, generation: generation, sequence: 1, context: .rule("claude"))
        #expect(tracker.programRead(reading, actualFrontmostAppID: wechat, currentSourceID: abc, context: quiet,
                                    slotOfSource: slotOf) == .none)
    }
}
