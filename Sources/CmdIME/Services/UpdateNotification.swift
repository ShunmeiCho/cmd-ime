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
    static let categoryIdentifier = "cmd-ime.update"
    static let updateNowAction = "cmd-ime.update-now"
    static let releaseNotesAction = "cmd-ime.release-notes"
    /// userInfo key: the release page travels with the notification, since CmdIME may have
    /// relaunched (and forgotten the check) by the time someone clicks it.
    static let releaseURLKey = "releaseURL"

    /// The buttons on the notification. Update Now only where an in-place update can work.
    static func registerActions() {
        var actions = [UNNotificationAction(identifier: releaseNotesAction,
                                            title: String(localized: "Release Notes"), options: [])]
        if SelfUpdater.canUpdateInPlace {
            actions.insert(UNNotificationAction(identifier: updateNowAction,
                                                title: String(localized: "Update Now"), options: [.foreground]), at: 0)
        }
        UNUserNotificationCenter.current().setNotificationCategories([
            UNNotificationCategory(identifier: categoryIdentifier, actions: actions, intentIdentifiers: [], options: []),
        ])
    }

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
    /// The body is the release's opening sentence when there is one.
    /// `isStillWanted` is asked after the permission prompt, which can sit for a while: the user may
    /// have turned update notifications off meanwhile.
    static func post(version: String, headline: String?, releaseURL: URL,
                     isStillWanted: @MainActor () -> Bool) async -> Bool {
        let center = UNUserNotificationCenter.current()
        // Denied: the caller shows the update card instead, if it is still wanted.
        guard (try? await center.requestAuthorization(options: [.alert])) == true,
              await isStillWanted() else { return false }
        let content = UNMutableNotificationContent()
        content.title = String(localized: "CmdIME \(version) is available")
        content.body = headline ?? String(localized: "Click to open CmdIME and update.")
        content.categoryIdentifier = categoryIdentifier
        content.userInfo = [releaseURLKey: releaseURL.absoluteString]
        return (try? await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))) != nil
    }
}

/// Hands the clicked button (or the default action, a click on the notification) to the app.
final class UpdateNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    let onResponse: @MainActor (_ action: String, _ releaseURL: URL?) -> Void

    init(onResponse: @escaping @MainActor (_ action: String, _ releaseURL: URL?) -> Void) {
        self.onResponse = onResponse
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let url = (response.notification.request.content.userInfo[UpdateNotification.releaseURLKey] as? String)
            .flatMap(URL.init(string:))
        await onResponse(response.actionIdentifier, url)
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner]
    }
}
