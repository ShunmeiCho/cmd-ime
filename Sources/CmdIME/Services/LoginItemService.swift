import Foundation
import ServiceManagement

struct LoginItemSnapshot: Equatable {
    var isAvailable: Bool
    var isEnabled: Bool
    var statusText: String
}

struct LoginItemService {
    func snapshot() -> LoginItemSnapshot {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled:
                return LoginItemSnapshot(isAvailable: true, isEnabled: true, statusText: String(localized: "Enabled"))
            case .requiresApproval:
                return LoginItemSnapshot(isAvailable: true, isEnabled: false, statusText: String(localized: "Needs approval"))
            case .notRegistered:
                return LoginItemSnapshot(isAvailable: true, isEnabled: false, statusText: String(localized: "Off"))
            case .notFound:
                return LoginItemSnapshot(isAvailable: true, isEnabled: false, statusText: String(localized: "Not found"))
            @unknown default:
                return LoginItemSnapshot(isAvailable: true, isEnabled: false, statusText: String(localized: "Unknown"))
            }
        }

        return LoginItemSnapshot(isAvailable: false, isEnabled: false, statusText: String(localized: "Requires macOS 13"))
    }

    func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            return
        }

        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

