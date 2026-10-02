import Foundation

/// What was true when an app-memory event happened, read by the caller at that moment.
public struct AppMemoryContext: Equatable, Sendable {
    /// A switch CmdIME requested has not been confirmed or abandoned yet. Changes seen
    /// meanwhile are intermediate (the Kana prelude, a retry) and are not the user's choice.
    public var isOwnSwitchPending: Bool
    /// The pending switch is a restore this tracker asked for, not a trigger the user pressed.
    public var isRestorePending: Bool
    /// The app in front holds secure keyboard input (a password field is focused), so macOS may
    /// have forced an ASCII source that the user never chose. The holder the system reports is the
    /// app that was in front when secure input was turned on, so a background process that turns
    /// it on is charged to that one app; that fails safe and is narrower than a system-wide gate.
    public var isSecureInputInFrontmostApp: Bool

    /// A switch the user asked for with a trigger is still in flight. An app coming to the front
    /// meanwhile must not start an automatic switch: it would supersede the trigger.
    public var isTriggerPending: Bool {
        isOwnSwitchPending && !isRestorePending
    }

    public init(
        isOwnSwitchPending: Bool = false,
        isRestorePending: Bool = false,
        isSecureInputInFrontmostApp: Bool = false
    ) {
        self.isOwnSwitchPending = isOwnSwitchPending
        self.isRestorePending = isRestorePending
        self.isSecureInputInFrontmostApp = isSecureInputInFrontmostApp
    }
}

/// App Memory and App Rules (see CONTEXT.md) as one state machine: the input source last
/// active while each app was in front, what to select when an app comes back (a rule, the
/// remembered source or the default slot, per `AppActivationSettings`), and the source to put back
/// after a password field. Keyed by an app id (bundle id, or the executable path for apps without
/// one); held in memory only.
public struct AppMemoryTracker: Equatable, Sendable {
    public enum Restore: Equatable, Sendable {
        case none
        /// Bring back a concrete source (remembered, or replaced by a password field); worth
        /// showing the indicator for.
        case select(sourceID: String)
        /// Select a slot an App Rule or the default names; worth showing the indicator for.
        case selectSlot(InputRole)
        /// A restore meant for an app the user already left is still on its way. Put back the
        /// source that was there before it, silently, so it does not land in this app.
        case putBack(sourceID: String)
    }

    private struct ForcedSource: Equatable, Sendable {
        let appID: String
        let sourceID: String
    }

    /// CmdIME's own id: its settings window is never an app to remember or restore.
    public let ownAppID: String?
    public private(set) var frontmostAppID: String?
    public private(set) var settings: AppActivationSettings
    private var remembered: [String: String] = [:]
    /// The source macOS forced on the app in front while secure input was on. It is still
    /// current after the password field is left, and must not become that app's memory.
    private var forced: ForcedSource?
    /// The source that was current in the app in front just before macOS forced one, to put
    /// back when secure input ends there.
    private var beforeForced: ForcedSource?
    /// The last source seen by any route, so the one a password field replaced is known.
    private var lastSourceID: String?
    /// The source that was current before the pending restore, kept while that restore is pending.
    private var sourceBeforeRestore: String?

    /// Counts every change of `frontmostAppID` and of the website rules. A website read carries the
    /// value it was made under, so a result for a browser already left, left and come back to, or
    /// matched against rules since replaced is told apart. A caller that builds a new tracker
    /// passes a value above the old one's, so numbers are never reused.
    public private(set) var activationGeneration: Int
    /// The app in front when it is one the caller can read into: a browser (its page) or a
    /// terminal (the program in its focused pane). A program goes down the same path as a page, so
    /// below "page" and "website" also stand for a terminal's program and its Program Rule; where
    /// the two differ, the code asks `frontSurface.kind`.
    private var frontSurface: Surface?
    /// The page in front of that browser, once read; `.unknown` never replaces a known one.
    private var websiteContext: WebsiteContext?
    /// The browser came to the front and its own target waits for the first read of the page.
    private var websiteHold: WebsiteHold?
    private var lastReadSequence = Int.min
    /// The generation that began with the user's own choice of source (a trigger, or by hand): the
    /// first read of it only records the page and switches nothing. Reads that were on their way
    /// when the user chose carry an older generation and are dropped, so none can straddle a choice.
    private var contextOnlyGeneration: Int?
    /// The website rules changed since the page was read: it is kept for what gets remembered, but
    /// the next read decides afresh instead of counting as "the same page".
    private var isWebsiteContextStale = false
    /// The switch on its way was asked for by a website rule and must not become the browser's memory.
    private var isWebsiteSwitchInFlight = false

    private enum SurfaceKind: Equatable, Sendable {
        case browser
        case terminal
    }

    private struct Surface: Equatable, Sendable {
        let kind: SurfaceKind
        let pid: Int32

        /// A browser wins when a caller names both, which no caller does.
        init?(browserPID: Int32?, terminalPID: Int32?) {
            if let browserPID {
                self.init(kind: .browser, pid: browserPID)
            } else if let terminalPID {
                self.init(kind: .terminal, pid: terminalPID)
            } else {
                return nil
            }
        }

        private init(kind: SurfaceKind, pid: Int32) {
            self.kind = kind
            self.pid = pid
        }
    }

    /// The pane of the terminal in front that is in focus, as far as a focus notice or a read has
    /// said. What the tracker knows about a program, a wait or a choice belongs to this pane; a
    /// notice or a read naming another pane is a focus change, one naming this pane is not.
    private var focusedPaneID: String?
    /// When the trigger that set `contextOnlyGeneration` was confirmed (the caller's monotonic
    /// clock). A focus notice carries when it was received, which can be well before it is
    /// handled: the trigger was pressed in the new pane only if it came after that.
    private var lastChoiceAt: TimeInterval = 0
    /// When `beforeForced` was recorded, compared the same way: a password field of the pane
    /// just left does not get its source put back into the new pane.
    private var beforeForcedAt: TimeInterval = 0
    /// The source that was current before a rule's switch that was still on its way when focus
    /// left its pane. The next pane read as having no rule gets it back, whether or not the switch
    /// has landed since; a rule, a trigger or a change of source by hand ends it.
    private var retiredSwitchSourceID: String?
    /// The pane a read moved focus to while a trigger's first read was still to come. A read
    /// carries no time, so the trigger was kept; that pane's own notice, when it comes, says
    /// when focus moved and settles whether the trigger was pressed there.
    private var paneThatKeptATriggerUnjudged: String?

    private struct WebsiteHold: Equatable, Sendable {
        /// What the user arrived with, to compare the decided target against. A pane that came
        /// into focus has none: the source at the read is what its rule is compared against.
        let arrivalSourceID: String?
        /// The app came to the front: without a rule for the page or program, its own target
        /// applies. False for a pane that came into focus inside a terminal already in front,
        /// where a program without a rule changes nothing.
        let fallsBackToApp: Bool
    }

    /// `frontBrowserPID` when the app in front as following starts is a browser, `frontTerminalPID`
    /// when it is a terminal: its page or program is read from then on, but nothing waits or is
    /// selected for an app that was already in front.
    public init(
        ownAppID: String?,
        frontmostAppID: String? = nil,
        frontBrowserPID: Int32? = nil,
        frontTerminalPID: Int32? = nil,
        activationGeneration: Int = 0,
        settings: AppActivationSettings = AppActivationSettings(remembersPerApp: true)
    ) {
        self.activationGeneration = activationGeneration
        self.ownAppID = ownAppID
        self.frontmostAppID = frontmostAppID
        self.frontSurface = frontmostAppID == nil ? nil : Surface(browserPID: frontBrowserPID, terminalPID: frontTerminalPID)
        self.settings = settings
    }

    public func rememberedSourceID(for appID: String) -> String? {
        remembered[appID]
    }

    /// Every app with a remembered source, by app id.
    public var rememberedSources: [String: String] {
        remembered
    }

    /// Secure input is on in the app in front after macOS replaced its source, and the replaced
    /// one should come back once it ends: the caller watches for that and calls `secureInputEnded`.
    public var isAwaitingSecureInputEnd: Bool {
        settings.restoresAfterPasswordField && beforeForced != nil
    }

    /// The browser whose page in front should be read now, with the generation to stamp reads
    /// with. Nil when the app in front is not a browser, there is no website rule, or the browser
    /// is "Keep as is".
    public var websiteWatch: (pid: Int32, generation: Int)? {
        guard let surface = frontSurface, surface.kind == .browser, let appID = frontmostAppID, appID != ownAppID,
              settings.watchesWebsites(in: appID) else { return nil }
        return (surface.pid, activationGeneration)
    }

    /// The terminal whose focused pane should be asked for its program now, with the generation to
    /// stamp reads with. Nil when the app in front is not a terminal, there is no Program Rule,
    /// the rules are paused, or the terminal is "Keep as is".
    public var programWatch: (pid: Int32, generation: Int)? {
        guard let surface = frontSurface, surface.kind == .terminal, let appID = frontmostAppID, appID != ownAppID,
              settings.watchesPrograms(in: appID) else { return nil }
        return (surface.pid, activationGeneration)
    }

    /// Whichever of the two is being read.
    private var surfaceWatch: (pid: Int32, generation: Int)? {
        websiteWatch ?? programWatch
    }

    /// The browser's own target is waiting for the first read of its page (or the terminal's for
    /// its program); the caller ends the wait with `websiteHoldExpired` or `programHoldExpired`
    /// when no read arrives in time.
    public var isWebsiteHoldWaiting: Bool {
        websiteHold != nil
    }

    /// New settings from the config. Memory of an app that no longer uses it is dropped, so what
    /// the Apps page lists is what can be restored.
    /// `context` says what the monitor is doing right now: only a restore still pending there can
    /// be put back, never a trigger that has since replaced it.
    @discardableResult
    public mutating func update(settings: AppActivationSettings, context: AppMemoryContext = AppMemoryContext()) -> Restore {
        let pageTargetBefore = currentPageRuleTarget
        if rulesOfTheSurfaceInFrontChange(to: settings) {
            // The page is read again against the new rules; a read matched against the old ones is
            // stale. What the page was stays known until then, so its source is still kept out of
            // the browser's memory.
            isWebsiteContextStale = true
            // The user's choice still waits for its first read: it waits in the new generation.
            if contextOnlyGeneration == activationGeneration {
                contextOnlyGeneration = activationGeneration + 1
            }
            activationGeneration += 1
        }
        self.settings = settings
        remembered = remembered.filter { settings.usesMemory(for: $0.key) }
        if surfaceWatch == nil {
            websiteHold = nil
        }
        // A website switch still on its way that the new settings no longer ask for (the browser
        // is not read any more, or the page's rule changed or went) is put back, not left to land.
        guard isWebsiteSwitchInFlight, surfaceWatch == nil || currentPageRuleTarget != pageTargetBefore else {
            return .none
        }
        isWebsiteSwitchInFlight = false
        // The monitor decides what is really pending: with a trigger there instead, the website
        // switch is already retired and nothing is put back over the user's choice.
        guard context.isRestorePending else { return .none }
        defer { sourceBeforeRestore = nil }
        return sourceBeforeRestore.map { .putBack(sourceID: $0) } ?? .none
    }

    /// The selected input source changed while `frontmostAppID` was in front.
    public mutating func sourceChanged(to sourceID: String, context: AppMemoryContext, at time: TimeInterval = 0) {
        let previousSourceID = lastSourceID
        lastSourceID = sourceID
        // Checked before the pending guard: a source forced while CmdIME's own restore is on its
        // way must still be marked, or it becomes the app's memory once secure input ends.
        if context.isSecureInputInFrontmostApp {
            markForced(sourceID, replacing: previousSourceID, at: time)
            return
        }
        guard !context.isOwnSwitchPending else { return }
        // macOS repeats the current source on focus changes; the forced one repeated is not a choice.
        guard !isForced(sourceID, in: frontmostAppID) else { return }
        forced = nil
        beforeForced = nil
        // The user chose by hand before the page was read: that choice stands. macOS repeating
        // the current source on a focus change is not a choice. In a terminal only a trigger is
        // one: a multiplexer selects ASCII for its prefix key and puts the source back around a
        // pane switch, the two notices arrive on either side of the focus notice, and nothing in
        // them tells that round trip from a switch by hand. A switch by hand still stands while
        // the pane and its program stay the same, and it ends a retired switch's put-back.
        if sourceID != previousSourceID {
            if frontSurface?.kind == .terminal {
                retiredSwitchSourceID = nil
            } else {
                userChoseSource(at: time)
            }
        }
        // What a pane not yet read holds may be under a rule: nothing is remembered until it is known.
        guard !isOnRuledPage, !isProgramUndecided else { return }
        remember(sourceID, for: frontmostAppID)
    }

    /// A switch CmdIME made was confirmed. Changes are ignored while one is pending, so the
    /// confirmed target is what gets remembered for the app in front, unless that app holds
    /// secure input, where nothing is remembered.
    public mutating func switchConfirmed(sourceID: String, context: AppMemoryContext) {
        lastSourceID = sourceID
        let wasAskedByWebsiteRule = isWebsiteSwitchInFlight
        isWebsiteSwitchInFlight = false
        guard !context.isSecureInputInFrontmostApp else { return }
        forced = nil
        beforeForced = nil
        // A browser's memory holds what was used on pages without a rule only, and a terminal's
        // nothing from a pane whose program is not known yet.
        guard !wasAskedByWebsiteRule, !isOnRuledPage, !isProgramUndecided else { return }
        remember(sourceID, for: frontmostAppID)
    }

    /// A switch the user asked for with a trigger was confirmed while `actualFrontmostAppID` is in
    /// front. The activation notification for that app can still be on its way: without this, it
    /// would arrive after the user's choice, restore over it and file the chosen source as the
    /// previous app's memory. So the activation is taken here first, with trigger semantics (no
    /// automatic switch, nothing remembered for the app left, whose memory already holds its last
    /// source), and the late notification then finds the app already in front and does nothing.
    public mutating func triggerConfirmed(
        sourceID: String,
        actualFrontmostAppID: String?,
        isRegularApp: Bool = true,
        context: AppMemoryContext,
        browserPID: Int32? = nil,
        terminalPID: Int32? = nil,
        at time: TimeInterval = 0
    ) {
        let surface = Surface(browserPID: browserPID, terminalPID: terminalPID)
        if let actual = actualFrontmostAppID, !isInFront(actual, surface: surface),
           isRegularApp || actual == ownAppID {
            frontmostChanged(to: actual, surface: surface)
            forced = nil
            beforeForced = nil
            sourceBeforeRestore = nil
        }
        // The trigger is the user's choice: it ends a wait for the page and replaces a website switch.
        userChoseSource(at: time)
        isWebsiteSwitchInFlight = false
        switchConfirmed(sourceID: sourceID, context: context)
    }

    /// Secure input ended while `frontmostAppID` stayed in front. If the source is still the one
    /// macOS forced, says to select the one it replaced. In a terminal, a pane whose program is
    /// known to have a slot rule gets that slot instead: the rule is what the pane is for. A pane
    /// not read yet says nothing about a rule (what is known belongs to the pane just left), so
    /// there the replaced source comes back.
    public mutating func secureInputEnded(
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        guard let before = beforeForced, let forced else { return .none }
        beforeForced = nil
        guard settings.restoresAfterPasswordField, !isOnKeepAsIsSite,
              !context.isSecureInputInFrontmostApp, !context.isOwnSwitchPending,
              before.appID == frontmostAppID, forced.appID == frontmostAppID,
              let currentSourceID, currentSourceID == forced.sourceID,
              before.sourceID != currentSourceID else {
            return .none
        }
        // Either way the pane's source is decided here: a wait kept through the password field
        // and a switch retired from the pane before have nothing left to do.
        websiteHold = nil
        retiredSwitchSourceID = nil
        if frontSurface?.kind == .terminal, !isWebsiteContextStale, case .slot(let slot)? = currentPageRuleTarget {
            guard slotOfSource(currentSourceID) != slot else { return .none }
            isWebsiteSwitchInFlight = true
            return .selectSlot(slot)
        }
        return .select(sourceID: before.sourceID)
    }

    /// `appID` came to the front. Remembers `currentSourceID` for the app being left, since a
    /// change notification can arrive late or not at all, then says what to select, if anything.
    /// `slotOfSource` names the slot a source belongs to, so a slot target already in place is left.
    /// An app that is not a regular app (a menu bar agent, or a system alert such as
    /// UserNotificationCenter) is not somewhere the user types: its activation is ignored, so
    /// nothing is remembered for it and a change made meanwhile stays with the app underneath.
    /// CmdIME itself always counts, whatever its activation policy at that moment.
    ///
    /// An activation notice is a prompt to look, not a record of what is in front: notices can
    /// queue up behind other main-thread work. With `actualFrontmostAppID` (the app that owns the
    /// menu bar when the notice is handled) the tracker reconciles to that app instead of the one
    /// named in the notice; `isRegularApp` then describes that app. A late notice for an app
    /// already left becomes a no-op, so it cannot undo a trigger confirmed since; a round trip
    /// that completed before any of its notices was handled reads as never having left.
    public mutating func appActivated(
        _ noticedAppID: String,
        isRegularApp: Bool = true,
        currentSourceID: String?,
        context: AppMemoryContext,
        actualFrontmostAppID: String? = nil,
        browserPID: Int32? = nil,
        terminalPID: Int32? = nil,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        let surface = Surface(browserPID: browserPID, terminalPID: terminalPID)
        let appID = actualFrontmostAppID ?? noticedAppID
        guard isRegularApp || appID == ownAppID else { return .none }
        // A browser is who it is by app id and process: a second instance of the same browser (another
        // profile) coming forward is an activation like any other, with its own pages, its own wait
        // and the same retiring of a switch still on its way.
        guard !isInFront(appID, surface: surface) else { return .none }
        if !context.isRestorePending {
            sourceBeforeRestore = nil
        }
        // Leaving a browser from a page under a website rule records nothing for the browser.
        if !context.isOwnSwitchPending, !context.isSecureInputInFrontmostApp, !isOnRuledPage, !isProgramUndecided,
           let currentSourceID, !isForced(currentSourceID, in: frontmostAppID) {
            remember(currentSourceID, for: frontmostAppID)
        }
        frontmostChanged(to: appID, surface: surface)
        lastSourceID = currentSourceID ?? lastSourceID
        beforeForced = nil
        // An app that holds secure input as it comes to the front may have had its source forced
        // before this call, or kept the ASCII source it arrived with; neither is a choice.
        forced = context.isSecureInputInFrontmostApp
            ? currentSourceID.map { ForcedSource(appID: appID, sourceID: $0) }
            : nil
        let pendingBefore = context.isRestorePending ? sourceBeforeRestore : nil
        // While a restore is pending, the current source is its intermediate step (the source
        // a Kana key brought in), not what the user arrived with.
        let arrivalSourceID = pendingBefore ?? currentSourceID
        let canRestore = appID != ownAppID && !context.isSecureInputInFrontmostApp && !context.isTriggerPending
        // A browser with website rules waits for its page to be read before anything is selected:
        // the page's rule, or else the browser's own target, is decided once by `websiteRead` or
        // `websiteHoldExpired`. A trigger in flight is the user's choice, so the first read after
        // it only records the page.
        let holdsForWebsite = canRestore && surfaceWatch != nil
        if holdsForWebsite {
            websiteHold = WebsiteHold(arrivalSourceID: arrivalSourceID, fallsBackToApp: true)
        } else if context.isTriggerPending, surfaceWatch != nil {
            contextOnlyGeneration = activationGeneration
        }
        let target = canRestore && !holdsForWebsite
            ? settings.target(for: appID, rememberedSourceID: remembered[appID])
            : .none
        switch target {
        case .source(let sourceID) where sourceID != arrivalSourceID:
            sourceBeforeRestore = sourceBeforeRestore ?? currentSourceID
            return .select(sourceID: sourceID)
        case .slot(let slot) where arrivalSourceID.flatMap(slotOfSource) != slot:
            sourceBeforeRestore = sourceBeforeRestore ?? currentSourceID
            return .selectSlot(slot)
        default:
            break
        }
        // Never restore into CmdIME, a password field or over a trigger in flight, but still
        // retire a restore meant for the app just left.
        if let pendingBefore {
            return .putBack(sourceID: pendingBefore)
        }
        return .none
    }

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
    private mutating func paneChanged(to paneID: String, noticeReceivedAt: TimeInterval?) {
        focusedPaneID = paneID
        paneThatKeptATriggerUnjudged = nil
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

    private mutating func contextRead(
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
        let previous = isWebsiteContextStale ? nil : websiteContext
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
        // to decide: the wait stays for the first read after it (or for `secureInputEnded`).
        guard !context.isSecureInputInFrontmostApp else {
            websiteHold = hold
            return .none
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

    private mutating func contextHoldExpired(
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

    public mutating func forget(_ appID: String) {
        remembered[appID] = nil
    }

    public mutating func forgetAll() {
        remembered.removeAll()
        forced = nil
        beforeForced = nil
        sourceBeforeRestore = nil
    }

    private mutating func markForced(_ sourceID: String, replacing previousSourceID: String?, at time: TimeInterval) {
        guard let appID = frontmostAppID else {
            forced = nil
            return
        }
        // Only the first forced change in this app knows what the user had; repeats keep it.
        if settings.leavesSourceAlone(in: appID) || isOnKeepAsIsSite {
            beforeForced = nil
        } else if forced?.appID != appID {
            beforeForced = previousSourceID.flatMap { previous in
                previous == sourceID ? nil : ForcedSource(appID: appID, sourceID: previous)
            }
            beforeForcedAt = time
        }
        forced = ForcedSource(appID: appID, sourceID: sourceID)
    }

    private func isForced(_ sourceID: String, in appID: String?) -> Bool {
        guard let forced, let appID else { return false }
        return forced == ForcedSource(appID: appID, sourceID: sourceID)
    }

    /// Whether `appID` is the app already in front. For a browser the process counts too; a caller
    /// that passes no pid (not a browser) is compared by app id alone.
    private func isInFront(_ appID: String, surface: Surface?) -> Bool {
        appID == frontmostAppID && (surface == nil || surface == frontSurface)
    }

    private mutating func frontmostChanged(to appID: String, surface: Surface?) {
        frontmostAppID = appID
        activationGeneration += 1
        frontSurface = surface
        websiteContext = nil
        isWebsiteContextStale = false
        websiteHold = nil
        contextOnlyGeneration = nil
        focusedPaneID = nil
        retiredSwitchSourceID = nil
        paneThatKeptATriggerUnjudged = nil
        // Each watcher counts its own reads, and a new generation has seen none.
        lastReadSequence = Int.min
    }

    /// The user chose a source in a browser (a trigger, or by hand). That starts a new generation:
    /// a wait for the page ends, every read on its way is stale, and the first read of the new
    /// generation only records the page, so the choice stands until the page changes.
    private mutating func userChoseSource(at time: TimeInterval) {
        guard frontSurface != nil else { return }
        lastChoiceAt = time
        retiredSwitchSourceID = nil
        paneThatKeptATriggerUnjudged = nil
        websiteHold = nil
        activationGeneration += 1
        contextOnlyGeneration = activationGeneration
    }

    /// What the website rule of the page in front selects, nil when the page has no rule.
    private var currentPageRuleTarget: AppActivationTarget? {
        guard surfaceWatch != nil, case .rule(let key) = websiteContext else { return nil }
        return ruleTarget(for: key)
    }

    /// Whether `next` changes the rules the app in front is read against. Rules of the other
    /// kind changing must not make the page or program in front be decided again: that would
    /// apply its rule over a choice the user has made since.
    private func rulesOfTheSurfaceInFrontChange(to next: AppActivationSettings) -> Bool {
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
    private func ruleTarget(for key: String) -> AppActivationTarget? {
        frontSurface?.kind == .terminal ? settings.programTarget(forRule: key) : settings.websiteTarget(forRule: key)
    }

    private func isKeepAsIsRule(_ key: String) -> Bool {
        frontSurface?.kind == .terminal ? settings.programTargets[key] == .keepAsIs : settings.websiteTargets[key] == .keepAsIs
    }

    /// The page in front is under a website rule that still exists.
    private var isOnRuledPage: Bool {
        guard surfaceWatch != nil, case .rule(let key) = websiteContext else { return false }
        return ruleTarget(for: key) != nil
    }

    /// The terminal in front is being read and the program of the pane in focus is not known yet
    /// (never read, or the pane changed since).
    private var isProgramUndecided: Bool {
        programWatch != nil && (websiteContext == nil || isWebsiteContextStale)
    }

    private var isOnKeepAsIsSite: Bool {
        guard surfaceWatch != nil, case .rule(let key) = websiteContext else { return false }
        return isKeepAsIsRule(key)
    }

    /// The page's rule when it has one, else the browser's own target, against what is selected.
    private mutating func websiteRestore(
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

    private mutating func remember(_ sourceID: String, for appID: String?) {
        guard let appID, appID != ownAppID, settings.usesMemory(for: appID) else { return }
        remembered[appID] = sourceID
    }
}
