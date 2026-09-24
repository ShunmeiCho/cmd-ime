import AppKit
import UserNotifications

/// The one system notification CmdIME sends: a new release exists. Permission is asked
/// for only when there is something to say, never at first launch.
/// What macOS currently lets CmdIME do with notifications.
enum NotificationPermission: Equatable {
    case unknown
    /// Never asked: macOS will ask the first time there is an update, or when the user asks here.
    case notAsked
    case allowed
    case blocked
}

enum UpdateNotification {
    static let identifier = "cmd-ime.update-available"

    static func permission() async -> NotificationPermission {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .notDetermined: .notAsked
        case .denied: .blocked
        case .authorized, .provisional, .ephemeral: .allowed
        @unknown default: .unknown
        }
    }

    /// Shows the system prompt if macOS has not asked yet; otherwise returns the standing answer.
    static func requestPermission() async -> NotificationPermission {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert])
        return await permission()
    }

    /// macOS offers no way to change a standing answer from inside an app.
    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else { return }
        NSWorkspace.shared.open(url)
    }

    /// Returns whether the notification was handed to the system, so a version is only marked
    /// as announced once it actually was.
    static func post(version: String) async -> Bool {
        let center = UNUserNotificationCenter.current()
        // Denied: the settings window still shows the update the next time it opens.
        guard (try? await center.requestAuthorization(options: [.alert])) == true else { return false }
        let content = UNMutableNotificationContent()
        content.title = "CmdIME \(version) is available"
        content.body = "Click to open CmdIME and update."
        return (try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))) != nil
    }
}

/// Clicking the notification opens the settings window, where the update button is.
final class UpdateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let onOpen: @MainActor () -> Void

    init(onOpen: @escaping @MainActor () -> Void) {
        self.onOpen = onOpen
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        await onOpen()
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
