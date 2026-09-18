import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SourceListColumn: View {
    @ObservedObject var model: AppModel
    let onAdd: (String) -> Void
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            SectionLabel("Input sources")
            if model.selectableSources.isEmpty {
                Label("No input sources", systemImage: "keyboard")
                    .font(.caption)
                Button("Refresh", action: onRefresh)
                    .buttonStyle(ConsoleButtonStyle())
                keyboardSettingsButton
            } else {
                ForEach(model.selectableSources, id: \.id) { source in
                    SourceRow(source: source, usage: model.sourceUsage(of: source), model: model) {
                        onAdd(source.id)
                    }
                }
                if model.unassignedSources.isEmpty {
                    Text("All input sources are in slots.")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                    keyboardSettingsButton
                }
            }
        }
        .frame(width: 196, alignment: .leading)
    }
}

struct SourceRow: View {
    let source: InputSourceInfo
    let usage: SlotSourceUsage
    @ObservedObject var model: AppModel
    let onAdd: () -> Void

    private var isAvailable: Bool { usage == .available }

    private var name: String {
        switch usage {
        case .available: "Available"
        case let .owned(id): "In use · \(model.config.displayName(for: id))"
        case let .resolved(id, _): "Fallback for \(model.config.displayName(for: id))"
        }
    }

    private var icon: String {
        switch usage {
        case .available: "plus.circle"
        case .owned: "checkmark.circle.fill"
        case .resolved: "arrow.triangle.branch"
        }
    }

    private var tint: Color {
        switch usage {
        case .available:
            let slot = try? model.config.addingSlot(for: source).slot
            return SlotLook(slots: slot.map { [$0] } ?? []).tint(for: slot?.id ?? .english)
        case let .owned(id), let .resolved(id, _):
            return SlotLook(slots: model.config.slots).tint(for: id)
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(tint).frame(width: 6, height: 6)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(source.localizedName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textPrimary)
                    .lineLimit(2)
                Label(name, systemImage: icon)
                    .font(.caption2)
                    .foregroundStyle(isAvailable ? DesignTokens.Colors.textMuted : tint)
                    .id(name)
                    .transition(.opacity)
            }
            Spacer(minLength: 0)
            if isAvailable {
                Button(action: onAdd) {
                    Image(systemName: "plus")
                        .frame(width: 22, height: 24)
                }
                .buttonStyle(ConsoleButtonStyle())
                .help("Add \(source.localizedName) as a slot")
            }
        }
        .padding(9)
        .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.card)
            .fill(DesignTokens.Colors.surfaceRaised))
        .animation(DesignTokens.Motion.stateChange, value: usage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(source.localizedName)
        .accessibilityValue(name)
        .accessibilityAddTraits(isAvailable ? .isButton : [])
        .accessibilityAction { if isAvailable { onAdd() } }
    }
}

@MainActor
var keyboardSettingsButton: some View {
    Button("Open Keyboard Settings…", action: openKeyboardSettings)
        .buttonStyle(ConsoleButtonStyle())
}

@MainActor
func openKeyboardSettings() {
    guard let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") else { return }
    NSWorkspace.shared.open(url)
}
