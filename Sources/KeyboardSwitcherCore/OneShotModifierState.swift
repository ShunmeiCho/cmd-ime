import Foundation

public struct OneShotModifierState: Equatable, Sendable {
    public enum Output: Equatable, Sendable {
        case wait
        case trigger(KeyTrigger)
    }

    private var activeTrigger: KeyTrigger?
    private var sawChordKey = false
    private var pendingSingleTap: KeyTrigger?

    public init() {}

    public mutating func modifierDown(_ trigger: KeyTrigger) {
        if let activeTrigger, activeTrigger != trigger {
            sawChordKey = true
            return
        }
        activeTrigger = trigger
        sawChordKey = false
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
        hasDoubleTapBinding: Bool = false
    ) -> Output {
        defer {
            activeTrigger = nil
            sawChordKey = false
        }

        guard activeTrigger == trigger, !sawChordKey else {
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
