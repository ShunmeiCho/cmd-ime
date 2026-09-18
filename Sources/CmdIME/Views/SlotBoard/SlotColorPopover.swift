import KeyboardSwitcherCore
import SwiftUI

/// The parent owns persistence and supplies the updated slot after each selection.
struct SlotColorPopover: View {
    let slot: SwitchSlot
    let onSelect: (String) -> Void
    let onClose: () -> Void
    var warning: String? = nil

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var selectedHex: String? {
        Color(cmdIMEHex: slot.tintHex)?.cmdIMEHexString
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(cmdIMEHex: slot.tintHex) ?? DesignTokens.Colors.textPrimary },
            set: { color in
                guard let hex = color.cmdIMEHexString else { return }
                onSelect(hex)
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            Text("Color for \(slot.name)")
                .font(DesignTokens.Typography.title)
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            HStack(spacing: DesignTokens.Spacing.xs) {
                ForEach(SlotPalette.colors, id: \.self) { hex in
                    swatch(hex)
                }
            }

            ColorPicker("Custom color", selection: colorBinding, supportsOpacity: false)
                .foregroundStyle(DesignTokens.Colors.textPrimary)
                .accessibilityLabel("Custom color for \(slot.name)")
                .accessibilityValue(selectedHex ?? slot.tintHex)

            if let warning {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(DesignTokens.Typography.body)
                    .foregroundStyle(DesignTokens.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityElement(children: .combine)
            }

            HStack {
                Spacer()
                Button("Close", action: onClose)
                    .buttonStyle(ConsoleButtonStyle())
                    .accessibilityLabel("Close color picker for \(slot.name)")
            }
        }
        .padding(DesignTokens.Spacing.md)
        .frame(width: 352)
        .background(DesignTokens.Colors.surfaceRaised)
    }

    private func swatch(_ hex: String) -> some View {
        let selected = selectedHex == hex
        return Button {
            onSelect(hex)
        } label: {
            Circle()
                .fill(Color(cmdIMEHex: hex) ?? DesignTokens.Colors.surfaceInset)
                .frame(width: 28, height: 28)
                .overlay {
                    Circle()
                        .strokeBorder(DesignTokens.Colors.separatorStrong, lineWidth: 1)
                }
                .overlay {
                    Image(systemName: "checkmark")
                        .font(DesignTokens.Typography.auxiliary.weight(.bold))
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .padding(3)
                        .background(Circle().fill(DesignTokens.Colors.surfaceInset))
                        .opacity(selected ? 1 : 0)
                }
                .padding(3)
                .overlay {
                    Circle()
                        .strokeBorder(DesignTokens.Colors.textPrimary, lineWidth: 2)
                        .opacity(selected ? 1 : 0)
                }
                .contentShape(Circle())
                .accessibilityHidden(true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color \(hex) for \(slot.name)")
        .accessibilityValue(selected ? "Selected" : "Not selected")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .animation(reduceMotion ? DesignTokens.Motion.quickFade : DesignTokens.Motion.stateChange,
                   value: selected)
    }
}
