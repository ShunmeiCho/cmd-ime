import KeyboardSwitcherCore
import SwiftUI

/// Builds the render models the settings draw: the same resolver the live panel
/// uses, so the preview and the miniatures cannot drift from the real bubble.
@MainActor
enum IndicatorPreviewModel {
    /// Miniatures are drawn at the smallest scale the Scale setting allows.
    static let miniatureScale = SwitcherConfig.minSwitchIndicatorScale

    static func make(
        model: AppModel,
        slot: SwitchSlot,
        previous: InputRole? = nil,
        isDark: Bool,
        miniatureOf theme: IndicatorTheme? = nil
    ) -> BubbleRenderModel? {
        var config = model.config
        if let theme {
            config.switchIndicatorThemeID = theme.id
            config.switchIndicatorSize = .medium
            config.switchIndicatorScale = miniatureScale
        }
        return IndicatorBubbleResolver.model(
            config: config,
            themes: model.indicatorLibrary.themes,
            sources: model.sources,
            slotID: slot.id,
            previousSlotID: previous,
            source: model.matchedSource(for: slot.id),
            context: .current(isDarkAppearance: isDark)
        )
    }
}

/// The "Switch indicator" settings card. Controls are the console components of
/// the settings window; the new design language lives in the bubble it previews.
struct IndicatorSettingsSection: View {
    static let unsupportedDisplayHelp = "Not available in this theme."
    static let inksColorCaption = "This theme prints with its own inks."

    @ObservedObject var model: AppModel
    @ObservedObject private var library: IndicatorLibrary
    @State private var isAdjusting = false

    init(model: AppModel) {
        self.model = model
        _library = ObservedObject(wrappedValue: model.indicatorLibrary)
    }

    private var theme: IndicatorTheme { library.theme(id: model.config.switchIndicatorThemeID) }

    var body: some View {
        CompactSection(title: "Switch indicator") {
            VStack(alignment: .leading, spacing: 10) {
                enabledRow
                IndicatorPreviewRow(model: model, library: library, isAdjusting: isAdjusting)
                    .opacity(model.config.showSwitchIndicator ? 1 : 0.45)
                Text("Appears near the focused caret after each switch.")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.Colors.textMuted)

                IndicatorThemePicker(model: model, library: library)
                displayRow
                sizeRow
                scaleRow
                colorRow
                IndicatorSlotChips(model: model)
                IndicatorTypographyRows(model: model, library: library, theme: theme, isAdjusting: $isAdjusting)
                if !theme.isBuiltIn {
                    IndicatorThemeEditor(model: model, theme: theme, isAdjusting: $isAdjusting)
                }
                IndicatorFontsRow(library: library)

                if let message = library.message {
                    IndicatorNotice(text: message)
                }
            }
        }
    }

    private var enabledRow: some View {
        CompactSettingRow("Enabled") {
            Toggle(
                "Show switch indicator",
                isOn: Binding(
                    get: { model.config.showSwitchIndicator },
                    set: { model.setSwitchIndicatorVisible($0) }
                )
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .tint(DesignTokens.Colors.success)
            .controlSize(.small)
            Spacer()
        }
    }

    /// The stored Display value is never rewritten by a theme; a segment the theme's
    /// layout cannot show is disabled and the bubble coerces it for drawing only.
    private var displayRow: some View {
        let supported = IndicatorDisplayComposition.supported(theme.archetype)
        return CompactSettingRow("Display") {
            VStack(alignment: .leading, spacing: 4) {
                ConsoleSegmentedControl(
                    options: SwitchIndicatorContentStyle.allCases.map {
                        ConsoleSegmentOption(value: $0, label: $0.displayName)
                    },
                    selection: Binding(
                        get: { model.config.switchIndicatorContentStyle },
                        set: { if supported.contains($0) { model.setSwitchIndicatorContentStyle($0) } }
                    )
                )
                .frame(width: 202)
                if supported.count < SwitchIndicatorContentStyle.allCases.count {
                    let names = supported.map(\.displayName).joined(separator: ", ")
                    Text("\(theme.name) shows \(names) only. \(Self.unsupportedDisplayHelp)")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .help(supported.count < SwitchIndicatorContentStyle.allCases.count ? Self.unsupportedDisplayHelp : "")
        }
    }

    private var sizeRow: some View {
        CompactSettingRow("Size") {
            ConsoleSegmentedControl(
                options: SwitchIndicatorSize.allCases.map { ConsoleSegmentOption(value: $0, label: $0.displayName) },
                selection: Binding(
                    get: { model.config.switchIndicatorSize },
                    set: { model.setSwitchIndicatorSize($0) }
                )
            )
            .frame(width: 160)
        }
    }

    private var scaleRow: some View {
        let percent = Int((model.config.switchIndicatorScale * 100).rounded())
        return CompactSettingRow("Scale \(percent)%") {
            Slider(
                value: Binding(
                    get: { model.config.switchIndicatorScale },
                    set: { model.setSwitchIndicatorScale($0) }
                ),
                in: SwitcherConfig.minSwitchIndicatorScale...SwitcherConfig.maxSwitchIndicatorScale,
                step: 0.05,
                onEditingChanged: { isAdjusting = $0 }
            )
            .accessibilityLabel("Indicator scale")
            .accessibilityValue("\(percent) percent")
            Button("Reset") {
                model.setSwitchIndicatorScale(SwitcherConfig.defaultSwitchIndicatorScale)
            }
            .buttonStyle(ConsoleButtonStyle())
        }
    }

    private var colorRow: some View {
        let usesSlotColor = theme.colorSource == .slot
        return CompactSettingRow("Color") {
            VStack(alignment: .leading, spacing: 4) {
                ConsoleSegmentedControl(
                    options: SwitchIndicatorColorStyle.selectable.map {
                        ConsoleSegmentOption(value: $0, label: $0.displayName)
                    },
                    selection: Binding(
                        // A style that is no longer offered reads as Slot until it is migrated.
                        get: {
                            let style = model.config.switchIndicatorColorStyle
                            return SwitchIndicatorColorStyle.selectable.contains(style) ? style : .role
                        },
                        set: { model.setSwitchIndicatorColorStyle($0) }
                    )
                )
                .frame(width: 202)
                .disabled(!usesSlotColor)
                .opacity(usesSlotColor ? 1 : 0.45)
                if !usesSlotColor {
                    Text(Self.inksColorCaption)
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
            }
        }
    }
}

/// An inline problem report: warning colour plus a glyph, so it does not rely on colour alone.
struct IndicatorNotice: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "exclamationmark.triangle.fill").accessibilityHidden(true)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption2)
        .foregroundStyle(DesignTokens.Colors.warning)
    }
}
