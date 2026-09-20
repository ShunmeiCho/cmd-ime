import Foundation

/// What one attempt of the reliability lab observed in the text client.
public struct LabObservation: Equatable, Sendable {
    /// The text the client held before the attempt typed anything; expected to be empty.
    public let textBefore: String
    /// What a plain letter produced while the baseline latin source was selected. An input method
    /// still attached to the client shows up here, before the slot under test is blamed for it.
    public let baselineText: String
    /// The text the client holds after the keys and the commit key.
    public let text: String
    /// What the system reported as the current source after the switch. Context only: it is cached
    /// per process and has been observed to lie while the correct script was being typed.
    public let reportedSourceID: String?

    public init(textBefore: String, baselineText: String, text: String, reportedSourceID: String?) {
        self.textBefore = textBefore
        self.baselineText = baselineText
        self.text = text
        self.reportedSourceID = reportedSourceID
    }
}

/// The result of one attempt. `void` attempts say something about the run, not about the product,
/// and are retried rather than counted.
public enum LabVerdict: Equatable, Sendable {
    case pass
    case fail(LabFailure)
    /// No expectation covers this input source, so nothing is claimed about it.
    case unjudged(reason: String)
    /// The attempt could not be trusted and has to be repeated.
    case void(reason: String)
}

public enum LabFailure: String, Equatable, Sendable, Codable {
    /// The keys produced plain latin letters: the switch was reported and the user still types English.
    case producedLatin
    /// Text came out, but not in the script this input source should produce.
    case producedWrongScript
    /// Nothing reached the client at all.
    case producedNothing

    public var message: String {
        switch self {
        case .producedLatin: "typed latin letters instead of the slot's language"
        case .producedWrongScript: "typed text in the wrong script"
        case .producedNothing: "produced no text at all"
        }
    }
}

public enum LabJudge {
    /// Judges one attempt. The committed text decides; the reported input source id never does.
    public static func judge(_ observation: LabObservation, expectation: LabExpectation?) -> LabVerdict {
        guard observation.textBefore.isEmpty else {
            return .void(reason: "the text field was not empty before the attempt")
        }
        // A previous input method still attached to this client would fail the slot under test for
        // something it did not do, so the baseline letter is checked first.
        guard !observation.baselineText.isEmpty else {
            return .void(reason: "the baseline latin source produced nothing")
        }
        guard observation.baselineText.allSatisfy(\.isASCII) else {
            return .void(reason: "the baseline latin source did not produce latin letters")
        }
        guard let expectation else {
            return .unjudged(reason: "no expectation covers this input source")
        }
        guard expectation.isVerified else {
            return .unjudged(reason: "the expectation for this input source has never been verified on a real Mac")
        }

        let text = observation.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .fail(.producedNothing) }
        guard !expectation.accepts(text) else { return .pass }
        return .fail(text.allSatisfy(\.isASCII) ? .producedLatin : .producedWrongScript)
    }
}
