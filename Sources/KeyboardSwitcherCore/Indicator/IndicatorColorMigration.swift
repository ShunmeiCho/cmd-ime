import Foundation

extension SwitcherConfig {
    /// Retires the per-slot custom indicator colours: a slot's colour now lives only
    /// in `tintHex`. Runs in memory and reaches disk with the next save. No key is
    /// removed, so no backup is needed and older binaries keep reading the file.
    ///
    /// Slots without a per-slot entry keep their tint; copying the single fallback
    /// colour into every slot would make all slot cards look the same.
    func retiringCustomIndicatorColors() -> SwitcherConfig {
        guard switchIndicatorColorStyle == .custom else { return self }
        var result = self
        result.slots = slots.map { slot in
            guard let stored = switchIndicatorCustomRoleColorHexes[slot.id.rawValue],
                  let normalized = IndicatorRGB.normalizedHex(stored) else { return slot }
            var updated = slot
            updated.tintHex = normalized
            return updated
        }
        result.switchIndicatorColorStyle = .role
        result.switchIndicatorCustomRoleColorHexes = [:]
        return result
    }
}
