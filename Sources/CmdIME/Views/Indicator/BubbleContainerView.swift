import AppKit
import SwiftUI

/// Content view of the indicator panel: the glass, when the theme has one, under a
/// single persistent hosting view. SwiftUI `Material` cannot be kept in its active
/// look inside a window that never becomes key, so the glass is an
/// `NSVisualEffectView` with `state = .active`, clipped by a mask image made from
/// the same continuous shape the SwiftUI edges are stroked along.
final class BubbleContainerView: NSView {
    struct Glass: Equatable {
        let isDark: Bool
        /// Ask for the system's Liquid Glass; honoured on macOS 26 and later only.
        var isLiquid = false
        /// The bubble inside the container, in the container's coordinates.
        let frame: CGRect
        let cornerRadius: CGFloat
    }

    private struct MaskKey: Equatable {
        let size: CGSize
        let radius: CGFloat
    }

    /// The bubble. On the liquid path it is handed to the material as its content
    /// view and AppKit owns its frame; everywhere else it is a plain top subview that
    /// this view sizes to its bounds.
    private let bubbleHost: NSHostingView<LiveBubbleRoot>
    /// The shadow, which paints into the panel's margin and so can never go inside the
    /// material. Bottom-most, present for every substrate.
    private let shadowHost: NSHostingView<LiveBubbleShadow>
    private var isBubbleHostInGlass = false
    private let glassView = NSVisualEffectView()
    /// An `NSGlassEffectView`; typed loosely because the class only exists on macOS 26+.
    private var liquidView: NSView?
    private var maskCache: (key: MaskKey, image: NSImage)?

    init(state: BubbleState) {
        bubbleHost = NSHostingView(rootView: LiveBubbleRoot(state: state))
        shadowHost = NSHostingView(rootView: LiveBubbleShadow(state: state))
        super.init(frame: .zero)
        // The panel is sized by the controller from a measurement, never by the view.
        shadowHost.sizingOptions = []
        shadowHost.autoresizingMask = [.width, .height]
        bubbleHost.sizingOptions = []
        bubbleHost.autoresizingMask = [.width, .height]
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.isEmphasized = false
        addSubview(shadowHost)
        addSubview(bubbleHost)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BubbleContainerView is created in code")
    }

    /// Nothing in the indicator is clickable; clicks land on whatever is below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        shadowHost.frame = bounds
        // Never while it is inside the material: there AppKit pins it to the glass with
        // constraints, and setting a frame fights them.
        if bubbleHost.superview === self { bubbleHost.frame = bounds }
    }

    /// The material only processes what it is given as its content view. A sibling
    /// placed behind it is on the far side of the glass's own renderer and cannot be
    /// in the same composite, which is why this is a move rather than a reorder.
    @available(macOS 26.0, *)
    private func moveBubbleHostIntoGlass(_ liquid: NSGlassEffectView) {
        guard !isBubbleHostInGlass || liquid.contentView !== bubbleHost else { return }
        bubbleHost.removeFromSuperview()
        liquid.contentView = bubbleHost
        isBubbleHostInGlass = true
    }

    private func moveBubbleHostBackToContainer() {
        guard isBubbleHostInGlass else { return }
        if #available(macOS 26.0, *) { (liquidView as? NSGlassEffectView)?.contentView = nil }
        // AppKit turns this off when it takes the content view and does not turn it
        // back on when it lets go, so a frame set afterwards would be ignored.
        bubbleHost.translatesAutoresizingMaskIntoConstraints = true
        bubbleHost.autoresizingMask = [.width, .height]
        addSubview(bubbleHost)
        bubbleHost.frame = bounds
        isBubbleHostInGlass = false
    }

    /// The glass view is installed only while the substrate is glass.
    func setGlass(_ glass: Glass?) {
        guard let glass else {
            moveBubbleHostBackToContainer()
            glassView.removeFromSuperview()
            liquidView?.removeFromSuperview()
            return
        }
        if glass.isLiquid, #available(macOS 26.0, *) {
            glassView.removeFromSuperview()
            let liquid = (liquidView as? NSGlassEffectView) ?? NSGlassEffectView()
            liquid.cornerRadius = glass.cornerRadius
            liquid.appearance = NSAppearance(named: glass.isDark ? .darkAqua : .aqua)
            liquid.frame = glass.frame
            if liquid.superview == nil {
                addSubview(liquid, positioned: .above, relativeTo: shadowHost)
            }
            liquidView = liquid
            moveBubbleHostIntoGlass(liquid)
            // The content view is pinned to the glass by constraints, and its frame
            // does not follow a new glass frame until the subtree is laid out.
            liquid.layoutSubtreeIfNeeded()
            return
        }
        moveBubbleHostBackToContainer()
        liquidView?.removeFromSuperview()
        glassView.material = glass.isDark ? .hudWindow : .popover
        glassView.appearance = NSAppearance(named: glass.isDark ? .vibrantDark : .vibrantLight)
        glassView.frame = glass.frame
        glassView.maskImage = maskImage(size: glass.frame.size, radius: glass.cornerRadius)
        if glassView.superview == nil {
            addSubview(glassView, positioned: .above, relativeTo: shadowHost)
        }
    }

    /// Drawn at the exact bubble size with no cap insets: a continuous corner takes
    /// about one and a half radii per edge, which breaks a stretchable mask on small bubbles.
    private func maskImage(size: CGSize, radius: CGFloat) -> NSImage {
        let key = MaskKey(size: size, radius: radius)
        if let maskCache, maskCache.key == key { return maskCache.image }
        let image = NSImage(size: size, flipped: false) { rect in
            guard let context = NSGraphicsContext.current?.cgContext else { return false }
            context.addPath(RoundedRectangle(cornerRadius: radius, style: .continuous).path(in: rect).cgPath)
            context.setFillColor(NSColor.black.cgColor)
            context.fillPath()
            return true
        }
        maskCache = (key, image)
        return image
    }
}
