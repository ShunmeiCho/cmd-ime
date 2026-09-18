import KeyboardSwitcherCore
import SwiftUI

/// Appearance controls of the selected user theme. Every change is written to the
/// theme file at once. Legibility problems are reported, never blocked: the two-ink
/// limit and the contrast floor bind the built-in themes, not the user's own.
struct IndicatorThemeEditor: View {
    private enum PaperSurface: Hashable {
        case glass, liquid, paper

        init(_ surface: IndicatorSurface) {
            switch surface {
            case .paper: self = .paper
            case .liquidGlass: self = .liquid
            case .glass, .none: self = .glass
            }
        }

        var surface: IndicatorSurface {
            switch self {
            case .glass: .glass
            case .liquid: .liquidGlass
            case .paper: .paper
            }
        }
    }

    private static let swatchCell = IndicatorSwatchButton.size + 2 * (SelectionRing.ringGap + SelectionRing.ringWidth)

    @ObservedObject var model: AppModel
    let theme: IndicatorTheme
    @Binding var isAdjusting: Bool

    private var substrateHex: String { theme.substrateHex ?? IndicatorTheme.defaultSubstrateHex }
    private var issues: [IndicatorThemeLegibility.Issue] { IndicatorThemeLegibility.issues(theme) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Editing \(theme.name)")

            if theme.surface != .none {
                CompactSettingRow("Surface") {
                    ConsoleSegmentedControl(
                        options: [ConsoleSegmentOption(value: PaperSurface.glass, label: "Glass"),
                                  ConsoleSegmentOption(value: PaperSurface.liquid, label: "Liquid"),
                                  ConsoleSegmentOption(value: PaperSurface.paper, label: "Paper")],
                        selection: Binding(
                            get: { PaperSurface(theme.surface) },
                            set: { surface in edit { Self.setSurface(surface.surface, on: &$0) } }
                        )
                    )
                    .frame(width: 210)
                }
            }

            if theme.surface == .paper { paperRows }

            CompactSettingRow("Color from") {
                ConsoleSegmentedControl(
                    options: [ConsoleSegmentOption(value: IndicatorColorSource.slot, label: "Each slot"),
                              ConsoleSegmentOption(value: IndicatorColorSource.inks, label: "One color")],
                    selection: Binding(get: { theme.colorSource }, set: { source in edit { $0.colorSource = source } })
                )
                .frame(width: 210)
            }

            // On glass the one colour fills the tile or the switcher thumb; paper has its own ink rows.
            if theme.surface != .paper, theme.colorSource == .inks {
                inkRow(
                    "Highlight",
                    options: InkCatalog.inks.map { ($0.name, $0.hex) },
                    selectedHex: theme.tileInkHex,
                    issueKey: "tileInkHex",
                    clearTitle: "Neutral"
                ) { hex, theme in theme.tileInkHex = hex }
            }

            slider("Corners", value: theme.cornerRadius, range: IndicatorTheme.Limits.cornerRadius.range, step: 1,
                   display: "\(Int(theme.cornerRadius.rounded())) pt") { value, theme in theme.cornerRadius = value }
            slider("Stroke", value: theme.strokeOpacity, range: IndicatorTheme.Limits.strokeOpacity.range, step: 0.02,
                   display: percent(theme.strokeOpacity)) { value, theme in theme.strokeOpacity = value }
            slider("Shadow", value: theme.shadowStrength, range: IndicatorTheme.Limits.shadowStrength.range, step: 0.05,
                   display: percent(theme.shadowStrength)) { value, theme in theme.shadowStrength = value }
        }
    }

    // MARK: - Paper

    @ViewBuilder
    private var paperRows: some View {
        inkRow(
            "Paper",
            options: InkCatalog.substrates.map { ($0.name, $0.hex) },
            selectedHex: substrateHex,
            issueKey: nil
        ) { hex, theme in theme.substrateHex = hex }

        inkRow(
            "Text ink",
            options: InkLegibility.textInks(on: substrateHex).map { ($0.name, $0.hex) },
            selectedHex: theme.textInkHex ?? IndicatorTheme.defaultPaperTextInkHex,
            issueKey: "textInkHex"
        ) { hex, theme in theme.textInkHex = hex }

        if theme.colorSource == .inks {
            inkRow(
                "Tile ink",
                options: InkLegibility.tileInks(on: substrateHex).map { ($0.name, $0.hex) },
                selectedHex: theme.tileInkHex,
                issueKey: "tileInkHex",
                clearTitle: "Same as text"
            ) { hex, theme in theme.tileInkHex = hex }

            pairsRow
        }
    }

    /// Approved two-ink pairs that pass on this paper, with their jobs already assigned.
    @ViewBuilder
    private var pairsRow: some View {
        let jobs = InkCatalog.pairs.compactMap { InkLegibility.assignment(for: $0, on: substrateHex) }
        if !jobs.isEmpty {
            CompactSettingRow("Pairs") {
                HStack(spacing: 6) {
                    ForEach(jobs, id: \.textInk.id) { pair in
                        let isSelected = theme.textInkHex == pair.textInk.hex && theme.tileInkHex == pair.tileInk.hex
                        Button {
                            edit {
                                $0.textInkHex = pair.textInk.hex
                                $0.tileInkHex = pair.tileInk.hex
                            }
                        } label: {
                            HStack(spacing: 0) {
                                Color(bubbleHex: pair.textInk.hex)
                                Color(bubbleHex: pair.tileInk.hex)
                            }
                            .frame(width: 30, height: IndicatorSwatchButton.size)
                            .clipShape(RoundedRectangle(cornerRadius: IndicatorSwatchButton.cornerRadius, style: .continuous))
                            .selectionRing(isSelected, cornerRadius: IndicatorSwatchButton.cornerRadius)
                            .padding(SelectionRing.ringGap + SelectionRing.ringWidth)
                        }
                        .buttonStyle(.plain)
                        .help("\(pair.textInk.name) text, \(pair.tileInk.name) tile")
                        .accessibilityLabel("\(pair.textInk.name) text with \(pair.tileInk.name) tile")
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func inkRow(
        _ title: String,
        options: [(name: String, hex: String)],
        selectedHex: String?,
        issueKey: String?,
        clearTitle: String? = nil,
        apply: @escaping (String?, inout IndicatorTheme) -> Void
    ) -> some View {
        CompactSettingRow(title) {
            VStack(alignment: .leading, spacing: 4) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.swatchCell), spacing: 2)], alignment: .leading, spacing: 2) {
                    ForEach(options, id: \.hex) { option in
                        IndicatorSwatchButton(
                            color: Color(bubbleHex: option.hex),
                            name: option.name,
                            isSelected: selectedHex == option.hex
                        ) { edit { apply(option.hex, &$0) } }
                    }
                }
                HStack(spacing: 8) {
                    ColorPicker(
                        "Custom \(title.lowercased())",
                        selection: Binding(
                            get: { Color(bubbleHex: selectedHex ?? theme.textInkHex ?? IndicatorTheme.defaultPaperTextInkHex) },
                            set: { color in
                                guard let hex = color.cmdIMEHexString, hex != selectedHex else { return }
                                edit { apply(hex, &$0) }
                            }
                        ),
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 34, height: 22)
                    if let clearTitle {
                        Button(clearTitle) { edit { apply(nil, &$0) } }
                            .buttonStyle(ConsoleButtonStyle())
                            .disabled(selectedHex == nil)
                    }
                }
                if let issue = issues.first(where: { $0.key == issueKey }) {
                    IndicatorNotice(text: String(
                        format: "%@ contrast %.1f:1, below %.1f:1", title, issue.ratio, issue.minimum
                    ))
                }
            }
        }
    }

    // MARK: - Helpers

    private func slider(
        _ title: String,
        value: Double,
        range: ClosedRange<Double>,
        step: Double,
        display: String,
        apply: @escaping (Double, inout IndicatorTheme) -> Void
    ) -> some View {
        CompactSettingRow(title) {
            Slider(
                value: Binding(
                    get: { value },
                    set: { next in
                        guard next != value else { return }
                        edit { apply(next, &$0) }
                    }
                ),
                in: range,
                step: step,
                onEditingChanged: { isAdjusting = $0 }
            )
            .accessibilityLabel("Theme \(title.lowercased())")
            .accessibilityValue(display)
            Text(display)
                .font(DesignTokens.Typography.auxiliary.monospacedDigit())
                .foregroundStyle(DesignTokens.Colors.textMuted)
                .frame(width: 38, alignment: .trailing)
        }
    }

    private func percent(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }

    private func edit(_ change: (inout IndicatorTheme) -> Void) {
        model.editIndicatorTheme(change)
    }

    /// Paper needs a sheet and a printing ink; glass reads best in the neutral label colour.
    private static func setSurface(_ surface: IndicatorSurface, on theme: inout IndicatorTheme) {
        theme.surface = surface
        if surface == .paper {
            theme.substrateHex = theme.substrateHex ?? IndicatorTheme.defaultSubstrateHex
            theme.textInkHex = theme.textInkHex ?? IndicatorTheme.defaultPaperTextInkHex
            theme.highlightStrength = 0
        } else {
            theme.substrateHex = nil
            theme.textInkHex = nil
            // The system material brings its own wash and highlight.
            theme.highlightStrength = surface == .liquidGlass ? 0 : IndicatorTheme.Limits.highlightStrength.fallback
            if surface == .liquidGlass { theme.washOpacity = 0 }
        }
    }
}
