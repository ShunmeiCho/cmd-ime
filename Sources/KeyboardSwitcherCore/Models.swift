import Foundation

public enum InputRole: String, Codable, CaseIterable, Sendable {
    case english
    case chinese
    case japanese
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
}

public struct KeyTrigger: Codable, Equatable, Hashable, Sendable {
    public var kind: TriggerKind
    public var gesture: TriggerGesture
    public var keyCode: Int
    public var keyName: String
    public var modifiers: [Modifier]

    public init(
        kind: TriggerKind,
        keyCode: Int,
        keyName: String,
        modifiers: [Modifier] = [],
        gesture: TriggerGesture = .tap
    ) {
        self.kind = kind
        self.gesture = gesture
        self.keyCode = keyCode
        self.keyName = keyName
        self.modifiers = modifiers.sorted()
    }

    public var displayName: String {
        if kind == .oneShotModifier {
            return gesture == .doubleTap ? "double-\(keyName)" : keyName
        }

        let prefix = modifiers.map(\.rawValue).joined(separator: "+")
        return prefix.isEmpty ? keyName : "\(prefix)+\(keyName)"
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
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(TriggerKind.self, forKey: .kind)
        gesture = try container.decodeIfPresent(TriggerGesture.self, forKey: .gesture) ?? .tap
        keyCode = try container.decode(Int.self, forKey: .keyCode)
        keyName = try container.decode(String.self, forKey: .keyName)
        modifiers = try container.decode([Modifier].self, forKey: .modifiers)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(gesture, forKey: .gesture)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(keyName, forKey: .keyName)
        try container.encode(modifiers, forKey: .modifiers)
    }
}

public enum BindingActionType: String, Codable, Sendable {
    case switchInputSource
    case sendKey
    case disable
}

public struct BindingAction: Codable, Equatable, Sendable {
    public var type: BindingActionType
    public var role: InputRole?
    public var output: KeyTrigger?

    public init(type: BindingActionType, role: InputRole? = nil, output: KeyTrigger? = nil) {
        self.type = type
        self.role = role
        self.output = output
    }

    public static func switchInputSource(_ role: InputRole) -> BindingAction {
        BindingAction(type: .switchInputSource, role: role)
    }

    public static func sendKey(_ trigger: KeyTrigger) -> BindingAction {
        BindingAction(type: .sendKey, output: trigger)
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

    public init(
        preferredIDs: [String] = [],
        languagePrefixes: [String] = [],
        nameContains: [String] = []
    ) {
        self.preferredIDs = preferredIDs
        self.languagePrefixes = languagePrefixes
        self.nameContains = nameContains
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
            "Small"
        case .medium:
            "Medium"
        case .large:
            "Large"
        }
    }
}

public enum SwitchIndicatorColorStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case role
    case accent
    case monochrome
    case custom

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .role:
            "Role"
        case .accent:
            "Accent"
        case .monochrome:
            "Mono"
        case .custom:
            "Custom"
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
            "Icon + Text"
        case .iconOnly:
            "Icon"
        case .textOnly:
            "Text"
        }
    }
}

public struct SwitcherConfig: Codable, Equatable, Sendable {
    public static let defaultSwitchIndicatorScale = 1.0
    public static let minSwitchIndicatorScale = 0.65
    public static let maxSwitchIndicatorScale = 1.3

    public var version: Int
    public var showMenuBarIcon: Bool
    public var showSwitchIndicator: Bool
    public var switchIndicatorSize: SwitchIndicatorSize
    public var switchIndicatorScale: Double
    public var switchIndicatorColorStyle: SwitchIndicatorColorStyle
    public var switchIndicatorContentStyle: SwitchIndicatorContentStyle
    public var switchIndicatorCustomColorHex: String
    public var bindings: [KeyBinding]
    public var inputSources: [String: RoleInputSourcePreference]

    public init(
        version: Int = 1,
        showMenuBarIcon: Bool = true,
        showSwitchIndicator: Bool = true,
        switchIndicatorSize: SwitchIndicatorSize = .medium,
        switchIndicatorScale: Double = SwitcherConfig.defaultSwitchIndicatorScale,
        switchIndicatorColorStyle: SwitchIndicatorColorStyle = .role,
        switchIndicatorContentStyle: SwitchIndicatorContentStyle = .iconAndText,
        switchIndicatorCustomColorHex: String = "#2F7CF6",
        bindings: [KeyBinding],
        inputSources: [String: RoleInputSourcePreference]
    ) {
        self.version = version
        self.showMenuBarIcon = showMenuBarIcon
        self.showSwitchIndicator = showSwitchIndicator
        self.switchIndicatorSize = switchIndicatorSize
        self.switchIndicatorScale = Self.clampedSwitchIndicatorScale(switchIndicatorScale)
        self.switchIndicatorColorStyle = switchIndicatorColorStyle
        self.switchIndicatorContentStyle = switchIndicatorContentStyle
        self.switchIndicatorCustomColorHex = switchIndicatorCustomColorHex
        self.bindings = bindings
        self.inputSources = inputSources
    }

    public static func clampedSwitchIndicatorScale(_ value: Double) -> Double {
        min(max(value, minSwitchIndicatorScale), maxSwitchIndicatorScale)
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

    public mutating func pinInputSourceID(_ id: String, for role: InputRole) {
        var preference = preference(for: role)
        preference.preferredIDs.removeAll { $0 == id }
        preference.preferredIDs.insert(id, at: 0)
        inputSources[role.rawValue] = preference
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
        case showMenuBarIcon
        case showSwitchIndicator
        case switchIndicatorSize
        case switchIndicatorScale
        case switchIndicatorColorStyle
        case switchIndicatorContentStyle
        case switchIndicatorCustomColorHex
        case bindings
        case inputSources
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decodeIfPresent(Int.self, forKey: .version) ?? 1
        showMenuBarIcon = try container.decodeIfPresent(Bool.self, forKey: .showMenuBarIcon) ?? true
        showSwitchIndicator = try container.decodeIfPresent(Bool.self, forKey: .showSwitchIndicator) ?? true
        switchIndicatorSize = try container.decodeIfPresent(SwitchIndicatorSize.self, forKey: .switchIndicatorSize) ?? .medium
        switchIndicatorScale = Self.clampedSwitchIndicatorScale(
            try container.decodeIfPresent(Double.self, forKey: .switchIndicatorScale)
                ?? Self.defaultSwitchIndicatorScale
        )
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
        bindings = try container.decode([KeyBinding].self, forKey: .bindings)
        inputSources = try container.decode([String: RoleInputSourcePreference].self, forKey: .inputSources)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(showMenuBarIcon, forKey: .showMenuBarIcon)
        try container.encode(showSwitchIndicator, forKey: .showSwitchIndicator)
        try container.encode(switchIndicatorSize, forKey: .switchIndicatorSize)
        try container.encode(switchIndicatorScale, forKey: .switchIndicatorScale)
        try container.encode(switchIndicatorColorStyle, forKey: .switchIndicatorColorStyle)
        try container.encode(switchIndicatorContentStyle, forKey: .switchIndicatorContentStyle)
        try container.encode(switchIndicatorCustomColorHex, forKey: .switchIndicatorCustomColorHex)
        try container.encode(bindings, forKey: .bindings)
        try container.encode(inputSources, forKey: .inputSources)
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
            ? " +\(languages.count - visibleLanguages.count) more"
            : ""
        return visibleLanguages.joined(separator: ", ") + suffix
    }
}
