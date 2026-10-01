import AppKit
import Combine
import SwiftUI

/// The update card in a corner of the screen, for when macOS does not let CmdIME post the update
/// notification. It never activates CmdIME or takes keyboard focus, so typing goes on where it was;
/// it closes on Later, on Skip, or once the update is no longer available.
@MainActor
final class UpdateCardController {
    // Wide enough for the title on one line beside three Japanese buttons (460 wrapped it to three).
    static let width: CGFloat = 580
    private static let screenMargin: CGFloat = 16

    private weak var model: AppModel?
    private var panel: NSPanel?
    private var statusWatch: AnyCancellable?

    init(model: AppModel) {
        self.model = model
    }

    func show() {
        guard let model, case .available = model.updateStatus else { return }
        let panel = panel ?? makePanel(model: model)
        self.panel = panel
        place(panel)
        panel.orderFrontRegardless()
        statusWatch = model.$updateStatus.sink { [weak self] status in
            guard case .available = status else {
                // Skip, or a newer check found nothing; an install in progress keeps the status.
                self?.close()
                return
            }
        }
    }

    func close() {
        statusWatch = nil
        panel?.orderOut(nil)
    }

    private func makePanel(model: AppModel) -> NSPanel {
        let panel = UpdateCardPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 160),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.contentView = FirstMouseHostingView(rootView: UpdateCard(model: model) { [weak self] in self?.close() })
        return panel
    }

    /// Top right of the screen with the mouse, below the menu bar, sized to the card's content.
    private func place(_ panel: NSPanel) {
        guard let content = panel.contentView else { return }
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        content.frame.size.width = Self.width
        let height = content.fittingSize.height
        panel.setFrame(NSRect(x: visible.maxX - Self.width - Self.screenMargin,
                              y: visible.maxY - height - Self.screenMargin,
                              width: Self.width, height: height), display: true)
    }
}

/// Can take clicks without activating the app.
private final class UpdateCardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The first click on a button acts at once, though CmdIME is not the active app.
private final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct UpdateCard: View {
    @ObservedObject var model: AppModel
    let onLater: () -> Void

    var body: some View {
        if case let .available(result) = model.updateStatus {
            UpdateAvailableBar(model: model, version: result.latestVersion)
                .overlay(alignment: .topTrailing) {
                    Button(action: onLater) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(DesignTokens.Colors.textMuted)
                    }
                    .buttonStyle(.plain)
                    .help("Later")
                    .accessibilityLabel("Later")
                    .offset(x: 6, y: -6)
                }
                .padding(8)
                .frame(width: UpdateCardController.width)
                .fixedSize(horizontal: false, vertical: true)
                .followsAppearancePreference()
        }
    }
}
