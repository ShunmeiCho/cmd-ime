#if os(macOS)
import ApplicationServices
import CoreGraphics
import Foundation

public struct PermissionSnapshot: Equatable, Sendable {
    public var inputMonitoringGranted: Bool
    public var accessibilityGranted: Bool

    public init(inputMonitoringGranted: Bool, accessibilityGranted: Bool) {
        self.inputMonitoringGranted = inputMonitoringGranted
        self.accessibilityGranted = accessibilityGranted
    }

    public var isReady: Bool {
        inputMonitoringGranted && accessibilityGranted
    }
}

public enum MacPermissionStatus {
    public static func current() -> PermissionSnapshot {
        PermissionSnapshot(
            inputMonitoringGranted: CGPreflightListenEventAccess(),
            accessibilityGranted: AXIsProcessTrusted()
        )
    }

    public static func request() {
        if !CGPreflightListenEventAccess() {
            CGRequestListenEventAccess()
        }

        let promptKey = "AXTrustedCheckOptionPrompt"
        let options = [promptKey: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
}
#endif

