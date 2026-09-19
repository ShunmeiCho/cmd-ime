import AppKit
import UserNotifications

/// The one system notification CmdIME sends: a new release exists. Permission is asked
/// for only when there is something to say, never at first launch.
enum UpdateNotification {
    static let identifier = "cmd-ime.update-available"

    static func post(version: String) {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert]) { granted, _ in
            // Denied: the settings window still shows the update the next time it opens.
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "CmdIME \(version) is available"
            content.body = "Click to open CmdIME and update."
            center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
        }
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
