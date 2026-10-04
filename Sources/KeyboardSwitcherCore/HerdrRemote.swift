import Foundation

/// A saved SSH machine from `herdr machine list --json`.
public struct HerdrMachine: Equatable, Sendable {
    public let id: String
    public let label: String
    /// The ssh target as saved: `venus`, `user@venus.lan`, `venus:2222`.
    public let target: String
    public let isEnabled: Bool
    public let isSelected: Bool

    public init(id: String, label: String, target: String, isEnabled: Bool, isSelected: Bool) {
        self.id = id
        self.label = label
        self.target = target
        self.isEnabled = isEnabled
        self.isSelected = isSelected
    }
}

/// How CmdIME reads another machine's Herdr panes, which only the herdr CLI can ask (`--machine`,
/// one ssh round trip per call, nothing pushed). Pure: the CLI is run by the caller.
public enum HerdrRemote {
    /// How long one CLI call may take. A call reuses the TUI's ssh connection (about 0.4 s,
    /// measured 2026-10-04); without it the CLI connects anew, which can take seconds.
    public static let callBudget: TimeInterval = 2.5
    /// How long a terminal's own target waits for the first read of a remote pane (three calls).
    public static let holdBudget: TimeInterval = 2
    /// The waits after one, two, three... failed reads in a row; the last repeats.
    public static let backoffIntervals: [TimeInterval] = [2, 5, 10, 30]

    /// The machine a Herdr window title names, when it is not this Mac. Herdr writes the host name
    /// of the server the panes run on (`{hostname}: ...`), which is not always a machine's label:
    /// the label or the host part of the ssh target is matched first, and when neither does, the one
    /// machine the client has selected (Herdr updates that about a second after the view changes).
    /// Disabled machines are never asked.
    public static func machine(titleMachine: String, localMachine: String?, machines: [HerdrMachine]) -> HerdrMachine? {
        guard titleMachine != localMachine else { return nil }
        let enabled = machines.filter(\.isEnabled)
        let named = enabled.filter { $0.label == titleMachine || shortHost(ofTarget: $0.target) == titleMachine }
        if named.count == 1 { return named.first }
        guard named.isEmpty else { return nil }
        let selected = enabled.filter(\.isSelected)
        return selected.count == 1 ? selected.first : nil
    }

    /// The host of an ssh target up to its first dot, without user or port.
    static func shortHost(ofTarget target: String) -> String {
        var host = Substring(target)
        if let at = host.lastIndex(of: "@") { host = host[host.index(after: at)...] }
        if let colon = host.firstIndex(of: ":") { host = host[..<colon] }
        if let dot = host.firstIndex(of: ".") { host = host[..<dot] }
        return String(host)
    }

    /// A remote pane's id as the tracker sees it. Ids are scoped to one server, so `w1:p1` on
    /// another machine must not read as the local `w1:p1`.
    public static func paneID(machineID: String, paneID: String) -> String {
        "machine:\(machineID)/\(paneID)"
    }

    public static func paneListArguments(machineID: String) -> [String] {
        ["--machine", machineID, "pane", "list"]
    }

    public static func processInfoArguments(machineID: String, paneID: String) -> [String] {
        ["--machine", machineID, "pane", "process-info", "--pane", paneID]
    }

    public static let machineListArguments = ["machine", "list", "--json"]

    /// Places a herdr binary is installed to; an app launched from Finder has no shell PATH.
    public static func binaryCandidates(home: String) -> [String] {
        ["/opt/homebrew/bin/herdr", "/usr/local/bin/herdr", home + "/.local/bin/herdr", home + "/.cargo/bin/herdr"]
    }

    /// Spaces out reads of a machine that does not answer, so an unreachable one costs a call now
    /// and then instead of every second.
    public struct Backoff: Equatable, Sendable {
        private var failures = 0

        public init() {}

        /// The wait before the next read after this one failed.
        public mutating func failed() -> TimeInterval {
            failures += 1
            return HerdrRemote.backoffIntervals[min(failures, HerdrRemote.backoffIntervals.count) - 1]
        }

        public mutating func succeeded() {
            failures = 0
        }
    }
}

/// Which expiry ends a terminal's wait for its first read. Every wait gets the short budget; a
/// watcher that finds a slow surface (another machine's Herdr) asks for the longer one before the
/// short budget is up, and then only the longer expiry counts. Asked late, nothing is extended.
public struct SurfaceHoldExtension: Equatable, Sendable {
    private var extendedGeneration: Int?

    public init() {}

    /// Whether the wait for `generation` is extended now. `waitingGeneration` is the generation
    /// whose wait has not expired yet, or nil.
    public mutating func extend(generation: Int, waitingGeneration: Int?) -> Bool {
        guard generation == waitingGeneration, extendedGeneration != generation else { return false }
        extendedGeneration = generation
        return true
    }

    /// Whether an expiry for `generation` ends the wait: the short one does unless the wait was
    /// extended, the extended one always does.
    public func counts(generation: Int, isExtended: Bool) -> Bool {
        isExtended || extendedGeneration != generation
    }
}
