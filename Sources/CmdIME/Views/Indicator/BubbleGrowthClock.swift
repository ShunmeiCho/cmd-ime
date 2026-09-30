import AppKit
import QuartzCore

/// Calls back once per display refresh with the seconds since it started, so the adaptive
/// bubble's glass and SwiftUI edges move on one clock. A display link on macOS 14 and later,
/// following the screen the panel is on; a 120 Hz timer before that.
@MainActor
final class BubbleGrowthClock: NSObject {
    /// Before macOS 14 there is no display link on a view; this is the refresh it assumes.
    private static let fallbackInterval = 1.0 / 120

    private let start = CACurrentMediaTime()
    private let onTick: (Double) -> Void
    private var displayLink: AnyObject?
    private var timer: Timer?

    init(view: NSView, onTick: @escaping (Double) -> Void) {
        self.onTick = onTick
        super.init()
        if #available(macOS 14.0, *) {
            let link = view.displayLink(target: self, selector: #selector(tick))
            link.add(to: .main, forMode: .common)
            displayLink = link
        } else {
            let timer = Timer(timeInterval: Self.fallbackInterval, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer, forMode: .common)
            self.timer = timer
        }
    }

    @objc private func tick() {
        onTick(CACurrentMediaTime() - start)
    }

    func stop() {
        if #available(macOS 14.0, *) { (displayLink as? CADisplayLink)?.invalidate() }
        displayLink = nil
        timer?.invalidate()
        timer = nil
    }
}
