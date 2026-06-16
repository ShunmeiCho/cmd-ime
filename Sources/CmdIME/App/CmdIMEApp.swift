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
        }

        MenuBarExtra("CmdIME", systemImage: "keyboard", isInserted: $model.config.showMenuBarIcon) {
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
}
