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

    /// Counts every change of `frontmostAppID`. A website read carries the value it was made
    /// under, so a result for a browser already left, or left and come back to, is told apart.
    public private(set) var activationGeneration = 0
    /// The pid of the app in front when it is a browser the caller can read pages of.
    private var frontBrowserPID: Int32?
    /// The page in front of that browser, once read; `.unknown` never replaces a known one.
    private var websiteContext: WebsiteContext?
    /// The browser came to the front and its own target waits for the first read of the page.
    private var websiteHold: WebsiteHold?
    private var lastReadSequence = Int.min
    /// The user chose a source (a trigger, or by hand) before the page was read: the next read
    /// only records the page and switches nothing.
    private var nextReadSetsContextOnly = false
    /// The switch on its way was asked for by a website rule and must not become the browser's memory.
    private var isWebsiteSwitchInFlight = false

    private struct WebsiteHold: Equatable, Sendable {
        /// What the user arrived with, to compare the decided target against.
        let arrivalSourceID: String?
    }

    public init(
        ownAppID: String?,
        frontmostAppID: String? = nil,
        settings: AppActivationSettings = AppActivationSettings(remembersPerApp: true)
    ) {
        self.ownAppID = ownAppID
        self.frontmostAppID = frontmostAppID
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
        guard let pid = frontBrowserPID, let appID = frontmostAppID, appID != ownAppID,
              settings.watchesWebsites(in: appID) else { return nil }
        return (pid, activationGeneration)
    }

    /// The browser's own target is waiting for the first read of its page; the caller ends the
    /// wait with `websiteHoldExpired` when no read arrives in time.
    public var isWebsiteHoldWaiting: Bool {
        websiteHold != nil
    }

    /// New settings from the config. Memory of an app that no longer uses it is dropped, so what
    /// the Apps page lists is what can be restored.
    public mutating func update(settings: AppActivationSettings) {
        if settings.websiteRules != self.settings.websiteRules {
            // The page is read again against the new rules.
            websiteContext = nil
        }
        self.settings = settings
        remembered = remembered.filter { settings.usesMemory(for: $0.key) }
        if websiteWatch == nil {
            websiteHold = nil
        }
    }

    /// The selected input source changed while `frontmostAppID` was in front.
    public mutating func sourceChanged(to sourceID: String, context: AppMemoryContext) {
        let previousSourceID = lastSourceID
        lastSourceID = sourceID
        // Checked before the pending guard: a source forced while CmdIME's own restore is on its
        // way must still be marked, or it becomes the app's memory once secure input ends.
        if context.isSecureInputInFrontmostApp {
            markForced(sourceID, replacing: previousSourceID)
            return
        }
        guard !context.isOwnSwitchPending else { return }
        // macOS repeats the current source on focus changes; the forced one repeated is not a choice.
        guard !isForced(sourceID, in: frontmostAppID) else { return }
        forced = nil
        beforeForced = nil
        // The user chose by hand before the page was read: that choice stands.
        cancelWebsiteHold()
        guard !isOnRuledPage else { return }
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
        // A browser's memory holds what was used on pages without a rule only.
        guard !wasAskedByWebsiteRule, !isOnRuledPage else { return }
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
        browserPID: Int32? = nil
    ) {
        if let actual = actualFrontmostAppID, actual != frontmostAppID, isRegularApp || actual == ownAppID {
            frontmostChanged(to: actual, browserPID: browserPID)
            forced = nil
            beforeForced = nil
            sourceBeforeRestore = nil
            nextReadSetsContextOnly = true
        }
        // The trigger is the user's choice: it ends a wait for the page and replaces a website switch.
        cancelWebsiteHold()
        isWebsiteSwitchInFlight = false
        switchConfirmed(sourceID: sourceID, context: context)
    }

    /// Secure input ended while `frontmostAppID` stayed in front. If the source is still the one
    /// macOS forced, says to select the one it replaced.
    public mutating func secureInputEnded(currentSourceID: String?, context: AppMemoryContext) -> Restore {
        guard let before = beforeForced, let forced else { return .none }
        beforeForced = nil
        guard settings.restoresAfterPasswordField,
              !context.isSecureInputInFrontmostApp, !context.isOwnSwitchPending,
              before.appID == frontmostAppID, forced.appID == frontmostAppID,
              let currentSourceID, currentSourceID == forced.sourceID,
              before.sourceID != currentSourceID else {
            return .none
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
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        let appID = actualFrontmostAppID ?? noticedAppID
        guard isRegularApp || appID == ownAppID else { return .none }
        guard appID != frontmostAppID else { return .none }
        if !context.isRestorePending {
            sourceBeforeRestore = nil
        }
        // Leaving a browser from a page under a website rule records nothing for the browser.
        if !context.isOwnSwitchPending, !context.isSecureInputInFrontmostApp, !isOnRuledPage,
           let currentSourceID, !isForced(currentSourceID, in: frontmostAppID) {
            remember(currentSourceID, for: frontmostAppID)
        }
        frontmostChanged(to: appID, browserPID: browserPID)
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
        let holdsForWebsite = canRestore && websiteWatch != nil
        if holdsForWebsite {
            websiteHold = WebsiteHold(arrivalSourceID: arrivalSourceID)
        } else if context.isTriggerPending, websiteWatch != nil {
            nextReadSetsContextOnly = true
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
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        guard let watch = websiteWatch, let appID = frontmostAppID,
              reading.pid == watch.pid, reading.generation == watch.generation,
              reading.sequence > lastReadSequence,
              actualFrontmostAppID == nil || actualFrontmostAppID == appID else {
            return .none
        }
        lastReadSequence = reading.sequence
        var page = reading.context
        if case .rule(let domain) = page, settings.websiteTargets[domain] == nil {
            page = .noRule
        }
        let previous = websiteContext
        let hold = websiteHold
        websiteHold = nil
        if page != .unknown {
            websiteContext = page
        }
        if nextReadSetsContextOnly, hold == nil {
            if page != .unknown { nextReadSetsContextOnly = false }
            return .none
        }
        guard !context.isTriggerPending, !context.isSecureInputInFrontmostApp else { return .none }
        if let hold {
            return websiteRestore(page: page, appID: appID, arrivalSourceID: hold.arrivalSourceID,
                                  currentSourceID: currentSourceID, slotOfSource: slotOfSource)
        }
        // An unread page that turns out to have no rule changes nothing: the hold already chose.
        guard page != .unknown, page != previous, !(previous == nil && page == .noRule) else { return .none }
        return websiteRestore(page: page, appID: appID, arrivalSourceID: currentSourceID,
                              currentSourceID: currentSourceID, slotOfSource: slotOfSource)
    }

    /// No read arrived in time after the browser came to the front: its own target applies.
    public mutating func websiteHoldExpired(
        generation: Int,
        currentSourceID: String?,
        context: AppMemoryContext,
        slotOfSource: (String) -> InputRole? = { _ in nil }
    ) -> Restore {
        guard generation == activationGeneration, let hold = websiteHold, let appID = frontmostAppID else {
            return .none
        }
        websiteHold = nil
        guard !context.isTriggerPending, !context.isSecureInputInFrontmostApp else { return .none }
        return websiteRestore(page: .unknown, appID: appID, arrivalSourceID: hold.arrivalSourceID,
                              currentSourceID: currentSourceID, slotOfSource: slotOfSource)
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

    private mutating func markForced(_ sourceID: String, replacing previousSourceID: String?) {
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
        }
        forced = ForcedSource(appID: appID, sourceID: sourceID)
    }

    private func isForced(_ sourceID: String, in appID: String?) -> Bool {
        guard let forced, let appID else { return false }
        return forced == ForcedSource(appID: appID, sourceID: sourceID)
    }

    private mutating func frontmostChanged(to appID: String, browserPID: Int32?) {
        frontmostAppID = appID
        activationGeneration += 1
        frontBrowserPID = browserPID
        websiteContext = nil
        websiteHold = nil
        nextReadSetsContextOnly = false
    }

    /// The user chose a source while the browser's target still waited for its page.
    private mutating func cancelWebsiteHold() {
        guard websiteHold != nil else { return }
        websiteHold = nil
        nextReadSetsContextOnly = true
    }

    /// The page in front is under a website rule that still exists.
    private var isOnRuledPage: Bool {
        guard websiteWatch != nil, case .rule(let domain) = websiteContext else { return false }
        return settings.websiteTargets[domain] != nil
    }

    private var isOnKeepAsIsSite: Bool {
        guard websiteWatch != nil, case .rule(let domain) = websiteContext else { return false }
        return settings.websiteTargets[domain] == .keepAsIs
    }

    /// The page's rule when it has one, else the browser's own target, against what is selected.
    private mutating func websiteRestore(
        page: WebsiteContext,
        appID: String,
        arrivalSourceID: String?,
        currentSourceID: String?,
        slotOfSource: (String) -> InputRole?
    ) -> Restore {
        let ruleTarget: AppActivationTarget? = {
            guard case .rule(let domain) = page else { return nil }
            return settings.websiteTarget(forRule: domain)
        }()
        let target = ruleTarget ?? settings.target(for: appID, rememberedSourceID: remembered[appID])
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
            return .none
        }
    }

    private mutating func remember(_ sourceID: String, for appID: String?) {
        guard let appID, appID != ownAppID, settings.usesMemory(for: appID) else { return }
        remembered[appID] = sourceID
    }
}
