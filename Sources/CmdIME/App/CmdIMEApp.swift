import AppKit
import Combine
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
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppWindowCoordinator.shared.setModel(model)
        statusItemController = StatusItemController(model: model)
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
final class StatusItemController: NSObject {
    private let model: AppModel
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(model: AppModel) {
        self.model = model
        super.init()
        updateVisibility(model.config.showMenuBarIcon)
        model.$config.sink { [weak self] config in
            Task { @MainActor in
                self?.updateVisibility(config.showMenuBarIcon)
                self?.refreshMenu()
            }
        }
        .store(in: &cancellables)
        model.$sources.sink { [weak self] _ in
            Task { @MainActor in
                self?.refreshMenu()
            }
        }
        .store(in: &cancellables)
    }

    private func updateVisibility(_ visible: Bool) {
        if visible {
            installStatusItemIfNeeded()
        } else {
            removeStatusItem()
        }
    }

    private func installStatusItemIfNeeded() {
        guard statusItem == nil else {
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "CmdIME"
        item.button?.toolTip = "CmdIME"
        item.menu = makeMenu()
        statusItem = item
    }

    private func removeStatusItem() {
        guard let statusItem else {
            return
        }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
    }

    private func refreshMenu() {
        statusItem?.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        for role in InputRole.allCases {
            let source = model.matchedSource(for: role)
            let presentation = InputSourcePresentation(source: source, fallbackRole: role)
            let item = menuItem(
                source == nil ? "\(presentation.title) (not matched)" : presentation.title,
                selector(for: role)
            )
            item.toolTip = source?.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings", #selector(showSettings)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit", #selector(quit)))
        return menu
    }

    private func menuItem(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func selector(for role: InputRole) -> Selector {
        switch role {
        case .english:
            #selector(switchEnglish)
        case .chinese:
            #selector(switchChinese)
        case .japanese:
            #selector(switchJapanese)
        }
    }

    @objc private func switchEnglish() {
        model.switchRole(.english)
    }

    @objc private func switchChinese() {
        model.switchRole(.chinese)
    }

    @objc private func switchJapanese() {
        model.switchRole(.japanese)
    }

    @objc private func showSettings() {
        AppWindowCoordinator.shared.showSettings()
    }

    @objc private func quit() {
        model.quit()
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
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "CmdIME"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(
            rootView: ContentView(model: model)
                .frame(minWidth: 660, minHeight: 500)
        )
        return window
    }
}
