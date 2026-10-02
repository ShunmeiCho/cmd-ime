import Foundation

/// The half of `AppMemoryTracker` that follows what is in front inside the app: a browser's page
/// (Website Rules) or the program in a terminal's focused pane (Program Rules). Reads, the wait
/// for the first one, pane focus and the decision they lead to.
extension AppMemoryTracker {
    /// A read of the page in front of the browser came back. A result for another pid, an older
    /// generation, an older read or a browser no longer in front is dropped. The first read after
    /// the browser came to the front decides what it waited for; later ones switch only when the
    /// page moves to another rule, to no rule or from no rule to one.
    public mutating func websiteRead(
        _ reading: WebsiteReading,
        actualFrontmostAppID: String? = nil,
        actualBrowserPID: Int32? = nil,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        contextRead(reading, watch: websiteWatch, actualFrontmostAppID: actualFrontmostAppID,
                    actualSurfacePID: actualBrowserPID, currentSourceID: currentSourceID, context: context,
                    slotOfSource: slotOfSource)
    }

    /// The program in the terminal's focused pane was read. Stamps, the first read after the
    /// terminal came to the front and a change of program are handled as for a page, with one
    /// difference: a program without a rule changes nothing once the terminal is in front.
    public mutating func programRead(
        _ reading: ProgramReading,
        actualFrontmostAppID: String? = nil,
        actualTerminalPID: Int32? = nil,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        contextRead(reading, watch: programWatch, actualFrontmostAppID: actualFrontmostAppID,
                    actualSurfacePID: actualTerminalPID, currentSourceID: currentSourceID, context: context,
                    slotOfSource: slotOfSource)
    }

    /// Focus moved to the pane `paneID` of the terminal in front; the notice was received at
    /// `time` (the caller's monotonic clock), which can be well before it is handled here. A
    /// notice for the pane already known to be in focus changes nothing, so a notice that repeats
    /// what a read has said, or the other way round, is harmless. A Program Rule is applied again
    /// every time a pane comes into focus, so a new pane is handled like an activation inside the
    /// terminal: a new generation (reads of the pane just left are stale), a wait for the first
    /// read of the new pane, and the next read decides afresh (`paneChanged`). A trigger whose
    /// first read is still to come stands only when it was confirmed after the notice was
    /// received, that is, in the new pane. A notice for a terminal that is not being read is dropped.
    public mutating func paneFocused(
        pid: Int32,
        paneID: String,
        at time: TimeInterval,
        actualFrontmostAppID: String? = nil,
        actualTerminalPID: Int32? = nil
    ) {
        guard let watch = programWatch, pid == watch.pid,
              actualFrontmostAppID == nil || actualFrontmostAppID == frontmostAppID,
              actualTerminalPID == nil || actualTerminalPID == watch.pid else { return }
        guard paneID != focusedPaneID else {
            // A read moved focus here first and kept a trigger it could not date. The notice
            // dates it: one confirmed before focus moved was pressed in the pane before, so this
            // pane is decided again by its next read.
            let keptATrigger = paneThatKeptATriggerUnjudged == paneID
            paneThatKeptATriggerUnjudged = nil
            guard keptATrigger, lastChoiceAt < time else { return }
            paneChanged(to: paneID, noticeReceivedAt: time)
            activationGeneration += 1
            contextOnlyGeneration = nil
            return
        }
        let triggerWasInTheNewPane = contextOnlyGeneration == activationGeneration && lastChoiceAt >= time
        paneChanged(to: paneID, noticeReceivedAt: time)
        activationGeneration += 1
        contextOnlyGeneration = triggerWasInTheNewPane ? activationGeneration : nil
    }

    /// Another pane is in focus, by a notice or by a read that names it. What differs from an app
    /// coming to the front:
    /// - The program of the pane just left stays known until the new pane is read, so a source
    ///   its rule selected is still kept out of the terminal's memory meanwhile.
    /// - A rule's switch still on its way belongs to the pane just left and is retired.
    /// - A source a password field replaced before the notice was received belongs to the pane
    ///   just left and is not put back here. A read gives no such time, and keeps it.
    /// - A wait that began when the terminal came to the front keeps its fallback.
    mutating func paneChanged(to paneID: String, noticeReceivedAt: TimeInterval?) {
        focusedPaneID = paneID
        paneThatKeptATriggerUnjudged = nil
        isDecisionDeferred = false
        isWebsiteContextStale = true
        if isWebsiteSwitchInFlight {
            retiredSwitchSourceID = retiredSwitchSourceID ?? sourceBeforeRestore
        }
        if let noticeReceivedAt, beforeForcedAt < noticeReceivedAt {
            beforeForced = nil
        }
        if websiteHold == nil {
            websiteHold = WebsiteHold(arrivalSourceID: nil, fallsBackToApp: false)
        }
    }

    mutating func contextRead(
        _ reading: WebsiteReading,
        watch: (pid: Int32, generation: Int)?,
        actualFrontmostAppID: String?,
        actualSurfacePID: Int32?,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole?
    ) -> Restore {
        guard let watch, let appID = frontmostAppID,
              reading.pid == watch.pid, reading.generation == watch.generation,
              reading.sequence > lastReadSequence,
              actualFrontmostAppID == nil || actualFrontmostAppID == appID,
              actualSurfacePID == nil || actualSurfacePID == watch.pid else {
            return .none
        }
        lastReadSequence = reading.sequence
        // A read that names another pane than the one known to be in focus is how a focus change
        // shows when no notice said so; this read is then the new pane's first.
        if frontSurface?.kind == .terminal, let paneID = reading.paneID, paneID != focusedPaneID {
            if focusedPaneID == nil {
                focusedPaneID = paneID
            } else {
                paneChanged(to: paneID, noticeReceivedAt: nil)
                if contextOnlyGeneration == activationGeneration {
                    paneThatKeptATriggerUnjudged = paneID
                }
            }
        }
        var page = reading.context
        if case .rule(let key) = page, ruleTarget(for: key) == nil {
            page = .noRule
        }
        // A page or program first seen under a password field is known but not decided on yet.
        let previous = isWebsiteContextStale || isDecisionDeferred ? nil : websiteContext
        let hold = websiteHold
        websiteHold = nil
        if page != .unknown {
            websiteContext = page
            isWebsiteContextStale = false
        }
        if reading.generation == contextOnlyGeneration {
            if page != .unknown { contextOnlyGeneration = nil }
            return .none
        }
        // A password field in front decides nothing, and takes nothing from what the read was
        // to decide: the wait stays, and with or without one the first read after the password
        // field decides as if nothing had been read (unless `secureInputEnded` decides first).
        guard !context.isSecureInputInFrontmostApp else {
            websiteHold = hold
            if page != .unknown, page != previous {
                isDecisionDeferred = true
            }
            return .none
        }
        if page != .unknown {
            isDecisionDeferred = false
        }
        guard !context.isTriggerPending else { return .none }
        // The pane is read: a switch retired when focus left the last one is settled now. A pane
        // without a rule gets back what was there before it, landed or not; a rule decides below.
        let retired = retiredSwitchSourceID
        if page != .unknown {
            retiredSwitchSourceID = nil
        }
        if page == .noRule, hold?.fallsBackToApp != true, let retired, retired != currentSourceID {
            isWebsiteSwitchInFlight = false
            sourceBeforeRestore = nil
            return .putBack(sourceID: retired)
        }
        if let hold {
            return websiteRestore(page: page, appID: appID, arrivalSourceID: hold.arrivalSourceID ?? currentSourceID,
                                  currentSourceID: currentSourceID, isRestorePending: context.isRestorePending,
                                  fallsBackToApp: hold.fallsBackToApp, slotOfSource: slotOfSource)
        }
        // An unread page that turns out to have no rule changes nothing: the hold already chose.
        guard page != .unknown, page != previous, !(previous == nil && page == .noRule) else { return .none }
        // A page that lost its rule gets the browser's own target. In a terminal a program without
        // a rule changes nothing: only the terminal coming to the front falls back to its target.
        return websiteRestore(page: page, appID: appID, arrivalSourceID: currentSourceID,
                              currentSourceID: currentSourceID, isRestorePending: context.isRestorePending,
                              fallsBackToApp: frontSurface?.kind != .terminal, slotOfSource: slotOfSource)
    }

    /// No read arrived in time after the browser came to the front: its own target applies.
    /// Like a read, the expiry is only a prompt to look: when another app is in front by now (its
    /// activation notice still on its way), the wait is dropped and nothing is selected there.
    public mutating func websiteHoldExpired(
        generation: Int,
        actualFrontmostAppID: String? = nil,
        actualBrowserPID: Int32? = nil,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        contextHoldExpired(generation: generation, kind: .browser, actualFrontmostAppID: actualFrontmostAppID,
                           actualSurfacePID: actualBrowserPID, currentSourceID: currentSourceID, context: context,
                           slotOfSource: slotOfSource)
    }

    /// No read of the program arrived in time after the terminal came to the front: the terminal's
    /// own target applies, under the same checks as `websiteHoldExpired`.
    public mutating func programHoldExpired(
        generation: Int,
        actualFrontmostAppID: String? = nil,
        actualTerminalPID: Int32? = nil,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        contextHoldExpired(generation: generation, kind: .terminal, actualFrontmostAppID: actualFrontmostAppID,
                           actualSurfacePID: actualTerminalPID, currentSourceID: currentSourceID, context: context,
                           slotOfSource: slotOfSource)
    }

    mutating func contextHoldExpired(
        generation: Int,
        kind: SurfaceKind,
        actualFrontmostAppID: String?,
        actualSurfacePID: Int32?,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole?
    ) -> Restore {
        guard generation == activationGeneration, frontSurface?.kind == kind, let hold = websiteHold,
              let appID = frontmostAppID else {
            return .none
        }
        // Under a password field the wait is kept for the first read after it.
        guard !context.isSecureInputInFrontmostApp else { return .none }
        websiteHold = nil
        guard actualFrontmostAppID == nil || actualFrontmostAppID == appID,
              actualSurfacePID == nil || actualSurfacePID == frontSurface?.pid else { return .none }
        guard !context.isTriggerPending else { return .none }
        return websiteRestore(page: .unknown, appID: appID, arrivalSourceID: hold.arrivalSourceID ?? currentSourceID,
                              currentSourceID: currentSourceID, isRestorePending: context.isRestorePending,
                              fallsBackToApp: hold.fallsBackToApp, slotOfSource: slotOfSource)
    }

    /// What the website rule of the page in front selects, nil when the page has no rule.
    var currentPageRuleTarget: AppActivationTarget? {
        guard surfaceWatch != nil, case .rule(let key) = websiteContext else { return nil }
        return ruleTarget(for: key)
    }

    /// Whether `next` changes the rules the app in front is read against. Rules of the other
    /// kind changing must not make the page or program in front be decided again: that would
    /// apply its rule over a choice the user has made since.
    func rulesOfTheSurfaceInFrontChange(to next: AppActivationSettings) -> Bool {
        switch frontSurface?.kind {
        case .browser:
            next.websiteRules != settings.websiteRules
        case .terminal:
            next.programRules != settings.programRules || next.programRulesPaused != settings.programRulesPaused
        case nil:
            false
        }
    }

    /// What the rule named `key` selects in the app in front: a website rule by its domain in a
    /// browser, a Program Rule by its name in a terminal. Nil when there is no such rule.
    func ruleTarget(for key: String) -> AppActivationTarget? {
        frontSurface?.kind == .terminal ? settings.programTarget(forRule: key) : settings.websiteTarget(forRule: key)
    }

    func isKeepAsIsRule(_ key: String) -> Bool {
        frontSurface?.kind == .terminal ? settings.programTargets[key] == .keepAsIs : settings.websiteTargets[key] == .keepAsIs
    }

    /// The page in front is under a website rule that still exists.
    var isOnRuledPage: Bool {
        guard surfaceWatch != nil, case .rule(let key) = websiteContext else { return false }
        return ruleTarget(for: key) != nil
    }

    /// The terminal in front is being read and the program of the pane in focus is not known yet
    /// (never read, or the pane changed since).
    var isProgramUndecided: Bool {
        programWatch != nil && (websiteContext == nil || isWebsiteContextStale)
    }

    var isOnKeepAsIsSite: Bool {
        guard surfaceWatch != nil, case .rule(let key) = websiteContext else { return false }
        return isKeepAsIsRule(key)
    }

    /// The page's rule when it has one, else the browser's own target, against what is selected.
    mutating func websiteRestore(
        page: WebsiteContext,
        appID: String,
        arrivalSourceID: String?,
        currentSourceID: String?,
        isRestorePending: Bool,
        fallsBackToApp: Bool,
        slotOfSource: (String) -> InputRole?
    ) -> Restore {
        // The source to put back belongs to the restore still on its way; one kept from an earlier,
        // finished restore in this browser is stale. While one is on its way, the current source
        // is its intermediate step, so what was there before it is what the new page arrives with.
        if !isRestorePending {
            sourceBeforeRestore = nil
        }
        let pendingBefore = sourceBeforeRestore
        let arrivalSourceID = pendingBefore ?? arrivalSourceID
        let ruleTarget: AppActivationTarget? = {
            guard case .rule(let key) = page else { return nil }
            return ruleTarget(for: key)
        }()
        let ownTarget = fallsBackToApp ? settings.target(for: appID, rememberedSourceID: remembered[appID]) : .none
        let target = ruleTarget ?? ownTarget
        switch target {
        case .source(let sourceID) where sourceID != arrivalSourceID:
            sourceBeforeRestore = sourceBeforeRestore ?? currentSourceID
            isWebsiteSwitchInFlight = ruleTarget != nil
            return .select(sourceID: sourceID)
        case .slot(let slot) where arrivalSourceID.flatMap(slotOfSource) != slot:
            sourceBeforeRestore = sourceBeforeRestore ?? currentSourceID
            isWebsiteSwitchInFlight = ruleTarget != nil
            return .selectSlot(slot)
        default:
            // Nothing to select here, but a switch asked for the page just left must not land on
            // this one: put back what was there before it, as leaving an app does.
            guard let pendingBefore else { return .none }
            isWebsiteSwitchInFlight = false
            return .putBack(sourceID: pendingBefore)
        }
    }
}
