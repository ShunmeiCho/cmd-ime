import KeyboardSwitcherCore
import SwiftUI

/// The first-run checklist at the top of the settings page. The current step is
/// derived by `SetupGuideState`; the card only renders it and reports the three
/// user decisions: Looks right, Finish and Skip.
struct SetupGuideCard: View {
    @ObservedObject var model: AppModel
    @Binding var session: SetupGuideSession
    let scroll: ScrollViewProxy
    /// Clears the slot board's trigger drafts after the guide rescans or rebuilds slots.
    let resetDrafts: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.setupFolds) private var folds

    var body: some View {
        let state = model.setupGuideState(session: session)
        Group {
            if let current = state.currentStep {
                card(state: state, current: current)
                    .transition(collapseTransition)
            }
        }
        .id(SetupGuideNavigation.guideID)
        // Consume each published value, not just the final rendered config: deletion
        // must invalidate proof even when the same ID is immediately created again.
        .onReceive(model.$config) { config in
            reconcileEvidence(config: config, sources: model.sources)
        }
        .onReceive(model.$sources) { sources in
            reconcileEvidence(config: model.config, sources: sources)
        }
        .onChange(of: state.currentStep) { step in
            guard let step else { return }
            SetupGuideNavigation.announce("Setup step \(step.rawValue) of \(SetupStep.allCases.count): \(step.title)")
        }
        .onChange(of: model.permissions.isReady) { isReady in
            // The model starts the listener only at launch or on Resume. Inside the
            // guide a fresh grant should lead straight on to the next step. A grant that
            // returns after being revoked leaves `isListening` stale, and the old event
            // tap is not known to recover, so the listener is rebuilt, never trusted.
            guard isReady, !state.isFinished else { return }
            if model.isListening {
                model.stopListening()
            }
            model.startListeningIfReady()
        }
    }

    private func reconcileEvidence(config: SwitcherConfig, sources: [InputSourceInfo]) {
        let next = session.triggerEvidence.reconciling(config: config, sources: sources)
        if next != session.triggerEvidence { session.triggerEvidence = next }
    }

    private func card(state: SetupGuideState, current: SetupStep) -> some View {
        CompactSection(title: "Setup guide") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 10) {
                    Text("Three short steps. Everything stays editable afterwards, and General > Show Setup Guide at the top shows this guide again.")
                        .setupBodyText()
                    Spacer(minLength: 8)
                    StatusPill(
                        text: "Step \(current.rawValue) of \(SetupStep.allCases.count)",
                        systemImage: "list.number",
                        tone: .neutral
                    )
                    Button(session.isReopened ? "Close Guide" : "Skip Setup") {
                        complete(announcement: session.isReopened ? "Setup guide closed." : "Setup skipped. The guide stays available under General.")
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }

                if current != .tryIt {
                    // "Try it" closes with the same answer; the earlier steps send the
                    // user to System Settings, or let them skip, before they get there.
                    Text("While Settings is open, CmdIME is in the Dock and the app switcher. After this window closes, it keeps running in the background with no menu bar icon. \(SetupGuideCopy.reopenHint) To stop it, use General > Quit CmdIME.")
                        .setupNoteText()
                }

                ForEach(SetupStep.allCases, id: \.self) { step in
                    SetupStepSection(step: step, isCurrent: step == current, isComplete: state.isComplete(step)) {
                        content(for: step, state: state)
                    }
                }
            }
            .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion),
                       value: current)
        }
    }

    @ViewBuilder
    private func content(for step: SetupStep, state: SetupGuideState) -> some View {
        switch step {
        case .permissions:
            SetupPermissionsStep(model: model, state: state)
        case .review:
            SetupReviewStep(
                model: model,
                state: state,
                onConfirm: {
                    withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                        session.hasConfirmedSlots = true
                    }
                },
                onChange: {
                    withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                        folds.unfold(.slotBoard)
                    }
                    SetupGuideNavigation.scroll(scroll, to: SetupFoldSection.slotBoard)
                    SetupGuideNavigation.announce("\(SetupFoldSection.slotBoard.title) section opened below the setup guide.")
                },
                resetDrafts: resetDrafts
            )
        case .tryIt:
            SetupTryItStep(model: model, session: $session) {
                complete(announcement: "Setup finished. CmdIME keeps running in the background.")
            }
        }
    }

    /// Finish, Skip and Close all end here: store the flag, drop the session state
    /// and let the card collapse toward the header status pill.
    private func complete(announcement: String) {
        withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
            model.completeSetup()
            session = SetupGuideSession()
        }
        SetupGuideNavigation.announce(announcement)
    }

    /// The status pill sits at the header's top trailing corner; the card shrinks
    /// toward it. Reduce Motion gets a plain fade.
    private var collapseTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .asymmetric(insertion: .opacity, removal: .scale(scale: 0.9, anchor: .topTrailing).combined(with: .opacity))
    }
}

private struct SetupStepSection<Content: View>: View {
    let step: SetupStep
    let isCurrent: Bool
    let isComplete: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                marker
                Text(step.title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(isCurrent || isComplete ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textMuted)
                Spacer(minLength: 8)
                Text(statusText)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isComplete ? DesignTokens.Colors.success : DesignTokens.Colors.textMuted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(step.title)
            .accessibilityValue(statusText)
            .accessibilityAddTraits(.isHeader)

            if isCurrent {
                content()
                    .transition(.opacity)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(isCurrent ? DesignTokens.Colors.surface : .clear)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                        .stroke(isCurrent ? DesignTokens.Colors.separatorStrong : DesignTokens.Colors.separator, lineWidth: 1)
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(step.rawValue) of \(SetupStep.allCases.count), \(step.title)")
    }

    private var marker: some View {
        ZStack {
            Circle()
                .fill((isComplete ? DesignTokens.Colors.success : DesignTokens.Colors.accent).opacity(isCurrent || isComplete ? 0.18 : 0))
                .overlay(Circle().stroke(markerColor.opacity(0.6), lineWidth: 1))
            if isComplete {
                Image(systemName: "checkmark")
                    .font(.caption2.weight(.bold))
            } else {
                Text("\(step.rawValue)")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
            }
        }
        .foregroundStyle(markerColor)
        .frame(width: 22, height: 22)
    }

    private var markerColor: Color {
        if isComplete { return DesignTokens.Colors.success }
        return isCurrent ? DesignTokens.Colors.accent : DesignTokens.Colors.textMuted
    }

    private var statusText: String {
        if isComplete { return "Done" }
        return isCurrent ? "Current step" : "Up next"
    }
}

extension SetupStep {
    var title: String {
        switch self {
        case .permissions: "Allow keyboard access"
        case .review: "Check what was detected"
        case .tryIt: "Try it"
        }
    }
}
