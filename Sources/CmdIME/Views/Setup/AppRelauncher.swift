import AppKit
import Foundation
import SwiftUI

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

/// Relaunch CmdIME, or Quit CmdIME when there is no bundle to reopen or scheduling the
/// reopen failed. Shared by the setup guide and the keyboard-control status in the
/// sidebar; `failed` lets the caller show the reopen hint that goes with Quit.
struct RelaunchButton: View {
    @ObservedObject var model: AppModel
    var prominent = false
    @Binding var failed: Bool

    var body: some View {
        if AppRelauncher.canRelaunch, !failed {
            Button("Relaunch CmdIME") {
                if AppRelauncher.scheduleReopenAfterExit() {
                    model.quit()
                } else {
                    failed = true
                    SetupGuideNavigation.announce(String(localized: "Relaunch is not available. Quit CmdIME and open it again."))
                }
            }
            .buttonStyle(ConsoleButtonStyle(prominent: prominent))
        } else {
            Button("Quit CmdIME") {
                model.quit()
            }
            .buttonStyle(ConsoleButtonStyle(prominent: prominent))
        }
    }
}
