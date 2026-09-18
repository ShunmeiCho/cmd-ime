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
    @State private var showsFonts = false
    @State private var fontQuery = ""

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

        // A searchable popover: several hundred installed families do not fit a menu.
        let query = fontQuery.trimmingCharacters(in: .whitespaces).lowercased()
        let matches: (String) -> Bool = { query.isEmpty || $0.lowercased().contains(query) }
        return Button { showsFonts.toggle() } label: {
            HStack(spacing: DesignTokens.Spacing.sm) {
                Text(currentFontName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            .font(DesignTokens.Typography.body.weight(.semibold))
            .foregroundStyle(isFamilyMissing ? DesignTokens.Colors.warning : DesignTokens.Colors.textPrimary)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .frame(minHeight: DesignTokens.Layout.fieldHeight)
            .background(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(DesignTokens.Colors.surfaceInset)
                .overlay(RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                    .stroke(DesignTokens.Colors.separatorStrong, lineWidth: 1)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Font")
        .accessibilityValue(currentFontName)
        .popover(isPresented: $showsFonts, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                TextField("Search fonts", text: $fontQuery)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        fontGroup("System", Self.designNames.map(\.1).filter(matches)) { name in
                            guard let design = Self.designNames.first(where: { $0.1 == name })?.0 else { return }
                            model.editIndicatorTheme {
                                $0.typography.displayFamily = nil
                                $0.typography.displayDesign = design
                            }
                        }
                        fontGroup("Presets", TypographyPreset.allCases.map { $0.rawValue.capitalized }.filter(matches)) { name in
                            guard let preset = TypographyPreset.allCases.first(where: { $0.rawValue.capitalized == name }) else { return }
                            model.editIndicatorTheme { theme in
                                let scale = theme.typography.textScale
                                theme.typography = preset.typography
                                theme.typography.textScale = scale
                            }
                        }
                        fontGroup("Imported", imported.filter(matches)) { select($0) }
                        fontGroup("Installed", installed.filter(matches)) { select($0) }
                    }
                }
                .frame(height: 280)
            }
            .padding(12)
            .frame(width: 280)
            .preferredColorScheme(.dark)
        }
    }

    @ViewBuilder
    private func fontGroup(_ title: String, _ names: [String], pick: @escaping (String) -> Void) -> some View {
        if !names.isEmpty {
            Text(title.uppercased())
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .padding(.top, 8)
                .padding(.bottom, 2)
            ForEach(names, id: \.self) { name in
                Button {
                    pick(name)
                    showsFonts = false
                } label: {
                    HStack {
                        Text(name).lineLimit(1)
                        Spacer(minLength: 4)
                        if name == currentFontName { Image(systemName: "checkmark") }
                    }
                    .font(DesignTokens.Typography.body)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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
