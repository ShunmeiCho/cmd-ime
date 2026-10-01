import Foundation

/// A per-website rule the user created: the page in front on this domain gets the target, in every
/// browser. Persisted in config.json, one rule per domain.
public struct WebsiteRule: Hashable, Sendable {
    /// What `domain` is compared with. Only whole-host matching exists; a rule with a kind this
    /// build does not know is dropped on decode, never applied as a domain rule.
    public enum Match: String, Codable, Sendable {
        case domain
    }

    public var match: Match
    /// A lowercase ASCII (punycode) host: no scheme, port, path or trailing dot.
    public var domain: String
    public var includesSubdomains: Bool
    public var target: AppRuleTarget

    public init(match: Match = .domain, domain: String, includesSubdomains: Bool = true, target: AppRuleTarget) {
        self.match = match
        self.domain = domain
        self.includesSubdomains = includesSubdomains
        self.target = target
    }
}

extension WebsiteRule: Codable {
    private enum CodingKeys: String, CodingKey {
        case match
        case domain
        case includesSubdomains = "subdomains"
        case kind
        case slot
    }

    private enum Kind: String, Codable {
        case slot
        case keepAsIs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        match = try container.decodeIfPresent(Match.self, forKey: .match) ?? .domain
        domain = try container.decode(String.self, forKey: .domain)
        includesSubdomains = try container.decodeIfPresent(Bool.self, forKey: .includesSubdomains) ?? true
        switch try container.decode(Kind.self, forKey: .kind) {
        case .slot:
            target = .slot(try container.decode(InputRole.self, forKey: .slot))
        case .keepAsIs:
            target = .keepAsIs
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(match, forKey: .match)
        try container.encode(domain, forKey: .domain)
        try container.encode(includesSubdomains, forKey: .includesSubdomains)
        switch target {
        case .slot(let slot):
            try container.encode(Kind.slot, forKey: .kind)
            try container.encode(slot, forKey: .slot)
        case .keepAsIs:
            try container.encode(Kind.keepAsIs, forKey: .kind)
        }
    }
}

/// Decodes one rule without failing the whole list: a rule from a newer build (an unknown match or
/// kind) is dropped instead of costing the user every setting.
struct LenientWebsiteRule: Decodable {
    let rule: WebsiteRule?

    init(from decoder: Decoder) throws {
        rule = try? WebsiteRule(from: decoder)
    }
}

extension [WebsiteRule] {
    /// Adds the rule, or replaces the one for the same domain where it stands.
    func setting(_ rule: WebsiteRule) -> [WebsiteRule] {
        var copy = self
        if let index = copy.firstIndex(where: { $0.domain == rule.domain }) {
            copy[index] = rule
        } else {
            copy.append(rule)
        }
        return copy
    }

    /// One rule per domain: a later duplicate replaces the earlier one where it stands.
    func uniquedByDomain() -> [WebsiteRule] {
        reduce([]) { $0.setting($1) }
    }
}

/// Which website rule covers a host.
public enum WebsiteRuleMatcher {
    /// `host` as `WebsiteHost.host(of:)` gives it. A rule matches its own domain, and with
    /// subdomains on any host ending in "." + domain; an IP address matches only exactly. The
    /// longest matching domain wins, so the answer does not depend on the order of the list.
    public static func match(host: String, in rules: [WebsiteRule]) -> WebsiteRule? {
        let isAddress = WebsiteHost.isIPLiteral(host)
        var best: WebsiteRule?
        for rule in rules where rule.match == .domain && !rule.domain.isEmpty {
            let matches = host == rule.domain
                || (!isAddress && rule.includesSubdomains && host.hasSuffix("." + rule.domain))
            if matches, rule.domain.count >= best?.domain.count ?? 0 {
                best = rule
            }
        }
        return best
    }
}

extension SwitcherConfig {
    public func websiteRule(for domain: String) -> WebsiteRule? {
        websiteRules.first { $0.domain == domain }
    }

    /// Adds the rule, or replaces the one for the same domain where it stands.
    public func setting(_ rule: WebsiteRule) -> SwitcherConfig {
        var copy = self
        copy.websiteRules = websiteRules.setting(rule)
        return copy
    }

    public func removingWebsiteRule(for domain: String) -> SwitcherConfig {
        var copy = self
        copy.websiteRules.removeAll { $0.domain == domain }
        return copy
    }
}
