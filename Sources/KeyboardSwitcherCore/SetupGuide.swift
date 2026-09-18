import Foundation

/// The three steps of the first-run setup guide, in the order they are walked.
public enum SetupStep: Int, CaseIterable, Comparable, Sendable {
    /// Allow keyboard access: Accessibility and Input Monitoring.
    case permissions = 1
    /// Check what was detected: confirm or change the detected slots.
    case review
    /// Try it: trigger the bound slots once.
    case tryIt

    public static func < (lhs: SetupStep, rhs: SetupStep) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Everything the setup guide needs to know. Plain values only, so the derivation
/// stays testable without AppKit or a live permission check.
public struct SetupGuideInput: Equatable, Sendable {
    public var accessibilityGranted: Bool
    public var inputMonitoringGranted: Bool
    public var listenerRunning: Bool
    /// The keyboard listener could not start. With both permissions granted this
    /// usually means macOS wants the app restarted before the grant takes effect.
    public var listenerFailed: Bool
    public var selectableSourceCount: Int
    public var slotCount: Int
    /// Slots that have at least one enabled switch trigger.
    public var boundSlotCount: Int
    /// Slots a fresh detection would create from the installed sources right now.
    public var detectableSlotCount: Int
    /// Session-only: the user pressed "Looks right" in the review step. Never persisted.
    public var hasConfirmedSlots: Bool
    public var hasCompletedSetup: Bool

    public init(
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        listenerRunning: Bool,
        listenerFailed: Bool = false,
        selectableSourceCount: Int,
        slotCount: Int,
        boundSlotCount: Int,
        detectableSlotCount: Int,
        hasConfirmedSlots: Bool,
        hasCompletedSetup: Bool
    ) {
        self.accessibilityGranted = accessibilityGranted
        self.inputMonitoringGranted = inputMonitoringGranted
        self.listenerRunning = listenerRunning
        self.listenerFailed = listenerFailed
        self.selectableSourceCount = selectableSourceCount
        self.slotCount = slotCount
        self.boundSlotCount = boundSlotCount
        self.detectableSlotCount = detectableSlotCount
        self.hasConfirmedSlots = hasConfirmedSlots
        self.hasCompletedSetup = hasCompletedSetup
    }

    /// Counts sources, slots and bound slots from the live configuration.
    public init(
        config: SwitcherConfig,
        sources: [InputSourceInfo],
        accessibilityGranted: Bool,
        inputMonitoringGranted: Bool,
        listenerRunning: Bool,
        listenerFailed: Bool = false,
        hasConfirmedSlots: Bool
    ) {
        let boundSlotIDs = Set(config.bindings.compactMap { binding -> InputRole? in
            guard binding.enabled, binding.action.type == .switchInputSource else { return nil }
            return binding.action.role
        })
        self.init(
            accessibilityGranted: accessibilityGranted,
            inputMonitoringGranted: inputMonitoringGranted,
            listenerRunning: listenerRunning,
            listenerFailed: listenerFailed,
            selectableSourceCount: InputSourceMatcher.selectableSources(from: sources).count,
            slotCount: config.slots.count,
            boundSlotCount: config.slots.filter { boundSlotIDs.contains($0.id) }.count,
            detectableSlotCount: SwitcherConfig.detectableSlotCount(from: sources),
            hasConfirmedSlots: hasConfirmedSlots,
            hasCompletedSetup: config.hasCompletedSetup
        )
    }
}

/// The derived state of the setup guide. The current step is never stored.
public struct SetupGuideState: Equatable, Sendable {
    /// Switching needs at least this many selectable input sources.
    public static let minimumSourceCount = 2
    /// Detection binds a key to this many slots at most; see `nextFreeOneShotTrigger`.
    public static let automaticTriggerLimit = 5

    /// The step to show, or nil once the guide is finished or skipped.
    public let currentStep: SetupStep?
    /// Fewer than two selectable sources: there is nothing to switch between yet.
    public let needsMoreSources: Bool
    /// At least one current slot has no enabled switch trigger.
    public let hasUnboundSlots: Bool
    /// Both permissions read as granted, yet the listener failed: offer a relaunch.
    public let shouldOfferRelaunch: Bool
    /// Detection left a single slot and would find more now. Counting sources is not
    /// enough: several sources of one language still detect as one slot.
    public let canDetectAgain: Bool

    public init(_ input: SetupGuideInput) {
        let permissionsGranted = input.accessibilityGranted && input.inputMonitoringGranted
        if input.hasCompletedSetup {
            currentStep = nil
        } else if !permissionsGranted || !input.listenerRunning || input.listenerFailed {
            // Permission grants alone do not prove the listener can receive triggers.
            currentStep = .permissions
        } else if !input.hasConfirmedSlots {
            currentStep = .review
        } else {
            currentStep = .tryIt
        }
        needsMoreSources = input.selectableSourceCount < Self.minimumSourceCount
        hasUnboundSlots = input.boundSlotCount < input.slotCount
        shouldOfferRelaunch = permissionsGranted && input.listenerFailed
        canDetectAgain = input.slotCount < Self.minimumSourceCount
            && input.detectableSlotCount > input.slotCount
    }

    public var isFinished: Bool {
        currentStep == nil
    }

    /// True for steps the guide has already passed, and for every step once finished.
    public func isComplete(_ step: SetupStep) -> Bool {
        guard let currentStep else { return true }
        return step < currentStep
    }
}

/// The current slots that still need a switch trigger, in their visible order.
/// This intentionally reports the live configuration instead of inferring why a
/// key is absent from the first-run automatic assignment policy.
public struct SetupUnboundSlots: Equatable, Sendable {
    /// Names shown before the remaining slots are summarized by count.
    public static let displayedNameLimit = 3

    public let names: [String]
    private let slotCount: Int

    public init(config: SwitcherConfig) {
        let boundIDs = Set(config.slotTriggers.map(\.slot))
        names = config.slots.filter { !boundIDs.contains($0.id) }.map(\.name)
        slotCount = config.slots.count
    }

    public var hasUnboundSlots: Bool {
        !names.isEmpty
    }

    /// Setup-guide copy for the current missing bindings. The automatic limit is
    /// described as first-run policy only; it never claims which slots received keys.
    public var notice: String? {
        guard !names.isEmpty else { return nil }

        let namesText: String
        if names.count <= Self.displayedNameLimit {
            namesText = names.joined(separator: ", ")
        } else {
            namesText = "\(names.prefix(Self.displayedNameLimit).joined(separator: ", ")), and \(names.count - Self.displayedNameLimit) more"
        }
        let currentState = names.count == 1
            ? "\(namesText) has no trigger yet."
            : "\(names.count) slots have no trigger yet: \(namesText)."
        let policy = slotCount > SetupGuideState.automaticTriggerLimit
            ? " On first detection, CmdIME automatically assigns up to \(SetupGuideState.automaticTriggerLimit) keys."
            : ""
        return "\(currentState) Use Change to bind one.\(policy)"
    }
}

extension SwitcherConfig {
    /// The same configuration with the setup guide marked finished or skipped.
    public func completingSetup(whatsNewVersion: String? = nil) -> SwitcherConfig {
        var result = self
        result.hasCompletedSetup = true
        if let whatsNewVersion {
            result.lastSeenWhatsNewVersion = whatsNewVersion
        }
        return result
    }

    /// How many slots `detected(from:)` would create from these sources. Zero when
    /// it would fall back to the legacy defaults, which is not a detection result.
    public static func detectableSlotCount(from sources: [InputSourceInfo]) -> Int {
        let fresh = detected(from: sources)
        return fresh == .default ? 0 : fresh.slots.count
    }
}

extension ConfigLoadResult {
    /// The configuration `keyboardctl` starts from. With no file yet, whatever the CLI
    /// writes is not a GUI first run, so the setup guide stays hidden for it. A pending
    /// first run that the GUI already saved is left pending.
    public var configForCLI: SwitcherConfig {
        isFirstRun ? config.completingSetup() : config
    }
}
