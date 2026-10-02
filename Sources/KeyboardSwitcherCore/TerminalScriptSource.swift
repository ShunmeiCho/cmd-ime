import Foundation

/// Terminals that can say, through AppleScript, which program runs in their tab in front
/// (spec `terminal-association.md` v4). Pure: the caller sends the Apple Event and reports back.
public enum TerminalScriptSource {
    public enum Kind: Equatable, Sendable {
        /// Ghostty with `id` and `pid` on `terminal` (Ghostty main; not in 1.3.1).
        case ghostty
        /// Terminal.app: `tty` of the selected tab.
        case terminalApp
    }

    /// Whether a scripting dictionary (the app's `.sdef` text) declares what `script(for:)` asks for.
    public static func dictionaryOffers(_ kind: Kind, sdef: String) -> Bool {
        switch kind {
        case .ghostty: sdef.contains("name=\"pid\"") && sdef.contains("name=\"focused terminal\"")
        case .terminalApp: sdef.contains("name=\"tty\"")
        }
    }

    /// What one answer says about the tab in front.
    public enum Answer: Equatable, Sendable {
        /// The pane (a terminal id or a tty) and the foreground process, found one way or the other.
        case process(paneID: String, pid: Int32)
        case device(paneID: String, device: String)

        public var paneID: String {
            switch self {
            case .process(let pane, _), .device(let pane, _): pane
            }
        }
    }

    /// What two reads (terminal answer, then the kernel's program) taken one after the other say.
    public enum Confirmation: Equatable, Sendable {
        /// The same tab running the same program both times: that program (nil when the kernel could not name it).
        case program(paneID: String, name: String?)
        /// Another tab, or another program in the same tab: nothing is known yet; read again.
        case changed(paneID: String)
    }

    /// The program is kept only when the second read names the same tab and the same program, so a program
    /// that exits (or a tab that changes) between the reads never has its rule applied to what replaced it.
    public static func confirm(first: Answer, firstProgram: String?, second: Answer, secondProgram: String?) -> Confirmation {
        guard first.paneID == second.paneID, firstProgram == secondProgram else {
            return .changed(paneID: second.paneID)
        }
        return .program(paneID: first.paneID, name: firstProgram)
    }

    private static let fieldSeparator = "\t"
    private static let ghosttyBundleID = "com.mitchellh.ghostty"
    private static let terminalBundleID = "com.apple.Terminal"

    public static func kind(forBundleID bundleID: String) -> Kind? {
        switch bundleID {
        case ghosttyBundleID: .ghostty
        case terminalBundleID: .terminalApp
        default: nil
        }
    }

    /// The script that asks for the tab in front: one line, fields separated by a tab.
    public static func script(for kind: Kind) -> String {
        switch kind {
        case .ghostty:
            """
            tell application id "\(ghosttyBundleID)"
            set t to focused terminal of selected tab of front window
            return (id of t as text) & tab & (pid of t as text)
            end tell
            """
        case .terminalApp:
            """
            tell application id "\(terminalBundleID)"
            return tty of selected tab of front window
            end tell
            """
        }
    }

    /// The answer in a script's reply, or nil for a reply of another shape.
    public static func answer(kind: Kind, reply: String) -> Answer? {
        let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .ghostty:
            let fields = text.components(separatedBy: fieldSeparator)
            guard fields.count == 2, !fields[0].isEmpty, let pid = Int32(fields[1]), pid > 0 else { return nil }
            return .process(paneID: fields[0], pid: pid)
        case .terminalApp:
            guard text.hasPrefix("/dev/ttys"), text.count > "/dev/ttys".count, !text.contains(" ") else { return nil }
            return .device(paneID: text, device: text)
        }
    }

    /// Whether CmdIME asks a terminal app at all. Whether it CAN answer is decided before, from its
    /// own scripting dictionary (`dictionaryOffers`); a failed query never proves the opposite (a
    /// window that closed, no window yet, a timeout), so it is only "cannot tell this time". The one
    /// failure that stops the asking is a refused Automation consent.
    public struct Availability: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case untried
            case available
            /// The user refused Automation consent; not asked again while CmdIME runs.
            case refused
        }

        public private(set) var state: State = .untried

        public init() {}

        public func shouldAsk(appPID: Int32) -> Bool {
            state != .refused
        }

        public mutating func answered() {
            state = .available
        }

        /// The Apple Event error code a failed query returned.
        public mutating func failed(errorCode: Int, appPID: Int32) {
            if errorCode == Self.notAuthorized {
                state = .refused
            }
        }

        /// errAEEventNotPermitted: Automation consent refused.
        static let notAuthorized = -1743
    }
}
