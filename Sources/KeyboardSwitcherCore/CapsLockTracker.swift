import Foundation

/// Turns the Caps Lock bit of successive Caps Lock key events into real toggles.
///
/// A Caps Lock key event does not always toggle: with "Use Caps Lock to switch to and from ABC"
/// on, or a press shorter than macOS's Caps Lock delay, the key arrives and the lock stays as it
/// was. Only a change of the bit is reported, and the first reading after an unknown state only
/// seeds it, so nothing is announced that the user did not just do.
public struct CapsLockTracker: Equatable, Sendable {
    public private(set) var isOn: Bool?

    public init(isOn: Bool? = nil) {
        self.isOn = isOn
    }

    /// Returns the new state when it differs from the last known one, else nil.
    public mutating func observe(isOn newValue: Bool) -> Bool? {
        defer { isOn = newValue }
        guard let isOn, isOn != newValue else { return nil }
        return newValue
    }
}
