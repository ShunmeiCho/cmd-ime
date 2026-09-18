/// Resolves a frozen drop gap against the latest slot identities, not stale geometry.
public enum SlotDropDestination {
    /// Returns an insertion index in `currentOrder` with the dragged slot removed.
    /// A nil `draggedID` denotes a source addition. Neighbors must describe an
    /// adjacent gap (including boundaries) in the original remaining order.
    /// Missing anchors are tolerated only when another anchor survives; ordered
    /// surviving anchors prefer insertion before the next neighbor.
    public static func finalIndex(
        originalOrder: [InputRole],
        draggedID: InputRole?,
        previousNeighbor: InputRole?,
        nextNeighbor: InputRole?,
        currentOrder: [InputRole]
    ) -> Int? {
        if let draggedID {
            guard originalOrder.contains(draggedID), currentOrder.contains(draggedID) else {
                return nil
            }
        }

        let original = originalOrder.filter { $0 != draggedID }
        let current = currentOrder.filter { $0 != draggedID }

        // Validate the captured gap before attempting to recover surviving anchors.
        let originalIndex: Int
        if let nextNeighbor {
            guard let index = original.firstIndex(of: nextNeighbor) else { return nil }
            originalIndex = index
        } else {
            originalIndex = original.count
        }
        let expectedPrevious = originalIndex > 0 ? original[originalIndex - 1] : nil
        guard previousNeighbor == expectedPrevious else { return nil }

        if original == current { return originalIndex }

        let previousIndex = previousNeighbor.flatMap { current.firstIndex(of: $0) }
        let nextIndex = nextNeighbor.flatMap { current.firstIndex(of: $0) }
        switch (previousIndex, nextIndex) {
        case let (previous?, next?):
            return previous < next ? next : nil
        case let (previous?, nil):
            return previous + 1
        case let (nil, next?):
            return next
        case (nil, nil):
            // Even a newly empty board cannot identify a vanished nonempty gap.
            return nil
        }
    }
}
