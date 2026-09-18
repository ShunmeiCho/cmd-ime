import AppKit
import KeyboardSwitcherCore
import SwiftUI

struct SwitchSlotCard<TriggerTypeControl: View, TriggerControl: View, InputSourceControl: View>: View {
    @Environment(\.slotLook) private var slotLook
    let role: InputRole
    let presentation: InputSourcePresentation
    let source: InputSourceInfo?
    let isActive: Bool
    let isDuplicate: Bool
    let triggerText: String
    let sourceStatus: String
    let bindingWarning: String?
    let onTest: () -> Void
    let onFix: () -> Void
    @ViewBuilder let triggerTypeControl: () -> TriggerTypeControl
    @ViewBuilder let triggerControl: () -> TriggerControl
    @ViewBuilder let inputSourceControl: () -> InputSourceControl

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            RoleBadge(role: role, symbol: presentation.symbol, size: 31, isActive: isActive)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(slotLook.name(for: role))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                    statusChip
                }

                if source == nil {
                    HStack(spacing: 6) {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.caption2.weight(.bold))
                            Text("Not matched")
                                .font(.caption.weight(.semibold))
                        }
                        .foregroundStyle(DesignTokens.Colors.warning)
                        // Without this an unmatched slot is a dead end: a user whose input
                        // sources are not Chinese or Japanese could never assign one here.
                        inputSourceControl()
                    }
                } else {
                    HStack(spacing: 6) {
                        Text(presentation.detail)
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textMuted)
                            .lineLimit(1)
                            .minimumScaleFactor(0.80)
                        inputSourceControl()
                    }
                }

                if let bindingWarning {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2.weight(.bold))
                        Text(bindingWarning)
                            .font(.caption2.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .help(bindingWarning)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(bindingWarning)
                }
            }
            .frame(width: 210, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                if source == nil {
                    TriggerKeycapSequence(role: role, triggerText: triggerText, isActive: isActive)
                        .frame(width: 92, alignment: .leading)
                    Text(sourceStatus)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .lineLimit(1)
                        .frame(width: 150, alignment: .leading)
                    Button("Fix", action: onFix)
                        .buttonStyle(ConsoleButtonStyle(prominent: true))
                        .frame(width: 58)
                } else {
                    triggerTypeControl()
                        .frame(width: 158)
                    triggerControl()
                        .frame(width: 126, alignment: .center)
                    Button("Test", action: onTest)
                        .buttonStyle(ConsoleButtonStyle())
                        .frame(width: 58)
                }
            }
            .frame(width: 362, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                .fill(DesignTokens.Colors.surfaceRaised)
                .overlay(
                    RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                        .stroke(slotStrokeColor, lineWidth: isActive ? 1.4 : 1)
                )
                .shadow(color: isActive ? slotLook.tint(for: role).opacity(0.26) : .clear, radius: 14, y: 5)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(slotLook.name(for: role)) switch slot")
        .accessibilityValue(isActive ? "Current" : (source == nil ? "Not matched" : "Configured"))
    }

    @ViewBuilder
    private var statusChip: some View {
        if bindingWarning != nil {
            Text("Warning")
                .slotChip(color: DesignTokens.Colors.warning)
        } else if isActive {
            Text("Current")
                .slotChip(color: slotLook.tint(for: role))
        } else if isDuplicate {
            Text("Duplicate")
                .slotChip(color: DesignTokens.Colors.warning)
        }
    }

    private var slotStrokeColor: Color {
        if isActive {
            return slotLook.tint(for: role).opacity(0.74)
        }
        if source == nil || isDuplicate || bindingWarning != nil {
            return DesignTokens.Colors.warning.opacity(0.35)
        }
        return slotLook.tint(for: role).opacity(0.22)
    }
}

private struct TriggerKeycapSequence: View {
    let role: InputRole
    let triggerText: String
    let isActive: Bool

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(keycaps.enumerated()), id: \.offset) { index, keycap in
                if index > 0 {
                    Text("+")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
                KeycapView(keycap.label, detail: keycap.detail, role: role, isPressed: isActive)
                    .font(.caption)
            }
        }
    }

    private var keycaps: [LiveKeycap] {
        if triggerText.isEmpty {
            return [LiveKeycap(label: role.defaultSymbol, detail: nil)]
        }

        let parts = triggerText.split(separator: "+").map { String($0) }
        if parts.count == 1 {
            return [LiveKeycap(keyName: parts[0])]
        }
        return parts.map { LiveKeycap(keyName: $0) }
    }
}

extension SwitchSlotsSection {
    func inputSourcePicker(for role: InputRole, source: InputSourceInfo?) -> some View {
        Menu {
            if source == nil {
                Button("Not matched") {}
                    .disabled(true)
            }
            ForEach(model.selectableSources, id: \.id) { candidate in
                Button(model.inputSourceMenuTitle(candidate, for: role)) {
                    model.setInputSourceID(candidate.id, for: role)
                }
                .disabled(!model.inputSourceSelection(candidate, for: role).isEnabled)
            }
        } label: {
            Text(source == nil ? "Choose" : "Change")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textMuted)
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.035))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                    )
            )
        }
        .menuStyle(.borderlessButton)
    }

}

private extension Text {
    func slotChip(color: Color) -> some View {
        self
            .font(.caption2.weight(.bold))
            .textCase(.uppercase)
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(color.opacity(0.16))
            )
    }
}
