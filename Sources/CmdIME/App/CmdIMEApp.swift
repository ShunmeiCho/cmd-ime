import AppKit
import SwiftUI

@main
struct CmdIMEApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("CmdIME", id: "main") {
            ContentView(model: model)
                .frame(minWidth: 720, minHeight: 520)
                .onAppear {
                    AppWindowCoordinator.shared.setModel(model)
                }
        }

        MenuBarExtra("CmdIME", isInserted: $model.config.showMenuBarIcon) {
            MenuBarContent(model: model)
        }

        Settings {
            ContentView(model: model)
                .frame(width: 720, height: 520)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowCoordinator.shared.showSettings()
        return true
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
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdIME"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 720, minHeight: 520)
        )
        return window
    }
}
