import AppKit
import Foundation

/// Relaunches the app bundle: a detached `/bin/sh` waits for this process to exit and
/// only then asks LaunchServices to open the bundle again, so two instances (and two
/// event taps) never run side by side. macOS applies some privacy grants only to a
/// fresh process, which is why the setup guide offers this.
@MainActor
enum AppRelauncher {
    private static let pollInterval = "0.2"
    /// Upper bound for the wait. If the app is somehow still alive afterwards, `open`
    /// merely brings its settings window forward.
    private static let maxPolls = 150

    /// `swift run` produces a bare binary with no bundle to reopen.
    static var canRelaunch: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    /// Schedules the reopen and returns true; the caller then terminates the app.
    /// The pid and bundle path travel as positional arguments, never as script text.
    static func scheduleReopenAfterExit() -> Bool {
        guard canRelaunch else { return false }
        let script = """
        i=0
        while /bin/kill -0 "$1" 2>/dev/null && [ "$i" -lt \(maxPolls) ]; do
          /bin/sleep \(pollInterval)
          i=$((i+1))
        done
        /usr/bin/open "$2"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [
            "-c", script, "cmd-ime-relaunch",
            String(ProcessInfo.processInfo.processIdentifier),
            Bundle.main.bundleURL.path,
        ]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }
}
