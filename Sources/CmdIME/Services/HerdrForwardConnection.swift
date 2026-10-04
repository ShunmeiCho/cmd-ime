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

    private static let ssh = "/usr/bin/ssh"
    private static let socketPoll: TimeInterval = 0.02
    private static let running = RunningProcesses()

    var isAlive: Bool { process.isRunning }

    private init(process: Process, socketPath: String, pidFile: String, now: TimeInterval) {
        self.process = process
        socket = HerdrSocket(path: socketPath)
        self.pidFile = pidFile
        lastUsed = now
    }

    /// Starts ssh for `machine` and returns the connection once Herdr answers through it, trying
    /// each place its socket can be; nil when ssh cannot connect without asking, or nothing answers.
    static func open(machine: HerdrMachine) -> HerdrForwardConnection? {
        dispatchPrecondition(condition: .notOnQueue(.main))
        guard let directory = socketDirectory(),
              let socketPath = HerdrForward.localSocketPath(directory: directory, machineID: machine.id),
              let user = resolvedUser(target: machine.target) else { return nil }
        let pidFile = socketPath + ".pid"
        endLeftover(pidFile: pidFile)
        for remote in HerdrForward.remoteSocketCandidates(user: user) {
            guard let connection = start(target: machine.target, socketPath: socketPath, remoteSocket: remote, pidFile: pidFile) else {
                continue
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
    }

    /// Ends every forward. Called when CmdIME quits, on main: an ssh with `-N` would otherwise
    /// outlive the app.
    static func endAll() {
        running.endAll()
    }

    private static func start(target: String, socketPath: String, remoteSocket: String, pidFile: String) -> HerdrForwardConnection? {
        try? FileManager.default.removeItem(atPath: socketPath)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ssh)
        process.arguments = HerdrForward.sshArguments(target: target, localSocket: socketPath, remoteSocket: remoteSocket)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        running.add(process.processIdentifier)
        try? String(process.processIdentifier).write(toFile: pidFile, atomically: true, encoding: .utf8)
        let now = ProcessInfo.processInfo.systemUptime
        let connection = HerdrForwardConnection(process: process, socketPath: socketPath, pidFile: pidFile, now: now)
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

    /// The login user ssh would use for `target`, from the user's ssh config, without connecting.
    private static func resolvedUser(target: String) -> String? {
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
        return HerdrForward.user(inResolvedConfig: String(decoding: data, as: UTF8.self))
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
    /// the pid in the file is still that ssh and not a process that took the number since.
    private static func endLeftover(pidFile: String) {
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8),
              let pid = pid_t(text.trimmingCharacters(in: .whitespacesAndNewlines)), pid > 0 else { return }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0,
           String(decoding: path.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) == ssh {
            kill(pid, SIGTERM)
        }
        try? FileManager.default.removeItem(atPath: pidFile)
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
