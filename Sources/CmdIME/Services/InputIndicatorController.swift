import AppKit
import ApplicationServices
import KeyboardSwitcherCore
import SwiftUI

@MainActor
final class InputIndicatorController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(role: InputRole, source: InputSourceInfo) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let size = NSSize(width: 172, height: 54)
        panel.contentView = NSHostingView(
            rootView: InputIndicatorView(
                symbol: symbol(for: role),
                title: title(for: role),
                subtitle: source.localizedName
            )
        )
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.orderFrontRegardless()

        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 850_000_000)
            guard !Task.isCancelled else {
                return
            }
            panel.orderOut(nil)
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 172, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.isFloatingPanel = true
        panel.isOpaque = false
        panel.level = .floating
        return panel
    }

    private func origin(for size: NSSize) -> NSPoint {
        let anchor = focusedCaretPoint() ?? NSEvent.mouseLocation
        let screen = screen(containing: anchor)
        let frame = screen.visibleFrame
        let proposed = NSPoint(x: anchor.x + 10, y: anchor.y + 18)

        return NSPoint(
            x: min(max(proposed.x, frame.minX + 8), frame.maxX - size.width - 8),
            y: min(max(proposed.y, frame.minY + 8), frame.maxY - size.height - 8)
        )
    }

    private func screen(containing point: NSPoint) -> NSScreen {
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(point) }) {
            return screen
        }
        if let main = NSScreen.main {
            return main
        }
        return NSScreen.screens.first!
    }

    private func focusedCaretPoint() -> NSPoint? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success, let focusedValue else {
            return nil
        }

        guard CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        let focusedElement = focusedValue as! AXUIElement
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            focusedElement,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success, let rangeValue else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            focusedElement,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success, let boundsValue else {
            return nil
        }

        guard CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let bounds = boundsValue as! AXValue
        var rect = CGRect.zero
        guard AXValueGetType(bounds) == .cgRect,
              AXValueGetValue(bounds, .cgRect, &rect),
              !rect.isEmpty else {
            return nil
        }

        return convertAccessibilityPoint(CGPoint(x: rect.midX, y: rect.minY))
    }

    private func convertAccessibilityPoint(_ point: CGPoint) -> NSPoint {
        let maxY = NSScreen.screens.map(\.frame.maxY).max() ?? 0
        let converted = NSPoint(x: point.x, y: maxY - point.y)
        if NSScreen.screens.contains(where: { $0.frame.contains(converted) }) {
            return converted
        }
        return NSPoint(x: point.x, y: point.y)
    }

    private func symbol(for role: InputRole) -> String {
        switch role {
        case .english:
            "A"
        case .chinese:
            "中"
        case .japanese:
            "あ"
        }
    }

    private func title(for role: InputRole) -> String {
        switch role {
        case .english:
            "English"
        case .chinese:
            "Chinese"
        case .japanese:
            "Japanese"
        }
    }
}

private struct InputIndicatorView: View {
    let symbol: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 10) {
            Text(symbol)
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 32, height: 32)
                .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 9))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .frame(width: 172, height: 54)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.secondary.opacity(0.18))
        }
    }
}
