import Foundation

/// A failure the lab has already investigated, so a user reading the report is told what is known
/// instead of being left with a bare FAIL.
///
/// A row belongs here only when the cause has been isolated on a real machine. Guesses stay out:
/// the point of the lab is to say what was measured.
public struct LabKnownIssue: Equatable, Sendable {
    public let sourceIDPrefix: String
    public let failure: LabFailure
    public let note: String

    static let all = [
        LabKnownIssue(
            sourceIDPrefix: "im.rime.inputmethod.Squirrel",
            failure: .producedLatin,
            note: "Known, and not caused by CmdIME: measured 2026-09-20 on macOS 27.0, this "
                + "happens to roughly one switch in five when latin was typed just before the "
                + "switch, and it happens with CmdIME not running at all, through a plain system "
                + "selection. Selecting twice, re-activating the app and sending a warm-up key "
                + "were each tried and none of them fixed it."
        ),
    ]

    public static func note(sourceID: String, failure: LabFailure) -> String? {
        all.first { sourceID.hasPrefix($0.sourceIDPrefix) && $0.failure == failure }?.note
    }
}
