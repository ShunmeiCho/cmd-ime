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
        pane: String? = "A",
        on source: String,
        context: AppMemoryContext = quiet
    ) -> AppMemoryTracker.Restore {
        let reading = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: sequence,
                                     context: program, paneID: pane)
        return tracker.programRead(reading, currentSourceID: source, context: context, slotOfSource: slotOf)
    }

    /// A focus notice for `pane`, received at `time`.
    private func focus(_ tracker: inout AppMemoryTracker, _ pane: String, at time: Double = 1) {
        tracker.paneFocused(pid: ghosttyPID, paneID: pane, at: time)
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

        #expect(read(&tracker, 1, program, pane: nil, on: abc) == .selectSlot(.japanese))
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

        focus(&tracker, "B")
        #expect(read(&tracker, 2, .rule("zsh"), pane: "B", on: pinyin) == .selectSlot(.english))
        tracker.switchConfirmed(sourceID: abc, context: restorePending)

        focus(&tracker, "A", at: 2)
        #expect(read(&tracker, 3, .rule("claude"), on: abc) == .selectSlot(.chinese))
    }

    @Test("another pane running the same program gets the rule again after a switch by hand")
    func sameProgramInAnotherPaneReapplies() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        tracker.sourceChanged(to: abc, context: quiet)
        // The switch by hand stands while the pane and its program stay the same.
        #expect(read(&tracker, 2, .rule("claude"), on: abc) == .none)

        focus(&tracker, "B")

        #expect(read(&tracker, 3, .rule("claude"), pane: "B", on: abc) == .selectSlot(.chinese))
    }

    @Test("a read naming another pane is a focus change by itself; a notice for the pane already known is not one")
    func focusChangeSeenByARead() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(read(&tracker, 2, .rule("claude"), pane: "B", on: abc) == .selectSlot(.chinese))
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        let generation = tracker.activationGeneration
        tracker.sourceChanged(to: abc, context: quiet)

        focus(&tracker, "B")

        #expect(tracker.activationGeneration == generation)
        #expect(read(&tracker, 3, .rule("claude"), pane: "B", on: abc) == .none)
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

        focus(&tracker, "B")

        #expect(read(&tracker, 2, .noRule, pane: "B", on: pinyin) == .none)
    }

    @Test("a Keep as is program is left alone and nothing is remembered there")
    func keepAsIsProgram() {
        var tracker = makeTracker(settings(ghosttyRule: nil, remembersPerApp: true))
        _ = activateGhostty(&tracker)

        #expect(read(&tracker, 1, .rule("vim"), on: abc) == .none)
        tracker.sourceChanged(to: kotoeri, context: quiet)

        #expect(tracker.rememberedSourceID(for: ghostty) == nil)
    }

    @Test("the prefix key's two source changes do not stop the rule, whichever side of the focus notice they arrive on")
    func prefixKeyAroundFocus() {
        for restoreArrivesLate in [false, true] {
            var tracker = makeTracker()
            _ = activateGhostty(&tracker)
            _ = read(&tracker, 1, .rule("claude"), on: abc)
            tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

            // The multiplexer selects ASCII for its prefix mode, then puts the source back.
            tracker.sourceChanged(to: abc, context: quiet)
            #expect(read(&tracker, 2, .rule("claude"), on: abc) == .none)
            if !restoreArrivesLate { tracker.sourceChanged(to: pinyin, context: quiet) }
            focus(&tracker, "B")
            if restoreArrivesLate { tracker.sourceChanged(to: pinyin, context: quiet) }

            #expect(read(&tracker, 3, .rule("zsh"), pane: "B", on: pinyin) == .selectSlot(.english))
            #expect(read(&tracker, 4, .rule("zsh"), pane: "B", on: pinyin) == .none)
        }
    }

    @Test("a prefix round trip during the wait after activation loses neither the rule nor the terminal's own target")
    func prefixKeyDuringTheActivationWait() {
        var ruled = makeTracker()
        _ = activateGhostty(&ruled, on: kotoeri)
        ruled.sourceChanged(to: abc, context: quiet)
        #expect(read(&ruled, 1, .rule("claude"), on: abc) == .selectSlot(.chinese))

        var unruled = makeTracker()
        _ = activateGhostty(&unruled, on: pinyin)
        unruled.sourceChanged(to: abc, context: quiet)
        unruled.sourceChanged(to: pinyin, context: quiet)
        #expect(read(&unruled, 1, .noRule, on: pinyin) == .selectSlot(.japanese))
    }

    @Test("in a terminal a switch by hand is not a choice against a read on its way: only a trigger is")
    func handSwitchDoesNotRetireARead() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        let onItsWay = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 1,
                                      context: .rule("claude"), paneID: "A")

        tracker.sourceChanged(to: kotoeri, context: quiet)

        #expect(tracker.programRead(onItsWay, currentSourceID: kotoeri, context: quiet, slotOfSource: slotOf)
            == .selectSlot(.chinese))
    }

    @Test("a read stamped before the focus notice is dropped")
    func readFromBeforeTheFocusNoticeIsStale() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        let old = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 2,
                                 context: .rule("zsh"), paneID: "A")

        focus(&tracker, "B")

        #expect(tracker.programRead(old, currentSourceID: pinyin, context: quiet, slotOfSource: slotOf) == .none)
    }

    @Test("a trigger pressed after the focus notice wins: the next read only records the program")
    func triggerAfterFocusWins() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        focus(&tracker, "B", at: 1)

        tracker.triggerConfirmed(sourceID: kotoeri, actualFrontmostAppID: ghostty, context: ownPending,
                                 terminalPID: ghosttyPID, at: 2)

        #expect(read(&tracker, 2, .rule("zsh"), pane: "B", on: kotoeri) == .none)
        #expect(read(&tracker, 3, .rule("zsh"), pane: "B", on: kotoeri) == .none)
    }

    @Test("a confirmed trigger retires the read that was on its way")
    func triggerRetiresAReadOnItsWay() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        let old = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 1,
                                 context: .rule("claude"), paneID: "A")

        tracker.triggerConfirmed(sourceID: kotoeri, actualFrontmostAppID: ghostty, context: ownPending,
                                 terminalPID: ghosttyPID, at: 1)

        #expect(tracker.programRead(old, currentSourceID: kotoeri, context: quiet, slotOfSource: slotOf) == .none)
        #expect(read(&tracker, 2, .rule("claude"), on: kotoeri) == .none)
    }

    @Test("after a password field, a pane whose program has a rule gets the rule's slot back")
    func passwordFieldInARuledPane() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)

        tracker.sourceChanged(to: abc, context: AppMemoryContext(isSecureInputInFrontmostApp: true))

        #expect(tracker.secureInputEnded(currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .selectSlot(.chinese))
    }

    @Test("a source selected by a Program Rule does not become the terminal's memory; one chosen under no rule does")
    func memoryHoldsOnlyWhatWasUsedWithoutARule() {
        var tracker = makeTracker(settings(ghosttyRule: nil, remembersPerApp: true))
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        tracker.sourceChanged(to: kotoeri, context: quiet)
        #expect(tracker.rememberedSourceID(for: ghostty) == nil)

        _ = read(&tracker, 2, .noRule, on: kotoeri)
        tracker.sourceChanged(to: abc, context: quiet)

        #expect(tracker.rememberedSourceID(for: ghostty) == abc)
    }

    @Test("pausing Program Rules while a rule's switch is on its way puts the source back, in a pane wait too")
    func pausingRetiresASwitchInFlight() {
        for duringAPaneWait in [false, true] {
            var tracker = makeTracker()
            _ = activateGhostty(&tracker)
            _ = read(&tracker, 1, .rule("claude"), on: abc)
            if duringAPaneWait { focus(&tracker, "B") }

            #expect(tracker.update(settings: settings(paused: true), context: restorePending) == .putBack(sourceID: abc))
            #expect(tracker.programWatch == nil)
            #expect(!tracker.isWebsiteHoldWaiting)
        }
    }

    @Test("changed Program Rules are matched afresh: a read stamped under the old ones is dropped")
    func rulesChangeStartsANewGeneration() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        _ = read(&tracker, 1, .rule("claude"), on: abc)
        tracker.switchConfirmed(sourceID: pinyin, context: restorePending)
        let old = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 2,
                                 context: .rule("zsh"), paneID: "A")
        var changed = settings()
        changed.programRules = [ProgramRule(name: "claude", target: .slot(.japanese))]

        _ = tracker.update(settings: changed, context: quiet)

        #expect(tracker.programRead(old, currentSourceID: pinyin, context: quiet, slotOfSource: slotOf) == .none)
        #expect(read(&tracker, 3, .rule("claude"), on: pinyin) == .selectSlot(.japanese))
    }

    @Test("rules changed while another app is in front are used when the terminal comes back")
    func rulesChangedElsewhere() {
        var tracker = makeTracker()
        _ = activateGhostty(&tracker)
        let old = ProgramReading(pid: ghosttyPID, generation: tracker.activationGeneration, sequence: 1,
                                 context: .rule("claude"), paneID: "A")
        _ = tracker.appActivated(wechat, currentSourceID: abc, context: quiet)
        var changed = settings()
        changed.programRules = [ProgramRule(name: "claude", target: .slot(.japanese))]
        _ = tracker.update(settings: changed, context: quiet)

        _ = activateGhostty(&tracker)

        #expect(tracker.programRead(old, currentSourceID: abc, context: quiet, slotOfSource: slotOf) == .none)
        #expect(read(&tracker, 2, .rule("claude"), on: abc) == .selectSlot(.japanese))
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

        tracker.paneFocused(pid: 9, paneID: "B", at: 1)
        tracker.paneFocused(pid: ghosttyPID, paneID: "B", at: 1, actualFrontmostAppID: wechat)

        #expect(tracker.activationGeneration == generation)
        let reading = ProgramReading(pid: ghosttyPID, generation: generation, sequence: 1, context: .rule("claude"), paneID: "A")
        #expect(tracker.programRead(reading, actualFrontmostAppID: wechat, currentSourceID: abc, context: quiet,
                                    slotOfSource: slotOf) == .none)
    }
}
