import Foundation

/// What the page in front of a browser is, as far as website rules care. The page address itself
/// never leaves the reader: only the domain of the matched rule, which the user wrote, does.
public enum WebsiteContext: Equatable, Sendable {
    /// Focus is outside a page (address bar, tab strip) or the page could not be read.
    case unknown
    case noRule
    /// The domain of the matching website rule.
    case rule(String)
}

/// One read, stamped so that a result that arrives late can be told from a current one.
public struct WebsiteReading: Equatable, Sendable {
    public var pid: Int32
    /// `AppMemoryTracker.activationGeneration` when the watcher was pointed at this browser.
    public var generation: Int
    /// Counts up per watcher; an older read never overrides a newer one.
    public var sequence: Int
    public var context: WebsiteContext

    public init(pid: Int32, generation: Int, sequence: Int, context: WebsiteContext) {
        self.pid = pid
        self.generation = generation
        self.sequence = sequence
        self.context = context
    }
}
