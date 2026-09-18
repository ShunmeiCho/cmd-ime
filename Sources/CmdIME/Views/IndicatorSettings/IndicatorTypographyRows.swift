import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Font, weight and text size of the display voice. They belong to the theme, so on
/// a built-in theme the first change makes an editable copy and applies it there.
struct IndicatorTypographyRows: View {
    private static let textScaleStep = 0.05
    private static let weightLabels: [IndicatorFontWeight: String] = [
        .regular: "Regular", .medium: "Medium", .semibold: "Semi", .bold: "Bold", .heavy: "Heavy",
    ]
    private static let designNames: [(IndicatorFontDesign, String)] = [
        (.default, "System"), (.rounded, "System Rounded"), (.serif, "System Serif"), (.monospaced, "System Mono"),
    ]

    @ObservedObject var model: AppModel
    @ObservedObject var library: IndicatorLibrary
    let theme: IndicatorTheme
    @Binding var isAdjusting: Bool

    private var typography: IndicatorTypography { theme.typography }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            CompactSettingRow("Font") {
                VStack(alignment: .leading, spacing: 4) {
                    fontMenu
                    fontNotice
                }
            }
            CompactSettingRow("Weight") {
                ConsoleSegmentedControl(
                    options: IndicatorFontWeight.allCases.map {
                        ConsoleSegmentOption(value: $0, label: Self.weightLabels[$0] ?? $0.rawValue)
                    },
                    selection: Binding(
                        get: { typography.displayWeight },
                        set: { weight in model.editIndicatorTheme { $0.typography.displayWeight = weight } }
                    )
                )
            }
            CompactSettingRow("Text \(Int((typography.textScale * 100).rounded()))%") {
                Slider(
                    value: Binding(
                        get: { typography.textScale },
                        set: { scale in
                            let clamped = IndicatorTypography.clampedTextScale(scale)
                            guard clamped != typography.textScale else { return }
                            model.editIndicatorTheme { $0.typography.textScale = clamped }
                        }
                    ),
                    in: IndicatorTypography.minTextScale...IndicatorTypography.maxTextScale,
                    step: Self.textScaleStep,
                    onEditingChanged: { isAdjusting = $0 }
                )
                .accessibilityLabel("Indicator text size")
                .accessibilityValue("\(Int((typography.textScale * 100).rounded())) percent")
            }
            if theme.isBuiltIn {
                Text("Changing the text creates an editable copy of \(theme.name).")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
        }
    }

    // MARK: - Font

    private var currentFontName: String {
        typography.displayFamily
            ?? Self.designNames.first { $0.0 == typography.displayDesign }?.1
            ?? "System"
    }

    private var isFamilyMissing: Bool {
        typography.displayFamily.map { !BubbleFontResolver.isAvailable(family: $0) } ?? false
    }

    private var fontMenu: some View {
        let imported = library.importedFamilies
        let importedKeys = Set(imported.map { $0.lowercased() })
        let installed = NSFontManager.shared.availableFontFamilies
            .filter { !$0.hasPrefix(".") && !importedKeys.contains($0.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        return ConsoleMenuButton(title: currentFontName, warning: isFamilyMissing) {
            ForEach(Self.designNames, id: \.1) { design, name in
                Button(name) {
                    model.editIndicatorTheme {
                        $0.typography.displayFamily = nil
                        $0.typography.displayDesign = design
                    }
                }
            }
            Divider()
            ForEach(TypographyPreset.allCases, id: \.self) { preset in
                Button("Preset: \(preset.rawValue.capitalized)") {
                    model.editIndicatorTheme { theme in
                        let scale = theme.typography.textScale
                        theme.typography = preset.typography
                        theme.typography.textScale = scale
                    }
                }
            }
            if !imported.isEmpty {
                Section("Imported") {
                    ForEach(imported, id: \.self) { family in
                        Button(family) { select(family) }
                    }
                }
            }
            Section("Installed") {
                ForEach(installed, id: \.self) { family in
                    Button(family) { select(family) }
                }
            }
        }
    }

    @ViewBuilder
    private var fontNotice: some View {
        if let family = typography.displayFamily {
            if isFamilyMissing {
                IndicatorNotice(text: "\(family) is not available. Using the system font.")
            } else if !BubbleFontResolver.hasExactWeight(family: family, weight: typography.displayWeight) {
                Text("Nearest available weight is used.")
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
        }
    }

    private func select(_ family: String) {
        model.editIndicatorTheme { $0.typography.displayFamily = family }
    }
}
