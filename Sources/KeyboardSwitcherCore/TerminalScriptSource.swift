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

    /// What one answer says about the tab in front.
    public enum Answer: Equatable, Sendable {
        /// The pane (a terminal id or a tty) and the foreground process, found one way or the other.
        case process(paneID: String, pid: Int32)
        case device(paneID: String, device: String)
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

    /// Whether CmdIME asks a terminal app at all. A script error that says the property does not
    /// exist (an older Ghostty) or a refusal by Automation consent stops the asking; other errors
    /// are treated as "cannot tell this time".
    public struct Availability: Equatable, Sendable {
        public enum State: Equatable, Sendable {
            case untried
            case available
            /// Lacks the property; tried again after the app is relaunched (a new pid).
            case unsupported(pid: Int32)
            /// The user refused Automation consent; not asked again while CmdIME runs.
            case refused
        }

        public private(set) var state: State = .untried

        public init() {}

        /// Ask now? A relaunched app (another pid) is tried once more after `unsupported`.
        public func shouldAsk(appPID: Int32) -> Bool {
            switch state {
            case .untried, .available: true
            case .unsupported(let pid): pid != appPID
            case .refused: false
            }
        }

        public mutating func answered() {
            state = .available
        }

        /// The Apple Event error code a failed query returned.
        public mutating func failed(errorCode: Int, appPID: Int32) {
            switch errorCode {
            case Self.notAuthorized:
                state = .refused
            case Self.noSuchProperty, Self.cannotGet where state != .available:
                state = .unsupported(pid: appPID)
            default:
                break
            }
        }

        /// errAEEventNotPermitted: Automation consent refused.
        static let notAuthorized = -1743
        /// errAEUnknownObjectType / errAENoSuchObject-like replies for a property the app's
        /// dictionary lacks; seen as -1728 ("Can't get") from Ghostty 1.3.1 (measured 2026-10-02).
        static let cannotGet = -1728
        static let noSuchProperty = -10000
    }
}
