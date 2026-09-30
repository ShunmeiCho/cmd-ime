import Foundation

public struct OneShotModifierState: Equatable, Sendable {
    /// The window a single tap waits for a second tap.
    public static let doubleTapWindow: TimeInterval = 0.22
    /// The window on a key whose only binding is a double tap. No single tap is held back
    /// there, so a slower second tap costs nothing.
    public static let doubleTapOnlyWindow: TimeInterval = 0.35
    /// A modifier held longer than this is held for something else (Command-hover in an IDE,
    /// Option to reveal a menu item), not tapped.
    public static let maximumTapHold: TimeInterval = 0.8

    /// How long to wait for a second tap after a first one on this key.
    public static func secondTapWindow(hasSingleTapBinding: Bool) -> TimeInterval {
        hasSingleTapBinding ? doubleTapWindow : doubleTapOnlyWindow
    }

    public enum Output: Equatable, Sendable {
        case wait
        case trigger(KeyTrigger)
    }

    private var activeTrigger: KeyTrigger?
    private var sawChordKey = false
    private var pendingSingleTap: KeyTrigger?
    private var pressedAt: TimeInterval = 0

    public init() {}

    /// `time` is any monotonic clock in seconds; only its difference to `modifierUp` counts.
    public mutating func modifierDown(_ trigger: KeyTrigger, at time: TimeInterval = 0) {
        if let activeTrigger, activeTrigger != trigger {
            sawChordKey = true
            return
        }
        activeTrigger = trigger
        sawChordKey = false
        pressedAt = time
    }

    public mutating func keyDown(_ keyCode: Int) {
        guard activeTrigger != nil else {
            return
        }
        if activeTrigger?.keyCode != keyCode {
            sawChordKey = true
        }
    }

    public mutating func modifierUp(
        _ trigger: KeyTrigger,
        hasDoubleTapBinding: Bool = false,
        at time: TimeInterval = 0
    ) -> Output {
        defer {
            activeTrigger = nil
            sawChordKey = false
        }

        let isHeldTooLong = time - pressedAt > Self.maximumTapHold
        guard activeTrigger == trigger, !sawChordKey, !isHeldTooLong else {
            pendingSingleTap = nil
            return .wait
        }

        if hasDoubleTapBinding {
            if pendingSingleTap == trigger {
                pendingSingleTap = nil
                var doubleTap = trigger
                doubleTap.gesture = .doubleTap
                return .trigger(doubleTap)
            }
            pendingSingleTap = trigger
            return .wait
        }

        pendingSingleTap = nil
        return .trigger(trigger)
    }

    public mutating func cancel() {
        activeTrigger = nil
        sawChordKey = false
        pendingSingleTap = nil
    }

    public mutating func flushPendingSingleTap() -> KeyTrigger? {
        defer {
            pendingSingleTap = nil
        }
        return pendingSingleTap
    }
}
