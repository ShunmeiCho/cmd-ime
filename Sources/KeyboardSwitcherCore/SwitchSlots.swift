import Foundation

public struct SwitchSlot: Codable, Equatable, Identifiable, Sendable {
    public let id: InputRole
    public var name: String
    public var tintHex: String

    public init(id: InputRole, name: String, tintHex: String) {
        self.id = id
        self.name = name
        self.tintHex = tintHex
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, tintHex
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedID = try container.decode(InputRole.self, forKey: .id)
        id = decodedID
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? Self.legacyDefaults.first(where: { $0.id == decodedID })?.name ?? decodedID.rawValue
        tintHex = try container.decodeIfPresent(String.self, forKey: .tintHex)
            ?? SlotPalette.nextColor(for: id, used: [])
    }

    public static let legacyDefaults: [SwitchSlot] = [
        SwitchSlot(id: .english, name: "English", tintHex: "#4D8CFF"),
        SwitchSlot(id: .chinese, name: "Chinese", tintHex: "#33A854"),
        SwitchSlot(id: .japanese, name: "Japanese", tintHex: "#E3574A"),
    ]
}

public enum SlotPalette {
    public static let colors = ["#4D8CFF", "#33A854", "#E3574A", "#9664D8", "#E49B35", "#32A6A8", "#D65B99", "#788697"]

    public static func nextColor(for id: InputRole, used: [String]) -> String {
        let used = Set(used.map { $0.uppercased() })
        if let legacy = SwitchSlot.legacyDefaults.first(where: { $0.id == id }), !used.contains(legacy.tintHex) {
            return legacy.tintHex
        }
        return colors.first { !used.contains($0) } ?? colors[used.count % colors.count]
    }
}

/// An in-memory undo receipt. Offsets refer to the configuration before removal.
/// Receipts are produced by removingSlotWithReceipt, not persisted in config JSON.
public struct RemovedSlot: Equatable, Sendable {
    public struct BindingEntry: Equatable, Sendable {
        public let offset: Int
        public let binding: KeyBinding
    }

    public let slot: SwitchSlot
    public let index: Int
    public let bindings: [BindingEntry]
    public let preference: RoleInputSourcePreference?
    public let customIndicatorColorHex: String?
}

/// Validation failures for pure slot edits. Unknown IDs never silently create slots.
public enum SlotError: Error, Equatable, LocalizedError, Sendable {
    case sourceAlreadyUsed
    case lastSlot
    /// A supplied name is empty after trimming whitespace and newlines.
    case invalidName
    case duplicateName
    case invalidTintHex(String)
    case unknownSlot(InputRole)
    case slotAlreadyExists(InputRole)
    /// The source has an empty ID, is not selectable, or is an auxiliary source.
    case invalidSource

    public var errorDescription: String? {
        switch self {
        case .sourceAlreadyUsed: "This input source is already preferred by another slot."
        case .lastSlot: "The last slot cannot be removed."
        case .invalidName: "A slot name cannot be empty."
        case .duplicateName: "Another slot already uses this name. Choose a different name."
        case let .invalidTintHex(input): "Invalid slot color \(input.debugDescription). Use six hexadecimal digits, such as #4D8CFF."
        case let .unknownSlot(id): "Unknown slot \"\(id.rawValue)\"."
        case let .slotAlreadyExists(id): "Slot \"\(id.rawValue)\" already exists."
        case .invalidSource: "Choose a selectable input source."
        }
    }
}

extension InputSourceInfo {
    public var primaryLanguage: String? {
        guard let first = languages.first else { return nil }
        let primary = first.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased().replacingOccurrences(of: "_", with: "-")
            .components(separatedBy: "-")[0]
        return primary.isEmpty ? nil : primary
    }

    public var badgeSymbol: String {
        switch primaryLanguage {
        case "en": "A"
        case "zh": "中"
        case "ja": "あ"
        case "ko": "한"
        case let language?: String(language.prefix(2)).uppercased()
        case nil: String(localizedName.prefix(1)).uppercased()
        }
    }
}

extension SwitcherConfig {
    /// Builds one slot per primary language, keeping the first eligible source in system order.
    /// If no slots can be detected, retains the legacy default configuration.
    public static func detected(from sources: [InputSourceInfo]) -> SwitcherConfig {
        var result = SwitcherConfig(slots: [], bindings: [], inputSources: [:])
        var languages: Set<String> = []
        for source in InputSourceMatcher.selectableSources(from: sources) {
            guard let language = source.primaryLanguage,
                  !languages.contains(language),
                  let added = try? result.addingSlot(for: source) else { continue }
            result = added.config
            languages.insert(language)
        }
        return result.slots.isEmpty ? .default : result
    }

    /// Replaces all slot-owned data, including remaps and custom slot colors,
    /// while retaining global settings. The original configuration is unchanged.
    public func rebuildingSlots(from sources: [InputSourceInfo]) -> SwitcherConfig {
        let detected = Self.detected(from: sources)
        var result = self
        result.version = Self.currentVersion
        result.slots = detected.slots
        result.bindings = detected.bindings
        result.inputSources = detected.inputSources
        result.switchIndicatorCustomRoleColorHexes = [:]
        return result
    }

    public func slot(_ id: InputRole) -> SwitchSlot? {
        slots.first { $0.id == id }
    }

    public func slot(matching query: String) -> SwitchSlot? {
        if let exact = slot(InputRole(rawValue: query)) { return exact }
        let matches = slots.filter {
            $0.id.rawValue.caseInsensitiveCompare(query) == .orderedSame
                || $0.name.caseInsensitiveCompare(query) == .orderedSame
        }
        return matches.count == 1 ? matches.first : nil
    }

    public func displayName(for role: InputRole) -> String {
        slot(role)?.name ?? role.rawValue
    }

    public func migrated() -> SwitcherConfig {
        var result = self
        result.version = max(version, Self.currentVersion)
        return result
    }

    public static func normalizedSlots(_ slots: [SwitchSlot], bindings: [KeyBinding]) -> [SwitchSlot] {
        var result: [SwitchSlot] = []
        var seen: Set<InputRole> = []
        for slot in slots.isEmpty ? SwitchSlot.legacyDefaults : slots {
            guard seen.insert(slot.id).inserted else { continue }
            result.append(slot)
        }
        for binding in bindings where binding.action.type == .switchInputSource {
            guard let id = binding.action.role, seen.insert(id).inserted else { continue }
            let legacy = SwitchSlot.legacyDefaults.first { $0.id == id }
            result.append(SwitchSlot(id: id, name: legacy?.name ?? id.rawValue,
                                     tintHex: SlotPalette.nextColor(for: id, used: result.map(\.tintHex))))
        }
        return result
    }

    public func unassignedSources(from sources: [InputSourceInfo]) -> [InputSourceInfo] {
        let resolved = Set(slots.compactMap { InputSourceMatcher.bestMatch(for: $0.id, sources: sources, config: self)?.id })
        return InputSourceMatcher.selectableSources(from: sources).filter { !resolved.contains($0.id) }
    }

    public func duplicateSlotIDs(for role: InputRole, sources: [InputSourceInfo]) -> [InputRole] {
        guard slot(role) != nil,
              let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: self) else { return [] }
        var seen: Set<InputRole> = [role]
        return slots.compactMap { slot in
            guard seen.insert(slot.id).inserted,
                  InputSourceMatcher.bestMatch(for: slot.id, sources: sources, config: self)?.id == source.id else { return nil }
            return slot.id
        }
    }

    public func nextFreeOneShotTrigger() -> KeyTrigger? {
        for name in ["left-command", "right-command", "left-option", "right-option", "left-control"] {
            guard let trigger = try? ShortcutParser.parse(name) else { continue }
            if !bindings.contains(where: { $0.enabled && $0.trigger.keyCode == trigger.keyCode }) { return trigger }
        }
        return nil
    }

    public func conflictingBinding(for trigger: KeyTrigger, excluding role: InputRole) -> KeyBinding? {
        bindings.first { binding in
            guard binding.enabled,
                  !(binding.action.type == .switchInputSource && binding.action.role == role),
                  binding.trigger.keyCode == trigger.keyCode else { return false }
            if trigger.kind == .oneShotModifier || binding.trigger.kind == .oneShotModifier { return true }
            return binding.trigger.gesture == trigger.gesture && Set(binding.trigger.modifiers) == Set(trigger.modifiers)
        }
    }

    public func addingSlot(for source: InputSourceInfo, name: String? = nil, at index: Int? = nil) throws(SlotError) -> (config: SwitcherConfig, slot: SwitchSlot) {
        try validateSource(source, excluding: nil)
        let languageName = source.primaryLanguage.flatMap { Locale(identifier: "en_US").localizedString(forLanguageCode: $0) }
        let base = Self.slug(languageName ?? source.localizedName)
        var id = InputRole(rawValue: base)
        var suffix = 2
        while slot(id) != nil {
            id = InputRole(rawValue: "\(base)-\(suffix)")
            suffix += 1
        }
        let sameLanguage = source.primaryLanguage.map { language in
            slots.contains { slot in
                let preference = preference(for: slot.id)
                return preference.fallbackLanguage == language
                    || (preference.fallbackLanguage == nil && preference.languagePrefixes.contains(language))
            }
        } ?? false
        let defaultName = sameLanguage ? source.localizedName : (languageName ?? source.localizedName)
        let trimmed = (name ?? defaultName).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidName }
        let slot = SwitchSlot(id: id, name: trimmed, tintHex: SlotPalette.nextColor(for: id, used: slots.map(\.tintHex)))
        var result = self
        result.slots.insert(slot, at: min(max(index ?? slots.count, 0), slots.count))
        result.inputSources[id.rawValue] = RoleInputSourcePreference(preferredIDs: [source.id], fallbackLanguage: source.primaryLanguage)
        if let trigger = nextFreeOneShotTrigger() {
            result.bindings.append(KeyBinding(trigger: trigger, action: .switchInputSource(id)))
        }
        return (result, slot)
    }

    public func assigningInputSource(_ source: InputSourceInfo, to role: InputRole) throws(SlotError) -> SwitcherConfig {
        guard slot(role) != nil else { throw .unknownSlot(role) }
        try validateSource(source, excluding: role)
        var result = self
        let preference = preference(for: role)
        // Legacy rules retain their ordered ID history and matching rules.
        if preference.fallbackLanguage == nil && (InputRole.legacy.contains(role) || !preference.languagePrefixes.isEmpty || !preference.nameContains.isEmpty) {
            result.pinInputSourceID(source.id, for: role)
        } else {
            var updated = preference
            updated.preferredIDs = [source.id]
            updated.fallbackLanguage = source.primaryLanguage
            result.inputSources[role.rawValue] = updated
        }
        return result
    }

    public func removingSlot(_ id: InputRole) throws(SlotError) -> SwitcherConfig {
        guard slot(id) != nil else { throw .unknownSlot(id) }
        guard Set(slots.map(\.id)).count > 1 else { throw .lastSlot }
        var result = self
        result.slots.removeAll { $0.id == id }
        result.bindings.removeAll { $0.action.type == .switchInputSource && $0.action.role == id }
        result.inputSources.removeValue(forKey: id.rawValue)
        result.switchIndicatorCustomRoleColorHexes.removeValue(forKey: id.rawValue)
        return result
    }

    public func removingSlotWithReceipt(_ id: InputRole) throws(SlotError) -> (config: SwitcherConfig, removed: RemovedSlot) {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { throw .unknownSlot(id) }
        let removed = RemovedSlot(
            slot: slots[index],
            index: index,
            bindings: bindings.enumerated().compactMap { offset, binding in
                guard binding.action.type == .switchInputSource, binding.action.role == id else { return nil }
                return RemovedSlot.BindingEntry(offset: offset, binding: binding)
            },
            preference: inputSources[id.rawValue],
            customIndicatorColorHex: switchIndicatorCustomRoleColorHexes[id.rawValue]
        )
        return (try removingSlot(id), removed)
    }

    /// Restores slot-owned data at its saved positions, clamping after intervening edits.
    /// ID/source ownership conflicts reject the whole operation. Enabled bindings
    /// whose triggers are now occupied are skipped and returned for a visible notice;
    /// disabled bindings are preserved because they do not reserve a trigger.
    public func restoringSlot(_ removed: RemovedSlot) throws(SlotError) -> (config: SwitcherConfig, skippedBindings: [RemovedSlot.BindingEntry]) {
        let id = removed.slot.id
        guard slot(id) == nil else { throw .slotAlreadyExists(id) }
        if let preferredID = removed.preference?.preferredIDs.first,
           slots.contains(where: { preference(for: $0.id).preferredIDs.first == preferredID }) {
            throw .sourceAlreadyUsed
        }

        var result = self
        result.slots.insert(removed.slot, at: min(max(removed.index, 0), result.slots.count))
        result.inputSources[id.rawValue] = removed.preference
        result.switchIndicatorCustomRoleColorHexes[id.rawValue] = removed.customIndicatorColorHex
        var skipped: [RemovedSlot.BindingEntry] = []
        for entry in removed.bindings {
            if entry.binding.enabled,
               result.conflictingBinding(for: entry.binding.trigger, excluding: id) != nil {
                skipped.append(entry)
                continue
            }
            let index = min(max(entry.offset - skipped.count, 0), result.bindings.count)
            result.bindings.insert(entry.binding, at: index)
        }
        return (result, skipped)
    }

    /// Destination is the final index, not an insertion index before removal.
    public func movingSlot(from source: Int, to destination: Int) -> SwitcherConfig {
        guard slots.indices.contains(source) else { return self }
        var result = self
        let slot = result.slots.remove(at: source)
        result.slots.insert(slot, at: min(max(destination, 0), result.slots.count))
        return result
    }

    public func movingSlot(_ id: InputRole, by offset: Int) -> SwitcherConfig {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { return self }
        // Clamp before adding so even Int.min/Int.max cannot overflow.
        let step = min(max(offset, -index), slots.count - 1 - index)
        return movingSlot(from: index, to: index + step)
    }

    public func renamingSlot(_ id: InputRole, to name: String) throws(SlotError) -> SwitcherConfig {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { throw .unknownSlot(id) }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .invalidName }
        guard !slots.contains(where: {
            $0.id != id && $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(trimmed) == .orderedSame
        }) else { throw .duplicateName }
        var result = self
        result.slots[index].name = trimmed
        return result
    }

    /// Sets only the slot's tint, normalized to uppercase #RRGGBB.
    public func settingSlotTint(_ hex: String, for id: InputRole) throws(SlotError) -> SwitcherConfig {
        guard let index = slots.firstIndex(where: { $0.id == id }) else { throw .unknownSlot(id) }
        let normalized = try Self.normalizedSlotTint(hex)
        var result = self
        result.slots[index].tintHex = normalized
        return result
    }

    private static func normalizedSlotTint(_ input: String) throws(SlotError) -> String {
        var hex = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.utf8.count == 6,
              hex.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else {
            throw .invalidTintHex(input)
        }
        return "#" + hex.uppercased()
    }

    private func validateSource(_ source: InputSourceInfo, excluding role: InputRole?) throws(SlotError) {
        guard !source.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !InputSourceMatcher.selectableSources(from: [source]).isEmpty else { throw .invalidSource }
        guard !slots.contains(where: { $0.id != role && preference(for: $0.id).preferredIDs.first == source.id }) else {
            throw .sourceAlreadyUsed
        }
    }

    private static func slug(_ text: String) -> String {
        let words = text.lowercased().components(separatedBy: CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789").inverted).filter { !$0.isEmpty }
        return words.isEmpty ? "slot" : words.joined(separator: "-")
    }
}

public extension SwitcherConfig {
    /// The slot whose enabled one-shot binding (tap or double tap) uses this physical
    /// modifier key, such as "right-shift". Used to draw the live keys strip from the
    /// real bindings instead of assuming the default ones.
    func slotID(forOneShotKeyName keyName: String) -> InputRole? {
        slotTriggers.first { $0.trigger.kind == .oneShotModifier && $0.trigger.keyName == keyName }?.slot
    }

    /// Enabled key-press (chord) triggers bound to existing slots, in slot order.
    var chordTriggers: [(slot: InputRole, trigger: KeyTrigger)] {
        slotTriggers.filter { $0.trigger.kind == .keyPress }
    }

    private var slotTriggers: [(slot: InputRole, trigger: KeyTrigger)] {
        slots.flatMap { slot in
            bindings.compactMap { binding -> (slot: InputRole, trigger: KeyTrigger)? in
                guard binding.enabled,
                      binding.action.type == .switchInputSource,
                      binding.action.role == slot.id
                else {
                    return nil
                }
                return (slot.id, binding.trigger)
            }
        }
    }
}
