import Foundation

/// A rule for the foreground program in a terminal pane, keyed by its exact, case-sensitive name.
public struct ProgramRule: Hashable, Sendable {
    public var name: String
    public var target: AppRuleTarget

    public init(name: String, target: AppRuleTarget) {
        self.name = name
        self.target = target
    }
}

extension ProgramRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case name
        case kind
        case slot
    }

    private enum Kind: String, Codable {
        case slot
        case keep
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .slot:
            target = .slot(try container.decode(InputRole.self, forKey: .slot))
        case .keep:
            target = .keepAsIs
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        switch target {
        case .slot(let slot):
            try container.encode(Kind.slot, forKey: .kind)
            try container.encode(slot, forKey: .slot)
        case .keepAsIs:
            try container.encode(Kind.keep, forKey: .kind)
        }
    }
}

/// A rule this build cannot read is dropped without losing the other settings.
struct LenientProgramRule: Decodable {
    let rule: ProgramRule?

    init(from decoder: Decoder) throws {
        rule = try? ProgramRule(from: decoder)
    }
}

public enum ProgramName {
    /// A command name, not a path or a command line. Case is significant.
    public static func normalized(userInput: String) -> String? {
        let name = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 64,
              !name.contains("/"), !name.contains(where: \.isWhitespace)
        else { return nil }
        return name
    }
}

extension [ProgramRule] {
    func setting(_ rule: ProgramRule) -> [ProgramRule] {
        var copy = self
        if let index = copy.firstIndex(where: { $0.name == rule.name }) {
            copy[index] = rule
        } else {
            copy.append(rule)
        }
        return copy
    }

    /// A later duplicate replaces the earlier rule where it stood.
    func uniquedByName() -> [ProgramRule] {
        reduce([]) { $0.setting($1) }
    }
}

public enum ProgramRuleMatcher {
    public static func match(name: String, in rules: [ProgramRule]) -> ProgramRule? {
        rules.last { $0.name == name }
    }
}

extension SwitcherConfig {
    public func programRule(for name: String) -> ProgramRule? {
        ProgramRuleMatcher.match(name: name, in: programRules)
    }

    /// Adds a rule, or replaces the rule for the same exact name in place.
    public func setting(_ rule: ProgramRule) -> SwitcherConfig {
        var copy = self
        copy.programRules = programRules.setting(rule)
        return copy
    }

    public func removingProgramRule(for name: String) -> SwitcherConfig {
        var copy = self
        copy.programRules.removeAll { $0.name == name }
        return copy
    }

    public func settingProgramRulesPaused(_ paused: Bool) -> SwitcherConfig {
        var copy = self
        copy.programRulesPaused = paused
        return copy
    }
}
