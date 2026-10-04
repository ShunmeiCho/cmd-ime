import Foundation

public struct InputRole: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let english = InputRole(rawValue: "english")
    public static let chinese = InputRole(rawValue: "chinese")
    public static let japanese = InputRole(rawValue: "japanese")
    public static let legacy: [InputRole] = [.english, .chinese, .japanese]
}

public enum TriggerKind: String, Codable, Sendable {
    case oneShotModifier
    case keyPress
}

public enum TriggerGesture: String, Codable, CaseIterable, Sendable {
    case tap
    case doubleTap
}

public enum Modifier: String, Codable, CaseIterable, Comparable, Sendable {
    case command
    case option
    case control
    case shift
    case fn
    case capsLock

    public static func < (lhs: Modifier, rhs: Modifier) -> Bool {
        Self.allCases.firstIndex(of: lhs)! < Self.allCases.firstIndex(of: rhs)!
    }

    /// Modifiers whose CGEventFlags bit is a latch (lock on/off), not a momentary
    /// press. They must be ignored during chord matching unless explicitly required.
    public static let latching: Set<Modifier> = [.capsLock, .fn]
}

public enum ModifierSide: String, Codable, Sendable {
    case left
    case right
}

public struct KeyTrigger: Codable, Equatable, Hashable, Sendable {
    public var kind: TriggerKind
    public var gesture: TriggerGesture
    public var keyCode: Int
    public var keyName: String
    public var modifiers: [Modifier]
    public var modifierSides: [Modifier: ModifierSide]

    public init(
        kind: TriggerKind,
        keyCode: Int,
        keyName: String,
        modifiers: [Modifier] = [],
        modifierSides: [Modifier: ModifierSide] = [:],
        gesture: TriggerGesture = .tap
    ) {
        self.kind = kind
        self.gesture = gesture
        self.keyCode = keyCode
        self.keyName = keyName
        self.modifiers = modifiers.sorted()
        self.modifierSides = Self.validModifierSides(modifierSides, kind: kind, modifiers: modifiers)
    }

    private static func validModifierSides(
        _ sides: [Modifier: ModifierSide], kind: TriggerKind, modifiers: [Modifier]
    ) -> [Modifier: ModifierSide] {
        sides.filter { kind == .keyPress && modifiers.contains($0.key) && !Modifier.latching.contains($0.key) }
    }

    public var displayName: String {
        if kind == .oneShotModifier {
            return gesture == .doubleTap ? "double-\(keyName)" : keyName
        }

        let prefix = modifierKeyNames.joined(separator: "+")
        return prefix.isEmpty ? keyName : "\(prefix)+\(keyName)"
    }

    /// The chord's modifiers as key names: `left-option` where a side is required, else `option`.
    public var modifierKeyNames: [String] {
        modifiers.map { modifier in
            modifierSides[modifier].map { "\($0.rawValue)-\(modifier.rawValue)" } ?? modifier.rawValue
        }
    }

    /// The same chord requiring these sides (none for either side).
    public func requiringSides(_ sides: [Modifier: ModifierSide]) -> KeyTrigger {
        KeyTrigger(kind: kind, keyCode: keyCode, keyName: keyName, modifiers: modifiers,
                   modifierSides: sides, gesture: gesture)
    }

    public var isReservedMacInputSourceShortcut: Bool {
        guard kind == .keyPress, keyCode == 49 else {
            return false
        }

        let modifierSet = Set(modifiers)
        return modifierSet == [.control] || modifierSet == [.control, .option]
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case gesture
        case keyCode
        case keyName
        case modifiers
        case modifierSides
    }

    private struct LenientModifierSide: Decodable {
        let value: ModifierSide?

        init(from decoder: Decoder) throws {
            value = try? decoder.singleValueContainer().decode(ModifierSide.self)
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TriggerKind.self, forKey: .kind)
        gesture = try container.decodeIfPresent(TriggerGesture.self, forKey: .gesture) ?? .tap
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        keyName = try container.decode(String.self, forKey: .keyName)
        modifiers = try container.decode([Modifier].self, forKey: .modifiers)
        let decodedSides = (try? container.decodeIfPresent([String: LenientModifierSide].self, forKey: .modifierSides)) ?? [:]
        var sides: [Modifier: ModifierSide] = [:]
        for (key, side) in decodedSides {
            if let modifier = Modifier(rawValue: key), let value = side.value {
                sides[modifier] = value
            }
        }
        modifierSides = Self.validModifierSides(sides, kind: kind, modifiers: modifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(gesture, forKey: .gesture)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(keyName, forKey: .keyName)
        try container.encode(modifiers, forKey: .modifiers)
        if !modifierSides.isEmpty {
            let sides = Dictionary(uniqueKeysWithValues: modifierSides.map { ($0.key.rawValue, $0.value) })
            try container.encode(sides, forKey: .modifierSides)
        }
    }
}

public enum BindingActionType: String, Codable, Sendable {
    case switchInputSource
    case sendKey
    case disable
    /// Peek: show the bubble for the current input source without switching. A build from
    /// before 0.12.0 does not know it and drops the binding through `LenientKeyBinding`.
    case showIndicator
    /// Toggle: switch between the two slots in `roles`. A build from before it drops the binding
    /// through `LenientKeyBinding`.
    case toggleSlots
}

public struct BindingAction: Codable, Equatable, Sendable {
    public var type: BindingActionType
    public var role: InputRole?
    public var output: KeyTrigger?
    /// The two slots of a `toggleSlots` action. Optional so older files decode unchanged.
    public var roles: [InputRole]?
    /// For `toggleSlots`: the slot its trigger was taken from, which gets it back when the Toggle lets go of it.
    public var takenFrom: InputRole?

    public init(type: BindingActionType, role: InputRole? = nil, output: KeyTrigger? = nil, roles: [InputRole]? = nil,
                takenFrom: InputRole? = nil) {
        self.type = type
        self.role = role
        self.output = output
        self.roles = roles
        self.takenFrom = takenFrom
    }

    public static func toggleSlots(_ first: InputRole, _ second: InputRole, takenFrom: InputRole? = nil) -> BindingAction {
        BindingAction(type: .toggleSlots, roles: [first, second], takenFrom: takenFrom)
    }

    /// Whether removing the slot `id` leaves this action pointing at nothing.
    public func names(slot id: InputRole) -> Bool {
        switch type {
        case .switchInputSource: role == id
        case .toggleSlots: roles?.contains(id) ?? false
        case .sendKey, .disable, .showIndicator: false
        }
    }

    public static func switchInputSource(_ role: InputRole) -> BindingAction {
        BindingAction(type: .switchInputSource, role: role)
    }

    public static func sendKey(_ trigger: KeyTrigger) -> BindingAction {
        BindingAction(type: .sendKey, output: trigger)
    }

    public static let showIndicator = BindingAction(type: .showIndicator)
}

/// One entry of the bindings array, which this build may not understand.
///
/// A config written by a newer CmdIME can name an action this one has never heard of. Decoding
/// the array strictly made that one binding cost the user every setting they had: the whole file
/// failed to decode, was moved aside as corrupt, and the app came up with defaults. Losing the
/// unreadable binding is the right price; losing the file is not.
struct LenientKeyBinding: Decodable {
    let binding: KeyBinding?

    init(from decoder: Decoder) throws {
        binding = try? KeyBinding(from: decoder)
    }
}

public struct KeyBinding: Codable, Equatable, Sendable {
    public var trigger: KeyTrigger
    public var action: BindingAction
    public var enabled: Bool

    public init(trigger: KeyTrigger, action: BindingAction, enabled: Bool = true) {
        self.trigger = trigger
        self.action = action
        self.enabled = enabled
    }
}

public struct RoleInputSourcePreference: Codable, Equatable, Sendable {
    public var preferredIDs: [String]
    public var languagePrefixes: [String]
    public var nameContains: [String]
    public var fallbackLanguage: String?

    public init(
        preferredIDs: [String] = [],
        languagePrefixes: [String] = [],
        nameContains: [String] = [],
        fallbackLanguage: String? = nil
    ) {
        self.preferredIDs = preferredIDs
        self.languagePrefixes = languagePrefixes
        self.nameContains = nameContains
        self.fallbackLanguage = fallbackLanguage
    }

    private enum CodingKeys: String, CodingKey {
        case preferredIDs, languagePrefixes, nameContains, fallbackLanguage
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preferredIDs = try container.decodeIfPresent([String].self, forKey: .preferredIDs) ?? []
        languagePrefixes = try container.decodeIfPresent([String].self, forKey: .languagePrefixes) ?? []
        nameContains = try container.decodeIfPresent([String].self, forKey: .nameContains) ?? []
        fallbackLanguage = try container.decodeIfPresent(String.self, forKey: .fallbackLanguage)
    }
}

public enum SwitchIndicatorSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case small
    case medium
    case large

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .small:
            CoreLocalization.text("Small")
        case .medium:
            CoreLocalization.text("Medium")
        case .large:
            CoreLocalization.text("Large")
        }
    }
}

public enum SwitchIndicatorColorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case role
    case accent
    case monochrome
    case custom

    /// What the settings offer. `custom` still decodes and is retired by migration.
    public static let selectable: [SwitchIndicatorColorStyle] = [.role, .accent, .monochrome]

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .role:
            CoreLocalization.text("Slot")
        case .accent:
            CoreLocalization.text("Accent")
        case .monochrome:
            CoreLocalization.text("Mono")
        case .custom:
            CoreLocalization.text("Custom")
        }
    }
}

public enum SwitchIndicatorContentStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case iconAndText
    case iconOnly
    case textOnly

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .iconAndText:
            CoreLocalization.text("Icon + Text")
        case .iconOnly:
            CoreLocalization.text("Icon")
        case .textOnly:
            CoreLocalization.text("Text")
        }
    }
}

public struct SwitcherConfig: Codable, Equatable, Sendable {
    public static let currentVersion = 3
    /// One number decides the indicator's size. It used to be two that multiplied -
    /// a Size of small, medium or large and a Scale on top of it - which meant the
    /// same percentage stood for a different size at each Size, and at the switcher's
    /// floor the slider bottomed out reading 110 %. The range spans what those two
    /// together could reach.
    public static let defaultSwitchIndicatorSizeFactor = 1.0
    public static let minSwitchIndicatorSizeFactor = 0.33
    public static let maxSwitchIndicatorSizeFactor = 1.60

    public var slots: [SwitchSlot]
    public var version: Int
    /// False only while the first-run setup guide is pending. Files written before
    /// this key existed decode as true, so existing users never see the guide.
    public var hasCompletedSetup: Bool
    public var lastSeenWhatsNewVersion: String?
    public var showSwitchIndicator: Bool
    /// The whole size of the indicator, 1.0 being its designed size.
    public var switchIndicatorSizeFactor: Double
    public var switchIndicatorColorStyle: SwitchIndicatorColorStyle
    public var switchIndicatorContentStyle: SwitchIndicatorContentStyle
    public var switchIndicatorCustomColorHex: String
    public var switchIndicatorCustomRoleColorHexes: [String: String]
    /// Nil selects the default built-in theme. An unknown id is kept as stored.
    public var switchIndicatorThemeID: String?
    /// When the indicator appears beyond CmdIME's own switches, and how long it stays.
    public var switchIndicatorBehavior: SwitchIndicatorBehavior
    /// App Memory (CONTEXT.md): restore the input source last used in an app when it comes
    /// back to the front. Off unless the user turns it on, since it switches without a trigger.
    public var rememberInputSourcePerApp: Bool
    /// App Rules (CONTEXT.md), in the order the user added them. One per app id.
    public var appRules: [AppRule]
    /// Website rules, in the order the user added them. One per domain.
    public var websiteRules: [WebsiteRule]
    /// Program rules, in the order the user added them. One per exact program name.
    public var programRules: [ProgramRule]
    /// Pause automatic program switching without discarding any rules.
    public var programRulesPaused: Bool
    /// Read another machine's Herdr panes over a standing ssh connection of CmdIME's own (a short
    /// python3 relay to that machine's Herdr socket) instead of the herdr CLI. Off by default:
    /// CmdIME then connects to the user's machines and runs code there.
    public var readsHerdrMachinesOverSSH: Bool
    /// The slot an app with no rule and nothing remembered gets when it comes to the front;
    /// nil leaves the input source unchanged.
    public var appDefaultSlot: InputRole?
    /// What a launcher panel with no rule and nothing remembered opens in.
    public var launcherDefault: LauncherDefault
    /// After a password field, put back the source macOS replaced with an ASCII one.
    public var restoreAfterPasswordField: Bool
    /// A bubble when Caps Lock turns on or off. Off unless the user turns it on.
    public var showCapsLockIndicator: Bool
    /// Auto space (issue #10): a half-width space at the Chinese and English boundary a trigger switch creates
    /// (see `AutoSpace`). Off unless turned on.
    public var autoSpaceBetweenChineseAndEnglish: Bool
    public var bindings: [KeyBinding]
    /// How many bindings in the file this build could not read, so the app can say so instead of
    /// letting them disappear quietly. Not persisted: it describes one load, not the config.
    public var unreadableBindingCount = 0
    public var inputSources: [String: RoleInputSourcePreference]

    public init(
        version: Int = SwitcherConfig.currentVersion,
        hasCompletedSetup: Bool = false,
        lastSeenWhatsNewVersion: String? = nil,
        slots: [SwitchSlot] = SwitchSlot.legacyDefaults,
        showSwitchIndicator: Bool = true,
        switchIndicatorSizeFactor: Double = SwitcherConfig.defaultSwitchIndicatorSizeFactor,
        switchIndicatorColorStyle: SwitchIndicatorColorStyle = .role,
        switchIndicatorContentStyle: SwitchIndicatorContentStyle = .iconAndText,
        switchIndicatorCustomColorHex: String = "#2F7CF6",
        switchIndicatorCustomRoleColorHexes: [String: String] = [:],
        switchIndicatorThemeID: String? = nil,
        switchIndicatorBehavior: SwitchIndicatorBehavior = SwitchIndicatorBehavior(),
        rememberInputSourcePerApp: Bool = false,
        appRules: [AppRule] = [],
        websiteRules: [WebsiteRule] = [],
        programRules: [ProgramRule] = [],
        programRulesPaused: Bool = false,
        readsHerdrMachinesOverSSH: Bool = false,
        appDefaultSlot: InputRole? = nil,
        launcherDefault: LauncherDefault = .english,
        restoreAfterPasswordField: Bool = true,
        showCapsLockIndicator: Bool = false,
        autoSpaceBetweenChineseAndEnglish: Bool = false,
        bindings: [KeyBinding],
        inputSources: [String: RoleInputSourcePreference]
    ) {
        self.slots = slots
        self.version = version
        self.hasCompletedSetup = hasCompletedSetup
        self.lastSeenWhatsNewVersion = lastSeenWhatsNewVersion
        self.showSwitchIndicator = showSwitchIndicator
        self.switchIndicatorSizeFactor = Self.clampedSwitchIndicatorSizeFactor(switchIndicatorSizeFactor)
        self.switchIndicatorColorStyle = switchIndicatorColorStyle
        self.switchIndicatorContentStyle = switchIndicatorContentStyle
        self.switchIndicatorCustomColorHex = switchIndicatorCustomColorHex
        self.switchIndicatorCustomRoleColorHexes = switchIndicatorCustomRoleColorHexes
        self.switchIndicatorThemeID = switchIndicatorThemeID
        self.switchIndicatorBehavior = switchIndicatorBehavior
        self.rememberInputSourcePerApp = rememberInputSourcePerApp
        self.appRules = appRules
        self.websiteRules = websiteRules
        self.programRules = programRules
        self.programRulesPaused = programRulesPaused
        self.readsHerdrMachinesOverSSH = readsHerdrMachinesOverSSH
        self.appDefaultSlot = appDefaultSlot
        self.launcherDefault = launcherDefault
        self.restoreAfterPasswordField = restoreAfterPasswordField
        self.showCapsLockIndicator = showCapsLockIndicator
        self.autoSpaceBetweenChineseAndEnglish = autoSpaceBetweenChineseAndEnglish
        self.bindings = bindings
        self.inputSources = inputSources
    }

    public static func clampedSwitchIndicatorSizeFactor(_ value: Double) -> Double {
        guard value.isFinite else { return defaultSwitchIndicatorSizeFactor }
        return min(max(value, minSwitchIndicatorSizeFactor), maxSwitchIndicatorSizeFactor)
    }

    public static var `default`: SwitcherConfig {
        SwitcherConfig(
            bindings: [
                KeyBinding(
                    trigger: KeyTrigger(kind: .oneShotModifier, keyCode: 55, keyName: "left-command"),
                    action: .switchInputSource(.english)
                ),
                KeyBinding(
                    trigger: KeyTrigger(kind: .oneShotModifier, keyCode: 54, keyName: "right-command"),
                    action: .switchInputSource(.chinese)
                ),
                KeyBinding(
                    trigger: KeyTrigger(kind: .keyPress, keyCode: 38, keyName: "j", modifiers: [.option]),
                    action: .switchInputSource(.japanese)
                ),
            ],
            inputSources: [
                InputRole.english.rawValue: RoleInputSourcePreference(
                    preferredIDs: [
                        "com.apple.keylayout.ABC",
                        "com.apple.keylayout.US",
                    ],
                    languagePrefixes: ["en"],
                    nameContains: ["ABC", "U.S.", "US"]
                ),
                InputRole.chinese.rawValue: RoleInputSourcePreference(
                    preferredIDs: [
                        "com.apple.inputmethod.SCIM.ITABC",
                        "com.apple.inputmethod.SCIM",
                    ],
                    languagePrefixes: ["zh"],
                    nameContains: ["Pinyin", "Chinese", "Simplified", "中文", "拼音"]
                ),
                InputRole.japanese.rawValue: RoleInputSourcePreference(
                    preferredIDs: [
                        "com.apple.inputmethod.Kotoeri.RomajiTyping.Japanese",
                        "com.apple.inputmethod.Kotoeri.RomajiTyping",
                    ],
                    languagePrefixes: ["ja"],
                    nameContains: ["Hiragana", "Japanese", "Kotoeri", "かな", "日本語"]
                ),
            ]
        )
    }

    public func preference(for role: InputRole) -> RoleInputSourcePreference {
        inputSources[role.rawValue] ?? RoleInputSourcePreference()
    }

    public func switchIndicatorCustomColorHex(for role: InputRole) -> String {
        switchIndicatorCustomRoleColorHexes[role.rawValue] ?? switchIndicatorCustomColorHex
    }

    public mutating func setSwitchIndicatorCustomColorHex(_ hex: String, for role: InputRole) {
        switchIndicatorCustomRoleColorHexes[role.rawValue] = hex
    }

    public func oneShotModifierConflict(for trigger: KeyTrigger, excluding role: InputRole) -> InputRole? {
        guard trigger.kind == .oneShotModifier else {
            return nil
        }

        return bindings.first { binding in
            binding.enabled
                && binding.action.type == .switchInputSource
                && binding.action.role != role
                && binding.trigger.kind == .oneShotModifier
                && (
                    binding.trigger.keyCode == trigger.keyCode
                        || binding.trigger.keyName == trigger.keyName
                )
        }?.action.role
    }

    public mutating func pinInputSourceID(_ id: String, for role: InputRole) {
        var preference = preference(for: role)
        preference.preferredIDs.removeAll { $0 == id }
        preference.preferredIDs.insert(id, at: 0)
        inputSources[role.rawValue] = preference
    }

    public mutating func sanitizePreferredIDs(using sources: [InputSourceInfo]) {
        let selectableSourcesByID = Dictionary(
            uniqueKeysWithValues: InputSourceMatcher.selectableSources(from: sources).map { ($0.id, $0) }
        )

        for role in slots.map(\.id) {
            var preference = preference(for: role)
            guard Self.canClassifySource(for: preference) else {
                continue
            }

            preference.preferredIDs = preference.preferredIDs.filter { id in
                guard let source = selectableSourcesByID[id] else {
                    return true
                }
                if Self.source(source, matches: preference) {
                    return true
                }

                let matchesOtherRole = slots.map(\.id).contains { otherRole in
                    otherRole != role && Self.source(source, matches: self.preference(for: otherRole))
                }
                return !matchesOtherRole
            }
            inputSources[role.rawValue] = preference
        }
    }

    public mutating func upsertSwitchBinding(trigger: KeyTrigger, role: InputRole) {
        let action = BindingAction.switchInputSource(role)
        bindings.removeAll { binding in
            binding.trigger == trigger
                || (
                    binding.action.type == .switchInputSource
                        && binding.action.role == role
                )
        }
        bindings.append(KeyBinding(trigger: trigger, action: action))
    }

    public mutating func upsertRemapBinding(trigger: KeyTrigger, output: KeyTrigger) {
        let action = BindingAction.sendKey(output)
        if let index = bindings.firstIndex(where: { $0.trigger == trigger }) {
            bindings[index] = KeyBinding(trigger: trigger, action: action)
        } else {
            bindings.append(KeyBinding(trigger: trigger, action: action))
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version
        case hasCompletedSetup
        case lastSeenWhatsNewVersion
        case slots
        case showSwitchIndicator
        case switchIndicatorSizeFactor
        /// Written, never read back on a current file: a build from before the two
        /// size controls were merged multiplies these together, and this pair makes
        /// that product the size this file actually asks for.
        case switchIndicatorSize
        case switchIndicatorScale
        case switchIndicatorColorStyle
        case switchIndicatorContentStyle
        case switchIndicatorCustomColorHex
        case switchIndicatorCustomRoleColorHexes
        case switchIndicatorThemeID
        case switchIndicatorBehavior
        case rememberInputSourcePerApp
        case appRules
        case websiteRules
        case programRules
        case programRulesPaused
        case readsHerdrMachinesOverSSH = "herdrMachinesOverSSH"
        case appDefaultSlot
        case launcherDefault
        case restoreAfterPasswordField
        case showCapsLockIndicator
        case autoSpaceBetweenChineseAndEnglish
        case bindings
        case inputSources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        hasCompletedSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? true
        lastSeenWhatsNewVersion = try container.decodeIfPresent(String.self, forKey: .lastSeenWhatsNewVersion)
        showSwitchIndicator = try container.decodeIfPresent(Bool.self, forKey: .showSwitchIndicator) ?? true
        // A file written before the merge carries the two controls that multiplied;
        // their product is the size it was rendering, so folding it keeps that size
        // to the point. A current file states the size once and the legacy pair it
        // also carries is ignored.
        let storedSizeFactor = try container.decodeIfPresent(Double.self, forKey: .switchIndicatorSizeFactor)
        if let storedSizeFactor, version >= 3 {
            switchIndicatorSizeFactor = Self.clampedSwitchIndicatorSizeFactor(storedSizeFactor)
        } else {
            let legacySize = try container.decodeIfPresent(SwitchIndicatorSize.self, forKey: .switchIndicatorSize) ?? .medium
            // The old Scale was clamped to 0.4...1.3 before it multiplied, so the fold
            // reproduces the size that build drew rather than the number on disk.
            let storedScale = try container.decodeIfPresent(Double.self, forKey: .switchIndicatorScale) ?? 1.0
            let legacyScale = min(max(storedScale.isFinite ? storedScale : 1.0, 0.4), 1.3)
            switchIndicatorSizeFactor = Self.clampedSwitchIndicatorSizeFactor(
                BubbleMetrics.factor(for: legacySize) * legacyScale
            )
        }
        switchIndicatorColorStyle = try container.decodeIfPresent(
            SwitchIndicatorColorStyle.self,
            forKey: .switchIndicatorColorStyle
        ) ?? .role
        switchIndicatorContentStyle = try container.decodeIfPresent(
            SwitchIndicatorContentStyle.self,
            forKey: .switchIndicatorContentStyle
        ) ?? .iconAndText
        switchIndicatorCustomColorHex = try container.decodeIfPresent(
            String.self,
            forKey: .switchIndicatorCustomColorHex
        ) ?? "#2F7CF6"
        switchIndicatorCustomRoleColorHexes = try container.decodeIfPresent(
            [String: String].self,
            forKey: .switchIndicatorCustomRoleColorHexes
        ) ?? [:]
        switchIndicatorThemeID = try container.decodeIfPresent(String.self, forKey: .switchIndicatorThemeID)
        switchIndicatorBehavior = try container.decodeIfPresent(
            SwitchIndicatorBehavior.self,
            forKey: .switchIndicatorBehavior
        ) ?? SwitchIndicatorBehavior()
        rememberInputSourcePerApp = try container.decodeIfPresent(Bool.self, forKey: .rememberInputSourcePerApp) ?? false
        appRules = (try container.decodeIfPresent([LenientAppRule].self, forKey: .appRules) ?? []).compactMap(\.rule)
        websiteRules = (try container.decodeIfPresent([LenientWebsiteRule].self, forKey: .websiteRules) ?? [])
            .compactMap(\.rule)
            .uniquedByDomain()
        programRules = (try container.decodeIfPresent([LenientProgramRule].self, forKey: .programRules) ?? [])
            .compactMap(\.rule)
            .uniquedByName()
        programRulesPaused = try container.decodeIfPresent(Bool.self, forKey: .programRulesPaused) ?? false
        readsHerdrMachinesOverSSH = try container.decodeIfPresent(Bool.self, forKey: .readsHerdrMachinesOverSSH) ?? false
        appDefaultSlot = try container.decodeIfPresent(InputRole.self, forKey: .appDefaultSlot)
        // A kind from a newer build reads as English rather than costing every setting.
        launcherDefault = (try? container.decodeIfPresent(LauncherDefault.self, forKey: .launcherDefault)) ?? .english
        restoreAfterPasswordField = try container.decodeIfPresent(Bool.self, forKey: .restoreAfterPasswordField) ?? true
        showCapsLockIndicator = try container.decodeIfPresent(Bool.self, forKey: .showCapsLockIndicator) ?? false
        autoSpaceBetweenChineseAndEnglish = try container.decodeIfPresent(Bool.self, forKey: .autoSpaceBetweenChineseAndEnglish) ?? false
        let decodedBindings = try container.decode([LenientKeyBinding].self, forKey: .bindings)
        bindings = decodedBindings.compactMap(\.binding)
        unreadableBindingCount = decodedBindings.count - bindings.count
        inputSources = try container.decode([String: RoleInputSourcePreference].self, forKey: .inputSources)
        slots = Self.normalizedSlots(
            try container.decodeIfPresent([SwitchSlot].self, forKey: .slots) ?? SwitchSlot.legacyDefaults,
            bindings: bindings
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(hasCompletedSetup, forKey: .hasCompletedSetup)
        try container.encodeIfPresent(lastSeenWhatsNewVersion, forKey: .lastSeenWhatsNewVersion)
        try container.encode(slots, forKey: .slots)
        try container.encode(showSwitchIndicator, forKey: .showSwitchIndicator)
        try container.encode(switchIndicatorSizeFactor, forKey: .switchIndicatorSizeFactor)
        // The legacy pair, so a build from before the merge draws this same size: it
        // multiplies them, and medium's factor is 1. Nothing here reads them back.
        try container.encode(SwitchIndicatorSize.medium, forKey: .switchIndicatorSize)
        try container.encode(switchIndicatorSizeFactor, forKey: .switchIndicatorScale)
        try container.encode(switchIndicatorColorStyle, forKey: .switchIndicatorColorStyle)
        try container.encode(switchIndicatorContentStyle, forKey: .switchIndicatorContentStyle)
        try container.encode(switchIndicatorCustomColorHex, forKey: .switchIndicatorCustomColorHex)
        try container.encode(switchIndicatorCustomRoleColorHexes, forKey: .switchIndicatorCustomRoleColorHexes)
        try container.encodeIfPresent(switchIndicatorThemeID, forKey: .switchIndicatorThemeID)
        try container.encode(switchIndicatorBehavior, forKey: .switchIndicatorBehavior)
        try container.encode(rememberInputSourcePerApp, forKey: .rememberInputSourcePerApp)
        try container.encode(appRules, forKey: .appRules)
        try container.encode(websiteRules, forKey: .websiteRules)
        if !programRules.isEmpty {
            try container.encode(programRules, forKey: .programRules)
        }
        if programRulesPaused {
            try container.encode(programRulesPaused, forKey: .programRulesPaused)
        }
        if readsHerdrMachinesOverSSH {
            try container.encode(readsHerdrMachinesOverSSH, forKey: .readsHerdrMachinesOverSSH)
        }
        try container.encodeIfPresent(appDefaultSlot, forKey: .appDefaultSlot)
        // Written only when changed, so a file that never had it reads back byte for byte.
        if launcherDefault != .english {
            try container.encode(launcherDefault, forKey: .launcherDefault)
        }
        try container.encode(restoreAfterPasswordField, forKey: .restoreAfterPasswordField)
        try container.encode(showCapsLockIndicator, forKey: .showCapsLockIndicator)
        // Written only when on, so a file that never had it reads back byte for byte.
        if autoSpaceBetweenChineseAndEnglish {
            try container.encode(autoSpaceBetweenChineseAndEnglish, forKey: .autoSpaceBetweenChineseAndEnglish)
        }
        try container.encode(bindings, forKey: .bindings)
        try container.encode(inputSources, forKey: .inputSources)
    }

    private static func canClassifySource(for preference: RoleInputSourcePreference) -> Bool {
        !preference.languagePrefixes.isEmpty || !preference.nameContains.isEmpty
    }

    private static func source(
        _ source: InputSourceInfo,
        matches preference: RoleInputSourcePreference
    ) -> Bool {
        let languagePrefixes = preference.languagePrefixes.map { $0.lowercased() }
        let matchesLanguage = !languagePrefixes.isEmpty && source.languages.contains { language in
            let normalized = language
                .lowercased()
                .replacingOccurrences(of: "_", with: "-")
            return languagePrefixes.contains { normalized.hasPrefix($0) }
        }

        let nameFragments = preference.nameContains.map { $0.lowercased() }
        let name = source.localizedName.lowercased()
        let matchesName = !nameFragments.isEmpty && nameFragments.contains { name.contains($0) }

        return matchesLanguage || matchesName
    }
}

public struct InputSourceInfo: Codable, Equatable, Sendable {
    public var id: String
    public var localizedName: String
    public var languages: [String]
    public var isSelectCapable: Bool

    public init(
        id: String,
        localizedName: String,
        languages: [String],
        isSelectCapable: Bool
    ) {
        self.id = id
        self.localizedName = localizedName
        self.languages = languages
        self.isSelectCapable = isSelectCapable
    }

    public var displayLanguages: String {
        guard !languages.isEmpty else {
            return ""
        }

        let visibleLanguages = languages.prefix(4)
        let suffix = languages.count > visibleLanguages.count
            ? CoreLocalization.text(" +%@ more", String(describing: languages.count - visibleLanguages.count))
            : ""
        return visibleLanguages.joined(separator: ", ") + suffix
    }

    /// Message for when a requested input-source selection did not take effect.
    public static func verificationMessage(requested: InputSourceInfo, current: InputSourceInfo?) -> String {
        if let current {
            return CoreLocalization.text("Requested %@, but macOS still reports %@.", String(describing: requested.localizedName), String(describing: current.localizedName))
        }
        return CoreLocalization.text("Requested %@, but macOS did not report the active input source.", String(describing: requested.localizedName))
    }
}
