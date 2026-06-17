import AppKit
import ApplicationServices
import KeyboardSwitcherCore
import SwiftUI

@MainActor
final class InputIndicatorController {
    private var panel: NSPanel?
    private var hideTask: Task<Void, Never>?

    func show(
        role: InputRole,
        source: InputSourceInfo,
        size: SwitchIndicatorSize,
        colorStyle: SwitchIndicatorColorStyle
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let metrics = InputIndicatorMetrics(size: size)
        panel.contentView = NSHostingView(
            rootView: InputIndicatorView(
                symbol: symbol(for: role),
                title: title(for: role),
                subtitle: source.localizedName,
                tint: tint(for: role, style: colorStyle),
                metrics: metrics
            )
        )
        panel.setContentSize(metrics.panelSize)
        panel.setFrameOrigin(origin(for: metrics.panelSize))
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

    private func tint(for role: InputRole, style: SwitchIndicatorColorStyle) -> Color {
        switch style {
        case .accent:
            return .accentColor
        case .monochrome:
            return Color(nsColor: .secondaryLabelColor)
        case .role:
            return roleTint(for: role)
        }
    }

    private func roleTint(for role: InputRole) -> Color {
        switch role {
        case .english:
            return Color(red: 0.16, green: 0.43, blue: 0.92)
        case .chinese:
            return Color(red: 0.12, green: 0.56, blue: 0.36)
        case .japanese:
            return Color(red: 0.78, green: 0.22, blue: 0.27)
        }
    }
}

private struct InputIndicatorMetrics {
    let panelSize: NSSize
    let horizontalPadding: CGFloat
    let spacing: CGFloat
    let symbolSize: CGFloat
    let symbolCornerRadius: CGFloat
    let symbolFontSize: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let bubbleCornerRadius: CGFloat

    init(size: SwitchIndicatorSize) {
        switch size {
        case .small:
            panelSize = NSSize(width: 138, height: 44)
            horizontalPadding = 10
            spacing = 8
            symbolSize = 26
            symbolCornerRadius = 7
            symbolFontSize = 15
            titleFontSize = 12
            subtitleFontSize = 10
            bubbleCornerRadius = 15
        case .medium:
            panelSize = NSSize(width: 172, height: 54)
            horizontalPadding = 12
            spacing = 10
            symbolSize = 32
            symbolCornerRadius = 9
            symbolFontSize = 18
            titleFontSize = 13
            subtitleFontSize = 11
            bubbleCornerRadius = 18
        case .large:
            panelSize = NSSize(width: 210, height: 66)
            horizontalPadding = 14
            spacing = 12
            symbolSize = 40
            symbolCornerRadius = 11
            symbolFontSize = 22
            titleFontSize = 15
            subtitleFontSize = 12
            bubbleCornerRadius = 22
        }
    }
}

private struct InputIndicatorView: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    let metrics: InputIndicatorMetrics

    var body: some View {
        HStack(spacing: metrics.spacing) {
            Text(symbol)
                .font(.system(size: metrics.symbolFontSize, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: metrics.symbolSize, height: metrics.symbolSize)
                .background(tint, in: RoundedRectangle(cornerRadius: metrics.symbolCornerRadius))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: metrics.titleFontSize, weight: .semibold))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: metrics.subtitleFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.horizontalPadding)
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.bubbleCornerRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.bubbleCornerRadius)
                .strokeBorder(.secondary.opacity(0.18))
        }
    }
}
