import Foundation

/// Which layout an adaptive theme (`IndicatorTheme.isAdaptive`) draws. A single switch
/// shows the Mark, the one slot switched to; a switch that arrives while the bubble is
/// still up means the user is looking for a slot, so the bubble expands in place to the
/// Badge row with every slot; Peek asks where the user is and what else there is, so it
/// always shows the row. Every other theme keeps its own archetype.
public enum AdaptiveBubbleLayout {
    public enum Occasion: Equatable, Sendable {
        /// A switch, with whether a bubble was still on screen when it arrived.
        case switched(whileVisible: Bool)
        case peek
    }

    public static func archetype(for theme: IndicatorTheme, occasion: Occasion) -> BubbleArchetype {
        guard theme.isAdaptive else { return theme.archetype }
        switch occasion {
        case .switched(whileVisible: false): return .mark
        case .switched(whileVisible: true), .peek: return .badge
        }
    }
}
