import KeyboardSwitcherCore
import SwiftUI

/// The native sidebar: one row per page, an SF Symbol plus a label, and the
/// keyboard-control status pinned at the bottom.
struct SettingsSidebar: View {
    @ObservedObject var model: AppModel
    @Binding var navigation: SettingsNavigation
    @AppStorage(SettingsDetail.defaultsKey) private var detail = SettingsDetail.brief

    var body: some View {
        List(selection: selection) {
            ForEach(navigation.visiblePages, id: \.self) { page in
                Label(page.label.title, systemImage: page.label.systemImage)
                    .tag(page)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The sidebar never changes width, and the footer has to be measured at that width: asked
            // for its size at a narrower one (a split view does, to find its minimum height), the
            // permission text wraps into a column taller than the window, and the whole split view
            // is then laid out past the window's top and bottom edges.
            VStack(spacing: 0) {
                ConsoleSegmentedControl(
                    options: SettingsDetail.allCases.map { ConsoleSegmentOption(value: $0, label: $0.title) },
                    selection: $detail
                )
                .accessibilityLabel("Explanations")
                .help("Brief shows the settings alone. Detailed adds what each one does.")
                .padding(DesignTokens.Layout.panelInset)
                KeyboardControlFooter(model: model)
            }
            .frame(width: DesignTokens.Layout.sidebarWidth)
        }
    }

    /// A click on empty sidebar space clears a List selection; the page stays instead.
    private var selection: Binding<SettingsPage?> {
        Binding(
            get: { navigation.selection },
            set: { page in
                guard let page else { return }
                navigation.select(page)
            }
        )
    }
}

extension SettingsPage {
    /// The sidebar row: a title and an SF Symbol available on macOS 13.
    var label: (title: String, systemImage: String) {
        switch self {
        case .setup: (String(localized: "Setup"), "checklist")
        case .slots: (String(localized: "Slots"), "keyboard")
        case .apps: (String(localized: "Apps"), "square.stack.3d.up")
        case .indicator: (String(localized: "Indicator"), "text.bubble")
        case .general: (String(localized: "General"), "gearshape")
        case .about: (String(localized: "About"), "info.circle")
        }
    }
}
