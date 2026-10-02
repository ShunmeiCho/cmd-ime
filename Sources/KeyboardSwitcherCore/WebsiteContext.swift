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
    /// For a terminal, the pane the program was read in, as its multiplexer names it. Nil for a
    /// page, and for a terminal window that shows no pane the reader can name.
    public var paneID: String?

    public init(pid: Int32, generation: Int, sequence: Int, context: WebsiteContext, paneID: String? = nil) {
        self.pid = pid
        self.generation = generation
        self.sequence = sequence
        self.context = context
        self.paneID = paneID
    }
}

/// What the program in a terminal's focused pane is, as far as Program Rules care: the same three
/// answers as for a page, with the program's name in `rule`. A surface no source can answer for
/// (a plain terminal tab) is `noRule`, not `unknown`: there is nothing to wait for.
public typealias ProgramContext = WebsiteContext
/// One read of that program, stamped like a read of a page.
public typealias ProgramReading = WebsiteReading
