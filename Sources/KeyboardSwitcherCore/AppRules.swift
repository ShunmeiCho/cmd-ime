import Foundation

/// What an App Rule (CONTEXT.md) does when its app comes to the front.
public enum AppRuleTarget: Hashable, Sendable {
    /// Select this slot, with the slot's fallback and activation recipe.
    case slot(InputRole)
    /// Leave the input source alone, and keep the app out of App Memory (remote desktops,
    /// virtual machines, games).
    case keepAsIs
}

/// A per-app rule the user created. Persisted in config.json, keyed by app id (bundle id, or
/// the executable path for an app without one).
public struct AppRule: Hashable, Sendable {
    public var appID: String
    /// The app's name when the rule was made, shown when the app is not installed any more.
    public var name: String?
    public var target: AppRuleTarget
    /// Restore the source last used in the app, and use the rule only on a first visit. Meaningless
    /// for `keepAsIs`, which never restores.
    public var rememberInstead: Bool

    public init(appID: String, name: String? = nil, target: AppRuleTarget, rememberInstead: Bool = false) {
        self.appID = appID
        self.name = name
        self.target = target
        self.rememberInstead = rememberInstead
    }
}

extension AppRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case appID = "app"
        case name
        case kind
        case slot
        case rememberInstead
    }

    private enum Kind: String, Codable {
        case slot
        case keepAsIs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        appID = try container.decode(String.self, forKey: .appID)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .slot:
            target = .slot(try container.decode(InputRole.self, forKey: .slot))
        case .keepAsIs:
            target = .keepAsIs
        }
        rememberInstead = try container.decodeIfPresent(Bool.self, forKey: .rememberInstead) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(appID, forKey: .appID)
        try container.encodeIfPresent(name, forKey: .name)
        switch target {
        case .slot(let slot):
            try container.encode(Kind.slot, forKey: .kind)
            try container.encode(slot, forKey: .slot)
        case .keepAsIs:
            try container.encode(Kind.keepAsIs, forKey: .kind)
        }
        try container.encode(rememberInstead, forKey: .rememberInstead)
    }
}

/// Decodes one rule without failing the whole list: a rule from a newer build (an unknown kind)
/// is dropped instead of costing the user every setting.
struct LenientAppRule: Decodable {
    let rule: AppRule?

    init(from decoder: Decoder) throws {
        rule = try? AppRule(from: decoder)
    }
}

/// What to select when an app comes to the front, before comparing with the source it arrived with.
public enum AppActivationTarget: Equatable, Sendable {
    case none
    /// A concrete source App Memory remembered.
    case source(String)
    case slot(InputRole)
}

/// The per-app settings the activation layer follows, taken from the config in one piece.
public struct AppActivationSettings: Equatable, Sendable {
    public var remembersPerApp: Bool
    public var rules: [String: AppRule]
    /// For an app with no rule and nothing remembered; nil leaves the source unchanged.
    public var defaultSlot: InputRole?
    public var restoresAfterPasswordField: Bool
    /// Slots that exist: a rule or default naming a deleted slot does nothing.
    public var slotIDs: Set<InputRole>
    /// Website rules, one per domain. On the page in front of a browser a matching one beats the
    /// browser's own slot rule, its memory and the default slot.
    public var websiteRules: [WebsiteRule]
    /// The same rules by domain.
    public var websiteTargets: [String: AppRuleTarget] {
        Dictionary(websiteRules.map { ($0.domain, $0.target) }, uniquingKeysWith: { _, later in later })
    }

    /// Program rules, one per exact name; paused rules are retained but never applied.
    public var programRules: [ProgramRule]
    public var programRulesPaused: Bool
    public var programTargets: [String: AppRuleTarget] {
        Dictionary(programRules.map { ($0.name, $0.target) }, uniquingKeysWith: { _, later in later })
    }

    public init(
        remembersPerApp: Bool = false,
        rules: [AppRule] = [],
        defaultSlot: InputRole? = nil,
        restoresAfterPasswordField: Bool = false,
        slotIDs: Set<InputRole> = [],
        websiteRules: [WebsiteRule] = [],
        programRules: [ProgramRule] = [],
        programRulesPaused: Bool = false
    ) {
        self.remembersPerApp = remembersPerApp
        // A later duplicate wins, the same as `setting(_:)` replacing in place.
        self.rules = Dictionary(rules.map { ($0.appID, $0) }, uniquingKeysWith: { _, later in later })
        self.defaultSlot = defaultSlot
        self.restoresAfterPasswordField = restoresAfterPasswordField
        self.slotIDs = slotIDs
        self.websiteRules = websiteRules
        self.programRules = programRules
        self.programRulesPaused = programRulesPaused
    }

    public init(config: SwitcherConfig) {
        self.init(
            remembersPerApp: config.rememberInputSourcePerApp,
            rules: config.appRules,
            defaultSlot: config.appDefaultSlot,
            restoresAfterPasswordField: config.restoreAfterPasswordField,
            slotIDs: Set(config.slots.map(\.id)),
            websiteRules: config.websiteRules,
            programRules: config.programRules,
            programRulesPaused: config.programRulesPaused
        )
    }

    /// Whether anything needs to follow app activations at all.
    public var isAnythingOn: Bool {
        remembersPerApp || !rules.isEmpty || defaultSlot != nil || restoresAfterPasswordField
            || !websiteTargets.isEmpty || (!programRulesPaused && !programRules.isEmpty)
    }

    /// Whether the pages of browser `appID` are read: only with a website rule to apply, and never
    /// for a "Keep as is" browser, where CmdIME changes nothing.
    public func watchesWebsites(in appID: String) -> Bool {
        !websiteTargets.isEmpty && !leavesSourceAlone(in: appID)
    }

    /// What the website rule for `domain` selects: nothing for a "Keep as is" site or a deleted
    /// slot. Nil when there is no such rule.
    public func websiteTarget(forRule domain: String) -> AppActivationTarget? {
        guard let target = websiteTargets[domain] else { return nil }
        guard case .slot(let slot) = target, slotIDs.contains(slot) else { return AppActivationTarget.none }
        return .slot(slot)
    }

    /// A Keep as is app is never queried, even when a program inside it has a rule.
    public func watchesPrograms(in appID: String) -> Bool {
        !programRulesPaused && !programRules.isEmpty && !leavesSourceAlone(in: appID)
    }

    /// Nil for no active rule; no switch for Keep as is or a deleted slot.
    public func programTarget(forRule name: String) -> AppActivationTarget? {
        guard !programRulesPaused, let target = programTargets[name] else { return nil }
        guard case .slot(let slot) = target, slotIDs.contains(slot) else { return AppActivationTarget.none }
        return .slot(slot)
    }

    /// "Keep as is" means CmdIME never changes the input source in that app, Password Put-back included.
    public func leavesSourceAlone(in appID: String) -> Bool {
        rules[appID]?.target == .keepAsIs
    }

    /// Whether the source used in `appID` is recorded. A rule decides for its own app: "keep as is"
    /// never, a slot rule only with "remember instead" (even while App Memory is off globally).
    public func usesMemory(for appID: String) -> Bool {
        guard let rule = rules[appID] else { return remembersPerApp }
        switch rule.target {
        case .keepAsIs: return false
        case .slot: return rule.rememberInstead
        }
    }

    /// App Rule beats App Memory unless the rule says "remember instead"; the default slot only
    /// covers an app with neither.
    public func target(for appID: String, rememberedSourceID: String?) -> AppActivationTarget {
        if usesMemory(for: appID), let rememberedSourceID {
            return .source(rememberedSourceID)
        }
        if let rule = rules[appID] {
            guard case .slot(let slot) = rule.target, slotIDs.contains(slot) else { return .none }
            return .slot(slot)
        }
        if let defaultSlot, slotIDs.contains(defaultSlot) {
            return .slot(defaultSlot)
        }
        return .none
    }
}

extension SwitcherConfig {
    public func appRule(for appID: String) -> AppRule? {
        appRules.first { $0.appID == appID }
    }

    /// Adds the rule, or replaces the one for the same app where it stands.
    public func setting(_ rule: AppRule) -> SwitcherConfig {
        var copy = self
        if let index = copy.appRules.firstIndex(where: { $0.appID == rule.appID }) {
            copy.appRules[index] = rule
        } else {
            copy.appRules.append(rule)
        }
        return copy
    }

    public func removingAppRule(for appID: String) -> SwitcherConfig {
        var copy = self
        copy.appRules.removeAll { $0.appID == appID }
        return copy
    }
}
