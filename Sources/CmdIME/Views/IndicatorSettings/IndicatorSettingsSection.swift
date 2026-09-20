import KeyboardSwitcherCore
import SwiftUI

/// Builds the render models the settings draw: the same resolver the live panel
/// uses, so the preview and the miniatures cannot drift from the real bubble.
@MainActor
enum IndicatorPreviewModel {
    /// Miniatures are drawn at the smallest scale the Scale setting allows.
    static let miniatureScale = 0.65
    /// Display, Size and Color share one width so their segments line up down the column.
    static let segmentedWidth: CGFloat = 330

    /// The appearance always comes from the system, as it does for the live panel:
    /// the preview must show the glass the user will really get over either page.
    static func make(
        model: AppModel,
        slot: SwitchSlot,
        previous: InputRole? = nil,
        miniatureOf theme: IndicatorTheme? = nil
    ) -> BubbleRenderModel? {
        var config = model.config
        if let theme {
            config.switchIndicatorThemeID = theme.id
            config.switchIndicatorSizeFactor = miniatureScale
        }
        return IndicatorBubbleResolver.model(
            config: config,
            themes: model.indicatorLibrary.themes,
            sources: model.sources,
            slotID: slot.id,
            previousSlotID: previous,
            source: model.matchedSource(for: slot.id),
            context: .current()
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
                .frame(width: IndicatorPreviewModel.segmentedWidth)
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

    /// One control, and the percentage is the size the bubble really draws at. It used
    /// to be two that multiplied, so the same percentage meant a different size under
    /// each Size button, and on the switcher the slider bottomed out reading 110 %.
    private var sizeRow: some View {
        let stored = model.config.switchIndicatorSizeFactor
        let effective = BubbleMetrics.effectiveFactor(stored, archetype: theme.archetype)
        let minimum = BubbleMetrics.effectiveFactor(
            SwitcherConfig.minSwitchIndicatorSizeFactor,
            archetype: theme.archetype
        )
        let percent = Int((effective * 100).rounded())
        return VStack(alignment: .leading, spacing: 4) {
            CompactSettingRow("Size \(percent)%") {
                Slider(
                    value: Binding(
                        get: { effective },
                        set: { model.setSwitchIndicatorSizeFactor($0) }
                    ),
                    in: minimum...SwitcherConfig.maxSwitchIndicatorSizeFactor,
                    step: 0.05,
                    onEditingChanged: { isAdjusting = $0 }
                )
                .accessibilityLabel("Indicator size")
                .accessibilityValue("\(percent) percent")
                Button("Reset") {
                    model.setSwitchIndicatorSizeFactor(SwitcherConfig.defaultSwitchIndicatorSizeFactor)
                }
                .buttonStyle(ConsoleButtonStyle())
            }
            // A theme that stops early says so, rather than leaving a slider that
            // looks free and is not.
            if minimum > SwitcherConfig.minSwitchIndicatorSizeFactor {
                Text("\(theme.name) does not shrink below \(Int((minimum * 100).rounded()))%.")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
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
                .frame(width: IndicatorPreviewModel.segmentedWidth)
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
