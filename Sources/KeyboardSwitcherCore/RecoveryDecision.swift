import Foundation

/// What the accessibility layer found about the caret's surroundings, gathered once per request.
///
/// Everything here is read before anything is changed, so the decision below can be made — and
/// tested — without touching the user's document.
public struct RecoveryContext: Equatable, Sendable {
    /// Any process can turn Secure Event Input on, and while it is on no key we send can be
    /// trusted to land where we think it will.
    public let isSecureEventInput: Bool
    public let bundleID: String
    public let axRole: String
    public let axSubrole: String?
    public let isEditable: Bool
    /// True when the user has text selected. Recovery is defined against the caret, not a selection.
    public let hasSelection: Bool
    /// `nil` when the adapter cannot tell whether a composition is open. Not knowing is a refusal.
    public let hasMarkedText: Bool?
    public let textBeforeCaret: String
    public let targetSourceID: String?

    public init(
        isSecureEventInput: Bool,
        bundleID: String,
        axRole: String,
        axSubrole: String? = nil,
        isEditable: Bool,
        hasSelection: Bool,
        hasMarkedText: Bool?,
        textBeforeCaret: String,
        targetSourceID: String?
    ) {
        self.isSecureEventInput = isSecureEventInput
        self.bundleID = bundleID
        self.axRole = axRole
        self.axSubrole = axSubrole
        self.isEditable = isEditable
        self.hasSelection = hasSelection
        self.hasMarkedText = hasMarkedText
        self.textBeforeCaret = textBeforeCaret
        self.targetSourceID = targetSourceID
    }
}

/// Why recovery will not run. Each case carries the sentence the user is shown, because a refusal
/// the user cannot explain to themselves is indistinguishable from the feature being broken.
public enum RecoveryRefusal: Equatable, Sendable {
    case secureEventInput
    case passwordField
    case notEditable
    case unverifiedEditor(bundleID: String, role: String)
    case noChineseSource
    case unverifiedInputSource(id: String)
    case textSelected
    case alreadyComposing
    case compositionStateUnknown
    case nothingBeforeCaret
    case notPinyin(run: String)

    public var message: String {
        switch self {
        case .secureEventInput:
            return "Something on this Mac has secure keyboard entry on, so recovery stays out of the way."
        case .passwordField:
            return "This is a password field."
        case .notEditable:
            return "There is nothing editable here."
        case let .unverifiedEditor(bundleID, role):
            return "Recovery has not been proven in this editor yet (\(bundleID), \(role)), so it will not touch your text."
        case .noChineseSource:
            return "No Chinese input source is set for recovery."
        case let .unverifiedInputSource(id):
            return "Recovery has not been proven with \"\(id)\" yet."
        case .textSelected:
            return "Recovery works on the word before the caret. Clear the selection first."
        case .alreadyComposing:
            return "An input method is already composing here."
        case .compositionStateUnknown:
            return "Cannot tell whether this editor is composing, so recovery will not touch your text."
        case .nothingBeforeCaret:
            return "There are no latin letters before the caret."
        case let .notPinyin(run):
            return "\"\(run)\" does not read as pinyin."
        }
    }
}

public enum RecoveryDecision: Equatable, Sendable {
    /// The exact run to remove and replay. Nothing else may be touched.
    case recover(run: String)
    case refuse(RecoveryRefusal)
}

/// Decides whether one recovery request may proceed, and on exactly which characters.
///
/// The order of the checks is the order of their cost to the user: the ones that could leak or
/// damage something come before the ones that are merely disappointing.
public enum RecoveryPolicy {
    public static func decide(_ context: RecoveryContext, support: RecoverySupport = .verified) -> RecoveryDecision {
        if context.isSecureEventInput { return .refuse(.secureEventInput) }
        if context.axSubrole == "AXSecureTextField" { return .refuse(.passwordField) }
        guard context.isEditable else { return .refuse(.notEditable) }
        guard support.allows(bundleID: context.bundleID, axRole: context.axRole) else {
            return .refuse(.unverifiedEditor(bundleID: context.bundleID, role: context.axRole))
        }
        guard let targetSourceID = context.targetSourceID else { return .refuse(.noChineseSource) }
        guard support.allows(inputSourceID: targetSourceID) else {
            return .refuse(.unverifiedInputSource(id: targetSourceID))
        }
        if context.hasSelection { return .refuse(.textSelected) }
        guard let hasMarkedText = context.hasMarkedText else { return .refuse(.compositionStateUnknown) }
        if hasMarkedText { return .refuse(.alreadyComposing) }
        guard let run = PinyinRun.candidate(before: context.textBeforeCaret) else {
            return .refuse(.nothingBeforeCaret)
        }
        guard PinyinRun.isPlausible(run) else { return .refuse(.notPinyin(run: String(run))) }
        return .recover(run: String(run))
    }
}

/// The editor and input-source combinations recovery has actually been measured on.
///
/// A combination earns a row here by passing, on a real Mac, the whole gate: the run is replaced,
/// the replay composes, a candidate commits, and one Command+Z puts the original letters back —
/// both with candidates open and after a commit. Anything else is unsupported, and unsupported
/// means refused. We do not learn an editor's undo behaviour by experimenting on the user's text.
public struct RecoverySupport: Equatable, Sendable {
    public struct Editor: Equatable, Sendable {
        public let bundleID: String
        public let axRole: String
    }

    public let editors: [Editor]
    /// Matched as a prefix, so a source's language variants ride on one row.
    public let inputSourceIDPrefixes: [String]

    public init(editors: [Editor], inputSourceIDPrefixes: [String]) {
        self.editors = editors
        self.inputSourceIDPrefixes = inputSourceIDPrefixes
    }

    public func allows(bundleID: String, axRole: String) -> Bool {
        editors.contains { $0.bundleID == bundleID && $0.axRole == axRole }
    }

    public func allows(inputSourceID: String) -> Bool {
        inputSourceIDPrefixes.contains { inputSourceID.hasPrefix($0) }
    }

    /// Measured 2026-09-20 on macOS 27.0. See `.claude/work/reliability-lab.md`.
    public static let verified = RecoverySupport(
        editors: [Editor(bundleID: "com.apple.TextEdit", axRole: "AXTextArea")],
        inputSourceIDPrefixes: ["com.tencent.inputmethod.wetype.pinyin"]
    )
}
