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
        var lanes = slotIDs.map { id in
            Lane(target: .slot(id), slotExists: true, rules: config.appRules.filter { $0.target == .slot(id) })
        }
        var deleted: [InputRole] = []
        for rule in config.appRules {
            if case .slot(let id) = rule.target, !slotIDs.contains(id), !deleted.contains(id) {
                deleted.append(id)
            }
        }
        lanes += deleted.map { id in
            Lane(target: .slot(id), slotExists: false, rules: config.appRules.filter { $0.target == .slot(id) })
        }
        lanes.append(Lane(target: .keepAsIs, slotExists: true, rules: config.appRules.filter { $0.target == .keepAsIs }))
        return lanes
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
        guard !appID.isEmpty else { return .refused("That is not an app.") }
        guard appID != ownAppID else { return .refused("CmdIME never switches input sources for itself.") }
        let existing = config.appRule(for: appID)
        guard existing?.target != target else { return .unchanged }
        if case .slot(let id) = target, config.slot(id) == nil {
            return .refused("That slot was deleted. Drop the app on another slot.")
        }
        let rule = AppRule(
            appID: appID,
            name: name ?? existing?.name,
            target: target,
            rememberInstead: target == .keepAsIs ? false : existing?.rememberInstead ?? false
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

/// The text a dragged app or rule chip carries inside the settings window. Other text dropped on
/// the board is not an app and is ignored.
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
