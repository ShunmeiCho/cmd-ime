import Foundation

/// When the website watcher reads the page in front. It holds no timer and no clock: the thread
/// that owns it passes the time in, asks `nextReadDue` how long to sleep, and reports each read
/// with `beginRead(at:)` and `readFinished(at:outcome:)`. Times are seconds on any one monotonic
/// clock.
///
/// - A browser coming to the front is read at once.
/// - A notification is read `debounce` after the last one, but never later than `maxWait` after
///   the first one no read has covered, so a page that keeps renaming itself is still read.
/// - One read is in flight at most. Notifications that arrive during it become one more read.
/// - A read that could not tell, after an activation or a notification, is repeated after each of
///   `retryIntervals`, counted from the end of the read before it. A newer notification, a new
///   activation or `stopped()` ends the retries.
public struct WebsiteReadScheduler: Equatable, Sendable {
    public static let debounce: TimeInterval = 0.030
    public static let maxWait: TimeInterval = 0.100
    /// Quick at first (a tab that is still loading), then wider: a browser that has just been
    /// launched answers only after a second or two (device acceptance, 2026-10-02: Chrome opened on
    /// a ruled page kept the old input source with 0.8 s of retries), and nothing notifies when its
    /// page becomes readable.
    public static let retryIntervals: [TimeInterval] = [0.2, 0.2, 0.2, 0.2, 0.5, 1, 1, 1.5]
    public static let retryInterval = retryIntervals[0]
    public static let maxRetries = retryIntervals.count

    public enum Outcome: Equatable, Sendable {
        /// The read named the page: a rule's domain, or no rule.
        case answered
        /// The read could not tell (no web area yet, focus in the address bar, a timeout).
        case unknown
    }

    private var isWatching = false
    private var activationDue: TimeInterval?
    private var firstUnreadNotification: TimeInterval?
    private var lastUnreadNotification: TimeInterval?
    private var retryDue: TimeInterval?
    private var retriesLeft = 0
    public private(set) var isReadInFlight = false

    public init() {}

    /// A browser to read came to the front, or the one in front changed (a retarget): whatever was
    /// waiting belonged to the previous one and is dropped, and a read is due now.
    public mutating func activated(at now: TimeInterval) {
        clearPending()
        isWatching = true
        activationDue = now
    }

    /// Nothing to read any more. A read still in flight has to be reported as finished.
    public mutating func stopped() {
        clearPending()
        isWatching = false
    }

    /// An accessibility notification from the browser in front.
    public mutating func notified(at now: TimeInterval) {
        guard isWatching else { return }
        if firstUnreadNotification == nil { firstUnreadNotification = now }
        lastUnreadNotification = now
        retryDue = nil
        retriesLeft = 0
    }

    /// When the next read should start, or nil when none is waiting or one is in flight. A time
    /// that has already passed means now.
    public var nextReadDue: TimeInterval? {
        guard !isReadInFlight else { return nil }
        if let activationDue { return activationDue }
        if let first = firstUnreadNotification, let last = lastUnreadNotification {
            return min(last + Self.debounce, first + Self.maxWait)
        }
        return retryDue
    }

    /// Starts the read that is due at `now`. False, and nothing changes, when none is due yet or
    /// one is already in flight; on true the caller reads and then calls `readFinished`.
    public mutating func beginRead(at now: TimeInterval) -> Bool {
        guard let due = nextReadDue, due <= now else { return false }
        if activationDue != nil || firstUnreadNotification != nil {
            retriesLeft = Self.maxRetries
        } else {
            retriesLeft -= 1
        }
        clearWaitingReads()
        isReadInFlight = true
        return true
    }

    public mutating func readFinished(at now: TimeInterval, outcome: Outcome) {
        guard isReadInFlight else { return }
        isReadInFlight = false
        // An activation or a notification during the read gets its own read and its own retries.
        guard activationDue == nil, firstUnreadNotification == nil else { return }
        if isWatching, outcome == .unknown, retriesLeft > 0 {
            retryDue = now + Self.retryIntervals[Self.maxRetries - retriesLeft]
        } else {
            retriesLeft = 0
        }
    }

    private mutating func clearWaitingReads() {
        activationDue = nil
        firstUnreadNotification = nil
        lastUnreadNotification = nil
        retryDue = nil
    }

    private mutating func clearPending() {
        clearWaitingReads()
        retriesLeft = 0
    }
}
