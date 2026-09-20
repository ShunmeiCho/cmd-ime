import Foundation

/// The shape of a run's failures, because a pass rate on its own has been measured to mislead.
///
/// On 2026-09-20 the same build, unchanged, produced nine failures in a row and then sixteen
/// passes in a row. A run of six that all passed would have called that build reliable; a run of
/// six taken an hour earlier would have called it broken. Both numbers were real. What separates
/// them is not the rate but whether failures arrive independently or in runs, and a report that
/// hides that is a report we could not defend.
public struct LabRunShape: Equatable, Sendable {
    public let attempts: Int
    public let failures: Int
    public let longestFailureStreak: Int
    public let longestPassStreak: Int
    public let clustering: LabClustering

    /// Judged attempts only. `unjudged` and `void` say something about the run, not the slot.
    public init(verdicts: [LabVerdict]) {
        let outcomes: [Bool] = verdicts.compactMap { verdict in
            switch verdict {
            case .pass: true
            case .fail: false
            case .unjudged, .void: nil
            }
        }
        attempts = outcomes.count
        failures = outcomes.filter { !$0 }.count
        longestFailureStreak = Self.longestStreak(of: false, in: outcomes)
        longestPassStreak = Self.longestStreak(of: true, in: outcomes)
        clustering = LabClustering(outcomes: outcomes)
    }

    private static func longestStreak(of value: Bool, in outcomes: [Bool]) -> Int {
        var longest = 0
        var current = 0
        for outcome in outcomes {
            current = outcome == value ? current + 1 : 0
            longest = max(longest, current)
        }
        return longest
    }

    public var failureRate: Double {
        attempts == 0 ? 0 : Double(failures) / Double(attempts)
    }

    /// One line for the report, in the terms the reader has to act on.
    public var summary: String {
        guard attempts > 0 else { return "no judged attempts" }
        let percent = Int((failureRate * 100).rounded())
        var line = "\(attempts) attempts, \(failures) failed (\(percent)%)"
        if failures > 0 {
            line += "; longest run of failures \(longestFailureStreak), of passes \(longestPassStreak)"
        }
        return line + ". " + clustering.summary
    }
}

/// Whether failures arrive independently or in runs.
///
/// Measured by counting runs — blocks of consecutive same results — and comparing that count with
/// what independent results of the same rate would give. Fewer runs than expected means the
/// failures are bunched. A conditional rate ("after a failure, how often does the next one fail")
/// cannot do this job: once the overall failure rate is high there is no room above it for the
/// conditional rate to rise into, and a badly bunched run reads as ordinary.
///
/// It refuses to read at all from too few failures, which is the whole point: the lab must not do
/// to itself what it warns users about.
public enum LabClustering: Equatable, Sendable {
    /// Not enough failures to say anything either way.
    case tooFewFailures(Int)
    /// Nothing passed, so there is no order to read — and nothing to argue about either.
    case everyAttemptFailed(Int)
    /// Markedly fewer runs than independent results would give: failures arrive in blocks.
    case clustered(runs: Int, expected: Double)
    /// Nothing in the order separates this from independent results.
    case noPattern(runs: Int, expected: Double)

    /// Below this many failures the normal approximation behind the test is not trustworthy.
    static let minimumFailures = 5
    /// Two standard deviations below the expected count, the usual bar for "not chance".
    static let significantZ = -1.96

    init(outcomes: [Bool]) {
        let failures = outcomes.filter { !$0 }.count
        let passes = outcomes.count - failures
        guard passes > 0 else {
            self = failures > 0 ? .everyAttemptFailed(failures) : .tooFewFailures(0)
            return
        }
        guard failures >= Self.minimumFailures else {
            self = .tooFewFailures(failures)
            return
        }
        let runs = zip(outcomes, outcomes.dropFirst()).reduce(1) { $0 + ($1.0 == $1.1 ? 0 : 1) }
        let total = Double(outcomes.count)
        let product = 2 * Double(passes) * Double(failures)
        let expected = product / total + 1
        let variance = product * (product - total) / (total * total * (total - 1))
        guard variance > 0 else {
            self = .tooFewFailures(failures)
            return
        }
        let z = (Double(runs) - expected) / variance.squareRoot()
        self = z <= Self.significantZ
            ? .clustered(runs: runs, expected: expected)
            : .noPattern(runs: runs, expected: expected)
    }

    public var summary: String {
        switch self {
        case let .everyAttemptFailed(count):
            return "Every one of the \(count) attempts failed; there is no passing run to compare against."
        case let .tooFewFailures(count):
            return count == 0
                ? "No failures here, which is not the same as none."
                : "Only \(count) failures: too few to say whether they come in runs."
        case let .clustered(runs, expected):
            return "Failures come in blocks: \(runs) runs where \(String(format: "%.1f", expected)) "
                + "would be expected if each attempt stood alone. A short passing run proves little here."
        case let .noPattern(runs, expected):
            return "No blocking: \(runs) runs against \(String(format: "%.1f", expected)) expected "
                + "if each attempt stood alone."
        }
    }
}
