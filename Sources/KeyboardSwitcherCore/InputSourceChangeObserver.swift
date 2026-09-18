#if os(macOS)
import Carbon
import Foundation

/// Signals an input-source change; never scans or selects sources itself.
/// Retain the observer while listening. Initialization, stop, and delivery use the main actor.
@MainActor
public final class InputSourceChangeObserver: NSObject {
    public enum Change: Sendable {
        case enabledSourcesChanged
        case selectedSourceChanged
    }

    /// Enabled-list changes wait for a quiet interval, preserving the original behavior.
    public static let coalescingInterval: TimeInterval = 0.2
    /// Selected-source changes are delivered immediately, without debounce.
    public static let selectedSourceCoalescingInterval: TimeInterval = 0

    private let onChange: @MainActor () -> Void
    private let deliveryInterval: TimeInterval
    private var pendingDelivery: Task<Void, Never>?
    private var stopped = false

    public init(change: Change = .enabledSourcesChanged, onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        let notificationName: String
        switch change {
        case .enabledSourcesChanged:
            notificationName = kTISNotifyEnabledKeyboardInputSourcesChanged as String
            deliveryInterval = Self.coalescingInterval
        case .selectedSourceChanged:
            notificationName = kTISNotifySelectedKeyboardInputSourceChanged as String
            deliveryInterval = Self.selectedSourceCoalescingInterval
        }
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(inputSourceChanged(_:)),
            name: Notification.Name(notificationName),
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

    @objc private func inputSourceChanged(_ notification: Notification) {
        guard !stopped else { return }
        if deliveryInterval == 0 {
            onChange()
            return
        }
        pendingDelivery?.cancel()
        let interval = deliveryInterval
        pendingDelivery = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
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
