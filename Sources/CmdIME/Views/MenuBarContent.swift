import KeyboardSwitcherCore
import SwiftUI

struct MenuBarContent: View {
    @ObservedObject var model: AppModel

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
            AppWindowCoordinator.shared.setModel(model)
            AppWindowCoordinator.shared.showSettings()
        }

        Divider()

        Button("Quit") {
            model.quit()
        }
    }
}
