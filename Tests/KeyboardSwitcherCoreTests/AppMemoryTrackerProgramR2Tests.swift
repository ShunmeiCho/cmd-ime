import Testing
@testable import KeyboardSwitcherCore

/// Orderings found by the second review of Program Rules (R2): each failed before its fix.
struct AppMemoryTrackerProgramR2OrderingTests {
    private let terminal = "com.mitchellh.ghostty"
    private let pid: Int32 = 701
    private let abc = "com.apple.keylayout.ABC"
    private let chinese = "com.apple.inputmethod.SCIM.ITABC"
    private let japanese = "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese"
    private let quiet = AppMemoryContext()
    private let pending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)
    private let secure = AppMemoryContext(isSecureInputInFrontmostApp: true)

    private func make() -> AppMemoryTracker {
        AppMemoryTracker(ownAppID: "cmdime", frontmostAppID: "editor",
            settings: AppActivationSettings(remembersPerApp: true, restoresAfterPasswordField: true,
                slotIDs: [.english, .chinese, .japanese],
                programRules: [ProgramRule(name: "claude", target: .slot(.chinese)),
                               ProgramRule(name: "zsh", target: .slot(.english))]))
    }

    private func slot(_ id: String) -> InputRole? {
        [abc: InputRole.english, chinese: .chinese, japanese: .japanese][id]
    }

    private func activate(_ state: inout AppMemoryTracker) {
        _ = state.appActivated(terminal, currentSourceID: abc, context: quiet,
                               terminalPID: pid, slotOfSource: slot)
    }

    private func reading(_ state: AppMemoryTracker, _ sequence: Int, _ context: ProgramContext) -> ProgramReading {
        ProgramReading(pid: pid, generation: state.activationGeneration, sequence: sequence, context: context)
    }

    private func read(_ state: inout AppMemoryTracker, _ sequence: Int, _ program: ProgramContext,
                      source: String, context: AppMemoryContext = AppMemoryContext()) -> AppMemoryTracker.Restore {
        state.programRead(reading(state, sequence, program), actualFrontmostAppID: terminal,
            actualTerminalPID: pid, currentSourceID: source, context: context, slotOfSource: slot)
    }

    @Test("a hand choice during the activation hold invalidates the read already in flight")
    func manualChoiceDuringActivationHold() {
        var state = make()
        activate(&state)
        let inFlight = reading(state, 1, .rule("claude"))
        state.sourceChanged(to: japanese, context: quiet)
        let result = state.programRead(inFlight, actualFrontmostAppID: terminal, actualTerminalPID: pid,
            currentSourceID: japanese, context: quiet, slotOfSource: slot)
        #expect(result == .none)
    }

    @Test("a hand choice after a program starts beats the old generation's in-flight read")
    func manualChoiceAcrossProgramRead() {
        var state = make()
        activate(&state)
        #expect(read(&state, 1, .rule("zsh"), source: abc) == .none)
        // claude has physically started; this matching read is awaiting main-thread delivery.
        let inFlight = reading(state, 2, .rule("claude"))
        state.sourceChanged(to: japanese, context: quiet)
        let result = state.programRead(inFlight, actualFrontmostAppID: terminal, actualTerminalPID: pid,
            currentSourceID: japanese, context: quiet, slotOfSource: slot)
        #expect(result == .none)
    }

    @Test("a trigger in A cannot suppress B's rule permanently when its own first read is late")
    func triggerBarrierMustBelongToItsPane() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese, context: pending)
        state.triggerConfirmed(sourceID: japanese, actualFrontmostAppID: terminal,
            context: AppMemoryContext(isOwnSwitchPending: true), terminalPID: pid)
        // The user really moves A -> B after the trigger; this is not a delayed notice for A.
        state.paneFocused(pid: pid, at: 1, actualFrontmostAppID: terminal, actualTerminalPID: pid)
        let first = read(&state, 2, .rule("zsh"), source: japanese)
        let expiry = state.programHoldExpired(generation: state.activationGeneration,
            currentSourceID: japanese, context: quiet, slotOfSource: slot)
        let second = read(&state, 3, .rule("zsh"), source: japanese)
        let third = read(&state, 4, .rule("zsh"), source: japanese)
        let results = [first, expiry, second, third]
        #expect(results.contains(.selectSlot(.english)))
    }

    @Test("a password in the new pane keeps its put-back when the pane's focus notice is delayed")
    func newPanePasswordBeforeDelayedFocus() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .noRule, source: abc)
        state.sourceChanged(to: chinese, context: quiet)
        // Physical B focus happens, then B's password field forces ASCII; its notice is late.
        state.sourceChanged(to: abc, context: secure)
        #expect(state.isAwaitingSecureInputEnd)
        state.paneFocused(pid: pid, at: 1, actualFrontmostAppID: terminal, actualTerminalPID: pid)
        _ = read(&state, 2, .noRule, source: abc, context: secure)
        let result = state.secureInputEnded(currentSourceID: abc, context: quiet)
        #expect(result == .select(sourceID: chinese))
    }

    @Test("a failed recheck must not discard a password restore in a pane that never moved")
    func failedSecondPaneQueryMustNotBecomeFocus() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .noRule, source: abc)
        state.sourceChanged(to: chinese, context: quiet)
        state.sourceChanged(to: abc, context: secure)
        // Source-traced ProgramWatcher branch: first pane=P; second pane=nil -> focusMovedMeanwhile.
        let firstPane = "P"
        let secondPane: String? = nil
        if secondPane != firstPane {
            state.paneFocused(pid: pid, at: 1, actualFrontmostAppID: terminal, actualTerminalPID: pid)
        }
        let result = state.secureInputEnded(currentSourceID: abc, context: quiet)
        #expect(result == .select(sourceID: chinese))
    }

    @Test("a delivered old-pane rule cannot remain in the new unruled pane after it confirms")
    func oldPaneRuleConfirmedBeforeNewRead() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .rule("zsh"), source: abc)
        let oldPane = reading(state, 2, .rule("claude"))
        // Both watcher pane queries observed A; B physically focuses before main accepts A.
        #expect(state.programRead(oldPane, currentSourceID: abc, context: quiet, slotOfSource: slot)
            == .selectSlot(.chinese))
        state.paneFocused(pid: pid, at: 1)
        // This can confirm within the watcher's 100 ms focus settle, before B's read arrives.
        state.switchConfirmed(sourceID: chinese, context: pending)
        let result = read(&state, 3, .noRule, source: chinese)
        #expect(result == .putBack(sourceID: abc))
    }
}

/// Behaviour the second review checked and found right; kept so it stays that way.
struct AppMemoryTrackerProgramR2KeptTests {
    private let terminal = "com.mitchellh.ghostty"
    private let pid: Int32 = 701
    private let abc = "abc"
    private let chinese = "chinese"
    private let japanese = "japanese"
    private let quiet = AppMemoryContext()
    private let pending = AppMemoryContext(isOwnSwitchPending: true, isRestorePending: true)

    private func make() -> AppMemoryTracker {
        AppMemoryTracker(ownAppID: "cmdime", frontmostAppID: "editor",
            settings: AppActivationSettings(remembersPerApp: true, restoresAfterPasswordField: true,
                slotIDs: [.english, .chinese, .japanese],
                programRules: [ProgramRule(name: "claude", target: .slot(.chinese)),
                               ProgramRule(name: "zsh", target: .slot(.english))]))
    }
    private func slot(_ id: String) -> InputRole? {
        [abc: InputRole.english, chinese: .chinese, japanese: .japanese][id]
    }
    private func activate(_ state: inout AppMemoryTracker) {
        _ = state.appActivated(terminal, currentSourceID: abc, context: quiet,
            terminalPID: pid, slotOfSource: slot)
    }
    private func read(_ state: inout AppMemoryTracker, _ sequence: Int, _ program: ProgramContext,
                      source: String, context: AppMemoryContext = AppMemoryContext()) -> AppMemoryTracker.Restore {
        state.programRead(ProgramReading(pid: pid, generation: state.activationGeneration,
            sequence: sequence, context: program), actualFrontmostAppID: terminal,
            actualTerminalPID: pid, currentSourceID: source, context: context, slotOfSource: slot)
    }

    @Test("a confirmed trigger invalidates the previously matched program read")
    func oldReadCannotOverrideTrigger() {
        var state = make()
        activate(&state)
        let old = ProgramReading(pid: pid, generation: state.activationGeneration, sequence: 1, context: .rule("claude"))
        state.triggerConfirmed(sourceID: japanese, actualFrontmostAppID: terminal,
            context: AppMemoryContext(isOwnSwitchPending: true), terminalPID: pid)
        #expect(state.programRead(old, currentSourceID: japanese, context: quiet, slotOfSource: slot) == .none)
        #expect(read(&state, 2, .rule("claude"), source: japanese) == .none)
    }

    @Test("a stable ruled program preserves a hand choice without recording it as app memory")
    func stableRuledProgramManualChoice() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese, context: pending)
        state.sourceChanged(to: japanese, context: quiet)
        #expect(read(&state, 2, .rule("claude"), source: japanese) == .none)
        #expect(state.rememberedSourceID(for: terminal) == nil)
    }

    @Test("a hand choice in a known unruled program remains terminal app memory")
    func unruledProgramManualChoice() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .noRule, source: abc)
        state.sourceChanged(to: japanese, context: quiet)
        #expect(read(&state, 2, .noRule, source: japanese) == .none)
        _ = state.appActivated("editor", currentSourceID: japanese, context: quiet)
        #expect(state.rememberedSourceID(for: terminal) == japanese)
    }

    @Test("expiry of a pane hold retires only a still-pending switch")
    func paneHoldExpiry() {
        for isPending in [false, true] {
            var state = make()
            activate(&state)
            _ = read(&state, 1, .rule("claude"), source: abc)
            if !isPending { state.switchConfirmed(sourceID: chinese, context: pending) }
            state.paneFocused(pid: pid, at: 1)
            let result = state.programHoldExpired(generation: state.activationGeneration,
                currentSourceID: isPending ? abc : chinese, context: isPending ? pending : quiet, slotOfSource: slot)
            #expect(result == (isPending ? .putBack(sourceID: abc) : .none))
            #expect(!state.isWebsiteHoldWaiting)
        }
    }

    @Test("pausing program rules during a pane hold retires a pending rule switch")
    func pauseDuringPaneHold() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .rule("claude"), source: abc)
        state.paneFocused(pid: pid, at: 1)
        var settings = state.settings
        settings.programRulesPaused = true
        #expect(state.update(settings: settings, context: pending) == .putBack(sourceID: abc))
        #expect(state.programWatch == nil)
        #expect(!state.isWebsiteHoldWaiting)
    }

    @Test("leaving and returning during a pane hold rejects its old reading")
    func paneHoldRoundTrip() {
        var state = make()
        activate(&state)
        _ = read(&state, 1, .rule("claude"), source: abc)
        state.switchConfirmed(sourceID: chinese, context: pending)
        state.paneFocused(pid: pid, at: 1)
        let old = ProgramReading(pid: pid, generation: state.activationGeneration, sequence: 2, context: .rule("zsh"))
        _ = state.appActivated("editor", currentSourceID: chinese, context: quiet)
        activate(&state)
        #expect(state.programRead(old, currentSourceID: abc, context: quiet, slotOfSource: slot) == .none)
        #expect(state.isWebsiteHoldWaiting)
        #expect(read(&state, 3, .rule("claude"), source: abc) == .selectSlot(.chinese))
    }

    @Test("rules updated with no front surface cannot reuse an old watch generation")
    func settingsOutsideSurface() {
        var state = make()
        activate(&state)
        let old = ProgramReading(pid: pid, generation: state.activationGeneration, sequence: 1, context: .rule("claude"))
        _ = state.appActivated("editor", currentSourceID: abc, context: quiet)
        var settings = state.settings
        settings.programRules = [ProgramRule(name: "claude", target: .slot(.japanese))]
        _ = state.update(settings: settings)
        activate(&state)
        #expect(state.programRead(old, currentSourceID: abc, context: quiet, slotOfSource: slot) == .none)
        #expect(read(&state, 2, .rule("claude"), source: abc) == .selectSlot(.japanese))
    }
}
