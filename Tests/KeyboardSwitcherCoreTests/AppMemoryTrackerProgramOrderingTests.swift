import Foundation
import Testing
@testable import KeyboardSwitcherCore

/// Orderings found by the three reviews of Program Rules (R1 to R3). Each failed before its fix.
/// Events name their pane; a focus notice carries when it was received, a trigger when it was
/// confirmed. The reviewers' originals are in `.claude/work/cards/program-rules/R*-adversarial-tests.swift.txt`.
struct AppMemoryTrackerProgramOrderingTests {
    private let terminal = "com.mitchellh.ghostty"
    private let pid: Int32 = 701
    private let abc = "com.apple.keylayout.ABC"
    private let chinese = "com.apple.inputmethod.SCIM.ITABC"
    private let japanese = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
    private let quiet = AppMemoryContext()
    private let pending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)
    private let triggerPending = AppMemoryContext(isOwnSwitchPending: true)
    private let secure = AppMemoryContext(isSecureInputInFrontmostApp: true)

    /// claude is chinese, zsh is english; the terminal has no rule of its own and remembers.
    private func tracker() -> AppMemoryTracker {
        AppMemoryTracker(
            ownAppID: "cmdime", frontmostAppID: "editor",
            settings: AppActivationSettings(
                remembersPerApp: true, restoresAfterPasswordField: true,
                slotIDs: [.english, .chinese, .japanese],
                programRules: [ProgramRule(name: "claude", target: .slot(.chinese)),
                               ProgramRule(name: "zsh", target: .slot(.english))]))
    }

    private func slot(_ id: String) -> InputRole? {
        [abc: InputRole.english, chinese: .chinese, japanese: .japanese][id]
    }

    private func activate(_ state: inout AppMemoryTracker) {
        _ = state.appActivated(terminal, currentSourceID: abc, context: quiet, terminalPID: pid, slotOfSource: slot)
    }

    private func read(_ state: inout AppMemoryTracker, _ sequence: Int, _ program: ProgramContext, pane: String? = "A",
                      on source: String, context: AppMemoryContext = AppMemoryContext()) -> AppMemoryTracker.Restore {
        state.programRead(
            ProgramReading(pid: pid, generation: state.activationGeneration, sequence: sequence, context: program, paneID: pane),
            actualFrontmostAppID: terminal, actualTerminalPID: pid, currentSourceID: source, context: context,
            slotOfSource: slot)
    }

    private func focus(_ state: inout AppMemoryTracker, _ pane: String, at time: Double) {
        state.paneFocused(pid: pid, paneID: pane, at: time, actualFrontmostAppID: terminal, actualTerminalPID: pid)
    }

    private func trigger(_ state: inout AppMemoryTracker, _ source: String, at time: Double) {
        state.triggerConfirmed(sourceID: source, actualFrontmostAppID: terminal, context: triggerPending,
                               terminalPID: pid, at: time)
    }

    /// Pane A runs claude and its rule's switch to chinese has landed.
    private func onClaudeInA() -> AppMemoryTracker {
        var state = tracker()
        activate(&state)
        _ = read(&state, 1, .rule("claude"), on: abc)
        state.switchConfirmed(sourceID: chinese, context: pending)
        return state
    }

    @Test("R1-1: a trigger in the new pane survives that pane's focus notice handled after it")
    func lateFocusNoticeKeepsTheTrigger() {
        var state = onClaudeInA()
        trigger(&state, japanese, at: 2)

        focus(&state, "B", at: 1)

        #expect(read(&state, 2, .rule("zsh"), pane: "B", on: japanese) == .none)
    }

    @Test("R2-2: a trigger in the pane just left ends with it; the new pane's rule applies")
    func triggerInThePaneLeftEndsWithIt() {
        var state = onClaudeInA()
        trigger(&state, japanese, at: 1)

        focus(&state, "B", at: 2)

        #expect(read(&state, 2, .rule("zsh"), pane: "B", on: japanese) == .selectSlot(.english))
    }

    @Test("R3-1: a read naming the new pane, then that pane's notice received before the trigger, keeps the trigger")
    func readThenEarlierNoticeForTheSamePane() {
        var state = onClaudeInA()
        trigger(&state, japanese, at: 2)

        #expect(read(&state, 2, .rule("zsh"), pane: "B", on: japanese) == .none)
        focus(&state, "B", at: 1)

        #expect(read(&state, 3, .rule("zsh"), pane: "B", on: japanese) == .none)
    }

    @Test("R4-2: a read naming the new pane cannot keep a trigger of the pane left: the pane's notice dates it",
          arguments: [ProgramContext.unknown, .rule("zsh")])
    func readThenLaterNoticeRetiresTheOldTrigger(firstRead: ProgramContext) {
        var state = onClaudeInA()
        trigger(&state, japanese, at: 1)

        #expect(read(&state, 2, firstRead, pane: "C", on: japanese) == .none)
        focus(&state, "C", at: 2)

        #expect(read(&state, 3, .rule("zsh"), pane: "C", on: japanese) == .selectSlot(.english))
    }

    @Test("R4-1: notices for B and then C, each with its own time, leave a trigger made in B behind")
    func triggerBetweenTwoNotices() {
        var state = onClaudeInA()
        trigger(&state, japanese, at: 2)

        focus(&state, "B", at: 1)
        focus(&state, "C", at: 3)

        #expect(read(&state, 2, .rule("zsh"), pane: "C", on: japanese) == .selectSlot(.english))
    }

    @Test("R3: the latest of several choices stands when the notice was received before or with it",
          arguments: [2.0, 4.0])
    func latestChoiceStands(noticeAt: Double) {
        var state = onClaudeInA()
        state.sourceChanged(to: japanese, context: quiet, at: 2)
        state.sourceChanged(to: abc, context: quiet, at: 3)
        trigger(&state, japanese, at: 4)

        focus(&state, "B", at: noticeAt)

        #expect(read(&state, 2, .rule("zsh"), pane: "B", on: japanese) == .none)
    }

    @Test("R1-2: a rule's switch still on its way is put back when the new pane has no rule")
    func pendingSwitchIsPutBack() {
        var state = tracker()
        activate(&state)
        #expect(read(&state, 1, .rule("claude"), on: abc) == .selectSlot(.chinese))

        focus(&state, "B", at: 1)

        #expect(read(&state, 2, .noRule, pane: "B", on: abc, context: pending) == .putBack(sourceID: abc))
    }

    @Test("R2-3, R3-4: the retired switch is put back after it has landed, and after a read that could not tell")
    func landedSwitchIsPutBack() {
        for firstReadCannotTell in [false, true] {
            var state = tracker()
            activate(&state)
            #expect(read(&state, 1, .rule("claude"), on: abc) == .selectSlot(.chinese))
            focus(&state, "B", at: 1)
            state.switchConfirmed(sourceID: chinese, context: pending)
            if firstReadCannotTell {
                #expect(read(&state, 2, .unknown, pane: nil, on: chinese) == .none)
            }

            #expect(read(&state, 3, .noRule, pane: "B", on: chinese) == .putBack(sourceID: abc))
            #expect(read(&state, 4, .noRule, pane: "B", on: abc) == .none)
        }
    }

    @Test("R3: a trigger or a switch by hand since ends the retired switch's put-back")
    func newChoiceEndsThePutBack() {
        for byTrigger in [false, true] {
            var state = tracker()
            activate(&state)
            _ = read(&state, 1, .rule("claude"), on: abc)
            focus(&state, "B", at: 1)
            state.switchConfirmed(sourceID: chinese, context: pending)
            if byTrigger {
                trigger(&state, japanese, at: 2)
            } else {
                state.sourceChanged(to: japanese, context: quiet, at: 2)
            }

            #expect(read(&state, 2, .noRule, pane: "B", on: japanese) == .none)
        }
    }

    @Test("R2: the expiry of a pane's wait only retires a switch still on its way")
    func paneWaitExpiry() {
        for isPending in [false, true] {
            var state = tracker()
            activate(&state)
            _ = read(&state, 1, .rule("claude"), on: abc)
            if !isPending { state.switchConfirmed(sourceID: chinese, context: pending) }
            focus(&state, "B", at: 1)

            let result = state.programHoldExpired(generation: state.activationGeneration,
                currentSourceID: isPending ? abc : chinese, context: isPending ? pending : quiet, slotOfSource: slot)

            #expect(result == (isPending ? .putBack(sourceID: abc) : .none))
            #expect(!state.isWebsiteHoldWaiting)
        }
    }

    @Test("R2: leaving the terminal during a pane's wait and coming back starts over")
    func paneWaitRoundTrip() {
        var state = onClaudeInA()
        focus(&state, "B", at: 1)
        let old = ProgramReading(pid: pid, generation: state.activationGeneration, sequence: 2, context: .rule("zsh"), paneID: "B")
        _ = state.appActivated("editor", currentSourceID: chinese, context: quiet)

        activate(&state)

        #expect(state.programRead(old, currentSourceID: abc, context: quiet, slotOfSource: slot) == .none)
        #expect(state.isWebsiteHoldWaiting)
        #expect(read(&state, 3, .rule("claude"), on: abc) == .selectSlot(.chinese))
    }

    @Test("R1-3: a rule's source stays out of the terminal's memory while the new pane cannot be read")
    func unreadablePaneKeepsRuleSourceOutOfMemory() {
        var state = onClaudeInA()
        #expect(state.rememberedSourceID(for: terminal) == nil)

        focus(&state, "B", at: 1)
        #expect(read(&state, 2, .unknown, pane: nil, on: chinese) == .none)
        _ = state.appActivated("editor", currentSourceID: chinese, context: quiet)

        #expect(state.rememberedSourceID(for: terminal) == nil)
    }

    @Test("R3-6: a source chosen before the program is known is not remembered, so a rule found there cannot be undone by it")
    func choiceBeforeTheFirstReadIsNotRemembered() {
        var state = tracker()
        activate(&state)

        state.sourceChanged(to: japanese, context: quiet, at: 1)
        _ = read(&state, 1, .rule("claude"), on: japanese)
        state.switchConfirmed(sourceID: chinese, context: pending)
        #expect(state.rememberedSourceID(for: terminal) == nil)
        _ = state.appActivated("editor", currentSourceID: chinese, context: quiet)
        activate(&state)

        #expect(read(&state, 2, .noRule, on: abc) == .none)
    }

    @Test("R2: a switch by hand under a rule is not remembered; under no rule it is")
    func handSwitchAndMemory() {
        var ruled = onClaudeInA()
        ruled.sourceChanged(to: japanese, context: quiet)
        #expect(read(&ruled, 2, .rule("claude"), on: japanese) == .none)
        #expect(ruled.rememberedSourceID(for: terminal) == nil)

        var unruled = tracker()
        activate(&unruled)
        _ = read(&unruled, 1, .noRule, on: abc)
        unruled.sourceChanged(to: japanese, context: quiet)
        _ = unruled.appActivated("editor", currentSourceID: japanese, context: quiet)
        #expect(unruled.rememberedSourceID(for: terminal) == japanese)
    }

    @Test("R1-5: a password field's put-back stays with the pane it was in")
    func passwordPutBackStaysWithItsPane() {
        var state = onClaudeInA()
        state.sourceChanged(to: abc, context: secure, at: 1)
        #expect(state.isAwaitingSecureInputEnd)

        focus(&state, "B", at: 2)
        #expect(read(&state, 2, .rule("zsh"), pane: "B", on: abc) == .none)

        #expect(state.secureInputEnded(currentSourceID: abc, context: quiet, slotOfSource: slot) == .none)
    }

    @Test("R2-4: a password field in the new pane keeps its put-back when that pane's notice is handled late")
    func newPanePasswordBeforeItsNotice() {
        var state = tracker()
        activate(&state)
        _ = read(&state, 1, .noRule, on: abc)
        state.sourceChanged(to: chinese, context: quiet, at: 1)
        // Focus is in B already: its password field replaces chinese, and B's notice (received at 2) comes after.
        state.sourceChanged(to: abc, context: secure, at: 3)

        focus(&state, "B", at: 2)
        _ = read(&state, 2, .noRule, pane: "B", on: abc, context: secure)

        #expect(state.secureInputEnded(currentSourceID: abc, context: quiet, slotOfSource: slot) == .select(sourceID: chinese))
    }

    @Test("R2-5: a notice for the pane already in focus does not touch a password field's put-back")
    func repeatedNoticeKeepsThePutBack() {
        var state = tracker()
        activate(&state)
        _ = read(&state, 1, .noRule, on: abc)
        state.sourceChanged(to: chinese, context: quiet, at: 1)
        state.sourceChanged(to: abc, context: secure, at: 2)

        focus(&state, "A", at: 3)

        #expect(state.secureInputEnded(currentSourceID: abc, context: quiet, slotOfSource: slot) == .select(sourceID: chinese))
    }

    @Test("R3-5: a password that ends before the new pane is read does not get the rule of the pane just left")
    func passwordEndsBeforeTheNewPaneIsRead() {
        var state = onClaudeInA()
        // In B already: a switch by hand, then B's password field; B's notice was received at 1.
        state.sourceChanged(to: japanese, context: quiet, at: 2)
        state.sourceChanged(to: abc, context: secure, at: 3)

        focus(&state, "B", at: 1)

        #expect(state.secureInputEnded(currentSourceID: abc, context: quiet, slotOfSource: slot) == .select(sourceID: japanese))
    }

    @Test("R4-3: nothing is remembered for a terminal while its program is not known")
    func undecidedProgramRemembersNothing() {
        var byTrigger = tracker()
        activate(&byTrigger)
        trigger(&byTrigger, japanese, at: 1)
        #expect(byTrigger.rememberedSourceID(for: terminal) == nil)

        var byLeaving = tracker()
        activate(&byLeaving)
        byLeaving.sourceChanged(to: japanese, context: quiet, at: 1)
        _ = byLeaving.appActivated("editor", currentSourceID: japanese, context: quiet)
        #expect(byLeaving.rememberedSourceID(for: terminal) == nil)

        var stale = tracker()
        activate(&stale)
        _ = read(&stale, 1, .noRule, on: abc)
        stale.sourceChanged(to: chinese, context: quiet)
        focus(&stale, "B", at: 1)
        stale.sourceChanged(to: japanese, context: quiet, at: 2)
        _ = stale.appActivated("editor", currentSourceID: japanese, context: quiet)
        #expect(stale.rememberedSourceID(for: terminal) == chinese)
    }

    @Test("R4-4: a read under a password field decides nothing and leaves the pane's rule for the read after it")
    func readUnderAPasswordFieldDefers() {
        var state = onClaudeInA()
        state.sourceChanged(to: abc, context: quiet)

        // Already ASCII: the password field of pane B replaces nothing.
        #expect(read(&state, 2, .rule("claude"), pane: "B", on: abc, context: secure) == .none)
        #expect(!state.isAwaitingSecureInputEnd)
        #expect(state.programHoldExpired(generation: state.activationGeneration, currentSourceID: abc,
                                         context: secure, slotOfSource: slot) == .none)

        #expect(read(&state, 3, .rule("claude"), pane: "B", on: abc) == .selectSlot(.chinese))
    }

    @Test("R5: a rule first read under a password field is decided by the first read after it, wait or no wait")
    func ruleReadUnderAPasswordFieldIsDecidedLater() {
        // A program that starts in the pane in focus while its password field is up: no wait exists.
        var started = tracker()
        activate(&started)
        _ = read(&started, 1, .noRule, on: abc)
        #expect(read(&started, 2, .rule("claude"), on: abc, context: secure) == .none)
        #expect(read(&started, 3, .rule("claude"), on: abc) == .selectSlot(.chinese))
        #expect(read(&started, 4, .rule("claude"), on: abc) == .none)

        // A pane focus whose wait expires after the password field ended and before the next read.
        var focused = onClaudeInA()
        focused.sourceChanged(to: abc, context: quiet)
        #expect(read(&focused, 2, .rule("claude"), pane: "B", on: abc, context: secure) == .none)
        #expect(focused.programHoldExpired(generation: focused.activationGeneration, currentSourceID: abc,
                                           context: quiet, slotOfSource: slot) == .none)
        #expect(read(&focused, 3, .rule("claude"), pane: "B", on: abc) == .selectSlot(.chinese))
    }

    @Test("R4-5: a password put-back by the pane's rule ends the retired switch")
    func passwordRuleEndsTheRetiredSwitch() {
        var state = AppMemoryTracker(ownAppID: "cmdime", frontmostAppID: "editor", settings: AppActivationSettings(
            restoresAfterPasswordField: true, slotIDs: [.english, .chinese, .japanese],
            programRules: [ProgramRule(name: "claude", target: .slot(.chinese)),
                           ProgramRule(name: "vim", target: .slot(.japanese))]))
        activate(&state)
        #expect(read(&state, 1, .rule("claude"), on: abc) == .selectSlot(.chinese))
        focus(&state, "B", at: 1)
        state.switchConfirmed(sourceID: chinese, context: pending)
        state.sourceChanged(to: abc, context: secure, at: 2)
        #expect(read(&state, 2, .rule("vim"), pane: "B", on: abc, context: secure) == .none)

        #expect(state.secureInputEnded(currentSourceID: abc, context: quiet, slotOfSource: slot) == .selectSlot(.japanese))
        state.switchConfirmed(sourceID: japanese, context: pending)

        // vim exits in B: a program without a rule changes nothing, and pane A's switch is long over.
        #expect(read(&state, 3, .noRule, pane: "B", on: japanese) == .none)
    }

    @Test("R4-6: a terminal's reads are not measured against the count of a browser's, nor the other way round")
    func watchersCountTheirOwnReads() {
        let browser = "com.google.Chrome"
        let browserPID: Int32 = 900
        var state = AppMemoryTracker(ownAppID: "cmdime", frontmostAppID: "editor", settings: AppActivationSettings(
            slotIDs: [.english, .chinese, .japanese],
            websiteRules: [WebsiteRule(domain: "example.jp", target: .slot(.japanese))],
            programRules: [ProgramRule(name: "claude", target: .slot(.chinese))]))
        _ = state.appActivated(browser, currentSourceID: abc, context: quiet, browserPID: browserPID, slotOfSource: slot)
        _ = state.websiteRead(WebsiteReading(pid: browserPID, generation: state.activationGeneration, sequence: 50,
                                             context: .noRule), currentSourceID: abc, context: quiet, slotOfSource: slot)

        activate(&state)
        #expect(read(&state, 1, .rule("claude"), on: abc) == .selectSlot(.chinese))

        _ = state.appActivated(browser, currentSourceID: chinese, context: quiet, browserPID: browserPID, slotOfSource: slot)
        #expect(state.websiteRead(WebsiteReading(pid: browserPID, generation: state.activationGeneration, sequence: 51,
                                                 context: .rule("example.jp")), currentSourceID: chinese, context: quiet,
                                  slotOfSource: slot) == .selectSlot(.japanese))
    }

    @Test("R1-5b: editing only Program Rules cannot reapply an unchanged website over a trigger")
    func programSettingsDoNotReapplyWebsiteRules() {
        let browser = "com.google.Chrome"
        let browserPID: Int32 = 900
        var settings = AppActivationSettings(
            slotIDs: [.english, .chinese, .japanese],
            websiteRules: [WebsiteRule(domain: "example.jp", target: .slot(.japanese))],
            programRules: [ProgramRule(name: "zsh", target: .slot(.english))])
        var state = AppMemoryTracker(ownAppID: "cmdime", frontmostAppID: "editor", settings: settings)
        _ = state.appActivated(browser, currentSourceID: abc, context: AppMemoryContext(),
                               browserPID: browserPID, slotOfSource: slot)
        _ = state.websiteRead(WebsiteReading(pid: browserPID, generation: state.activationGeneration,
                                             sequence: 1, context: .rule("example.jp")),
                              currentSourceID: abc, context: AppMemoryContext(), slotOfSource: slot)
        state.switchConfirmed(sourceID: japanese,
                              context: AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true))
        state.triggerConfirmed(sourceID: abc, actualFrontmostAppID: browser,
                               context: AppMemoryContext(isOwnSwitchPending: true), browserPID: browserPID)
        #expect(state.websiteRead(WebsiteReading(pid: browserPID, generation: state.activationGeneration,
                                                sequence: 2, context: .rule("example.jp")),
                                  currentSourceID: abc, context: AppMemoryContext(), slotOfSource: slot) == .none)
        // Only Program Rules changed, for instance by an external config update.
        settings.programRulesPaused = true
        _ = state.update(settings: settings)
        #expect(state.websiteRead(WebsiteReading(pid: browserPID, generation: state.activationGeneration,
                                                sequence: 3, context: .rule("example.jp")),
                                  currentSourceID: abc, context: AppMemoryContext(), slotOfSource: slot) == .none)
    }
}
