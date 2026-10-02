import Foundation
import Testing
@testable import KeyboardSwitcherCore

private let japanese = InputRole(rawValue: "japanese")
private let english = InputRole(rawValue: "english")

private func decodedConfig(websiteRules json: String) throws -> SwitcherConfig {
    let data = Data(#"{"version": 3, "bindings": [], "inputSources": {}, "websiteRules": \#(json)}"#.utf8)
    return try JSONDecoder().decode(SwitcherConfig.self, from: data)
}

struct WebsiteRuleCodingTests {
    @Test("a rule round-trips and always writes its match type")
    func roundTripWritesMatch() throws {
        let rules = [
            WebsiteRule(domain: "example.com", includesSubdomains: false, target: .slot(japanese)),
            WebsiteRule(domain: "localhost", target: .keepAsIs),
        ]

        let data = try JSONEncoder().encode(rules)

        #expect(try JSONDecoder().decode([WebsiteRule].self, from: data) == rules)
        let written = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(written[0]["match"] as? String == "domain")
        #expect(written[0]["subdomains"] as? Bool == false)
        #expect(written[0]["kind"] as? String == "slot")
        #expect(written[0]["slot"] as? String == "japanese")
        #expect(written[1]["kind"] as? String == "keepAsIs")
    }

    @Test("a rule without a match type is a domain rule")
    func missingMatchIsDomain() throws {
        let config = try decodedConfig(websiteRules: #"[{"domain": "example.com", "subdomains": false, "kind": "keepAsIs"}]"#)

        #expect(config.websiteRules == [WebsiteRule(match: .domain, domain: "example.com", includesSubdomains: false, target: .keepAsIs)])
    }

    @Test("a rule without the subdomains key includes subdomains")
    func missingSubdomainsIsTrue() throws {
        let config = try decodedConfig(websiteRules: #"[{"match": "domain", "domain": "example.com", "kind": "slot", "slot": "japanese"}]"#)

        #expect(config.websiteRules == [WebsiteRule(domain: "example.com", includesSubdomains: true, target: .slot(japanese))])
    }

    @Test("a rule with an unknown match type or kind is dropped, and the rules beside it stay")
    func unknownMatchOrKindDropsOnlyThatRule() throws {
        let config = try decodedConfig(websiteRules: #"""
        [{"match": "regex", "domain": "^https://a", "kind": "keepAsIs"},
         {"match": "domain", "domain": "b.example", "kind": "remember"},
         {"match": "domain", "domain": "c.example", "kind": "keepAsIs"}]
        """#)

        #expect(config.websiteRules == [WebsiteRule(domain: "c.example", target: .keepAsIs)])
    }

    @Test("of two rules for one domain the later one is kept, where the first stood")
    func laterDuplicateWins() throws {
        let config = try decodedConfig(websiteRules: #"""
        [{"domain": "example.com", "subdomains": false, "kind": "keepAsIs"},
         {"domain": "other.example", "kind": "keepAsIs"},
         {"domain": "example.com", "subdomains": true, "kind": "slot", "slot": "japanese"}]
        """#)

        #expect(config.websiteRules == [
            WebsiteRule(domain: "example.com", includesSubdomains: true, target: .slot(japanese)),
            WebsiteRule(domain: "other.example", target: .keepAsIs),
        ])
    }

    @Test("a config file without the key has no website rules")
    func missingKeyIsEmpty() throws {
        let data = Data(#"{"version": 3, "bindings": [], "inputSources": {}}"#.utf8)

        #expect(try JSONDecoder().decode(SwitcherConfig.self, from: data).websiteRules.isEmpty)
    }

    @Test("website rules survive a config round trip")
    func configRoundTrip() throws {
        var config = SwitcherConfig.default
        config.websiteRules = [
            WebsiteRule(domain: "example.com", includesSubdomains: false, target: .slot(japanese)),
            WebsiteRule(domain: "127.0.0.1", includesSubdomains: false, target: .keepAsIs),
        ]

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.websiteRules == config.websiteRules)
    }
}

struct WebsiteRuleConfigTests {
    @Test("setting a rule for a domain that has one replaces it in place")
    func settingReplacesByDomain() {
        var config = SwitcherConfig.default
        config.websiteRules = [
            WebsiteRule(domain: "example.com", includesSubdomains: false, target: .keepAsIs),
            WebsiteRule(domain: "other.example", target: .keepAsIs),
        ]

        let next = config.setting(WebsiteRule(domain: "example.com", includesSubdomains: true, target: .slot(japanese)))

        #expect(next.websiteRules == [
            WebsiteRule(domain: "example.com", includesSubdomains: true, target: .slot(japanese)),
            WebsiteRule(domain: "other.example", target: .keepAsIs),
        ])
        #expect(next.websiteRule(for: "example.com")?.target == .slot(japanese))
    }

    @Test("setting a rule for a new domain appends it, and removing takes only that domain")
    func settingAppendsAndRemovingRemoves() {
        let config = SwitcherConfig.default
            .setting(WebsiteRule(domain: "example.com", target: .keepAsIs))
            .setting(WebsiteRule(domain: "other.example", target: .slot(english)))

        #expect(config.websiteRules.map(\.domain) == ["example.com", "other.example"])
        #expect(config.removingWebsiteRule(for: "example.com").websiteRules.map(\.domain) == ["other.example"])
    }
}

struct WebsiteHostTests {
    private func host(_ address: String) -> String? {
        URL(string: address).flatMap(WebsiteHost.host(of:))
    }

    @Test("only http and https addresses have a host", arguments: [
        "file:///Users/someone/page.html", "about:blank", "chrome://newtab/", "favorites://", "ftp://example.com/",
    ])
    func otherSchemesHaveNoHost(address: String) {
        #expect(host(address) == nil)
    }

    @Test("the host is lowercase, without the port or a trailing dot")
    func hostIsCanonical() {
        #expect(host("https://Mail.Example.COM:8443/inbox?q=1#top") == "mail.example.com")
        #expect(host("HTTP://example.com./") == "example.com")
        #expect(host("https://user:secret@example.com/") == "example.com")
    }

    @Test("an IP address is its own host, IPv6 without the brackets")
    func addressHosts() {
        #expect(host("http://127.0.0.1:8765/a.html") == "127.0.0.1")
        #expect(host("http://[2001:DB8::1]:8080/") == "2001:db8::1")
    }

    @Test("a typed domain is stored lowercase with subdomains on, and www is kept")
    func plainDomain() throws {
        let plain = try #require(WebsiteHost.normalized(userInput: "  Example.com \n"))
        #expect(plain.domain == "example.com")
        #expect(plain.includesSubdomains)
        #expect(WebsiteHost.normalized(userInput: "www.example.com")?.domain == "www.example.com")
        #expect(WebsiteHost.normalized(userInput: "localhost")?.domain == "localhost")
    }

    @Test("*.x is x with subdomains on")
    func wildcard() throws {
        let wildcard = try #require(WebsiteHost.normalized(userInput: "*.example.com"))

        #expect(wildcard.domain == "example.com")
        #expect(wildcard.includesSubdomains)
    }

    @Test("a pasted address is reduced to its host", arguments: [
        "https://mail.example.com:8443/inbox?q=1#top", "http://Mail.Example.com./", "mail.example.com/inbox", "mail.example.com:8443",
    ])
    func pastedAddress(input: String) {
        #expect(WebsiteHost.normalized(userInput: input)?.domain == "mail.example.com")
    }

    @Test("an IP address is stored as typed and has no subdomains", arguments: [
        ("127.0.0.1", "127.0.0.1"), ("http://127.0.0.1:8765/a.html", "127.0.0.1"),
        ("::1", "::1"), ("[2001:DB8::1]", "2001:db8::1"), ("http://[::1]:8765/", "::1"),
    ])
    func addressInput(input: String, domain: String) throws {
        let normalized = try #require(WebsiteHost.normalized(userInput: input))

        #expect(normalized.domain == domain)
        #expect(!normalized.includesSubdomains)
    }

    @Test("an international name is stored as punycode, or refused where URL gives no ASCII host")
    func internationalName() {
        let normalized = WebsiteHost.normalized(userInput: "BÜCHER.example")

        // macOS 14 and later convert the name; an older Foundation reads no host, and the input is refused.
        #expect(normalized == nil || normalized?.domain == "xn--bcher-kva.example")
        #expect(normalized?.domain.allSatisfy(\.isASCII) != false)
        #expect(WebsiteHost.normalized(userInput: "xn--bcher-kva.example")?.domain == "xn--bcher-kva.example")
    }

    @Test("input that is not a host is refused", arguments: [
        "", "   ", "exa mple.com", "example..com", ".com", "*.", "a,b.com", "file:///Users/someone/page.html",
        "about:blank", "256.1.1.1", "1.2.3", "https://",
    ])
    func refusedInput(input: String) {
        #expect(WebsiteHost.normalized(userInput: input) == nil)
    }
}

struct WebsiteRuleMatcherTests {
    private func rule(_ domain: String, subdomains: Bool = true, _ target: AppRuleTarget = .keepAsIs) -> WebsiteRule {
        WebsiteRule(domain: domain, includesSubdomains: subdomains, target: target)
    }

    @Test("a rule covers its domain and, dot-anchored, its subdomains")
    func dotAnchoredSuffix() {
        let rules = [rule("example.com")]

        #expect(WebsiteRuleMatcher.match(host: "example.com", in: rules) == rules[0])
        #expect(WebsiteRuleMatcher.match(host: "mail.example.com", in: rules) == rules[0])
        #expect(WebsiteRuleMatcher.match(host: "xexample.com", in: rules) == nil)
        #expect(WebsiteRuleMatcher.match(host: "example.com.evil.test", in: rules) == nil)
    }

    @Test("a rule without subdomains covers only its exact host")
    func exactOnly() {
        let rules = [rule("example.com", subdomains: false)]

        #expect(WebsiteRuleMatcher.match(host: "example.com", in: rules) == rules[0])
        #expect(WebsiteRuleMatcher.match(host: "mail.example.com", in: rules) == nil)
    }

    @Test("the longest matching domain wins, whatever the order of the list")
    func longestWins() {
        let wide = rule("example.com", .slot(english))
        let narrow = rule("mail.example.com", .slot(japanese))

        #expect(WebsiteRuleMatcher.match(host: "inbox.mail.example.com", in: [wide, narrow]) == narrow)
        #expect(WebsiteRuleMatcher.match(host: "inbox.mail.example.com", in: [narrow, wide]) == narrow)
        #expect(WebsiteRuleMatcher.match(host: "docs.example.com", in: [narrow, wide]) == wide)
    }

    @Test("an IP address matches only exactly")
    func addressMatchesExactly() {
        let rules = [rule("0.0.1"), rule("127.0.0.1"), rule("::1")]

        #expect(WebsiteRuleMatcher.match(host: "127.0.0.1", in: rules) == rules[1])
        #expect(WebsiteRuleMatcher.match(host: "10.0.0.1", in: rules) == nil)
        #expect(WebsiteRuleMatcher.match(host: "::1", in: rules) == rules[2])
        #expect(WebsiteRuleMatcher.match(host: "fe80::1", in: rules) == nil)
    }
}

struct WebsiteHostDisplayTests {
    @Test("an international domain is shown in its own script where Foundation decodes it, a plain one as stored")
    func displayName() {
        // Older Foundation leaves punycode as it is; either reading names the same domain.
        #expect(["例え.jp", "xn--r8jz45g.jp"].contains(WebsiteHost.displayName(ofDomain: "xn--r8jz45g.jp")))
        #expect(WebsiteHost.displayName(ofDomain: "github.com") == "github.com")
        #expect(WebsiteHost.displayName(ofDomain: "127.0.0.1") == "127.0.0.1")
    }
}

struct WebsiteHostIPv6Tests {
    @Test("an IPv6 address has one spelling, typed or read from a page")
    func canonicalSpelling() throws {
        let typed = WebsiteHost.normalized(userInput: "[2001:0db8:0:0:0:0:0:1]")
        let page = try #require(URL(string: "http://[2001:DB8::1]:8080/x"))

        #expect(typed?.domain == "2001:db8::1")
        #expect(typed?.includesSubdomains == false)
        #expect(WebsiteHost.host(of: page) == "2001:db8::1")
    }

    @Test("something that only looks like an IPv6 address is refused")
    func invalidAddress() throws {
        #expect(WebsiteHost.normalized(userInput: ":::") == nil)
        #expect(WebsiteHost.normalized(userInput: "[1:2:3]") == nil)
        #expect(WebsiteHost.host(of: try #require(URL(string: "http://[1:2:3]/"))) == nil)
    }
}
