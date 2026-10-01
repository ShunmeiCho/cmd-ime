import KeyboardSwitcherCore
import SwiftUI

/// Step 1: one row per permission, a privacy sentence that matches what
/// `EventTapMonitor` does, and a way out when macOS wants a restart.
struct SetupPermissionsStep: View {
    @ObservedObject var model: AppModel
    let state: SetupGuideState
    /// Holds the restart-hint flags, so they survive a visit to another page.
    @Binding var session: SetupGuideSession

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("macOS asks for two permissions before CmdIME can notice your trigger keys in other apps. CmdIME cannot grant them itself: turn on CmdIME in each list.")
                .setupBodyText()

            SetupPermissionRow(
                title: String(localized: "Accessibility"),
                purpose: String(localized: "Lets CmdIME handle a trigger before other apps see it, and find the text caret for the switch indicator."),
                granted: model.permissions.accessibilityGranted
            ) {
                session.didOpenPermissionSettings = true
                model.openAccessibilitySettings()
            }

            SetupPermissionRow(
                title: String(localized: "Input Monitoring"),
                purpose: String(localized: "Lets CmdIME see key presses while another app is in front, so triggers work everywhere."),
                granted: model.permissions.inputMonitoringGranted
            ) {
                session.didOpenPermissionSettings = true
                model.openInputMonitoringSettings()
            }

            if !model.permissions.isReady {
                HStack(spacing: 10) {
                    Button("Request Permissions") {
                        session.didOpenPermissionSettings = true
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
                    text: String(localized: "Both permissions are ready, but the keyboard listener could not start. macOS often applies a new permission only after the app restarts.")
                ) {
                    Button("Try Again") {
                        model.startListeningIfReady()
                    }
                    .buttonStyle(ConsoleButtonStyle())
                    RelaunchButton(model: model, prominent: true, failed: $session.relaunchFailed)
                }
            } else if model.permissions.isReady, !model.isListening {
                SetupNotice(
                    systemImage: "pause.circle.fill",
                    tone: .warning,
                    text: String(localized: "Permissions are ready, but the keyboard listener is not running. Start it before trying your triggers.")
                ) {
                    Button(model.isKeyboardControlPaused ? String(localized: "Resume") : String(localized: "Start Listening")) {
                        model.startListeningIfReady()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                }
            } else if session.didOpenPermissionSettings, !model.permissions.isReady {
                SetupNotice(
                    systemImage: "arrow.clockwise.circle.fill",
                    tone: .neutral,
                    text: String(localized: "Turned it on and it still reads Missing? macOS sometimes reports a new permission only after the app restarts.")
                ) {
                    RelaunchButton(model: model, prominent: false, failed: $session.relaunchFailed)
                }
            }

            if showsQuitInsteadOfRelaunch {
                Text(model.config.hasCompletedSetup
                    ? String(localized: "After quitting, open CmdIME again from Spotlight or the Applications folder.")
                    : String(localized: "After quitting, open CmdIME again from Spotlight or the Applications folder. The guide continues where it stopped."))
                    .setupNoteText()
            }

            Text("Privacy: \(SetupGuideCopy.privacy)")
                .setupNoteText()
        }
        .onChange(of: state.shouldOfferRelaunch) { offered in
            if offered {
                SetupGuideNavigation.announce(String(localized: "The keyboard listener could not start. Try again, or restart CmdIME."))
            }
        }
    }

    /// A restart is on offer, but only as "Quit": there is no bundle to reopen, or
    /// scheduling the reopen failed.
    private var showsQuitInsteadOfRelaunch: Bool {
        let offersRestart = state.shouldOfferRelaunch || (session.didOpenPermissionSettings && !model.permissions.isReady)
        return offersRestart && (session.relaunchFailed || !AppRelauncher.canRelaunch)
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
            .accessibilityValue(granted ? String(localized: "Ready") : String(localized: "Missing"))

            Spacer(minLength: 8)

            if granted {
                StatusPill(text: String(localized: "Ready"), systemImage: "checkmark", tone: .success)
                    .accessibilityHidden(true)
            } else {
                // The restart hint refers to this word, and status is never icon-only.
                StatusPill(text: String(localized: "Missing"), systemImage: "exclamationmark.triangle.fill", tone: .warning)
                    .accessibilityHidden(true)
                Button("Open Settings", action: onOpenSettings)
                    .buttonStyle(ConsoleButtonStyle())
                    .accessibilityLabel("Open \(title) settings")
            }
        }
        .padding(10)
        .background(SetupInsetBackground())
        .onChange(of: granted) { granted in
            SetupGuideNavigation.announce(granted ? String(localized: "\(title) is ready") : String(localized: "\(title) is missing"))
        }
    }
}
