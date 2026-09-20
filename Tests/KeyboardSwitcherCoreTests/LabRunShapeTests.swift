import XCTest
@testable import KeyboardSwitcherCore

final class LabRunShapeTests: XCTestCase {
    /// `p` for pass, `f` for fail, so a run reads as the sequence it was.
    private func shape(_ run: String) -> LabRunShape {
        LabRunShape(verdicts: run.map { $0 == "p" ? .pass : .fail(.producedLatin) })
    }

    func testCountsOnlyJudgedAttempts() {
        let verdicts: [LabVerdict] = [
            .pass, .fail(.producedLatin), .void(reason: "not run"), .unjudged(reason: "no expectation"),
        ]
        let shape = LabRunShape(verdicts: verdicts)
        XCTAssertEqual(shape.attempts, 2)
        XCTAssertEqual(shape.failures, 1)
    }

    func testMeasuresTheLongestRunOfEach() {
        let shape = shape("ppfffppppf")
        XCTAssertEqual(shape.longestFailureStreak, 3)
        XCTAssertEqual(shape.longestPassStreak, 4)
    }

    /// The run that started this: nine failures, then sixteen passes, one unchanged build.
    func testCallsABlockOfFailuresClustered() {
        guard case let .clustered(runs, expected) = shape("fffffffffpppppppppppppppp").clustering
        else { return XCTFail("a block of failures should read as clustered") }
        XCTAssertEqual(runs, 2)
        XCTAssertGreaterThan(expected, 10)
    }

    /// The reason the conditional rate was dropped: at a high failure rate it has no room to rise,
    /// so a badly blocked run used to read as ordinary.
    func testFindsBlockingEvenWhenMostAttemptsFail() {
        guard case .clustered = shape("ffffffffffffffffpppp").clustering else {
            return XCTFail("16 failures then 4 passes is blocked however high the rate is")
        }
    }

    func testAlternatingFailuresShowNoBlocking() {
        guard case .noPattern = shape("pfpfpfpfpfpf").clustering else {
            return XCTFail("alternating failures are the opposite of blocked")
        }
    }

    /// The lab must not do to itself what it warns users about: a handful of failures cannot
    /// support a claim either way.
    func testRefusesToReadTooFewFailures() {
        XCTAssertEqual(shape("ppppppppppffp").clustering, .tooFewFailures(2))
        XCTAssertEqual(shape("pppppp").clustering, .tooFewFailures(0))
    }

    func testSummaryNamesTheRateAndTheShape() {
        let summary = shape("ffffffffpppppppp").summary
        XCTAssertTrue(summary.contains("16 attempts, 8 failed (50%)"), summary)
        XCTAssertTrue(summary.contains("longest run of failures 8"), summary)
        XCTAssertTrue(summary.contains("come in blocks"), summary)
    }

    /// A run where nothing passed is not a short run; the runs test simply has nothing to compare.
    func testSaysSoWhenEveryAttemptFailed() {
        XCTAssertEqual(shape("ffffffffffffff").clustering, .everyAttemptFailed(14))
        XCTAssertTrue(shape("ffffffffffffff").summary.contains("Every one of the 14 attempts failed"))
    }

    func testSaysSoWhenThereIsNothingToJudge() {
        XCTAssertEqual(LabRunShape(verdicts: []).summary, "no judged attempts")
    }
}
