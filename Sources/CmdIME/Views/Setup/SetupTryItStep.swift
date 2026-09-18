import KeyboardSwitcherCore
import SwiftUI

/// Step 3: a scratch field to try the triggers in. A slot counts as tried when the
/// event tap reports a successful trigger; direct and system switches do not count.
struct SetupTryItStep: View {
    @ObservedObject var model: AppModel
    @Binding var session: SetupGuideSession
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Scratch text only: never stored, never read by anything else.
    @State private var scratchText = ""
    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let progress = progress()
        VStack(alignment: .leading, spacing: 10) {
            Text(model.config.showSwitchIndicator
                ? "Click into the field, then fire each trigger. The matching line lights up, the input source changes, and the switch indicator shows up near the caret."
                : "Click into the field, then fire each trigger. The matching line lights up and the input source changes.")
                .setupBodyText()

            if !model.isListening {
                SetupNotice(
                    systemImage: "pause.circle.fill",
                    tone: .warning,
                    text: "The keyboard listener is paused, so triggers do nothing right now."
                ) {
                    Button("Resume") {
                        model.startListeningIfReady()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .accessibilityLabel("Resume keyboard listener")
                }
            }

            TextField(placeholder(for: progress), text: $scratchText)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .focused($isFieldFocused)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(SetupInsetBackground(
                    stroke: isFieldFocused ? DesignTokens.Colors.accent.opacity(0.64) : DesignTokens.Colors.separatorStrong
                ))
                .accessibilityLabel("Practice field")
                .accessibilityHint(placeholder(for: progress))

            SetupSlotSentenceList(model: model, triedSlots: Set(progress.triedSlots))

            if !progress.unmatchedSlots.isEmpty {
                SetupNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning,
                    text: unmatchedText(for: progress)
                )
            }

            Text(progressText(for: progress))
                .font(.caption.weight(.semibold))
                .foregroundStyle(progress.isComplete ? DesignTokens.Colors.success : DesignTokens.Colors.textMuted)

            SetupNotice(
                systemImage: "info.circle.fill",
                tone: .neutral,
                text: "CmdIME keeps running in the background and has no menu bar icon. \(SetupGuideCopy.reopenHint) To stop it, use General > Quit CmdIME. The switch indicator can be customized in the Switch indicator section below."
            )

            HStack(spacing: 8) {
                Button("Finish", action: onFinish)
                    .buttonStyle(ConsoleButtonStyle(prominent: progress.isComplete || progress.boundSlots.isEmpty))
                    .accessibilityLabel("Finish setup")
                Button("Back") {
                    withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                        session.hasConfirmedSlots = false
                    }
                }
                .buttonStyle(ConsoleButtonStyle())
                .accessibilityLabel("Back to the detected slots")
            }
        }
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion),
                   value: session.triggerEvidence)
        .onAppear {
            // Focus after the step has been laid out, so the first trigger already
            // has a caret to show the indicator at.
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
        // A passthrough event is not replayed on entering the step.
        .onReceive(model.triggeredSwitches) { event in
            markTried(event)
        }
    }

    private func markTried(_ event: SetupTriggeredSwitch) {
        guard model.isListening, !model.isRecordingTrigger else { return }
        let slot = event.slotID
        let before = progress()
        session.triggerEvidence = session.triggerEvidence.recording(event, config: model.config, sources: model.sources)
        let after = progress()
        guard after.triedSlots.contains(slot), !before.triedSlots.contains(slot) else { return }
        let name = model.config.displayName(for: slot)
        SetupGuideNavigation.announce(after.isComplete
            ? "Trigger confirmed for \(name). Every available bound slot was tried. Press Finish to close the guide."
            : "Switched to \(name). \(progressText(for: after))")
    }

    private func progress() -> SetupTryItProgress {
        SetupTryItProgress(config: model.config, sources: model.sources, evidence: session.triggerEvidence)
    }

    /// Why a bound line has no mark: its trigger is swallowed but has nothing to select.
    private func unmatchedText(for progress: SetupTryItProgress) -> String {
        let names = progress.unmatchedSlots.map { model.config.displayName(for: $0) }
        return names.count == 1
            ? "\(names[0]) has no matching input source, so its trigger cannot switch yet. Choose a source for it on the slot board."
            : "\(names.joined(separator: ", ")) have no matching input source, so their triggers cannot switch yet. Choose a source for each on the slot board."
    }

    /// "Tap Right Command alone" for the next untried slot, nil once all were tried.
    private func nextInstruction(for progress: SetupTryItProgress) -> String? {
        guard let next = progress.nextSlot,
              let trigger = model.config.slotTriggers.first(where: { $0.slot == next })?.trigger else {
            return nil
        }
        return SetupTriggerPhrase(trigger: trigger).instruction
    }

    private func placeholder(for progress: SetupTryItProgress) -> String {
        if progress.boundSlots.isEmpty {
            return progress.unmatchedSlots.isEmpty ? "No slot has a key yet" : "No slot can switch yet"
        }
        guard let instruction = nextInstruction(for: progress) else {
            return "Every slot switched. Type to check, then press Finish."
        }
        return "\(instruction), then type here"
    }

    /// Repeats the next key outside the field, where typed text cannot hide it.
    private func progressText(for progress: SetupTryItProgress) -> String {
        if progress.boundSlots.isEmpty {
            return progress.unmatchedSlots.isEmpty
                ? "No slot has a key yet. Go back and press Change to bind one, or finish now."
                : "No slot can switch yet. Go back and press Change to choose input sources, or finish now."
        }
        let count = "\(progress.triedSlots.count) of \(progress.boundSlots.count) slots tried"
        guard let instruction = nextInstruction(for: progress) else {
            return "\(count). Setup is done: press Finish."
        }
        return "\(count). Next: \(instruction)"
    }
}
