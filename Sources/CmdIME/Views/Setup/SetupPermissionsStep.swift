import KeyboardSwitcherCore
import SwiftUI

/// Step 1: one row per permission, a privacy sentence that matches what
/// `EventTapMonitor` does, and a way out when macOS wants a restart.
struct SetupPermissionsStep: View {
    @ObservedObject var model: AppModel
    let state: SetupGuideState

    /// macOS reports some grants only to a fresh process. Once a settings pane was
    /// opened and a permission still reads as missing, the restart hint appears.
    @State private var didOpenSettings = false
    @State private var relaunchFailed = false

    private static let pollInterval = Duration.seconds(1)

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("macOS asks for two permissions before CmdIME can notice your trigger keys in other apps. CmdIME cannot grant them itself: turn on CmdIME in each list.")
                .setupBodyText()

            SetupPermissionRow(
                title: "Accessibility",
                purpose: "Lets CmdIME handle a trigger before other apps see it, and find the text caret for the switch indicator.",
                granted: model.permissions.accessibilityGranted
            ) {
                didOpenSettings = true
                model.openAccessibilitySettings()
            }

            SetupPermissionRow(
                title: "Input Monitoring",
                purpose: "Lets CmdIME see key presses while another app is in front, so triggers work everywhere.",
                granted: model.permissions.inputMonitoringGranted
            ) {
                didOpenSettings = true
                model.openInputMonitoringSettings()
            }

            if !model.permissions.isReady {
                HStack(spacing: 10) {
                    Button("Request Permissions") {
                        didOpenSettings = true
                        model.requestPermissions()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))

                    Text("CmdIME not in the list yet? Request Permissions makes macOS add it.")
                        .setupNoteText()
                }
            }

            if state.shouldOfferRelaunch {
                SetupNotice(
                    systemImage: "xmark.octagon.fill",
                    tone: .danger,
                    text: "Both permissions are ready, but the keyboard listener could not start. macOS often applies a new permission only after the app restarts."
                ) {
                    Button("Try Again") {
                        model.startListeningIfReady()
                    }
                    .buttonStyle(ConsoleButtonStyle())
                    relaunchButton(prominent: true)
                }
            } else if didOpenSettings, !model.permissions.isReady {
                SetupNotice(
                    systemImage: "arrow.clockwise.circle.fill",
                    tone: .neutral,
                    text: "Turned it on and it still reads Missing? macOS sometimes reports a new permission only after the app restarts."
                ) {
                    relaunchButton(prominent: false)
                }
            }

            if showsQuitInsteadOfRelaunch {
                Text(model.config.hasCompletedSetup
                    ? "After quitting, open CmdIME again from Launchpad or Spotlight."
                    : "After quitting, open CmdIME again from Launchpad or Spotlight. The guide continues where it stopped.")
                    .setupNoteText()
            }

            Text("Privacy: CmdIME checks each key event in memory, by key code and modifier state, only to spot your triggers. What you type is never stored and never sent anywhere. The only thing saved is your own configuration.")
                .setupNoteText()
        }
        .onChange(of: state.shouldOfferRelaunch) { offered in
            if offered {
                SetupGuideNavigation.announce("The keyboard listener could not start. Try again, or restart CmdIME.")
            }
        }
        .task {
            // Flip to Ready while System Settings is still in front, where macOS allows it.
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.pollInterval)
                if MacPermissionStatus.current() != model.permissions {
                    model.refreshRuntimeStatus()
                }
            }
        }
    }

    /// A restart is on offer, but only as "Quit": there is no bundle to reopen, or
    /// scheduling the reopen failed.
    private var showsQuitInsteadOfRelaunch: Bool {
        let offersRestart = state.shouldOfferRelaunch || (didOpenSettings && !model.permissions.isReady)
        return offersRestart && (relaunchFailed || !AppRelauncher.canRelaunch)
    }

    @ViewBuilder
    private func relaunchButton(prominent: Bool) -> some View {
        if AppRelauncher.canRelaunch, !relaunchFailed {
            Button("Relaunch CmdIME") {
                if AppRelauncher.scheduleReopenAfterExit() {
                    model.quit()
                } else {
                    relaunchFailed = true
                    SetupGuideNavigation.announce("Relaunch is not available. Quit CmdIME and open it again.")
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

private struct SetupPermissionRow: View {
    let title: String
    let purpose: String
    let granted: Bool
    let onOpenSettings: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.callout.weight(.bold))
                .foregroundStyle(granted ? DesignTokens.Colors.success : DesignTokens.Colors.warning)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                Text(purpose)
                    .setupNoteText()
            }
            .accessibilityElement(children: .combine)
            .accessibilityValue(granted ? "Ready" : "Missing")

            Spacer(minLength: 8)

            if granted {
                StatusPill(text: "Ready", systemImage: "checkmark", tone: .success)
                    .accessibilityHidden(true)
            } else {
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(ConsoleButtonStyle())
                    .accessibilityLabel("Open \(title) settings")
            }
        }
        .padding(10)
        .background(SetupInsetBackground())
        .onChange(of: granted) { granted in
            SetupGuideNavigation.announce("\(title) is \(granted ? "ready" : "missing")")
        }
    }
}
