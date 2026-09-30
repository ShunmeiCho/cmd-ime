import Foundation

/// What `keyboardctl diagnose` prints and what Settings copies with Copy Diagnostics:
/// each slot's configured preference and the source `InputSourceMatcher.match` picks
/// for it, the same match the switch pipeline makes. It names input sources and
/// settings only; nothing typed is in it.
public struct DiagnosisReport: Encodable, Equatable, Sendable {
    public struct SlotEntry: Encodable, Equatable, Sendable {
        public let slot: String
        public let name: String
        public let duplicateSlots: [String]
        public let preferredIDs: [String]
        public let fallbackLanguage: String?
        public let languagePrefixes: [String]
        public let nameContains: [String]
        public let matchedSourceID: String?
        public let matchedSourceName: String?
        public let matchedSourceLanguages: [String]?
        public let matchTier: String
        public let matchedValue: String?
    }

    public let currentInputSourceID: String?
    public let currentInputSourceName: String?
    public let rememberInputSourcePerApp: Bool
    public let appRuleCount: Int
    /// Display name of the slot for apps with no rule and no memory; nil keeps the source.
    public let appDefaultSlot: String?
    public let restoreAfterPasswordField: Bool
    public let systemPerDocumentSwitching: Bool
    public let slots: [SlotEntry]

    public init(
        current: InputSourceInfo?,
        config: SwitcherConfig,
        sources: [InputSourceInfo],
        systemPerDocumentSwitching: Bool
    ) {
        currentInputSourceID = current?.id
        currentInputSourceName = current?.localizedName
        rememberInputSourcePerApp = config.rememberInputSourcePerApp
        appRuleCount = config.appRules.count
        appDefaultSlot = config.appDefaultSlot.map { config.displayName(for: $0) }
        restoreAfterPasswordField = config.restoreAfterPasswordField
        self.systemPerDocumentSwitching = systemPerDocumentSwitching
        slots = config.slots.map { slot in
            let preference = config.preference(for: slot.id)
            let result = InputSourceMatcher.match(for: slot.id, sources: sources, config: config)
            return SlotEntry(
                slot: slot.id.rawValue,
                name: slot.name,
                duplicateSlots: config.duplicateSlotIDs(for: slot.id, sources: sources).map(\.rawValue),
                preferredIDs: preference.preferredIDs,
                fallbackLanguage: preference.fallbackLanguage,
                languagePrefixes: preference.languagePrefixes,
                nameContains: preference.nameContains,
                matchedSourceID: result.source?.id,
                matchedSourceName: result.source?.localizedName,
                matchedSourceLanguages: result.source?.languages,
                matchTier: result.tier.rawValue,
                matchedValue: result.matchedValue
            )
        }
    }

    public var json: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Every field is a string, number, bool or array of them; encoding cannot fail.
        let data = (try? encoder.encode(self)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// The lines Copy Diagnostics puts above `text`: what only the running app knows.
    public static func appSummary(
        appVersion: String,
        build: String?,
        macOSVersion: OperatingSystemVersion,
        keyboardControl: String,
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool
    ) -> String {
        [
            "CmdIME \(appVersion)\(build.map { " (\($0))" } ?? "")",
            IssueReport.macOSName(macOSVersion),
            "Keyboard control: \(keyboardControl)",
            "Accessibility: \(accessibilityGranted ? "granted" : "not granted")",
            "Input Monitoring: \(inputMonitoringGranted ? "granted" : "not granted")",
        ].joined(separator: "\n")
    }

    public var text: String {
        var lines: [String] = []
        let current = currentInputSourceID.map { id in "\(currentInputSourceName ?? id) (\(id))" } ?? "unknown"
        lines.append("Current input source: \(current)")
        // App Memory itself lives in the running app's memory; only the setting is in the config.
        lines.append("Remember input source per app: \(rememberInputSourcePerApp ? "on" : "off")")
        lines.append("App rules: \(appRuleCount); apps without a rule: \(appDefaultSlot ?? "keep as is"); "
            + "switch back after password fields: \(restoreAfterPasswordField ? "on" : "off")")
        if systemPerDocumentSwitching {
            lines.append("macOS \"Automatically switch to a document's input source\": on (it fights per-app memory)")
        }
        for entry in slots {
            lines.append("")
            lines.append("[\(entry.slot)] \(entry.name)")
            if !entry.duplicateSlots.isEmpty {
                lines.append("  duplicate with: \(entry.duplicateSlots.joined(separator: ", "))")
            }
            lines.append("  preferredIDs: \(entry.preferredIDs.joined(separator: ", "))")
            if let language = entry.fallbackLanguage {
                lines.append("  fallbackLanguage: \(language)")
            }
            lines.append("  languagePrefixes: \(entry.languagePrefixes.joined(separator: ", "))")
            lines.append("  nameContains: \(entry.nameContains.joined(separator: ", "))")
            if let id = entry.matchedSourceID {
                let languages = (entry.matchedSourceLanguages ?? []).joined(separator: ",")
                lines.append("  matched: \(entry.matchedSourceName ?? id) (\(id)) languages=\(languages)")
            } else {
                lines.append("  matched: none")
            }
            let matchedValueText = entry.matchedValue.map { " (\($0))" } ?? ""
            lines.append("  reason: \(entry.matchTier)\(matchedValueText)")
        }
        return lines.joined(separator: "\n")
    }
}
