import Foundation
import Testing
@testable import KeyboardSwitcherCore

private let debounce = WebsiteReadScheduler.debounce
private let maxWait = WebsiteReadScheduler.maxWait
private let retryInterval = WebsiteReadScheduler.retryInterval
private let tolerance = 1e-9

/// A scheduler watching a browser whose activation read has already answered.
private func settledScheduler() -> WebsiteReadScheduler {
    var scheduler = WebsiteReadScheduler()
    scheduler.activated(at: 0)
    #expect(begin(&scheduler, at: 0))
    scheduler.readFinished(at: 0, outcome: .answered)
    return scheduler
}

/// `beginRead` mutates, which `#expect` cannot take directly.
private func begin(_ scheduler: inout WebsiteReadScheduler, at now: TimeInterval) -> Bool {
    scheduler.beginRead(at: now)
}

/// Runs the read that is due, as the watcher thread would, and returns when it started.
private func runDueRead(_ scheduler: inout WebsiteReadScheduler, outcome: WebsiteReadScheduler.Outcome) throws -> TimeInterval {
    let due = try #require(scheduler.nextReadDue)
    #expect(begin(&scheduler, at: due))
    scheduler.readFinished(at: due, outcome: outcome)
    return due
}

struct WebsiteReadSchedulerTests {
    @Test("nothing is due before a browser is watched, and a notification then is ignored")
    func idleUntilActivated() {
        var scheduler = WebsiteReadScheduler()

        scheduler.notified(at: 1)

        #expect(scheduler.nextReadDue == nil)
        #expect(!begin(&scheduler, at: 2))
    }

    @Test("an activation is read at once")
    func activationReadsAtOnce() {
        var scheduler = WebsiteReadScheduler()

        scheduler.activated(at: 5)

        #expect(scheduler.nextReadDue == 5)
        #expect(begin(&scheduler, at: 5))
    }

    @Test("a first notification is read after the debounce, well within the max wait")
    func firstNotificationReadsAfterDebounce() throws {
        var scheduler = settledScheduler()

        scheduler.notified(at: 1)

        let due = try #require(scheduler.nextReadDue)
        #expect(abs(due - (1 + debounce)) < tolerance)
        #expect(due <= 1 + maxWait)
        #expect(!begin(&scheduler, at: 1 + debounce / 2))
        #expect(begin(&scheduler, at: due))
    }

    @Test("a title that changes every 100 ms is read every 100 ms")
    func slowStormReadsEveryNotification() throws {
        var scheduler = settledScheduler()
        var reads: [TimeInterval] = []

        for step in 0..<5 {
            scheduler.notified(at: 1 + Double(step) * 0.100)
            reads.append(try runDueRead(&scheduler, outcome: .answered))
        }

        #expect(reads.count == 5)
        #expect(zip(reads, reads.dropFirst()).allSatisfy { $1 - $0 <= maxWait + tolerance })
    }

    @Test("notifications faster than the debounce are still read no later than the max wait after the first")
    func fastStormReadsAtMaxWait() throws {
        var scheduler = settledScheduler()
        var reads: [TimeInterval] = []
        var firstUnread: TimeInterval?

        // A title set every 20 ms for a second: the debounce alone would never fire.
        for step in 0..<50 {
            let now = 1 + Double(step) * 0.020
            if let due = scheduler.nextReadDue, due <= now {
                #expect(due <= (firstUnread ?? due) + maxWait + tolerance)
                reads.append(try runDueRead(&scheduler, outcome: .answered))
                firstUnread = nil
            }
            scheduler.notified(at: now)
            firstUnread = firstUnread ?? now
        }

        #expect((5...10).contains(reads.count))
    }

    @Test("only one read is in flight")
    func oneReadInFlight() {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)

        #expect(begin(&scheduler, at: 0))

        #expect(scheduler.isReadInFlight)
        #expect(scheduler.nextReadDue == nil)
        scheduler.notified(at: 0.01)
        #expect(scheduler.nextReadDue == nil)
        #expect(!begin(&scheduler, at: 1))
    }

    @Test("notifications during a read give exactly one follow-up read")
    func notificationsDuringReadGiveOneFollowUp() throws {
        var scheduler = settledScheduler()
        scheduler.notified(at: 1)
        #expect(begin(&scheduler, at: 1 + debounce))

        scheduler.notified(at: 1.04)
        scheduler.notified(at: 1.05)
        scheduler.notified(at: 1.06)
        scheduler.readFinished(at: 1.07, outcome: .answered)

        let followUp = try runDueRead(&scheduler, outcome: .answered)
        #expect(abs(followUp - (1.06 + debounce)) < tolerance)
        #expect(scheduler.nextReadDue == nil)
    }

    @Test("a read that could not tell is retried four times, 200 ms apart, then given up")
    func unknownReadIsRetried() throws {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)
        var reads: [TimeInterval] = []

        while scheduler.nextReadDue != nil {
            reads.append(try runDueRead(&scheduler, outcome: .unknown))
        }

        #expect(reads.count == 1 + WebsiteReadScheduler.maxRetries)
        #expect(zip(reads, reads.dropFirst()).allSatisfy { abs($1 - $0 - retryInterval) < tolerance })
    }

    @Test("a retry that answers ends the retries")
    func answeredRetryStops() throws {
        var scheduler = settledScheduler()
        scheduler.notified(at: 1)
        _ = try runDueRead(&scheduler, outcome: .unknown)

        _ = try runDueRead(&scheduler, outcome: .answered)

        #expect(scheduler.nextReadDue == nil)
    }

    @Test("a newer notification cancels the retries and starts its own")
    func notificationCancelsRetries() throws {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)
        _ = try runDueRead(&scheduler, outcome: .unknown)
        _ = try runDueRead(&scheduler, outcome: .unknown)
        #expect(scheduler.nextReadDue == 2 * retryInterval)

        scheduler.notified(at: 0.25)

        #expect(try runDueRead(&scheduler, outcome: .answered) == 0.25 + debounce)
        #expect(scheduler.nextReadDue == nil)
    }

    @Test("a notification during a retry read replaces the retries with its own read")
    func notificationDuringRetryRead() throws {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)
        _ = try runDueRead(&scheduler, outcome: .unknown)
        #expect(begin(&scheduler, at: retryInterval))

        scheduler.notified(at: 0.21)
        scheduler.readFinished(at: 0.22, outcome: .unknown)

        #expect(scheduler.nextReadDue == 0.21 + debounce)
    }

    @Test("a retarget drops what was waiting, reads the new browser at once and gives it fresh retries")
    func retargetCancelsAndReadsAtOnce() throws {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)
        _ = try runDueRead(&scheduler, outcome: .unknown)
        scheduler.notified(at: 0.05)

        scheduler.activated(at: 0.06)

        #expect(scheduler.nextReadDue == 0.06)
        var reads = 0
        while scheduler.nextReadDue != nil {
            _ = try runDueRead(&scheduler, outcome: .unknown)
            reads += 1
        }
        #expect(reads == 1 + WebsiteReadScheduler.maxRetries)
    }

    @Test("a retarget during a read waits for it, then reads at once without retrying the old read")
    func retargetDuringRead() {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)
        #expect(begin(&scheduler, at: 0))

        scheduler.activated(at: 0.01)

        #expect(scheduler.nextReadDue == nil)
        scheduler.readFinished(at: 0.02, outcome: .unknown)
        #expect(scheduler.nextReadDue == 0.01)
        #expect(begin(&scheduler, at: 0.02))
    }

    @Test("stopping drops every waiting read and retry")
    func stoppedSchedulesNothing() throws {
        var scheduler = WebsiteReadScheduler()
        scheduler.activated(at: 0)
        _ = try runDueRead(&scheduler, outcome: .unknown)

        scheduler.stopped()
        scheduler.notified(at: 0.1)

        #expect(scheduler.nextReadDue == nil)
    }
}
