#if os(macOS)
import Carbon
import Foundation

/// Signals that enabled input sources should be rescanned; never scans or selects them.
/// Retain the observer while listening. Initialization, stop, and delivery use the main actor.
@MainActor
public final class InputSourceChangeObserver: NSObject {
    /// Deliver once after a burst has been quiet for this interval.
    public static let coalescingInterval: TimeInterval = 0.2

    private let onChange: @MainActor () -> Void
    private var pendingDelivery: Task<Void, Never>?
    private var stopped = false

    public init(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enabledSourcesChanged(_:)),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
    }

    /// Stops permanently and cancels pending delivery. Repeated calls are safe.
    public func stop() {
        guard !stopped else { return }
        stopped = true
        DistributedNotificationCenter.default().removeObserver(self)
        pendingDelivery?.cancel()
        pendingDelivery = nil
    }

    @objc private func enabledSourcesChanged(_ notification: Notification) {
        guard !stopped else { return }
        pendingDelivery?.cancel()
        pendingDelivery = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.coalescingInterval * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, !self.stopped else { return }
            self.pendingDelivery = nil
            self.onChange()
        }
    }

    deinit {
        pendingDelivery?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }
}
#endif
