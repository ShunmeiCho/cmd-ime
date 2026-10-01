import AppKit
import Carbon
import KeyboardSwitcherCore
import SwiftUI
import UserNotifications

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
    private lazy var updateNotifications = UpdateNotificationDelegate { [model] action, releaseURL in
        switch action {
        case UpdateNotification.releaseNotesAction:
            if let releaseURL { NSWorkspace.shared.open(releaseURL) } else { model.openLatestRelease() }
        case UpdateNotification.updateNowAction:
            AppWindowCoordinator.shared.showSettings()
            model.updateFromNotification()
        default:
            AppWindowCoordinator.shared.showSettings()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.installMainMenu()
        AppWindowCoordinator.shared.setModel(model)
        // Creating the indicator library registers the imported fonts for this process.
        _ = model.indicatorLibrary
        if !Self.wasLaunchedAsLoginItem() {
            AppWindowCoordinator.shared.showSettings()
        }
        UNUserNotificationCenter.current().delegate = updateNotifications
        UpdateNotification.registerActions()
        #if DEBUG
        if UserDefaults.standard.bool(forKey: "CmdIMEPreviewUpdateCard") { model.previewUpdateCard() }
        #endif
        model.startUpdateReminder()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshRuntimeStatus()
        // The General page stays on screen, so a change made in System Settings has to
        // be picked up on the way back.
        model.refreshNotificationPermission()
    }

    /// Cancel, not .terminateLater: a quit can start inside a main-actor Task (the restart after
    /// Update Now), where .terminateLater's modal loop would hold the main queue the import needs.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        model.shouldDelayQuitForImport() ? .terminateCancel : .terminateNow
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.willTerminate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppWindowCoordinator.shared.showSettings()
        return true
    }

    /// Accessory apps still need a responder-chain menu for keyboard equivalents.
    static func installMainMenu() {
        let menu = NSMenu(title: "CmdIME")
        let edit = NSMenu(title: String(localized: "Edit"))
        let editItem = NSMenuItem(title: String(localized: "Edit"), action: nil, keyEquivalent: "")
        editItem.submenu = edit
        menu.addItem(editItem)
        edit.addItem(withTitle: String(localized: "Undo"), action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: String(localized: "Redo"), action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: String(localized: "Cut"), action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: String(localized: "Copy"), action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: String(localized: "Paste"), action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: String(localized: "Select All"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let windowMenu = NSMenu(title: String(localized: "Window"))
        let windowItem = NSMenuItem(title: String(localized: "Window"), action: nil, keyEquivalent: "")
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        windowMenu.addItem(withTitle: String(localized: "Close"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        windowMenu.addItem(withTitle: String(localized: "Minimize"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        NSApp.mainMenu = menu
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
final class AppWindowCoordinator: NSObject, NSWindowDelegate {
    static let shared = AppWindowCoordinator()

    private weak var model: AppModel?
    private var settingsWindow: NSWindow?

    private override init() {
        super.init()
    }

    func setModel(_ model: AppModel) {
        self.model = model
    }

    func showSettings() {
        if let window = NSApp.windows.first(where: { $0.title == "CmdIME" }) {
            // A false return leaves the window usable; listening status would overwrite any message.
            _ = NSApp.setActivationPolicy(.regular)
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
        _ = NSApp.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window.title == "CmdIME" else {
            return
        }
        _ = NSApp.setActivationPolicy(.accessory)
    }

    private func makeSettingsWindow(model: AppModel) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820 + DesignTokens.Layout.sidebarWidth, height: 840),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdIME"
        // The material runs under the title bar, so the window reads as one sheet.
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.appearance = AppearancePreference.stored.nsAppearance
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("CmdIMESettings")
        let hostingView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: DesignTokens.Layout.sidebarWidth + DesignTokens.Layout.detailMinWidth, minHeight: 640)
        )
        if #available(macOS 14.0, *) {
            // As a window's content view the hosting view would otherwise bridge `.all`: the split
            // view could then retitle the window, which is found by "CmdIME", and add a toolbar
            // with a sidebar toggle to a sidebar that never collapses. The option is macOS 14 and later.
            hostingView.sceneBridgingOptions = []
        }
        window.contentView = hostingView
        return window
    }
}
