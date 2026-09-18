import KeyboardSwitcherCore
import SwiftUI

/// Step 2: the detected slots as plain sentences, read from the real bindings.
struct SetupReviewStep: View {
    @ObservedObject var model: AppModel
    let state: SetupGuideState
    let onConfirm: () -> Void
    let onChange: () -> Void
    /// Clears the slot board's trigger drafts after the slots were rescanned or rebuilt.
    let resetDrafts: () -> Void

    /// The model's own result line for Refresh and Detect Again. The settings window
    /// shows `statusText` nowhere else, and a failed rescan must not pass silently.
    @State private var lastActionMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(introText)
                .setupBodyText()

            if state.needsMoreSources {
                SetupNotice(
                    systemImage: "keyboard.badge.ellipsis",
                    tone: .warning,
                    text: "Switching needs at least two input sources. Add one in System Settings > Keyboard > Input Sources, then press Refresh."
                ) {
                    Button("Open Keyboard Settings") {
                        openKeyboardSettings()
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    refreshButton
                }
            } else if canDetectAgain {
                SetupNotice(
                    systemImage: "plus.circle.fill",
                    tone: .neutral,
                    text: "A fresh detection would now create more slots than are set up here. Detect Again replaces the current slots and triggers with one slot per installed language."
                ) {
                    Button("Detect Again") {
                        model.resetSlotsFromDetectedSources()
                        resetDrafts()
                        report(model.statusText)
                    }
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    refreshButton
                }
            } else if model.config.slots.count < SetupGuideState.minimumSourceCount {
                SetupNotice(
                    systemImage: "info.circle.fill",
                    tone: .neutral,
                    text: "Detection makes one slot per language, so input sources that share a language share one slot. To switch between them, add a slot on the slot board with Change."
                )
            }

            if let lastActionMessage {
                Text(lastActionMessage)
                    .setupNoteText()
            }

            SetupSlotSentenceList(model: model)

            if state.hasSlotsBeyondAutomaticTriggers {
                SetupNotice(
                    systemImage: "info.circle.fill",
                    tone: .neutral,
                    text: "The first five slots got a key. The others have none yet: bind them on the slot board with Change."
                )
            }

            if usesOneShotShift {
                SetupNotice(
                    systemImage: "exclamationmark.triangle.fill",
                    tone: .warning,
                    text: "A lone Shift tap is also how many Chinese and Japanese input methods toggle their own modes. CmdIME never picks Shift by itself; keep it only if the two do not clash."
                )
            }

            HStack(spacing: 8) {
                Button("Looks right", action: onConfirm)
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                Button("Change", action: onChange)
                    .buttonStyle(ConsoleButtonStyle())
                    .accessibilityLabel("Change slots on the slot board")
            }
        }
    }

    private var refreshButton: some View {
        Button("Refresh") {
            // The model's own line counts every TIS entry, palettes and input-mode
            // parents included; the guide only ever talks about selectable sources.
            let didScan = model.scan()
            resetDrafts()
            report(didScan ? Self.foundMessage(count: model.selectableSources.count) : model.statusText)
        }
        .buttonStyle(ConsoleButtonStyle())
        .accessibilityLabel("Refresh input sources")
    }

    private func report(_ message: String) {
        lastActionMessage = message
        SetupGuideNavigation.announce(message)
    }

    /// First run only: detection left a single slot and would find more now. Returning
    /// users rebuild through the slot board's confirmed Reset to Detected instead.
    private var canDetectAgain: Bool {
        !model.config.hasCompletedSetup && state.canDetectAgain
    }

    /// Only a pending first run shows detected slots; a replay shows the user's own.
    private var introText: String {
        let slots = "Each line below is a slot, a switch target: fire its trigger and that input source becomes active."
        return model.config.hasCompletedSetup
            ? slots
            : "\(slots) On first launch CmdIME creates one slot per installed language."
    }

    private static func foundMessage(count: Int) -> String {
        count == 1
            ? "Found 1 input source you can switch to."
            : "Found \(count) input sources you can switch to."
    }

    private var usesOneShotShift: Bool {
        model.config.slotTriggers.contains { $0.trigger.isOneShotShift }
    }
}

/// The sentence rows shared by "Check what was detected" and "Try it".
struct SetupSlotSentenceList: View {
    @ObservedObject var model: AppModel
    /// Nil outside "Try it".
    var triedSlots: Set<InputRole>?

    var body: some View {
        let triggers = model.config.slotTriggers
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.config.slots) { slot in
                let slotTriggers = triggers.filter { $0.slot == slot.id }.map(\.trigger)
                SetupSlotSentenceRow(
                    slot: slot,
                    triggers: slotTriggers,
                    source: model.matchedSource(for: slot.id),
                    isActive: triedSlots != nil && model.activeRole == slot.id,
                    // A slot without a key cannot be tried, so it gets no mark.
                    isTried: slotTriggers.isEmpty ? nil : triedSlots.map { $0.contains(slot.id) }
                )
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SetupInsetBackground())
    }
}
