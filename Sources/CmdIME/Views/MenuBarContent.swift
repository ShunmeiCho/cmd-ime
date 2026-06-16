import KeyboardSwitcherCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("English") {
            model.switchRole(.english)
        }

        Button("Chinese") {
            model.switchRole(.chinese)
        }

        Button("Japanese") {
            model.switchRole(.japanese)
        }

        Divider()

        Button("Settings") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
    }
}
