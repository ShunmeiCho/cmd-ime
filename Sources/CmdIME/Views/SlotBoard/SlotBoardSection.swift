import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SwitchSlotsSection: View {
    @ObservedObject var model: AppModel
    @State private var showsResetConfirmation = false
    @Binding var triggerDrafts: [InputRole: String]
    @Binding var triggerTypeDrafts: [InputRole: BindingTriggerType]
    let resetDrafts: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionLabel("Switch slots")
                Spacer()
                Button("Reset to Detected") {
                    showsResetConfirmation = true
                }
                .buttonStyle(ConsoleButtonStyle())
            }

            VStack(spacing: 9) {
                ForEach(model.config.slots) { slot in
                    switchSlotCard(for: slot)
                }
            }
        }
        .confirmationDialog(
            "Rebuild slots from installed input sources?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace All Slots and Triggers", role: .destructive) {
                model.resetSlotsFromDetectedSources()
                resetDrafts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces all slots and triggers, including key remaps, with one slot per installed primary language. Your current configuration will be backed up before replacement. General indicator settings are kept; slot-specific colors are reset.")
        }
    }

    private func switchSlotCard(for slot: SwitchSlot) -> some View {
        let role = slot.id
        let source = model.matchedSource(for: role)
        let presentation = InputSourcePresentation(source: source, slot: slot)
        let duplicate = hasDuplicateSource(source, for: role)

        return SwitchSlotCard(
            role: role,
            presentation: presentation,
            source: source,
            isActive: model.activeRole == role,
            isDuplicate: duplicate,
            triggerText: model.bindingText(for: role),
            sourceStatus: sourceStatus(source, for: role),
            bindingWarning: model.slotNotices[role] ?? model.oneShotConflictWarning(for: role),
            onTest: { model.switchRole(role) },
            onFix: {
                model.initializeFromScan()
                resetDrafts()
            }
        ) {
            triggerTypePicker(for: role)
        } triggerControl: {
            triggerControl(for: role)
        } inputSourceControl: {
            inputSourcePicker(for: role, source: source)
        }
    }

    private func sourceStatus(_ source: InputSourceInfo?, for role: InputRole) -> String {
        guard let source else {
            return "Choose an input method for this slot."
        }

        if hasDuplicateSource(source, for: role) {
            return "\(source.localizedName) is already used by another slot."
        }

        return "This slot activates \(source.localizedName)."
    }

    private func hasDuplicateSource(_ source: InputSourceInfo?, for role: InputRole) -> Bool {
        guard let source else {
            return false
        }

        return model.config.slots.contains { otherSlot in
            otherSlot.id != role && model.matchedSource(for: otherSlot.id)?.id == source.id
        }
    }

}
