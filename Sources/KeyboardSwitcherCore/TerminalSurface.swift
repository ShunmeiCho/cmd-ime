import Foundation

/// Apps that show terminal panes, by bundle id: the only apps asked which program is in front for
/// Program Rules. A multiplexer runs inside any of them, so the list names terminals, not sources.
public enum TerminalCatalog {
    private static let bundleIDs: Set<String> = [
        "com.mitchellh.ghostty",
        "com.apple.Terminal",
        "com.googlecode.iterm2",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
        "org.alacritty",
        "dev.warp.Warp-Stable",
    ]

    public static func isTerminal(_ bundleID: String) -> Bool {
        bundleIDs.contains(bundleID)
    }
}

/// What CmdIME says to a local Herdr server, and how it tells that Herdr is what a terminal window
/// shows. Pure: the socket and the window title are read by the caller.
public enum HerdrSurface {
    /// The focus events a pane, tab or workspace switch pushes.
    private static let focusEventTypes = ["pane.focused", "tab.focused", "workspace.focused"]
    private static let titleSeparator = ": "

    /// The machine a window title drawn by Herdr starts with ("junming: keyboard" names junming):
    /// the text before the first ": " when it is one word. Nil for a title of another shape, which
    /// is how a plain terminal tab reads. The rest of the title is not looked at.
    public static func machine(inWindowTitle title: String) -> String? {
        guard let separator = title.range(of: titleSeparator) else { return nil }
        let machine = title[..<separator.lowerBound]
        guard !machine.isEmpty, !machine.contains(where: \.isWhitespace) else { return nil }
        return String(machine)
    }

    /// A program name against the rules: exact and case sensitive. A program that could not be
    /// read is `unknown`.
    public static func context(program: String?, rules: [ProgramRule]) -> ProgramContext {
        guard let program else { return .unknown }
        return rules.contains { $0.name == program } ? .rule(program) : .noRule
    }

    public static var paneListRequest: Data {
        request(method: "pane.list", params: [:])
    }

    public static func processInfoRequest(paneID: String) -> Data {
        request(method: "pane.process_info", params: ["pane_id": paneID])
    }

    public static var focusSubscriptionRequest: Data {
        request(method: "events.subscribe", params: ["subscriptions": focusEventTypes.map { ["type": $0] }])
    }

    /// One request line, newline included.
    private static func request(method: String, params: [String: Any]) -> Data {
        let body: [String: Any] = ["id": "cmd-ime", "method": method, "params": params]
        // The values above are strings, arrays and dictionaries of strings: always serializable.
        var line = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        line.append(UInt8(ascii: "\n"))
        return line
    }
}
