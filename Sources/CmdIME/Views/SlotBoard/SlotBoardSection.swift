import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SlotBoardSection: View {
    @ObservedObject var model: AppModel
    @StateObject private var drag = SlotBoardDragController()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showsResetConfirmation = false
    @State private var renamingSlotID: InputRole?
    @State private var pendingRenameCommit: (() -> Bool)?
    @State private var focusedSlotID: InputRole?
    @State private var revealRequest: (id: InputRole, token: UUID)?
    @State private var seatingID: InputRole?
    @State private var seatGeneration = 0
    @State private var seatPhase = SeatPhase.idle
    @State private var settleProgress: CGFloat = 1
    @State private var seatProgress: CGFloat = 1
    @Binding var triggerDrafts: [InputRole: String]
    @Binding var triggerTypeDrafts: [InputRole: BindingTriggerType]
    let resetDrafts: () -> Void
    var footer: AnyView = AnyView(EmptyView())

    var body: some View {
        let generation = seatGeneration
        let phase = seatPhase
        ScrollViewReader { proxy in
            HStack(alignment: .top, spacing: DesignTokens.Layout.panelGap) {
                SourceListColumn(model: model, drag: drag,
                                 onBeginDrag: { beginDrag(.source($0), value: $1) }, onAdd: add, onRefresh: {
                    guard commitPendingRename() else { return }
                    guard model.refreshSources() else { return }
                    resetDrafts()
                }, onOpenSettings: showKeyboardSettings, onLocate: locateSlot)
                VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
                    HStack(spacing: DesignTokens.Layout.rowGap) {
                        SectionLabel("Slots")
                        Spacer(minLength: 0)
                        AddSlotMenu(sources: model.unassignedSources, onAdd: add, onOpenSettings: showKeyboardSettings)
                        ConsoleMenuButton(title: "Manage") {
                            Button("Reset to Detected") {
                                guard commitPendingRename() else { return }
                                showsResetConfirmation = true
                            }
                        }
                        .fixedSize()
                        .accessibilityLabel("Manage slots")
                    }
                    .frame(height: DesignTokens.Layout.panelHeaderHeight)
                    SlotListColumn(slots: model.config.slots, notice: model.boardNotice,
                                   canUndo: model.canUndoRemoval, seatingID: seatingID, drag: drag,
                                   insertionTint: dragTint, onUndo: undo, onDismiss: dismissNotice, onAdd: add) { slot in
                        card(for: slot)
                    }
                    Divider()
                    footer
                }
                .padding(DesignTokens.Layout.panelInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
                    .fill(DesignTokens.Colors.surface))
            }
            .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion),
                       value: model.boardNotice)
            .onChange(of: model.boardNotice) { notice in
                guard let notice else { return }
                switch notice {
                case let .rejected(reason): announce(reason)
                case let .removed(name): announce("Removed slot \(name). Undo available.")
                case let .found(_, name): announce("Found \(name). Add Slot available.")
                }
                // Drag rejection must not scroll the board under the held pointer.
                guard drag.payload == nil else { return }
                DispatchQueue.main.async {
                    withAnimation(DesignTokens.Motion.resolved(DesignTokens.Motion.expandCollapse, reduceMotion: reduceMotion)) {
                        proxy.scrollTo("boardNotice")
                    }
                }
            }
        }
        .coordinateSpace(name: "slotBoard")
        .overlay(alignment: .topLeading) { dragGhost }
        .zIndex(drag.payload == nil ? 0 : 1)
        .onDisappear { drag.tearDown() }
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
            drag.updateReduceMotion(reduced)
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

    private func card(for slot: SwitchSlot, isGhost: Bool = false) -> some View {
        let source = model.matchedSource(for: slot.id)
        return SlotCard(
            slot: slot, source: source, isActive: model.activeRole == slot.id,
            isDuplicate: !model.config.duplicateSlotIDs(for: slot.id, sources: model.sources).isEmpty,
            position: model.config.slots.firstIndex(where: { $0.id == slot.id }) ?? 0,
            count: model.config.slots.count, triggerText: model.bindingText(for: slot.id),
            hasTrigger: model.trigger(for: slot.id) != nil,
            warning: model.slotNotices[slot.id] ?? model.oneShotConflictWarning(for: slot.id),
            isRenaming: !isGhost && renamingSlotID == slot.id,
            onRename: isGhost ? {} : {
                guard commitPendingRename() else { return }
                renamingSlotID = slot.id
            },
            onCommitRename: isGhost ? { _ in false } : { name in
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
            onCancelRename: isGhost ? {} : {
                model.clearSlotNotice(for: slot.id)
                renamingSlotID = nil
                pendingRenameCommit = nil
            },
            onRenameDraftChanged: isGhost ? {} : { model.clearSlotNotice(for: slot.id) },
            onRenameCommitChanged: isGhost ? { _ in } : { callback in
                // An outgoing field must not clear the incoming field's registration.
                guard renamingSlotID == slot.id else { return }
                pendingRenameCommit = callback
            },
            onTest: isGhost ? {} : {
                guard commitPendingRename() else { return }
                model.switchRole(slot.id)
            },
            onMove: isGhost ? { _ in } : { move(slot.id, by: $0) },
            onRemove: isGhost ? {} : { remove(slot.id) },
            onColorSelect: isGhost ? { _ in } : { hex in
                guard commitPendingRename() else { return }
                _ = model.setSlotTint(hex, for: slot.id)
            },
            triggerControls: AnyView(HStack(spacing: 8) {
                triggerTypePicker(for: slot.id, isGhost: isGhost)
                triggerControl(for: slot.id, isGhost: isGhost)
            }),
            inputSourceControl: AnyView(inputSourcePicker(for: slot.id, source: source, isGhost: isGhost)),
            matchNotice: AnyView(matchNotice(for: slot, isGhost: isGhost)),
            seatProgress: !isGhost && seatingID == slot.id ? seatProgress : 1,
            focusName: !isGhost && focusedSlotID == slot.id,
            isGhost: isGhost,
            dragHandle: isGhost ? AnyView(SlotDragHandleGlyph()) : AnyView(
                SlotDragHandle(controller: drag, enabled: model.config.slots.count > 1) {
                    beginDrag(.slot(slot.id), value: $0)
                })
        )
        .background {
            SlotRevealAnchor(requestID: !isGhost && revealRequest?.id == slot.id ? revealRequest?.token : nil,
                             isEnabled: !isGhost && drag.payload == nil,
                             canReveal: { !isGhost && drag.payload == nil }) {
                guard revealRequest?.id == slot.id, !isGhost else { return }
                revealRequest = nil
                seat(slot.id, waitForLayout: false)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var dragGhost: some View {
        if drag.payload != nil {
            SlotDragGhost(controller: drag, pointer: drag.pointer, tint: dragTint) {
                if let slot = drag.slotSnapshot {
                    card(for: slot, isGhost: true)
                } else if let source = drag.sourceSnapshot {
                    SourceRow(source: source, usage: .available, model: model, drag: drag,
                              onBeginDrag: { _ in false }, onAdd: {}, isGhost: true)
                }
            }
            .id(drag.sessionID)
            .transition(.opacity.animation(DesignTokens.Motion.quickFade))
        }
    }

    private var dragTint: Color {
        if let slot = drag.slotSnapshot {
            return SlotLook(slots: [slot]).tint(for: slot.id)
        }
        if let source = drag.sourceSnapshot, let added = try? model.config.addingSlot(for: source) {
            return SlotLook(slots: [added.slot]).tint(for: added.slot.id)
        }
        return DesignTokens.Colors.accent
    }

    private func matchNotice(for slot: SwitchSlot, isGhost: Bool) -> some View {
        let explanation = SlotMatchExplanation.resolve(for: slot.id, sources: model.sources, config: model.config)
        let preferredID = model.config.preference(for: slot.id).preferredIDs.first
        let preferredName = model.sources.first { $0.id == preferredID }?.localizedName
        let source = model.matchedSource(for: slot.id)
        var reason: String?
        if let source, case let .owned(owner) = model.sourceUsage(of: source), owner != slot.id {
            reason = "Already pinned to \(model.config.displayName(for: owner)). Choose another input source."
        }
        return SlotMatchNotice(explanation: explanation, preferredName: preferredName,
                               pinUnavailableReason: reason) {
            guard !isGhost, let source, commitPendingRename() else { return }
            model.setInputSourceID(source.id, for: slot.id)
        }
        .allowsHitTesting(!isGhost)
        .accessibilityHidden(isGhost)
    }

    private func locateSlot(_ id: InputRole) {
        guard drag.payload == nil, commitPendingRename(), model.config.slot(id) != nil else { return }
        focusedSlotID = id
        revealRequest = (id, UUID())
    }

    private func beginDrag(_ payload: SlotDragPayload, value: DragGesture.Value) -> Bool {
        guard !model.isRecordingTrigger, commitPendingRename(), drag.prepareForBegin() else { return false }
        return drag.begin(payload: payload, startLocation: value.startLocation, location: value.location,
                          config: model.config, sources: model.selectableSources,
                          currentOrder: { model.config.slots.map(\.id) }, reduceMotion: reduceMotion,
                          commit: commitDrop, reject: model.rejectSlotDrop,
                          pulse: { if !drag.isForcingCompletion { seat($0, waitForLayout: false) } }, validate: dropRejection)
    }

    private func dropRejection(_ payload: SlotDragPayload) -> String? {
        switch payload {
        case let .slot(id):
            return model.config.slot(id) == nil ? SlotError.unknownSlot(id).localizedDescription : nil
        case let .source(id):
            guard let source = model.selectableSources.first(where: { $0.id == id }) else {
                return "This input source is no longer available."
            }
            switch model.sourceUsage(of: source) {
            case .available: return nil
            case let .owned(owner): return "Already in slot \(model.config.displayName(for: owner))"
            case let .resolved(owner, _): return "Fallback for \(model.config.displayName(for: owner))"
            }
        }
    }

    private func commitDrop(_ payload: SlotDragPayload, index: Int) -> Bool {
        if let reason = dropRejection(payload) {
            model.rejectSlotDrop(reason)
            return false
        }
        switch payload {
        case let .slot(id):
            guard let source = model.config.slots.firstIndex(where: { $0.id == id }) else { return false }
            let expected = model.config.movingSlot(from: source, to: index).slots
            model.moveSlot(id, toFinalIndex: index)
            guard model.config.slots == expected else { return false }
            if source != index {
                announce("\(model.config.displayName(for: id)) moved to position \(min(index + 1, expected.count)) of \(expected.count).")
            }
            return true
        case let .source(id):
            var added: InputRole?
            withAnimation(drag.isForcingCompletion ? nil : DesignTokens.Motion.resolved(
                DesignTokens.Motion.expandCollapse, reduceMotion: drag.reduceMotion)) {
                added = model.addSlot(sourceID: id, at: index)
            }
            guard let added else { return false }
            resetDrafts()
            focusedSlotID = added
            if !drag.isForcingCompletion { seat(added, waitForLayout: !drag.reduceMotion) }
            announce("Added slot \(model.config.displayName(for: added)) at position \(index + 1) of \(model.config.slots.count).")
            return true
        }
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
        revealRequest = (id, UUID())
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

    private func seat(_ id: InputRole, waitForLayout: Bool = true) {
        seatGeneration += 1
        seatingID = id
        seatPhase = .settling
        seatProgress = 1
        if reduceMotion || !waitForLayout {
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
        ConsoleMenuButton(title: "Add Slot", systemImage: "plus") {
            if sources.isEmpty {
                Button("All input sources are in slots") {}.disabled(true)
                Button("Open Keyboard Settings…", action: onOpenSettings)
            } else {
                ForEach(sources, id: \.id) { source in
                    Button(source.localizedName) { onAdd(source.id) }
                }
            }
        }
        .fixedSize()
        .accessibilityLabel("Add Slot")
    }
}
