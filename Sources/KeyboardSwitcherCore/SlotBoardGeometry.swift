/// Frozen slot-board geometry. Coordinates are in the board's named space.
public enum SlotBoardGeometry {
    /// Closest gap centre; exact ties prefer the lower insertion index.
    public static func insertionIndex(probeY: Double, top: Double, restingHeights: [Double],
                                      spacing: Double, placeholderHeight: Double) -> Int {
        var centre = top + placeholderHeight / 2
        var closest = 0
        var distance = abs(probeY - centre)
        for (index, height) in restingHeights.enumerated() {
            centre += height + spacing
            let candidate = abs(probeY - centre)
            if candidate < distance {
                closest = index + 1
                distance = candidate
            }
        }
        return closest
    }

    public static func placeholderMinY(at index: Int, top: Double, restingHeights: [Double], spacing: Double) -> Double {
        restingHeights.prefix(min(max(index, 0), restingHeights.count))
            .reduce(top) { $0 + $1 + spacing }
    }

    /// Converts a final reorder destination to a gap in the unchanged model order.
    public static func insertionLineGap(finalIndex: Int, sourceIndex: Int) -> Int? {
        guard finalIndex != sourceIndex else { return nil }
        return finalIndex > sourceIndex ? finalIndex + 1 : finalIndex
    }
}
