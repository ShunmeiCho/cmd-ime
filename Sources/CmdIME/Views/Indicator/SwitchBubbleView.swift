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
    /// Set for an adaptive bubble for its whole life, nil for every other bubble. The
    /// pill is then drawn at `fixedSize` from its leading edge and clips what it holds,
    /// so the row can grow out of the Mark inside a panel that never changes size.
    var expansion: BubbleExpansion?
}

/// The adaptive bubble's growth, one frame of it. At rest (and for the Mark) every
/// value is its default.
struct BubbleExpansion: Equatable {
    /// How far the Badge row is shifted toward where the Mark drew its glyph.
    var rowOffset: CGFloat = 0
    /// How far each slot's glyph has arrived, by slot index; a missing slot is fully there.
    var reveal: [Int: Double] = [:]
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
    /// False only for the live panel, where the shadow is drawn by a second hosting
    /// view that stays outside the system material. It is the one part of the bubble
    /// that paints beyond the bubble rect, so it is backdrop rather than content.
    var drawsOutsideShadow = true
    var presentation = BubblePresentation()

    var body: some View {
        if let expansion = presentation.expansion {
            adaptiveBody(expansion)
        } else {
            standardBody
        }
    }

    private var standardBody: some View {
        let metrics = model.metrics
        let shape = BubbleChrome.shape(metrics.bubbleRadius)

        return content(reveal: [:])
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
            .background { if drawsOutsideShadow { BubbleOutsideShadow(model: model) } }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.title), \(model.detail)")
    }

    /// The pill at its current size, content pinned to its leading edge and clipped by
    /// it: while it grows, the row is wider than the pill and slides out from under it.
    private func adaptiveBody(_ expansion: BubbleExpansion) -> some View {
        let shape = BubbleChrome.shape(model.metrics.bubbleRadius)

        return content(reveal: expansion.reveal)
            .fixedSize()
            .scaleEffect(presentation.contentScale, anchor: presentation.anchor)
            // The same floor the measurement saw, so the Mark stays centred in its pill.
            .frame(minWidth: model.metrics.baseHeight.points)
            .offset(x: expansion.rowOffset)
            .frame(width: presentation.fixedSize?.width, height: presentation.fixedSize?.height, alignment: .leading)
            .clipShape(shape)
            .background {
                BubbleSubstrateFill(substrate: model.substrate, isLive: mode == .live).clipShape(shape)
            }
            .overlay {
                if model.substrate != .none { BubbleEdges(model: model) }
            }
            .background { if drawsOutsideShadow { BubbleOutsideShadow(model: model) } }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(model.title), \(model.detail)")
    }

    @ViewBuilder
    private func content(reveal: [Int: Double]) -> some View {
        switch model.archetype {
        case .tileTwoLine:
            TileTwoLineBubble(model: model).environment(\.layoutDirection, direction)
        case .lineWithBar:
            LineWithBarBubble(model: model).environment(\.layoutDirection, direction)
        case .stackedText:
            StackedTextBubble(model: model).environment(\.layoutDirection, direction)
        case .tileOnly:
            BubbleTile(model: model)
        case .mark:
            MarkView(model: model)
        case .badge:
            BadgeStripView(
                model: model,
                thumbIndex: presentation.thumbIndex ?? model.activeIndex,
                stripTravel: presentation.stripTravel,
                reduceMotion: presentation.reduceMotion,
                reveal: reveal
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
