import Foundation

/// The host a website rule is compared with, taken from a page address or from what the user typed.
public enum WebsiteHost {
    private static let webSchemes: Set<String> = ["http", "https"]
    private static let wildcardPrefix = "*."
    private static let assumedScheme = "https://"
    /// The longest host name DNS allows.
    private static let maxDomainLength = 253

    /// The host of an http or https address: lowercase, without the port or a trailing dot. Nil for
    /// every other scheme (`file:`, `about:`, `chrome:`) and for an address with no host.
    public static func host(of url: URL) -> String? {
        guard let scheme = url.scheme?.lowercased(), webSchemes.contains(scheme) else { return nil }
        guard var host = url.host?.lowercased() else { return nil }
        if host.hasSuffix(".") { host.removeLast() }
        // One spelling per IPv6 address, so a rule and a page that write it differently still match.
        // A host with a colon that is not an address is no host.
        if host.contains(":") { return canonicalIPv6(host) }
        return host.isEmpty ? nil : host
    }

    /// The shortest standard spelling of an IPv6 address (`2001:db8::1`), nil when it is not one.
    static func canonicalIPv6(_ host: String) -> String? {
        var address = in6_addr()
        guard inet_pton(AF_INET6, host, &address) == 1 else { return nil }
        var text = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
        guard inet_ntop(AF_INET6, &address, &text, socklen_t(text.count)) != nil else { return nil }
        return String(cString: text)
    }

    /// A stored domain as the user reads it: an international name in its own script instead of
    /// punycode (`例え.jp` for `xn--r8jz45g.jp`). Where Foundation does not decode it, the stored form.
    public static func displayName(ofDomain domain: String) -> String {
        URLComponents(string: assumedScheme + domain)?.host ?? domain
    }

    /// What a rule stores for a domain the user typed: `example.com`, `*.example.com` or a pasted
    /// address, reduced to its host. `www.` is kept as typed. An international name is stored as
    /// the punycode host `URL(string:)` gives; where that gives no ASCII host the input is refused,
    /// as is anything that is not a host name or an IP address.
    ///
    /// `includesSubdomains` is true unless the host is an IP address, which has no subdomains.
    public static func normalized(userInput: String) -> (domain: String, includesSubdomains: Bool)? {
        let trimmed = userInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard var domain = parsedHost(hasScheme(trimmed) ? trimmed : assumedScheme + trimmed) else { return nil }
        if domain.hasPrefix(wildcardPrefix) { domain.removeFirst(wildcardPrefix.count) }
        if isIPLiteral(domain) {
            return isAddress(domain) ? (domain, false) : nil
        }
        return isDomainName(domain) ? (domain, true) : nil
    }

    /// Whether a host is an IP address as a browser reads it: an IPv6 literal, or a name whose last
    /// label is a number. Such a host has no subdomains.
    static func isIPLiteral(_ host: String) -> Bool {
        if host.contains(":") { return true }
        guard let last = host.split(separator: ".", omittingEmptySubsequences: false).last else { return false }
        return !last.isEmpty && last.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func hasScheme(_ text: String) -> Bool {
        guard let separator = text.range(of: "://") else { return false }
        let scheme = text[..<separator.lowerBound]
        return !scheme.isEmpty && scheme.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || "+-.".contains($0)) }
    }

    /// A bare IPv6 address has to be bracketed before `URL(string:)` reads it as a host.
    private static func parsedHost(_ text: String) -> String? {
        if let url = URL(string: text), let host = host(of: url) { return host }
        guard let separator = text.range(of: "://") else { return nil }
        let rest = text[separator.upperBound...]
        guard rest.filter({ $0 == ":" }).count > 1, !rest.contains("[") else { return nil }
        return URL(string: String(text[..<separator.upperBound]) + "[" + rest + "]").flatMap(host(of:))
    }

    private static func isAddress(_ host: String) -> Bool {
        if host.contains(":") {
            return canonicalIPv6(host) != nil
        }
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        return parts.count == 4 && parts.allSatisfy { part in
            part.allSatisfy { $0.isASCII && $0.isNumber } && (UInt8(part) != nil)
        }
    }

    private static func isDomainName(_ host: String) -> Bool {
        guard host.count <= maxDomainLength else { return false }
        return host.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
        }
    }
}
