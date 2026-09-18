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

    private let hostingView: NSHostingView<LiveBubbleRoot>
    private let glassView = NSVisualEffectView()
    /// An `NSGlassEffectView`; typed loosely because the class only exists on macOS 26+.
    private var liquidView: NSView?
    private var maskCache: (key: MaskKey, image: NSImage)?

    init(state: BubbleState) {
        hostingView = NSHostingView(rootView: LiveBubbleRoot(state: state))
        super.init(frame: .zero)
        // The panel is sized by the controller from a measurement, never by the view.
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        glassView.blendingMode = .behindWindow
        glassView.state = .active
        glassView.isEmphasized = false
        addSubview(hostingView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("BubbleContainerView is created in code")
    }

    /// Nothing in the indicator is clickable; clicks land on whatever is below.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        hostingView.frame = bounds
    }

    /// The glass view is installed only while the substrate is glass.
    func setGlass(_ glass: Glass?) {
        guard let glass else {
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
                addSubview(liquid, positioned: .below, relativeTo: hostingView)
            }
            liquidView = liquid
            return
        }
        liquidView?.removeFromSuperview()
        glassView.material = glass.isDark ? .hudWindow : .popover
        glassView.appearance = NSAppearance(named: glass.isDark ? .vibrantDark : .vibrantLight)
        glassView.frame = glass.frame
        glassView.maskImage = maskImage(size: glass.frame.size, radius: glass.cornerRadius)
        if glassView.superview == nil {
            addSubview(glassView, positioned: .below, relativeTo: hostingView)
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
