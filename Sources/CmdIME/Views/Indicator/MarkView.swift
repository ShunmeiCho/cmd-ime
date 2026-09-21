import KeyboardSwitcherCore
import SwiftUI

/// The caret mark: one symbol, one surface, nothing else.
///
/// There is no second enclosure inside the capsule and no inactive slot beside the
/// active one. A mark reports where you have arrived; the alternatives and their
/// order belong to the Switcher, which is a place for choosing.
///
/// A theme that prints with its own inks draws the glyph straight onto the surface.
/// A theme carrying the Color setting fills the capsule with the slot's colour and
/// knocks the glyph out of it, which is the relationship the system's own caret badge
/// has. The two shipped themes are exactly those two readings.
struct MarkView: View {
    let model: BubbleRenderModel

    var body: some View {
        let metrics = MarkMetrics(model: model)
        symbol(metrics)
            .foregroundStyle(Color(bubbleHex: isTinted ? model.glyphHex : model.titleHex))
            .frame(width: metrics.bubbleWidth.points, height: metrics.bubbleHeight.points)
            .background {
                if isTinted, let fill = model.tileFillHex {
                    BubbleChrome.shape(metrics.bubbleHeight / 2).fill(Color(bubbleHex: fill))
                }
            }
            // The symbol is a spatial map of nothing: it is never mirrored.
            .environment(\.layoutDirection, .leftToRight)
    }

    /// The glyph, and beside it the mark that tells two slots sharing a glyph apart,
    /// set on the same baseline so it reads as part of the identity rather than as a
    /// footnote attached to it.
    private func symbol(_ metrics: MarkMetrics) -> some View {
        let glyph = metrics.glyphSize.points
        let mark = metrics.markSize.points
        return HStack(spacing: (MarkMetrics.Base.markGap * metrics.factor).points) {
            Text(model.symbol.glyph)
                .font(BubbleFontResolver.display(model.typography, size: glyph))
            if let value = model.symbol.mark {
                Text(value)
                    .font(BubbleFontResolver.utility(model.typography, size: mark))
            }
        }
        .lineLimit(1)
        .fixedSize()
        .accessibilityHidden(true)
    }

    /// The surface carries a colour of its own only when the theme takes one from the
    /// Color setting. With the theme's own inks the fill resolves to the neutral of
    /// the appearance, which is the text colour, and painting the capsule in it would
    /// leave a white lozenge over the glass.
    private var isTinted: Bool {
        guard let fill = model.tileFillHex else { return false }
        return fill != model.detailHex
    }
}
