import Foundation
import KeyboardSwitcherCore

#if os(macOS)
import AppKit
#endif

/// `keyboardctl app-rule`: App Rules (CONTEXT.md) from the command line. Like every config edit
/// here, the running app picks the change up only after a relaunch.
extension CLI {
    static let keepWord = "keep"
    private static let appRuleUsage = "Usage: keyboardctl app-rule list | set <bundle-id|--frontmost> <slot|keep> [--remember] | remove <bundle-id> | launcher-default [english|apps|<slot>]"
    private static let englishWord = "english"
    private static let sameAsAppsWord = "apps"

    func manageAppRule() throws {
        let store = ConfigStore(url: configURL)
        switch try argument(at: 1, name: "list, set, remove or launcher-default") {
        case "list":
            guard args.count == 2 else { throw CLIError.invalidArgument(Self.appRuleUsage) }
            printAppRules(try loadConfig(from: store))
        case "set":
            try setAppRule(store: store)
        case "remove":
            guard args.count == 3 else { throw CLIError.invalidArgument(Self.appRuleUsage) }
            let appID = try argument(at: 2, name: "bundle-id")
            let config = try loadConfig(from: store)
            guard config.appRule(for: appID) != nil else {
                throw CLIError.invalidArgument("No rule for \(appID). Run \"keyboardctl app-rule list\".")
            }
            try save(config.removingAppRule(for: appID), to: store)
            print("Removed the rule for \(appID)")
        case "launcher-default":
            try setLauncherDefault(store: store)
        case let operation:
            throw CLIError.unknownCommand("app-rule \(operation)")
        }
    }

    private func setAppRule(store: ConfigStore) throws {
        var positional: [String] = []
        var remember = false
        var frontmost = false
        for argument in args.dropFirst(2) {
            switch argument {
            case "--remember": remember = true
            case "--frontmost": frontmost = true
            default:
                guard !argument.hasPrefix("--") else { throw CLIError.invalidArgument(Self.appRuleUsage) }
                positional.append(argument)
            }
        }
        guard positional.count == (frontmost ? 1 : 2) else { throw CLIError.invalidArgument(Self.appRuleUsage) }
        let app = try frontmost ? frontmostApp() : (id: positional[0], name: nil)
        let config = try loadConfig(from: store)
        // "keep" is a word, not a slot query, so it wins over a slot whose name starts with it.
        let targetQuery = positional[positional.count - 1]
        let target: AppRuleTarget = targetQuery == Self.keepWord
            ? .keepAsIs
            : .slot(try requireSlot(targetQuery, in: config).id)
        guard !remember || target != .keepAsIs else {
            throw CLIError.invalidArgument("--remember needs a slot; \"keep\" never restores.")
        }
        let name = app.name ?? config.appRule(for: app.id)?.name
        try save(config.setting(AppRule(appID: app.id, name: name, target: target, rememberInstead: remember)), to: store)
        print("\(app.name ?? app.id): \(targetDescription(target, in: config))\(remember ? ", remember instead" : "")")
    }

    /// With no value, prints what launchers open in. "english" and "apps" are words, not slot
    /// queries, so they win over a slot whose name starts with them.
    private func setLauncherDefault(store: ConfigStore) throws {
        guard args.count <= 3 else { throw CLIError.invalidArgument(Self.appRuleUsage) }
        let config = try loadConfig(from: store)
        guard args.count == 3 else {
            print("Launchers without a rule or memory: \(launcherDefaultDescription(config.launcherDefault, in: config))")
            return
        }
        let query = try argument(at: 2, name: "english, apps or a slot")
        let value: LauncherDefault = switch query {
        case Self.englishWord: .english
        case Self.sameAsAppsWord: .sameAsOtherApps
        default: .slot(try requireSlot(query, in: config).id)
        }
        var next = config
        next.launcherDefault = value
        try save(next, to: store)
        print("Launchers without a rule or memory: \(launcherDefaultDescription(value, in: next))")
    }

    func launcherDefaultDescription(_ value: LauncherDefault, in config: SwitcherConfig) -> String {
        switch value {
        case .english: "english"
        case .slot(let slot) where config.slot(slot) == nil: "\(slot.rawValue) (slot deleted, english)"
        case .slot(let slot): "slot \(config.displayName(for: slot))"
        case .sameAsOtherApps: "same as other apps"
        }
    }

    private func printAppRules(_ config: SwitcherConfig) {
        if config.appRules.isEmpty {
            print("No app rules. Add one with \"keyboardctl app-rule set <bundle-id> <slot|keep>\".")
        } else {
            print("app\tname\ttarget\tremember")
            for rule in config.appRules {
                let remember = rule.rememberInstead ? "yes" : "no"
                print("\(rule.appID)\t\(rule.name ?? "")\t\(targetDescription(rule.target, in: config))\t\(remember)")
            }
        }
        let fallback = config.appDefaultSlot.map { "slot \(config.displayName(for: $0))" } ?? "keep as is"
        print("Apps without a rule or memory: \(fallback)")
        print("Launchers without a rule or memory: \(launcherDefaultDescription(config.launcherDefault, in: config))")
    }

    func targetDescription(_ target: AppRuleTarget, in config: SwitcherConfig) -> String {
        switch target {
        case .keepAsIs: "keep as is"
        case .slot(let slot) where config.slot(slot) == nil: "\(slot.rawValue) (slot deleted)"
        case .slot(let slot): slot.rawValue
        }
    }

    /// The app in front when the command runs, keyed the way the running app keys it.
    private func frontmostApp() throws -> (id: String, name: String?) {
        #if os(macOS)
        let app = NSWorkspace.shared.frontmostApplication
        guard let id = app?.bundleIdentifier ?? app?.executableURL?.path else {
            throw CLIError.invalidArgument("Could not tell which app is in front.")
        }
        return (id, app?.localizedName)
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }
}
