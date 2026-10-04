import Darwin
import Foundation
import KeyboardSwitcherCore

/// One ssh process that forwards a saved machine's Herdr socket to a socket on this Mac
/// (`HerdrForward`). Runs nothing on the machine. Used only on the program watcher's thread; the
/// pids are also kept in `running` so a quitting app can end them from the main thread.
final class HerdrForwardConnection {
    let socket: HerdrSocket
    var lastUsed: TimeInterval
    private let process: Process
    private let pidFile: String
    private let configFile: String

    private static let ssh = "/usr/bin/ssh"
    private static let socketPoll: TimeInterval = 0.02
    private static let running = RunningProcesses()

    var isAlive: Bool { process.isRunning }

    private init(process: Process, socketPath: String, pidFile: String, configFile: String, now: TimeInterval) {
        self.process = process
        socket = HerdrSocket(path: socketPath)
        self.pidFile = pidFile
        self.configFile = configFile
        lastUsed = now
    }

    /// Starts ssh for `machine` and returns the connection once Herdr answers through it, trying
    /// each place its socket can be; nil when ssh cannot connect without asking, or nothing answers.
    /// A forwarded socket appears only once ssh is connected, so an ssh that never puts it in place
    /// failed before any remote path mattered: the other paths are not tried (each try can take
    /// `connectBudget` on the watcher thread).
    static func open(machine: HerdrMachine) -> HerdrForwardConnection? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let directory = socketDirectory(),
              let socketPath = HerdrForward.localSocketPath(directory: directory, machineID: machine.id),
              let resolved = resolvedConfig(target: machine.target),
              let user = HerdrForward.user(inResolvedConfig: resolved) else { return nil }
        let pidFile = socketPath + ".pid"
        let configFile = socketPath + ".conf"
        endLeftover(pidFile: pidFile, socketPath: socketPath)
        let config = Data(HerdrForward.privateConfig(fromResolved: resolved).utf8)
        for remote in HerdrForward.remoteSocketCandidates(user: user) {
            // Written for every try: closing a failed one removes it.
            guard FileManager.default.createFile(atPath: configFile, contents: config, attributes: [.posixPermissions: 0o600]),
                  let connection = start(target: machine.target, socketPath: socketPath, remoteSocket: remote,
                                         pidFile: pidFile, configFile: configFile) else {
                return nil
            }
            if connection.socket.reply(to: HerdrSurface.paneListRequest, budget: HerdrForward.requestBudget)
                .flatMap(HerdrReplyParser.focusedPane(from:)) != nil {
                return connection
            }
            connection.close()
        }
        return nil
    }

    func close() {
        if process.isRunning { process.terminate() }
        Self.running.remove(process.processIdentifier)
        try? FileManager.default.removeItem(atPath: socket.path)
        try? FileManager.default.removeItem(atPath: pidFile)
        try? FileManager.default.removeItem(atPath: configFile)
    }

    /// Ends every forward. Called when CmdIME quits, on main: an ssh with `-N` would otherwise
    /// outlive the app.
    static func endAll() {
        running.endAll()
    }

    private static func start(
        target: String, socketPath: String, remoteSocket: String, pidFile: String, configFile: String
    ) -> HerdrForwardConnection? {
        try? FileManager.default.removeItem(atPath: socketPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ssh)
        process.arguments = HerdrForward.sshArguments(
            target: target, configFile: configFile, localSocket: socketPath, remoteSocket: remoteSocket)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // An ssh that ends on its own leaves the set at once, so quitting never signals a pid
        // another process has taken since.
        let running = running
        process.terminationHandler = { ended in running.remove(ended.processIdentifier) }
        guard (try? process.run()) != nil else { return nil }
        running.add(process.processIdentifier)
        try? String(process.processIdentifier).write(toFile: pidFile, atomically: true, encoding: .utf8)
        let now = ProcessInfo.processInfo.systemUptime
        let connection = HerdrForwardConnection(
            process: process, socketPath: socketPath, pidFile: pidFile, configFile: configFile, now: now)
        let deadline = now + HerdrForward.connectBudget
        while !FileManager.default.fileExists(atPath: socketPath) {
            guard process.isRunning, ProcessInfo.processInfo.systemUptime < deadline else {
                connection.close()
                return nil
            }
            Thread.sleep(forTimeInterval: socketPoll)
        }
        return connection
    }

    /// The user's ssh settings for `target` as ssh resolves them (`ssh -G`), without connecting.
    private static func resolvedConfig(target: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ssh)
        process.arguments = HerdrForward.resolveArguments(target: target)
        let output = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        // `ssh -G` prints a few kilobytes and exits; reading to the end waits for it.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    /// A short private directory: a Unix socket path must fit in 104 bytes.
    private static func socketDirectory() -> String? {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("cmd-ime-herdr").path
        do {
            try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
        } catch {
            return nil
        }
        return directory
    }

    /// An ssh left running by a CmdIME that did not quit cleanly (a crash, `pkill`) is ended, if
    /// the pid in the file is still that ssh: /usr/bin/ssh with this forward's socket among its
    /// arguments. A pid taken since by another process, the user's own ssh included, is left alone.
    private static func endLeftover(pidFile: String, socketPath: String) {
        defer { try? FileManager.default.removeItem(atPath: pidFile) }
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0,
              String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == ssh,
              let arguments = processArguments(pid: pid),
              arguments.range(of: Data(socketPath.utf8)) != nil else { return }
        kill(pid, SIGTERM)
    }

    /// The raw argument area of a process (`KERN_PROCARGS2`): executable path, argv and env,
    /// NUL-separated. Readable for this user's own processes only.
    private static func processArguments(pid: pid_t) -> Data? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, UInt32(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        return Data(buffer.prefix(size))
    }

    private final class RunningProcesses: @unchecked Sendable {
        private let lock = NSLock()
        private var pids: Set<pid_t> = []

        func add(_ pid: pid_t) {
            lock.withLock { _ = pids.insert(pid) }
        }

        func remove(_ pid: pid_t) {
            lock.withLock { _ = pids.remove(pid) }
        }

        func endAll() {
            let all = lock.withLock { pids }
            for pid in all { kill(pid, SIGTERM) }
        }
    }
}
