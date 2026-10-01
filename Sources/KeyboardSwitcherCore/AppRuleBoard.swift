import Foundation

/// The Apps page's rule board (CONTEXT.md, App Rule): one lane per slot plus "Keep as is", the
/// apps that can be dragged onto a lane, and what a drop does. The page only draws it.
public enum AppRuleBoard {
    public struct Lane: Equatable, Sendable {
        public let target: AppRuleTarget
        /// False for a lane kept only because rules still name a deleted slot.
        public let slotExists: Bool
        /// In the order the user added them.
        public let rules: [AppRule]
        /// The website chips of this lane, one per domain, in the order the user added them.
        public let websiteRules: [WebsiteRule]
    }

    public enum DropResult: Equatable, Sendable {
        /// The app already had this rule.
        case unchanged
        case changed(SwitcherConfig)
        case refused(String)
    }

    /// Slot lanes in slot order, then a lane for each deleted slot a rule still names (never
    /// hidden, so such a rule stays visible), then "Keep as is".
    public static func lanes(for config: SwitcherConfig) -> [Lane] {
        let slotIDs = config.slots.map(\.id)
        let websiteRules = config.websiteRules.uniquedByDomain()
        func lane(_ target: AppRuleTarget, slotExists: Bool) -> Lane {
            Lane(
                target: target,
                slotExists: slotExists,
                rules: config.appRules.filter { $0.target == target },
                websiteRules: websiteRules.filter { $0.target == target }
            )
        }
        var deleted: [InputRole] = []
        for target in config.appRules.map(\.target) + websiteRules.map(\.target) {
            if case .slot(let id) = target, !slotIDs.contains(id), !deleted.contains(id) {
                deleted.append(id)
            }
        }
        return slotIDs.map { lane(.slot($0), slotExists: true) }
            + deleted.map { lane(.slot($0), slotExists: false) }
            + [lane(.keepAsIs, slotExists: true)]
    }

    /// Dropping an app on a lane creates its rule or moves the existing one where it stands in the
    /// list. Remember survives a move between slots; "Keep as is" never remembers. A lane for a
    /// deleted slot takes no new apps (a chip dropped back on it changes nothing), and CmdIME
    /// itself never gets a rule.
    public static func drop(
        appID: String,
        name: String?,
        on target: AppRuleTarget,
        in config: SwitcherConfig,
        ownAppID: String?
    ) -> DropResult {
        guard !appID.isEmpty else { return .refused(CoreLocalization.text("That is not an app.")) }
        guard appID != ownAppID else { return .refused(CoreLocalization.text("CmdIME never switches input sources for itself.")) }
        let existing = config.appRule(for: appID)
        guard existing?.target != target else { return .unchanged }
        if case .slot(let id) = target, config.slot(id) == nil {
            return .refused(CoreLocalization.text("That slot was deleted. Drop the app on another slot."))
        }
        let rule = AppRule(
            appID: appID,
            name: name ?? existing?.name,
            target: target,
            rememberInstead: target == .keepAsIs ? false : existing?.rememberInstead ?? false
        )
        return .changed(config.setting(rule))
    }

    /// Dropping a website chip on a lane moves its rule where it stands in the list and keeps its
    /// subdomain setting; a domain with no rule yet gets one, with `includesSubdomains` (on when
    /// not given). A lane for a deleted slot takes no new websites (a chip dropped back on it
    /// changes nothing).
    public static func drop(
        websiteDomain domain: String,
        includesSubdomains: Bool? = nil,
        on target: AppRuleTarget,
        in config: SwitcherConfig
    ) -> DropResult {
        guard !domain.isEmpty else { return .refused(CoreLocalization.text("That is not a website.")) }
        let existing = config.websiteRule(for: domain)
        guard existing?.target != target else { return .unchanged }
        if case .slot(let id) = target, config.slot(id) == nil {
            return .refused(CoreLocalization.text("That slot was deleted. Drop the website on another slot."))
        }
        let rule = WebsiteRule(
            match: existing?.match ?? .domain,
            domain: domain,
            includesSubdomains: existing?.includesSubdomains ?? includesSubdomains ?? true,
            target: target
        )
        return .changed(config.setting(rule))
    }

    /// The key App Memory and App Rules use for an app: its bundle id, or the executable path of an
    /// app that has none. Nil when neither is known.
    public static func appID(bundleIdentifier: String?, executablePath: String?) -> String? {
        if let bundleIdentifier, !bundleIdentifier.isEmpty { return bundleIdentifier }
        if let executablePath, !executablePath.isEmpty { return executablePath }
        return nil
    }
}

/// An app the board offers for dragging.
public struct AppCandidate: Hashable, Sendable {
    public let id: String
    public let name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

public enum AppCandidateList {
    /// What the board's app list shows. Without a query, the running apps; with one, running and
    /// installed apps whose name or id contains it (case and accents ignored). Running apps come
    /// first, each app once, by name; apps that already have a rule and CmdIME itself are left out.
    public static func visible(
        running: [AppCandidate],
        installed: [AppCandidate],
        ruledIDs: Set<String>,
        ownAppID: String?,
        query: String
    ) -> [AppCandidate] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let pools = trimmed.isEmpty ? [running] : [running, installed]
        var seen = ruledIDs
        if let ownAppID { seen.insert(ownAppID) }
        var result: [AppCandidate] = []
        for pool in pools {
            let matching = pool.filter { trimmed.isEmpty || matches($0, trimmed) }
            for app in byName(matching) where !seen.contains(app.id) {
                seen.insert(app.id)
                result.append(app)
            }
        }
        return result
    }

    private static func matches(_ app: AppCandidate, _ query: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        return app.name.range(of: query, options: options) != nil || app.id.range(of: query, options: options) != nil
    }

    private static func byName(_ apps: [AppCandidate]) -> [AppCandidate] {
        apps.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// What a dragged app or rule chip carries inside the settings window, as UTF-8 under the board's
/// private drag types (never as plain text, so it cannot land in another app). Anything that does
/// not decode is not an app and is ignored.
public enum AppDragPayload {
    static let prefix = "cmdime-app\n"

    public static func encode(appID: String, name: String) -> String {
        prefix + appID + "\n" + name
    }

    public static func decode(_ text: String) -> (appID: String, name: String?)? {
        guard text.hasPrefix(prefix) else { return nil }
        let fields = text.dropFirst(prefix.count).split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        guard let id = fields.first, !id.isEmpty else { return nil }
        let name = fields.count > 1 && !fields[1].isEmpty ? String(fields[1]) : nil
        return (String(id), name)
    }
}
