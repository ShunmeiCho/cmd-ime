import AppKit
import Carbon
import KeyboardSwitcherCore
import SwiftUI

@main
@MainActor
enum CmdIMEMain {
    private static var appDelegate: AppDelegate?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        appDelegate = delegate
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppWindowCoordinator.shared.setModel(model)
        if !Self.wasLaunchedAsLoginItem() {
            AppWindowCoordinator.shared.showSettings()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshRuntimeStatus()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowCoordinator.shared.showSettings()
        return true
    }

    private static func wasLaunchedAsLoginItem() -> Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventClass == AEEventClass(kCoreEventClass),
              event.eventID == AEEventID(kAEOpenApplication) else {
            return false
        }

        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}

@MainActor
final class AppWindowCoordinator {
    static let shared = AppWindowCoordinator()

    private weak var model: AppModel?
    private var settingsWindow: NSWindow?

    private init() {}

    func setModel(_ model: AppModel) {
        self.model = model
    }

    func showSettings() {
        if let window = NSApp.windows.first(where: { $0.title == "CmdIME" }) {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        guard let model else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = settingsWindow ?? makeSettingsWindow(model: model)
        settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeSettingsWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdIME"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 720, minHeight: 640)
        )
        return window
    }
}
