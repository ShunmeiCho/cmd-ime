import KeyboardSwitcherCore
import SwiftUI

/// macOS's own input source badge under the text cursor, which shows next to CmdIME's bubble on
/// every switch. Hiding it changes a system-wide preference, so the state is read from macOS
/// whenever the page appears and written only when the user flips the checkbox.
struct SystemIndicatorSection: View {
    @ObservedObject var model: AppModel
    @State private var isHidden = SystemInputIndicator.isHidden()

    var body: some View {
        CompactSection(title: String(localized: "System indicator")) {
            CompactSettingRow(String(localized: "Under the cursor")) {
                VStack(alignment: .leading, spacing: 2) {
                    Toggle("Hide the input source badge macOS shows under the cursor", isOn: Binding(
                        get: { isHidden },
                        set: { setHidden($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .controlSize(.small)
                    caption(String(localized: "macOS draws it on every input source change, CmdIME's included, and CmdIME cannot leave it out of a switch. This turns it off in every app for your user account."))
                    caption(String(localized: "Apps pick it up as they relaunch; log out and back in for all of them. Control+Space then shows its older list in the middle of the screen. Uncheck to put the macOS default back."))
                }
            }
        }
        .onAppear { isHidden = SystemInputIndicator.isHidden() }
    }

    /// A refused write shows in the window's failure bar; the checkbox shows what macOS kept.
    private func setHidden(_ hidden: Bool) {
        model.setSystemInputIndicatorHidden(hidden)
        isHidden = SystemInputIndicator.isHidden()
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(DesignTokens.Colors.textMuted)
            .fixedSize(horizontal: false, vertical: true)
    }
}
