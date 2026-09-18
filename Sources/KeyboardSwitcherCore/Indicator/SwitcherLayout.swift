import Foundation

public enum SwitcherVariant: String, Sendable {
    /// Every slot is visible and the thumb travels between cells.
    case row
    /// Three cells are visible, the thumb stays centred and the strip travels.
    case carousel
}

/// Positions are fractions of the strip width, leading to trailing. The view
/// mirrors them when the app's layout direction is right-to-left.
public struct SwitcherArrangement: Equatable, Sendable {
    public struct Item: Equatable, Sendable {
        public let slotIndex: Int
        public let x: Double
        public let y: Double
        public let isActive: Bool
    }

    public let variant: SwitcherVariant
    public let columns: Int
    public let items: [Item]
    /// Nil when there is no previous slot: the thumb fades in on the target.
    public let thumbStartX: Double?
    public let thumbEndX: Double
    /// Carousel only: signed cells the strip slides, the short way round.
    public let stripTravelCells: Int
    /// Carousel only: the jump is longer than the strip can show, so contents crossfade.
    public let crossfadesContent: Bool
}

public enum SwitcherLayout {
    static let maxRowSlotsAtAnyWidth = 3
    static let carouselColumns = 3
    static let carouselReach = 2
    static let centerX = 0.5

    public static func arrangement(
        slotCount: Int,
        activeIndex: Int,
        previousIndex: Int?,
        maxWidth: Double,
        cellWidth: Double,
        spacing: Double,
        padding: Double
    ) -> SwitcherArrangement {
        guard slotCount > 0 else {
            return SwitcherArrangement(variant: .row, columns: 0, items: [], thumbStartX: nil,
                                       thumbEndX: centerX, stripTravelCells: 0, crossfadesContent: false)
        }
        let active = min(max(activeIndex, 0), slotCount - 1)
        let previous = previousIndex.flatMap { (0..<slotCount).contains($0) ? $0 : nil }
        let rowWidth = 2 * padding + Double(slotCount) * cellWidth + Double(slotCount - 1) * spacing

        if slotCount <= maxRowSlotsAtAnyWidth || rowWidth <= maxWidth {
            func x(_ index: Int) -> Double { (Double(index) + 0.5) / Double(slotCount) }
            return SwitcherArrangement(
                variant: .row,
                columns: slotCount,
                items: (0..<slotCount).map { Item(slotIndex: $0, x: x($0), isActive: $0 == active) },
                thumbStartX: previous.map(x),
                thumbEndX: x(active),
                stripTravelCells: 0,
                crossfadesContent: false
            )
        }

        let distance = previous.map { shortestCyclicDistance(from: $0, to: active, count: slotCount) } ?? 0
        return SwitcherArrangement(
            variant: .carousel,
            columns: carouselColumns,
            // The outermost neighbours sit outside the window so the strip has content while it travels.
            items: (-carouselReach...carouselReach).map { offset in
                Item(
                    slotIndex: ((active + offset) % slotCount + slotCount) % slotCount,
                    x: (Double(offset) + 1.5) / Double(carouselColumns),
                    isActive: offset == 0
                )
            },
            thumbStartX: previous == nil ? nil : centerX,
            thumbEndX: centerX,
            stripTravelCells: min(max(distance, -carouselReach), carouselReach),
            crossfadesContent: abs(distance) > carouselReach
        )
    }

    /// Signed steps from one slot to another around the ring; a tie goes forward.
    static func shortestCyclicDistance(from: Int, to: Int, count: Int) -> Int {
        let forward = ((to - from) % count + count) % count
        return forward <= count - forward ? forward : forward - count
    }

    private typealias Item = SwitcherArrangement.Item
}

private extension SwitcherArrangement.Item {
    /// The strip is a single line, so every item sits on its vertical centre.
    init(slotIndex: Int, x: Double, isActive: Bool) {
        self.init(slotIndex: slotIndex, x: x, y: SwitcherLayout.centerX, isActive: isActive)
    }
}
