import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SlotBoardSection: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsResetConfirmation = false
    @State private var renamingSlotID: InputRole?
    @State private var pendingRenameCommit: (() -> Bool)?
    @State private var focusedSlotID: InputRole?
    @State private var seatingID: InputRole?
    @State private var seatGeneration = 0
    @State private var seatPhase = SeatPhase.idle
    @State private var settleProgress: CGFloat = 1
    @State private var seatProgress: CGFloat = 1
    @Binding var triggerDrafts: [InputRole: String]
    @Binding var triggerTypeDrafts: [InputRole: BindingTriggerType]
    let resetDrafts: () -> Void

    var body: some View {
        let generation = seatGeneration
        let phase = seatPhase
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    SectionLabel("Switch slots")
                    Spacer()
                    AddSlotMenu(sources: model.unassignedSources, onAdd: add, onOpenSettings: showKeyboardSettings)
                    Button("Reset to Detected") {
                        guard commitPendingRename() else { return }
                        showsResetConfirmation = true
                    }
                    .buttonStyle(ConsoleButtonStyle())
                }
                HStack(alignment: .top, spacing: 14) {
                    SourceListColumn(model: model, onAdd: add, onRefresh: {
                        guard commitPendingRename() else { return }
                        model.scan()
                        resetDrafts()
                    }, onOpenSettings: showKeyboardSettings)
                    SlotListColumn(slots: model.config.slots, notice: model.boardNotice,
                                   canUndo: model.canUndoRemoval, seatingID: seatingID, onUndo: undo, onDismiss: dismissNotice) { slot in
                        card(for: slot)
                    }
                }
            }
            .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion),
                       value: model.boardNotice)
            .onChange(of: model.boardNotice) { notice in
                guard let notice else { return }
                switch notice {
                case let .rejected(reason): announce(reason)
                case let .removed(name): announce("Removed slot \(name). Undo available.")
                }
                DispatchQueue.main.async {
                    withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                        proxy.scrollTo("boardNotice")
                    }
                }
            }
        }
        .modifier(MotionCompletion(progress: settleProgress) {
            guard phase == .settling else { return }
            beginPulse(generation: generation)
        })
        .modifier(MotionCompletion(progress: seatProgress) {
            guard generation == seatGeneration, phase == .pulsing, seatPhase == .pulsing else { return }
            seatPhase = .idle
            seatingID = nil
        })
        .onChange(of: reduceMotion) { reduced in
            if reduced { beginPulse(generation: seatGeneration) }
        }
        .confirmationDialog(
            "Rebuild slots from installed input sources?",
            isPresented: $showsResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Replace All Slots and Triggers", role: .destructive) {
                structuralChange { model.resetSlotsFromDetectedSources() }
                resetDrafts()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This replaces all slots and triggers, including key remaps, with one slot per installed primary language. Your current configuration will be backed up before replacement. General indicator settings are kept; slot-specific colors are reset.")
        }
    }

    private func card(for slot: SwitchSlot) -> some View {
        let source = model.matchedSource(for: slot.id)
        return SlotCard(
            slot: slot, source: source, isActive: model.activeRole == slot.id,
            isDuplicate: !model.config.duplicateSlotIDs(for: slot.id, sources: model.sources).isEmpty,
            position: model.config.slots.firstIndex(where: { $0.id == slot.id }) ?? 0,
            count: model.config.slots.count, triggerText: model.bindingText(for: slot.id),
            hasTrigger: model.trigger(for: slot.id) != nil,
            warning: model.slotNotices[slot.id] ?? model.oneShotConflictWarning(for: slot.id),
            isRenaming: renamingSlotID == slot.id,
            onRename: {
                guard commitPendingRename() else { return }
                renamingSlotID = slot.id
            },
            onCommitRename: { name in
                let succeeded = model.renameSlot(slot.id, to: name)
                if succeeded {
                    renamingSlotID = nil
                    pendingRenameCommit = nil
                    announce("Renamed slot \(model.config.displayName(for: slot.id)).")
                } else {
                    announce(model.slotNotices[slot.id] ?? model.statusText)
                }
                return succeeded
            },
            onCancelRename: {
                renamingSlotID = nil
                pendingRenameCommit = nil
            },
            onRenameCommitChanged: { callback in
                // An outgoing field must not clear the incoming field's registration.
                guard renamingSlotID == slot.id else { return }
                pendingRenameCommit = callback
            },
            onTest: {
                guard commitPendingRename() else { return }
                model.switchRole(slot.id)
            },
            onMove: { move(slot.id, by: $0) }, onRemove: { remove(slot.id) },
            triggerControls: AnyView(HStack(spacing: 8) {
                triggerTypePicker(for: slot.id)
                triggerControl(for: slot.id)
            }),
            inputSourceControl: AnyView(inputSourcePicker(for: slot.id, source: source)),
            seatProgress: seatingID == slot.id ? seatProgress : 1,
            focusName: focusedSlotID == slot.id
        )
    }

    @discardableResult
    func commitPendingRename() -> Bool {
        pendingRenameCommit?() ?? true
    }

    private func structuralChange(_ action: () -> Void) {
        withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion), action)
    }

    private func showKeyboardSettings() {
        guard commitPendingRename() else { return }
        openKeyboardSettings()
    }

    private func add(_ sourceID: String) {
        guard commitPendingRename() else { return }
        var added: InputRole?
        structuralChange { added = model.addSlot(sourceID: sourceID, at: nil) }
        guard let id = added else { return }
        resetDrafts()
        focusedSlotID = id
        seat(id)
        let position = (model.config.slots.firstIndex(where: { $0.id == id }) ?? 0) + 1
        let trigger = model.bindingText(for: id)
        announce("Added slot \(model.config.displayName(for: id)) at position \(position) of \(model.config.slots.count). Trigger \(trigger.isEmpty ? "not assigned" : trigger).")
    }

    private func move(_ id: InputRole, by offset: Int) {
        guard commitPendingRename() else { return }
        let before = model.config.slots
        structuralChange { model.moveSlot(id, by: offset) }
        guard before != model.config.slots else { return }
        seat(id)
        let position = (model.config.slots.firstIndex(where: { $0.id == id }) ?? 0) + 1
        announce("\(model.config.displayName(for: id)) moved to position \(position) of \(model.config.slots.count).")
    }

    private func remove(_ id: InputRole) {
        guard commitPendingRename() else { return }
        structuralChange { model.removeSlot(id) }
        resetDrafts()
        if model.config.slot(id) == nil, focusedSlotID == id { focusedSlotID = nil }
    }

    private func undo() {
        guard commitPendingRename() else { return }
        let before = Set(model.config.slots.map(\.id))
        structuralChange { model.undoRemoveSlot() }
        resetDrafts()
        if let restored = model.config.slots.first(where: { !before.contains($0.id) }) {
            focusedSlotID = restored.id
            seat(restored.id)
            if case .rejected = model.boardNotice { return }
            announce("Restored slot \(restored.name).")
        }
    }

    private func dismissNotice() {
        guard commitPendingRename() else { return }
        structuralChange { model.dismissBoardNotice() }
    }

    private func seat(_ id: InputRole) {
        seatGeneration += 1
        seatingID = id
        seatPhase = .settling
        seatProgress = 1
        if reduceMotion {
            beginPulse(generation: seatGeneration)
        } else {
            settleProgress = 0
            let generation = seatGeneration
            DispatchQueue.main.async {
                guard generation == seatGeneration else { return }
                withAnimation(.linear(duration: DesignTokens.Motion.slow)) { settleProgress = 1 }
            }
        }
    }

    private func beginPulse(generation: Int) {
        guard generation == seatGeneration, seatingID != nil, seatPhase == .settling else { return }
        seatPhase = .pulsing
        seatProgress = 0
        DispatchQueue.main.async {
            guard generation == seatGeneration else { return }
            withAnimation(DesignTokens.Motion.seatPulse) { seatProgress = 1 }
        }
    }

    func announce(_ message: String) {
        guard let window = NSApp.keyWindow else { return }
        NSAccessibility.post(element: window, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }
}

private enum SeatPhase {
    case idle, settling, pulsing
}

private struct AddSlotMenu: View {
    let sources: [InputSourceInfo]
    let onAdd: (String) -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        Menu("Add Slot") {
            if sources.isEmpty {
                Button("All input sources are in slots") {}.disabled(true)
                Button("Open Keyboard Settings…", action: onOpenSettings)
            } else {
                ForEach(sources, id: \.id) { source in
                    Button(source.localizedName) { onAdd(source.id) }
                }
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel("Add Slot")
    }
}
