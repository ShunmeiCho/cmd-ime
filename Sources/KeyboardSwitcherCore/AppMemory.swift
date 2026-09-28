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

/// App Memory (see CONTEXT.md): the input source last active while each app was in front,
/// restored when the user returns to that app. Keyed by an app id (bundle id, or the
/// executable path for apps without one); held in memory only.
public struct AppMemoryTracker: Equatable, Sendable {
    public enum Restore: Equatable, Sendable {
        case none
        /// Bring back the app's remembered source; worth showing the indicator for.
        case select(sourceID: String)
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
    private var remembered: [String: String] = [:]
    /// The source macOS forced on the app in front while secure input was on. It is still
    /// current after the password field is left, and must not become that app's memory.
    private var forced: ForcedSource?
    /// The source that was current before the pending restore, kept while that restore is pending.
    private var sourceBeforeRestore: String?

    public init(ownAppID: String?, frontmostAppID: String? = nil) {
        self.ownAppID = ownAppID
        self.frontmostAppID = frontmostAppID
    }

    public func rememberedSourceID(for appID: String) -> String? {
        remembered[appID]
    }

    /// The selected input source changed while `frontmostAppID` was in front.
    public mutating func sourceChanged(to sourceID: String, context: AppMemoryContext) {
        // Checked before the pending guard: a source forced while CmdIME's own restore is on its
        // way must still be marked, or it becomes the app's memory once secure input ends.
        if context.isSecureInputInFrontmostApp {
            forced = frontmostAppID.map { ForcedSource(appID: $0, sourceID: sourceID) }
            return
        }
        guard !context.isOwnSwitchPending else { return }
        // macOS repeats the current source on focus changes; the forced one repeated is not a choice.
        guard !isForced(sourceID, in: frontmostAppID) else { return }
        forced = nil
        remember(sourceID, for: frontmostAppID)
    }

    /// A switch CmdIME made was confirmed. Changes are ignored while one is pending, so the
    /// confirmed target is what gets remembered for the app in front, unless that app holds
    /// secure input, where nothing is remembered.
    public mutating func switchConfirmed(sourceID: String, context: AppMemoryContext) {
        guard !context.isSecureInputInFrontmostApp else { return }
        forced = nil
        remember(sourceID, for: frontmostAppID)
    }

    /// `appID` came to the front. Remembers `currentSourceID` for the app being left, since a
    /// change notification can arrive late or not at all, then says what to select, if anything.
    public mutating func appActivated(
        _ appID: String,
        currentSourceID: String?,
        context: AppMemoryContext
    ) -> Restore {
        guard appID != frontmostAppID else { return .none }
        if !context.isRestorePending {
            sourceBeforeRestore = nil
        }
        if !context.isOwnSwitchPending, !context.isSecureInputInFrontmostApp,
           let currentSourceID, !isForced(currentSourceID, in: frontmostAppID) {
            remember(currentSourceID, for: frontmostAppID)
        }
        frontmostAppID = appID
        // An app that holds secure input as it comes to the front may have had its source forced
        // before this call, or kept the ASCII source it arrived with; neither is a choice.
        forced = context.isSecureInputInFrontmostApp
            ? currentSourceID.map { ForcedSource(appID: appID, sourceID: $0) }
            : nil
        let pendingBefore = context.isRestorePending ? sourceBeforeRestore : nil
        // While a restore is pending, the current source is its intermediate step (the source
        // a Kana key brought in), not what the user arrived with.
        let arrivalSourceID = pendingBefore ?? currentSourceID
        let canRestore = appID != ownAppID && !context.isSecureInputInFrontmostApp
        if canRestore, let sourceID = remembered[appID], sourceID != arrivalSourceID {
            sourceBeforeRestore = sourceBeforeRestore ?? currentSourceID
            return .select(sourceID: sourceID)
        }
        // Never restore into CmdIME or a password field, but still retire a restore meant for
        // the app just left.
        if let pendingBefore {
            return .putBack(sourceID: pendingBefore)
        }
        return .none
    }

    public mutating func forgetAll() {
        remembered.removeAll()
        forced = nil
        sourceBeforeRestore = nil
    }

    private func isForced(_ sourceID: String, in appID: String?) -> Bool {
        guard let forced, let appID else { return false }
        return forced == ForcedSource(appID: appID, sourceID: sourceID)
    }

    private mutating func remember(_ sourceID: String, for appID: String?) {
        guard let appID, appID != ownAppID else { return }
        remembered[appID] = sourceID
    }
}
