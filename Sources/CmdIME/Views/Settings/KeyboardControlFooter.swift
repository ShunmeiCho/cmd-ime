import KeyboardSwitcherCore
import SwiftUI

/// The keyboard-control status pinned under the sidebar pages. Ready states stay short,
/// with the permission summary behind a button; missing permissions or a failed listener
/// expand to the actions that can fix them. CmdIME never grants a permission itself:
/// every action opens System Settings, asks macOS to list CmdIME, or restarts the listener.
struct KeyboardControlFooter: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsPermissionDetails = false
    @State private var relaunchFailed = false

    private var needsAttention: Bool {
        !model.permissions.isReady || model.didListenerFailToStart
    }

    var body: some View {
        let status = RuntimeStatusPresentation(model: model)
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            SectionLabel("Keyboard control")
            statusRow(status)
            if needsAttention {
                PermissionsCard(model: model, status: status)
                if model.permissions.isReady, model.didListenerFailToStart {
                    listenerFailedActions
                }
            } else {
                // Full width, so its edges line up with the pill and the Pause button above it.
                Button {
                    showsPermissionDetails.toggle()
                } label: {
                    HStack(spacing: DesignTokens.Layout.rowGap) {
                        Label("Keyboard access ready", systemImage: "checkmark.circle.fill")
                        Spacer(minLength: 0)
                        Image(systemName: showsPermissionDetails ? "chevron.up" : "chevron.down")
                            .accessibilityHidden(true)
                    }
                    .font(DesignTokens.Typography.auxiliary)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(ConsoleButtonStyle())
                .help("Show or hide keyboard permission details")
                .accessibilityValue(showsPermissionDetails ? "Expanded" : "Collapsed")
                if showsPermissionDetails {
                    PermissionsCard(model: model, status: status)
                }
            }
        }
        .padding(DesignTokens.Layout.panelInset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Divider() }
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion),
                   value: needsAttention)
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion),
                   value: showsPermissionDetails)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Keyboard control")
    }

    /// The pill and Pause or Resume, while nothing needs fixing or the listener still runs.
    /// The sidebar is narrow, so the button drops below the pill when both do not fit on
    /// one line.
    private func statusRow(_ status: RuntimeStatusPresentation) -> some View {
        let pill = StatusPill(text: status.title, systemImage: status.systemImage, tone: status.tone)
            .help(status.detail)
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: DesignTokens.Layout.rowGap) {
                pill
                Spacer(minLength: DesignTokens.Layout.rowGap)
                primaryButton(status)
            }
            VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
                pill
                primaryButton(status)
            }
        }
    }

    @ViewBuilder
    private func primaryButton(_ status: RuntimeStatusPresentation) -> some View {
        // A listener still running after a revoke keeps Pause, so it can be stopped. A failed
        // listener shows Try Again instead, never a second Resume beside it.
        if let title = status.primaryActionTitle, !needsAttention || model.isListening {
            Button(title, action: performPrimaryAction)
                .buttonStyle(ConsoleButtonStyle(prominent: status.primaryActionProminent))
                .fixedSize()
        }
    }

    /// Both permissions read as granted, yet the listener could not start: the same
    /// way out the setup guide offers, since macOS often wants a fresh process.
    private var listenerFailedActions: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            Button("Try Again") {
                model.startListeningIfReady()
            }
            .buttonStyle(ConsoleButtonStyle())
            RelaunchButton(model: model, prominent: true, failed: $relaunchFailed)
            if relaunchFailed || !AppRelauncher.canRelaunch {
                Text("After quitting, open CmdIME again from Spotlight or the Applications folder.")
                    .setupNoteText()
            }
        }
    }

    private func performPrimaryAction() {
        if model.isListening {
            model.stopListening()
        } else {
            model.startListeningIfReady()
        }
    }
}

@MainActor
private struct RuntimeStatusPresentation {
    let title: String
    let detail: String
    let systemImage: String
    let tone: StatusPill.Tone
    /// Pause or Resume. Nil for Needs Permission and Listener Failed, which show their
    /// fixes in the expanded footer instead. A listener still running after a permission
    /// is revoked reads Active and keeps Pause.
    let primaryActionTitle: String?
    let primaryActionProminent: Bool

    init(model: AppModel) {
        if model.permissions.isReady && model.sources.isEmpty {
            title = "No Input Sources"
            detail = "No input methods are available. Refresh methods or add an input source in System Settings."
            systemImage = "keyboard.badge.ellipsis"
            tone = .warning
            primaryActionTitle = model.isListening ? "Pause" : "Resume"
            primaryActionProminent = !model.isListening
        } else if model.isListening {
            title = "Active"
            detail = "Listening for your configured shortcuts."
            systemImage = "checkmark.circle.fill"
            tone = .success
            primaryActionTitle = "Pause"
            primaryActionProminent = false
        } else if !model.permissions.isReady {
            title = "Needs Permission"
            detail = "Grant Accessibility and Input Monitoring to enable global shortcuts."
            systemImage = "exclamationmark.triangle.fill"
            tone = .warning
            primaryActionTitle = nil
            primaryActionProminent = true
        } else if model.didListenerFailToStart {
            title = "Listener Failed"
            detail = "Keyboard listener could not start. Re-grant permissions, then try again."
            systemImage = "xmark.octagon.fill"
            tone = .danger
            primaryActionTitle = nil
            primaryActionProminent = true
        } else {
            title = "Paused"
            detail = "Shortcuts are not being captured."
            systemImage = "pause.circle.fill"
            tone = .neutral
            primaryActionTitle = "Resume"
            primaryActionProminent = true
        }
    }
}

/// The status detail, one row per permission, and Request Permissions while one is
/// missing. Stacked, because the sidebar is too narrow for the rows side by side.
private struct PermissionsCard: View {
    @ObservedObject var model: AppModel
    let status: RuntimeStatusPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.rowGap) {
            Text(status.detail)
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                PermissionMiniStatus(
                    title: "Accessibility",
                    granted: model.permissions.accessibilityGranted,
                    actionTitle: "Open",
                    action: model.openAccessibilitySettings
                )

                PermissionMiniStatus(
                    title: "Input Monitoring",
                    granted: model.permissions.inputMonitoringGranted,
                    actionTitle: "Open",
                    action: model.openInputMonitoringSettings
                )
            }

            if !model.permissions.isReady {
                Button("Request Permissions") {
                    model.requestPermissions()
                }
                .buttonStyle(ConsoleButtonStyle(prominent: true))
            }
        }
    }
}

private struct PermissionMiniStatus: View {
    let title: String
    let granted: Bool
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: DesignTokens.Layout.rowGap) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(granted ? DesignTokens.Colors.success : DesignTokens.Colors.warning)

            Text(title)
                .font(DesignTokens.Typography.body.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            Spacer()

            if granted {
                Text("Ready")
                    .font(DesignTokens.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.success)
            } else {
                Button(actionTitle, action: action)
                    .buttonStyle(ConsoleButtonStyle())
            }
        }
        .padding(.vertical, DesignTokens.Layout.rowGap)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(granted ? "ready" : "missing")")
    }
}
