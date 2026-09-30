import Foundation

/// When the switch indicator appears and how long it stays, beside the master
/// `showSwitchIndicator` switch. Stored as one optional key, so a file written before it
/// existed reads the defaults: bubbles for changes made outside CmdIME, none on an app
/// switch, no hidden apps, and each theme's own hold.
public struct SwitchIndicatorBehavior: Codable, Equatable, Sendable {
    /// Hold choices offered in Settings, in seconds. Nil (Automatic) keeps each theme's own.
    public static let holdChoices: [Double] = [0.5, 1, 1.5, 2, 3, 5]
    public static let minHoldSeconds = 0.3
    public static let maxHoldSeconds = 10.0

    /// A bubble when the input source changes without CmdIME: Control+Space, the Globe key,
    /// the menu bar, another app.
    public var showsExternalChanges: Bool
    /// A bubble when switching apps leaves a different input source than before, even when
    /// nothing else showed one.
    public var showsOnAppSwitch: Bool
    /// Apps (bundle id, or executable path for an app without one) in which no bubble shows.
    public var hiddenAppIDs: [String]
    /// How long the bubble stays after it appears. Nil keeps each theme's own hold.
    public var holdSeconds: Double?

    public init(
        showsExternalChanges: Bool = true,
        showsOnAppSwitch: Bool = false,
        hiddenAppIDs: [String] = [],
        holdSeconds: Double? = nil
    ) {
        self.showsExternalChanges = showsExternalChanges
        self.showsOnAppSwitch = showsOnAppSwitch
        self.hiddenAppIDs = hiddenAppIDs
        self.holdSeconds = holdSeconds.flatMap { Self.clampedHold($0) }
    }

    public func isHidden(in appID: String?) -> Bool {
        guard let appID else { return false }
        return hiddenAppIDs.contains(appID)
    }

    /// The hold to use, given the theme's own.
    public func hold(automatic: Double) -> Double {
        holdSeconds ?? automatic
    }

    public func hiding(_ appID: String) -> SwitchIndicatorBehavior {
        guard !hiddenAppIDs.contains(appID) else { return self }
        var next = self
        next.hiddenAppIDs.append(appID)
        return next
    }

    public func showing(_ appID: String) -> SwitchIndicatorBehavior {
        var next = self
        next.hiddenAppIDs.removeAll { $0 == appID }
        return next
    }

    /// A non-finite value means Automatic.
    public static func clampedHold(_ seconds: Double) -> Double? {
        guard seconds.isFinite else { return nil }
        return min(max(seconds, minHoldSeconds), maxHoldSeconds)
    }

    private enum CodingKeys: String, CodingKey {
        case showsExternalChanges, showsOnAppSwitch, hiddenAppIDs, holdSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            showsExternalChanges: try container.decodeIfPresent(Bool.self, forKey: .showsExternalChanges) ?? true,
            showsOnAppSwitch: try container.decodeIfPresent(Bool.self, forKey: .showsOnAppSwitch) ?? false,
            hiddenAppIDs: try container.decodeIfPresent([String].self, forKey: .hiddenAppIDs) ?? [],
            holdSeconds: try container.decodeIfPresent(Double.self, forKey: .holdSeconds)
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(showsExternalChanges, forKey: .showsExternalChanges)
        try container.encode(showsOnAppSwitch, forKey: .showsOnAppSwitch)
        try container.encode(hiddenAppIDs, forKey: .hiddenAppIDs)
        try container.encodeIfPresent(holdSeconds, forKey: .holdSeconds)
    }
}

/// Decides, event by event, whether a bubble shows. It keeps the last input source it knows
/// of, so a change is judged against what was really selected: CmdIME's own confirmed switch
/// already showed its bubble, and the system's notice of that same change arriving afterwards
/// must not show a second one.
public struct IndicatorOccasionTracker: Sendable {
    /// How long after an app comes to the front its input source is judged: App Memory's
    /// restore (a Kana prelude plus a confirmation retry) and macOS's per-document switching
    /// land well inside it.
    public static let appSwitchSettleDelay: TimeInterval = 0.4

    public private(set) var lastKnownSourceID: String?
    private var activation: Activation?

    private struct Activation: Sendable {
        let appID: String
        let sourceBefore: String?
        var hasShownBubble = false
    }

    public init(currentSourceID: String? = nil) {
        lastKnownSourceID = currentSourceID
    }

    /// CmdIME confirmed a switch it made. `reported` is false for a switch it makes silently
    /// (App Memory putting a source back); that one never shows a bubble.
    public mutating func ownSwitchConfirmed(
        sourceID: String,
        reported: Bool,
        frontmostAppID: String?,
        config: SwitcherConfig
    ) -> Bool {
        lastKnownSourceID = sourceID
        guard reported, config.showSwitchIndicator,
              !config.switchIndicatorBehavior.isHidden(in: frontmostAppID) else { return false }
        activation?.hasShownBubble = true
        return true
    }

    /// The system says the selected source changed. While CmdIME's own switch is in flight the
    /// changes are its steps (a Kana prelude, a retry) and its confirmation shows the bubble.
    public mutating func sourceChanged(
        to sourceID: String?,
        isOwnSwitchPending: Bool,
        frontmostAppID: String?,
        config: SwitcherConfig
    ) -> Bool {
        guard let sourceID else { return false }
        let isNew = sourceID != lastKnownSourceID
        lastKnownSourceID = sourceID
        guard isNew, !isOwnSwitchPending, config.showSwitchIndicator,
              config.switchIndicatorBehavior.showsExternalChanges,
              !config.switchIndicatorBehavior.isHidden(in: frontmostAppID) else { return false }
        activation?.hasShownBubble = true
        return true
    }

    /// An app came to the front. Its source is judged after `appSwitchSettleDelay`.
    public mutating func appActivated(_ appID: String) {
        activation = Activation(appID: appID, sourceBefore: lastKnownSourceID)
    }

    /// The settle delay after `appActivated` ran out. Shows a bubble when the source differs
    /// from the one before the switch and no bubble showed since; a later activation retires
    /// this one.
    public mutating func appSwitchSettled(
        appID: String,
        currentSourceID: String?,
        config: SwitcherConfig
    ) -> Bool {
        guard let pending = activation, pending.appID == appID else { return false }
        activation = nil
        guard let currentSourceID else { return false }
        lastKnownSourceID = currentSourceID
        guard currentSourceID != pending.sourceBefore, !pending.hasShownBubble,
              config.showSwitchIndicator,
              config.switchIndicatorBehavior.showsOnAppSwitch,
              !config.switchIndicatorBehavior.isHidden(in: appID) else { return false }
        return true
    }
}
