import KeyboardSwitcherCore
import SwiftUI

/// What the persistent hosting view of the panel (and the settings preview)
/// observes. A re-trigger mutates this object; the view tree is never rebuilt, so
/// the thumb spring retargets from wherever it is.
@MainActor
final class BubbleState: ObservableObject {
    @Published private(set) var model: BubbleRenderModel?
    @Published private(set) var presentation = BubblePresentation()
    private var generation = 0

    /// `fresh` is an appearance from hidden: the content settles and the thumb starts
    /// on the previous slot. Otherwise the bubble is visible and only its content swaps.
    func present(
        _ next: BubbleRenderModel,
        fresh: Bool,
        anchor: UnitPoint,
        fixedSize: CGSize?,
        reduceMotion: Bool
    ) {
        generation += 1
        let current = generation
        // Only a strip has a thumb to travel; every other archetype draws the slot
        // switched to and nothing else.
        let travels = next.archetype.showsAllSlots && !reduceMotion
        // Exhaustive, with no default: an archetype that shows every slot has to say
        // how far its strip travels rather than silently not moving.
        func stripTravelCells() -> Int {
            switch next.archetype {
            case .switcher: SwitcherStripMetrics(model: next).arrangement.stripTravelCells
            case .badge: BadgeMetrics(model: next).arrangement.stripTravelCells
            case .tileTwoLine, .lineWithBar, .stackedText, .tileOnly, .mark: 0
            }
        }
        let travel = travels ? Double(stripTravelCells()) : 0
        let startIndex = !travels ? next.activeIndex
            : fresh ? (next.previousIndex ?? next.activeIndex)
            : (presentation.thumbIndex ?? next.activeIndex)

        let start = BubblePresentation(
            thumbIndex: startIndex,
            stripTravel: travel,
            contentScale: fresh && !reduceMotion ? BubbleMotion.contentSettleScale : 1,
            anchor: anchor,
            fixedSize: fixedSize,
            reduceMotion: reduceMotion
        )
        var immediate = Transaction()
        immediate.disablesAnimations = true

        if fresh {
            withTransaction(immediate) {
                model = next
                presentation = start
            }
        } else if reduceMotion {
            // The thumb and the emphasis crossfade in place.
            withAnimation(BubbleMotion.contentSwap) {
                model = next
                presentation = start
            }
        } else {
            withAnimation(BubbleMotion.contentSwap) { model = next }
            // Starting positions are not animated toward: the springs below own that.
            withTransaction(immediate) { presentation = start }
        }
        guard !reduceMotion else { return }

        // The starting values must reach the screen once before they can animate.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == current else { return }
            withAnimation(BubbleMotion.contentSettle) { self.presentation.contentScale = 1 }
            // Only a strip has a thumb to travel; the other archetypes draw the slot
            // switched to and nothing else, so there is nothing to animate toward.
            guard next.archetype.showsAllSlots else { return }
            withAnimation(next.archetype == .badge ? BubbleMotion.badgeThumbSpring : BubbleMotion.thumbSpring) {
                self.presentation.thumbIndex = next.activeIndex
                self.presentation.stripTravel = 0
            }
        }
    }

    /// After the bubble is gone, so the next appearance does not flash old content.
    func clear() {
        generation += 1
        model = nil
    }
}

/// The bubble itself. On the liquid path this view is the system material's
/// `contentView`, so it is laid out to the bubble rect; everywhere else it fills the
/// panel and centres itself. One view, two regimes, no branch here: the bubble is
/// fixed-size inside a frame that fills whatever it is given.
struct LiveBubbleRoot: View {
    @ObservedObject var state: BubbleState

    var body: some View {
        ZStack {
            if let model = state.model {
                SwitchBubbleView(model: model, mode: .live, drawsOutsideShadow: false,
                                 presentation: state.presentation)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// The bubble's shadow, and nothing else. It lives in a second hosting view that fills
/// the panel, because it paints into the margin outside the bubble rect and so cannot
/// go inside the material.
struct LiveBubbleShadow: View {
    @ObservedObject var state: BubbleState

    var body: some View {
        ZStack {
            if let model = state.model, let size = state.presentation.fixedSize {
                Color.clear
                    .frame(width: size.width, height: size.height)
                    .background { BubbleOutsideShadow(model: model) }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
