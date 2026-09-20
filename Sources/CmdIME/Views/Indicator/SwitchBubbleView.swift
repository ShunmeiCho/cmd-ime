import KeyboardSwitcherCore
import SwiftUI

/// The transient part of drawing a bubble: where the thumb is, how far the content
/// has settled. At rest every value is its default.
struct BubblePresentation: Equatable {
    /// Nil puts the thumb on the active slot.
    var thumbIndex: Int?
    var stripTravel = 0.0
    var contentScale: CGFloat = 1
    /// The corner nearest the caret; the content settles from it.
    var anchor: UnitPoint = .bottomLeading
    /// The live panel pins the bubble to its measured whole-point size so the
    /// glass mask behind it and the edges drawn here coincide.
    var fixedSize: CGSize?
    var reduceMotion = false
}

/// The single drawing of the switch indicator. The live panel, the settings
/// preview and the theme miniatures all render a `BubbleRenderModel` through this
/// view; nothing else draws a bubble.
struct SwitchBubbleView: View {
    enum Mode {
        /// Inside the indicator panel: the glass is a visual effect view underneath.
        case live
        /// Inside a window: the glass is approximated by a translucent fill.
        case preview
    }

    let model: BubbleRenderModel
    var mode: Mode = .preview
    var presentation = BubblePresentation()

    var body: some View {
        let metrics = model.metrics
        let shape = BubbleChrome.shape(metrics.bubbleRadius)

        content
            .scaleEffect(presentation.contentScale, anchor: presentation.anchor)
            .frame(minWidth: model.archetype == .tileOnly ? nil : metrics.baseHeight.points)
            .frame(maxWidth: metrics.maxBubbleWidth.points)
            .frame(width: presentation.fixedSize?.width, height: presentation.fixedSize?.height)
            .background {
                BubbleSubstrateFill(substrate: model.substrate, isLive: mode == .live).clipShape(shape)
            }
            .overlay {
                if model.substrate != .none { BubbleEdges(model: model) }
            }
            .background { BubbleOutsideShadow(model: model) }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.title), \(model.detail)")
    }

    @ViewBuilder
    private var content: some View {
        switch model.archetype {
        case .tileTwoLine:
            TileTwoLineBubble(model: model).environment(\.layoutDirection, direction)
        case .lineWithBar:
            LineWithBarBubble(model: model).environment(\.layoutDirection, direction)
        case .stackedText:
            StackedTextBubble(model: model).environment(\.layoutDirection, direction)
        case .tileOnly:
            BubbleTile(model: model)
        case .badge:
            BadgeStripView(
                model: model,
                thumbIndex: presentation.thumbIndex ?? model.activeIndex,
                stripTravel: presentation.stripTravel,
                reduceMotion: presentation.reduceMotion
            )
        case .switcher:
            SwitcherStripView(
                model: model,
                thumbIndex: presentation.thumbIndex ?? model.activeIndex,
                stripTravel: presentation.stripTravel,
                reduceMotion: presentation.reduceMotion
            )
        }
    }

    /// Direction follows the language being switched to, not the language of the app.
    private var direction: LayoutDirection {
        model.isRightToLeft ? .rightToLeft : .leftToRight
    }
}
