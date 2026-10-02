import Foundation
import Testing
@testable import KeyboardSwitcherCore

/// Orderings found by the first review of Program Rules (R1): each failed before its fix.
struct AppMemoryTrackerProgramOrderingTests {
    private let terminal = "com.mitchellh.ghostty"
    private let pid: Int32 = 701
    private let abc = "com.apple.keylayout.ABC"
    private let chinese = "com.apple.inputmethod.SCIM.ITABC"
    private let japanese = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"

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

    private func read(_ tracker: inout AppMemoryTracker, sequence: Int, program: ProgramContext,
                      source: String, pending: Bool = false) -> AppMemoryTracker.Restore {
        tracker.programRead(
            ProgramReading(pid: pid, generation: tracker.activationGeneration,
                           sequence: sequence, context: program),
            actualFrontmostAppID: terminal, actualTerminalPID: pid, currentSourceID: source,
            context: AppMemoryContext(isOwnSwitchPending: pending, isRestorePending: pending),
            slotOfSource: slot)
    }

    @Test("a trigger after physical pane focus survives the delayed focus notice")
    func delayedFocusDoesNotEraseNewerTrigger() {
        var state = tracker()
        _ = state.appActivated(terminal, currentSourceID: abc, context: AppMemoryContext(),
                               terminalPID: pid, slotOfSource: slot)
        _ = read(&state, sequence: 1, program: .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese,
                              context: AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true))
        // Prefix starts, ends, and physical focus has moved to zsh. Its pushed notice is late.
        state.sourceChanged(to: abc, context: AppMemoryContext())
        state.sourceChanged(to: chinese, context: AppMemoryContext())
        state.triggerConfirmed(sourceID: japanese, actualFrontmostAppID: terminal,
                               context: AppMemoryContext(isOwnSwitchPending: true), terminalPID: pid, at: 2)
        // The notice was received before the trigger (at 1) and is handled after it.
        state.paneFocused(pid: pid, at: 1, actualFrontmostAppID: terminal, actualTerminalPID: pid)
        #expect(read(&state, sequence: 2, program: .rule("zsh"), source: japanese) == .none)
    }

    @Test("leaving a ruled pane retires its still pending switch when the new pane has no rule")
    func pendingRuleCannotLandInUnruledPane() {
        var state = tracker()
        _ = state.appActivated(terminal, currentSourceID: abc, context: AppMemoryContext(),
                               terminalPID: pid, slotOfSource: slot)
        #expect(read(&state, sequence: 1, program: .rule("claude"), source: abc) == .selectSlot(.chinese))
        // The monitor is awaiting its Kana delay or selection-confirmation retry.
        state.paneFocused(pid: pid, at: 1)
        #expect(read(&state, sequence: 2, program: .noRule, source: abc, pending: true)
                == .putBack(sourceID: abc))
    }

    @Test("a rule source cannot become terminal memory while a newly focused pane is unreadable")
    func unreadablePaneKeepsRuleSourceOutOfMemory() {
        var state = tracker()
        _ = state.appActivated(terminal, currentSourceID: abc, context: AppMemoryContext(),
                               terminalPID: pid, slotOfSource: slot)
        _ = read(&state, sequence: 1, program: .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese,
                              context: AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true))
        #expect(state.rememberedSourceID(for: terminal) == nil)
        state.paneFocused(pid: pid, at: 1)
        #expect(read(&state, sequence: 2, program: .unknown, source: chinese) == .none)
        _ = state.appActivated("editor", currentSourceID: chinese, context: AppMemoryContext())
        #expect(state.rememberedSourceID(for: terminal) == nil)
    }

    @Test("a delayed prefix restoration notification cannot suppress a real pane's rule")
    func prefixNotificationAfterFocusDoesNotCancelRule() {
        var state = tracker()
        _ = state.appActivated(terminal, currentSourceID: abc, context: AppMemoryContext(),
                               terminalPID: pid, slotOfSource: slot)
        _ = read(&state, sequence: 1, program: .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese,
                              context: AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true))
        state.sourceChanged(to: abc, context: AppMemoryContext())
        // Physical restore happened already; its distributed notification is delivered after focus.
        state.paneFocused(pid: pid, at: 1)
        state.sourceChanged(to: chinese, context: AppMemoryContext())
        #expect(read(&state, sequence: 2, program: .rule("zsh"), source: chinese) == .selectSlot(.english))
        #expect(read(&state, sequence: 3, program: .rule("zsh"), source: chinese) == .none)
    }

    @Test("Password Put-back from a pane already left cannot override the new pane's rule")
    func passwordPutBackBelongsToItsPane() {
        var state = tracker()
        _ = state.appActivated(terminal, currentSourceID: abc, context: AppMemoryContext(),
                               terminalPID: pid, slotOfSource: slot)
        _ = read(&state, sequence: 1, program: .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese,
                              context: AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true))
        state.sourceChanged(to: abc, context: AppMemoryContext(isSecureInputInFrontmostApp: true))
        #expect(state.isAwaitingSecureInputEnd)
        state.paneFocused(pid: pid, at: 1)
        #expect(read(&state, sequence: 2, program: .rule("zsh"), source: abc) == .none)
        #expect(state.secureInputEnded(currentSourceID: abc, context: AppMemoryContext(), slotOfSource: slot) == .none)
    }

    @Test("editing only Program Rules cannot reapply an unchanged website over a trigger")
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
