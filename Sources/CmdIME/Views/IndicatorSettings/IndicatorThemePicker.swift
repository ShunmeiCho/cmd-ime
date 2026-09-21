import AppKit
import KeyboardSwitcherCore
import SwiftUI
import UniformTypeIdentifiers

/// Built-in themes, then user themes, each as a live miniature drawn by the real
/// bubble view for the user's own first slot, so it is truthful for any language set.
struct IndicatorThemePicker: View {
    private static let cellMinWidth: CGFloat = 116
    private static let stageHeight: CGFloat = 56
    private static let stagePadding: CGFloat = 6
    private static let stageRadius: CGFloat = 8
    private static let textSlack = 4.0
    private static let dotsAllowance: CGFloat = 8
    /// The stage behind each theme thumbnail: recessed in both appearances, never a black slab on a light window.
    private static var stageColor: Color { DesignTokens.Colors.surfaceInset }

    @ObservedObject var model: AppModel
    @ObservedObject var library: IndicatorLibrary

    /// Re-renders the thumbnails when the appearance around them changes.
    @Environment(\.colorScheme) private var colorScheme

    /// The indicator floats over other apps, so it follows macOS, not this window. Said only
    /// when the two differ, which is when dark thumbnails in a light window look like a bug.
    private var systemAppearanceNote: String? {
        let isSystemDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        guard (colorScheme == .dark) != isSystemDark else { return nil }
        return "The indicator appears over other apps, so it follows the macOS appearance (\(isSystemDark ? "Dark" : "Light") now), not this window's."
    }

    private var selected: IndicatorTheme { library.theme(id: model.config.switchIndicatorThemeID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Theme")
                    .font(DesignTokens.Typography.body.weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                Spacer()
                actionsMenu.frame(width: 44)
            }
            if let note = systemAppearanceNote {
                Text(note)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: Self.cellMinWidth), spacing: 10)], spacing: 12) {
                ForEach(library.themes) { theme in
                    cell(for: theme)
                }
            }

            if let missing = missingThemeID {
                IndicatorNotice(text: "Theme \(missing) was not found. Using \(selected.name).")
            }
            ForEach(library.listing.rejected, id: \.fileName) { rejection in
                IndicatorNotice(text: "\(rejection.fileName): \(rejection.issue.message)")
            }
        }
    }

    /// The stored id when it names no theme; the bubble falls back to the default built-in.
    private var missingThemeID: String? {
        guard let id = model.config.switchIndicatorThemeID, !library.themes.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    // MARK: - Cells

    private func cell(for theme: IndicatorTheme) -> some View {
        let isSelected = theme.id == selected.id
        return Button {
            model.setSwitchIndicatorThemeID(theme.id)
        } label: {
            VStack(spacing: 5) {
                GeometryReader { proxy in
                    miniature(for: theme, fitting: proxy.size)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .frame(height: Self.stageHeight)
                .background(RoundedRectangle(cornerRadius: Self.stageRadius, style: .continuous).fill(Self.stageColor))
                .clipShape(RoundedRectangle(cornerRadius: Self.stageRadius, style: .continuous))
                .selectionRing(isSelected, cornerRadius: Self.stageRadius)

                Text(theme.name)
                    .font(DesignTokens.Typography.auxiliary.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .padding(SelectionRing.ringGap + SelectionRing.ringWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .overlay(alignment: .topLeading) {
            // Your own themes carry a visible remove button; built-ins cannot be removed.
            if !theme.isBuiltIn {
                Button { remove(theme) } label: {
                    Image(systemName: "trash.circle.fill")
                        .font(.system(size: 16))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(DesignTokens.Colors.textPrimary, DesignTokens.Colors.surfaceRaised)
                }
                .buttonStyle(.plain)
                .help("Move \(theme.name) to the Trash")
                .accessibilityLabel("Remove theme \(theme.name)")
            }
        }
        .contextMenu {
            Button("Duplicate and Edit") {
                if let copy = library.duplicate(theme) { model.setSwitchIndicatorThemeID(copy.id) }
            }
            if !theme.isBuiltIn {
                Button("Move to Trash", role: .destructive) { remove(theme) }
            }
        }
    }

    /// The file goes to the Trash, so a mistaken removal can be put back from there.
    private func remove(_ theme: IndicatorTheme) {
        guard library.removeTheme(id: theme.id) else { return }
        if theme.id == selected.id { model.setSwitchIndicatorThemeID(nil) }
    }

    /// Wide bubbles (a switcher row, a long source name) are scaled down to fit the
    /// cell; nothing is cropped, so the miniature still shows the whole bubble.
    @ViewBuilder
    private func miniature(for theme: IndicatorTheme, fitting size: CGSize) -> some View {
        if let slot = model.config.slots.first,
           let bubble = IndicatorPreviewModel.make(model: model, slot: slot, miniatureOf: theme) {
            let natural = naturalSize(of: bubble)
            let available = CGSize(width: size.width - 2 * Self.stagePadding, height: size.height - 2 * Self.stagePadding)
            let scale = min(1, available.width / max(natural.width, 1), available.height / max(natural.height, 1))
            SwitchBubbleView(model: bubble, mode: .preview)
                .scaleEffect(scale)
                .frame(width: natural.width * scale, height: natural.height * scale)
                .accessibilityHidden(true)
        }
    }

    /// Estimated from the metrics and the text measured in the system font: close
    /// enough to choose a scale, and the stage clips whatever the estimate misses.
    private func naturalSize(of bubble: BubbleRenderModel) -> CGSize {
        let metrics = bubble.metrics
        let height = metrics.baseHeight.points
        func width(_ text: String, size: Double, weight: NSFont.Weight) -> Double {
            Double((text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight)]).width)
        }
        let title = width(bubble.title, size: metrics.titleSize, weight: .semibold)
        let detail = width(bubble.detail, size: metrics.detailSize, weight: .medium)
        func column(_ content: Double) -> Double {
            min(max(content + Self.textSlack, metrics.textMinWidth), metrics.textMaxWidth)
        }

        switch bubble.archetype {
        case .switcher:
            let strip = SwitcherStripMetrics(model: bubble)
            let dots = strip.arrangement.variant == .carousel ? Self.dotsAllowance : 0
            return CGSize(width: strip.windowWidth + 2 * strip.padding, height: strip.cellHeight + 2 * strip.padding + dots)
        case .mark:
            let mark = MarkMetrics(model: bubble)
            return CGSize(width: mark.bubbleWidth.points, height: mark.bubbleHeight.points)
        case .badge:
            let badge = BadgeMetrics(model: bubble)
            let dots = badge.arrangement.variant == .carousel ? Self.dotsAllowance : 0
            return CGSize(width: badge.bubbleWidth.points, height: (badge.bubbleHeight + dots).points)
        case .tileOnly:
            return CGSize(width: metrics.tileSide.points, height: metrics.tileSide.points)
        case .tileTwoLine where bubble.display == .iconOnly:
            return CGSize(width: height, height: height)
        case .tileTwoLine where bubble.display == .textOnly:
            return CGSize(width: (column(title) + 2 * metrics.trailingPadding).points, height: height)
        case .tileTwoLine:
            let fixed = metrics.inset + metrics.tileSide + metrics.gap + metrics.trailingPadding
            return CGSize(width: (fixed + column(max(title, detail))).points, height: height)
        case .lineWithBar:
            let fixed = metrics.inset + 2 * metrics.gap + metrics.titleSize * 2 + metrics.trailingPadding
            return CGSize(width: (fixed + column(title)).points, height: height)
        case .stackedText:
            return CGSize(width: (column(max(title, detail)) + 2 * metrics.trailingPadding).points, height: height)
        }
    }

    // MARK: - Actions

    private var actionsMenu: some View {
        ConsoleMenuButton(title: "", systemImage: "ellipsis", showsChevron: false) {
            Button("Duplicate and Edit") {
                if let copy = library.duplicate(selected) { model.setSwitchIndicatorThemeID(copy.id) }
            }
            Divider()
            Button("Import...", action: importTheme)
            Button("Export...", action: exportTheme)
            Button("Move to Trash", role: .destructive) { remove(selected) }
                .disabled(selected.isBuiltIn)
            Divider()
            Button("Show in Finder") { library.revealInFinder(library.themesDirectory) }
        }
        .accessibilityLabel("Theme actions")
    }

    private func importTheme() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a CmdIME indicator theme file."
        guard panel.runModal() == .OK, let url = panel.url, let theme = library.importTheme(from: url) else { return }
        model.setSwitchIndicatorThemeID(theme.id)
    }

    private func exportTheme() {
        let theme = selected
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(IndicatorThemeStore.sanitizedID(theme.name) ?? "theme").json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        library.exportTheme(theme, to: url)
    }
}
