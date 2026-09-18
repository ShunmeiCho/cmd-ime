import AppKit

/// The indicator's window. It never becomes key or main, never takes the mouse and
/// never joins window cycling: the app being typed into must not notice it.
final class BubblePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        backgroundColor = .clear
        isOpaque = false
        // The shadow is drawn by the bubble view so previews share it.
        hasShadow = false
        ignoresMouseEvents = true
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        animationBehavior = .none
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
        isExcludedFromWindowsMenu = true
        setAccessibilityElement(false)
    }
}
