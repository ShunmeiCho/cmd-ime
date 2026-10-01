import Foundation
import KeyboardSwitcherCore

/// `keyboardctl website-rule`: Website Rules (CONTEXT.md) from the command line. Like every config
/// edit here, the running app picks the change up only after a relaunch. Nothing here reads a
/// browser: `test` matches an address the user types.
extension CLI {
    private static let websiteRuleUsage = "Usage: keyboardctl website-rule list | set <domain> <slot|keep> [--exact] | remove <domain> | test <url>"
    private static let exactFlag = "--exact"
    private static let assumedScheme = "https://"

    func manageWebsiteRule() throws {
        let store = ConfigStore(url: configURL)
        switch try argument(at: 1, name: "list, set, remove or test") {
        case "list":
            guard args.count == 2 else { throw CLIError.invalidArgument(Self.websiteRuleUsage) }
            printWebsiteRules(try loadConfig(from: store))
        case "set":
            try setWebsiteRule(store: store)
        case "remove":
            guard args.count == 3 else { throw CLIError.invalidArgument(Self.websiteRuleUsage) }
            let typed = try argument(at: 2, name: "domain")
            // A rule is stored under its normalized domain; one edited by hand is found as typed.
            let domain = WebsiteHost.normalized(userInput: typed)?.domain ?? typed
            let config = try loadConfig(from: store)
            guard config.websiteRule(for: domain) != nil else {
                throw CLIError.invalidArgument("No rule for \(domain). Run \"keyboardctl website-rule list\".")
            }
            try save(config.removingWebsiteRule(for: domain), to: store)
            print("Removed the rule for \(domain)")
        case "test":
            guard args.count == 3 else { throw CLIError.invalidArgument(Self.websiteRuleUsage) }
            try testWebsiteRule(try argument(at: 2, name: "url"), in: try loadConfig(from: store))
        case let operation:
            throw CLIError.unknownCommand("website-rule \(operation)")
        }
    }

    private func setWebsiteRule(store: ConfigStore) throws {
        var positional: [String] = []
        var exact = false
        for argument in args.dropFirst(2) {
            if argument == Self.exactFlag {
                exact = true
            } else {
                guard !argument.hasPrefix("--") else { throw CLIError.invalidArgument(Self.websiteRuleUsage) }
                positional.append(argument)
            }
        }
        guard positional.count == 2 else { throw CLIError.invalidArgument(Self.websiteRuleUsage) }
        guard let normalized = WebsiteHost.normalized(userInput: positional[0]) else {
            throw CLIError.invalidArgument("\(positional[0]) is not a website. Give a domain such as example.com, *.example.com or a page address.")
        }
        let config = try loadConfig(from: store)
        // "keep" is a word, not a slot query, so it wins over a slot whose name starts with it.
        let target: AppRuleTarget = positional[1] == Self.keepWord
            ? .keepAsIs
            : .slot(try requireSlot(positional[1], in: config).id)
        let rule = WebsiteRule(
            domain: normalized.domain,
            includesSubdomains: normalized.includesSubdomains && !exact,
            target: target
        )
        try save(config.setting(rule), to: store)
        print(description(of: rule, in: config))
    }

    private func printWebsiteRules(_ config: SwitcherConfig) {
        guard !config.websiteRules.isEmpty else {
            print("No website rules. Add one with \"keyboardctl website-rule set <domain> <slot|keep>\".")
            return
        }
        print("domain\tsubdomains\ttarget")
        for rule in config.websiteRules {
            print("\(rule.domain)\t\(rule.includesSubdomains ? "yes" : "no")\t\(targetDescription(rule.target, in: config))")
        }
    }

    /// Which rule an address the user typed falls under. An address without a scheme is read as https.
    private func testWebsiteRule(_ typed: String, in config: SwitcherConfig) throws {
        let address = typed.contains("://") ? typed : Self.assumedScheme + typed
        guard let host = URL(string: address).flatMap(WebsiteHost.host(of:)) else {
            throw CLIError.invalidArgument("\(typed) is not an http or https address.")
        }
        if let rule = WebsiteRuleMatcher.match(host: host, in: config.websiteRules) {
            print(description(of: rule, in: config))
        } else {
            print("no rule")
        }
    }

    private func description(of rule: WebsiteRule, in config: SwitcherConfig) -> String {
        let scope = rule.includesSubdomains ? "and subdomains" : "exact"
        return "\(rule.domain) (\(scope)): \(targetDescription(rule.target, in: config))"
    }
}
