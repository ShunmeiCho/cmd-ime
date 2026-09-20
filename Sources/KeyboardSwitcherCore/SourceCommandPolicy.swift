import Foundation

/// The decisions behind `keyboardctl source`, kept free of Carbon so they can be tested.
///
/// The command exists so that editor plugins written for `im-select` and `macism` can call
/// keyboardctl unchanged: read prints one input source id, write takes one and prints nothing.
public enum SourceCommandPolicy {
    /// What the arguments after the `source` noun asked for.
    public enum Request: Equatable {
        case read
        /// `waitMilliseconds` caps how long the confirmation may retry; nil uses the default ladder.
        case select(id: String, waitMilliseconds: Int?)
    }

    /// Why an id cannot be selected. The three cases are separate because the user's next
    /// action differs: install it, enable it, or pick a different id.
    public enum Rejection: Equatable {
        case unknown(id: String)
        case installedButNotEnabled(id: String)
        case notAKeyboardSource(id: String)

        public var message: String {
            switch self {
            case let .unknown(id):
                return "no input source with id \"\(id)\". Run \"keyboardctl scan\" to list ids."
            case let .installedButNotEnabled(id):
                return "input source \"\(id)\" is installed but not enabled. "
                    + "Enable it in System Settings > Keyboard > Input Sources."
            case let .notAKeyboardSource(id):
                return "\"\(id)\" is not a keyboard input source, so it cannot be selected for typing."
            }
        }
    }

    /// The verbs `source` accepts. Every other token after `source` is an input source id:
    /// real ids are reverse-DNS, so they never collide with these words.
    public static let verbs: Set<String> = ["current", "select"]

    /// Flags the command understands, so they can be stripped before positional parsing.
    public static let flags: Set<String> = ["--json", "--quiet"]

    public static func parse(_ arguments: [String]) -> Request {
        var positional = arguments.filter { !$0.hasPrefix("--") }
        if let first = positional.first, verbs.contains(first) {
            positional.removeFirst()
            if first == "current" { return .read }
        }
        guard let id = positional.first else { return .read }
        // An unparseable wait is ignored rather than rejected, the way macism treats it.
        let wait = positional.dropFirst().first.flatMap(Int.init)
        return .select(id: id, waitMilliseconds: wait.map { max(0, $0) })
    }

    /// True when a bare first argument should be read as an input source id rather than a
    /// mistyped command. Ids are reverse-DNS, so the dot is what separates the two.
    public static func looksLikeInputSourceID(_ token: String, knownCommands: Set<String>) -> Bool {
        !knownCommands.contains(token) && !token.hasPrefix("-") && token.contains(".")
    }

    /// `selectable` and `keyboardSources` come from the live system; `isInstalled` answers the
    /// disabled-versus-absent question that the selectable list alone cannot.
    public static func rejection(
        for id: String,
        selectable: [String],
        keyboardSources: Set<String>,
        isInstalled: Bool
    ) -> Rejection? {
        if selectable.contains(id) {
            return keyboardSources.contains(id) ? nil : .notAKeyboardSource(id: id)
        }
        return isInstalled ? .installedButNotEnabled(id: id) : .unknown(id: id)
    }

    /// Retrying a selection is only ours to do while nothing else has moved the input source.
    /// An editor firing on every Esc and i can start a second switch inside our retry ladder;
    /// pushing our target back then would leave the user typing the wrong language.
    public static func shouldRetrySelection(current: String?, target: String, previous: String?) -> Bool {
        guard current != target else { return false }
        guard let current else { return true }
        return current == previous
    }
}
