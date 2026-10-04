import Foundation

/// How CmdIME reads another machine's Herdr over ssh when the user turned that on: ssh forwards
/// that machine's Herdr socket to a socket on this Mac (`-N -L`, no remote command is run), and
/// the forwarded socket is asked like the local one. Herdr's CLI takes about 0.4 s a call; a
/// request over the forward about 110 ms, and focus changes are pushed (measured 2026-10-04 against
/// venus). Herdr closes a connection after one reply, so every request opens its own channel.
/// Pure: ssh is run by the caller.
public enum HerdrForward {
    /// How long one request over the forward may take.
    public static let requestBudget: TimeInterval = 1
    /// How long ssh may take to put the forwarded socket in place.
    public static let connectBudget: TimeInterval = 6
    /// After a forward failed, the CLI is used for this long before ssh is tried again.
    public static let retryAfter: TimeInterval = 60
    /// A forward no read has used for this long is closed.
    public static let idleTimeout: TimeInterval = 120
    /// The pause between two reads that answered. Focus changes are pushed; program starts and
    /// exits are not.
    public static let pollInterval: TimeInterval = 0.25
    /// A Unix socket path longer than this does not fit `sockaddr_un` on macOS.
    static let maxSocketPathBytes = 103
    private static let socketPathSuffix = "/.config/herdr/herdr.sock"

    /// Options in `ssh -G` output that CmdIME's connection must not take over: the forwards the
    /// user set up for their own sessions (a `RemoteForward` for another tool would be held, and
    /// dropped on idle, by CmdIME), connection sharing, and anything that runs a command.
    /// `ClearAllForwardings` cannot do this: it drops CmdIME's own `-L` too (measured 2026-10-04).
    private static let droppedOptions: Set<String> = [
        "localforward", "remoteforward", "dynamicforward", "clearallforwardings", "exitonforwardfailure",
        "controlmaster", "controlpath", "controlpersist", "permitlocalcommand", "localcommand",
        "remotecommand", "requesttty", "sessiontype", "stdinnull", "forkafterauthentication",
    ]

    /// The user's ssh settings for one host as `ssh -G` resolved them, without the options in
    /// `droppedOptions`: the private config CmdIME's ssh runs with (`-F`), so it reaches the host the
    /// way the user's own ssh does and opens nothing but its own forward.
    public static func privateConfig(fromResolved output: String) -> String {
        output.split(whereSeparator: \.isNewline)
            .filter { line in
                let key = line.split(separator: " ", maxSplits: 1).first.map { $0.lowercased() } ?? ""
                return !key.isEmpty && !droppedOptions.contains(key)
            }
            .joined(separator: "\n") + "\n"
    }

    /// ssh arguments that forward `remoteSocket` on the machine to `localSocket` here and run
    /// nothing there, with `configFile` from `privateConfig(fromResolved:)`. Never asks anything
    /// (`BatchMode`): a machine that needs a password or has an unknown host key fails, and the CLI
    /// is used.
    public static func sshArguments(target: String, configFile: String, localSocket: String, remoteSocket: String) -> [String] {
        [
            "-F", configFile,
            "-N", "-T",
            "-o", "BatchMode=yes",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StreamLocalBindUnlink=yes",
            "-o", "ConnectTimeout=5",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=2",
            "-L", localSocket + ":" + remoteSocket,
            "--", destination(ofTarget: target),
        ]
    }

    /// `ssh -G` arguments: ssh resolves the target against the user's ssh config without connecting.
    public static func resolveArguments(target: String) -> [String] {
        ["-G", "--", destination(ofTarget: target)]
    }

    /// A `host:port` target as an ssh URL, the only form ssh takes a port in; anything else (an ssh
    /// config alias, `user@host`) is passed as saved.
    static func destination(ofTarget target: String) -> String {
        guard !target.contains("://"), !target.contains("["),
              let colon = target.lastIndex(of: ":"),
              let port = Int(target[target.index(after: colon)...]), port > 0,
              target[..<colon].firstIndex(of: ":") == nil else { return target }
        return "ssh://" + target
    }

    /// The login user in `ssh -G` output.
    public static func user(inResolvedConfig output: String) -> String? {
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(separator: " ", maxSplits: 1)
            if fields.count == 2, fields[0] == "user", !fields[1].isEmpty {
                return String(fields[1])
            }
        }
        return nil
    }

    /// Where Herdr's socket can be on the machine, most likely first. ssh needs an absolute path,
    /// and the remote home is not known without running something there, so the usual homes are
    /// tried in turn.
    public static func remoteSocketCandidates(user: String) -> [String] {
        guard !user.isEmpty, !user.contains("/") else { return [] }
        let homes = user == "root" ? ["/root"] : ["/home/" + user, "/Users/" + user]
        return homes.map { $0 + socketPathSuffix }
    }

    /// The forwarded socket for a machine in `directory`, or nil when the path would not fit.
    public static func localSocketPath(directory: String, machineID: String) -> String? {
        let name = machineID.filter { $0.isLetter || $0.isNumber }.prefix(16)
        guard !name.isEmpty else { return nil }
        let path = directory + "/" + name + ".sock"
        return path.utf8.count <= maxSocketPathBytes ? path : nil
    }

    /// Whether a forward is worth trying now: on, and not within `retryAfter` of the last failure.
    public static func shouldTry(isOn: Bool, lastFailure: TimeInterval?, now: TimeInterval) -> Bool {
        guard isOn else { return false }
        guard let lastFailure else { return true }
        return now - lastFailure >= retryAfter
    }
}
