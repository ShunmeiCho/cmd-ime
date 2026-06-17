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
        scale: Double,
        colorStyle: SwitchIndicatorColorStyle,
        contentStyle: SwitchIndicatorContentStyle,
        customColorHex: String
    ) {
        let panel = panel ?? makePanel()
        self.panel = panel

        let presentation = InputSourcePresentation(source: source, fallbackRole: role)
        let metrics = InputIndicatorMetrics(size: size, scale: scale, contentStyle: contentStyle)
        panel.contentView = NSHostingView(
            rootView: InputIndicatorView(
                symbol: presentation.symbol,
                title: presentation.title,
                subtitle: presentation.detail,
                tint: tint(for: presentation, style: colorStyle, customColorHex: customColorHex),
                contentStyle: contentStyle,
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

    private func tint(
        for presentation: InputSourcePresentation,
        style: SwitchIndicatorColorStyle,
        customColorHex: String
    ) -> Color {
        switch style {
        case .accent:
            return .accentColor
        case .monochrome:
            return Color(nsColor: .secondaryLabelColor)
        case .custom:
            return Color(cmdIMEHex: customColorHex) ?? .accentColor
        case .role:
            return presentation.tint
        }
    }
}

private struct InputIndicatorMetrics {
    let panelSize: NSSize
    let horizontalPadding: CGFloat
    let verticalPadding: CGFloat
    let spacing: CGFloat
    let symbolSize: CGFloat
    let symbolCornerRadius: CGFloat
    let symbolFontSize: CGFloat
    let titleFontSize: CGFloat
    let subtitleFontSize: CGFloat
    let bubbleCornerRadius: CGFloat
    let bubbleStrokeOpacity: Double

    init(size: SwitchIndicatorSize, scale: Double, contentStyle: SwitchIndicatorContentStyle) {
        let scaleFactor = CGFloat(SwitcherConfig.clampedSwitchIndicatorScale(scale))
        let basePanelSize: NSSize
        let baseHorizontalPadding: CGFloat
        let baseVerticalPadding: CGFloat
        let baseSpacing: CGFloat
        let baseSymbolSize: CGFloat
        let baseSymbolCornerRadius: CGFloat
        let baseSymbolFontSize: CGFloat
        let baseTitleFontSize: CGFloat
        let baseSubtitleFontSize: CGFloat
        let baseBubbleCornerRadius: CGFloat

        switch size {
        case .small:
            baseHorizontalPadding = 10
            baseVerticalPadding = 6
            baseSpacing = 8
            baseSymbolSize = 26
            baseSymbolCornerRadius = 7
            baseSymbolFontSize = 15
            baseTitleFontSize = 12
            baseSubtitleFontSize = 10
            baseBubbleCornerRadius = 15
        case .medium:
            baseHorizontalPadding = 12
            baseVerticalPadding = 7
            baseSpacing = 10
            baseSymbolSize = 32
            baseSymbolCornerRadius = 9
            baseSymbolFontSize = 18
            baseTitleFontSize = 13
            baseSubtitleFontSize = 11
            baseBubbleCornerRadius = 18
        case .large:
            baseHorizontalPadding = 14
            baseVerticalPadding = 8
            baseSpacing = 12
            baseSymbolSize = 40
            baseSymbolCornerRadius = 11
            baseSymbolFontSize = 22
            baseTitleFontSize = 15
            baseSubtitleFontSize = 12
            baseBubbleCornerRadius = 22
        }

        switch (size, contentStyle) {
        case (.small, .iconOnly):
            basePanelSize = NSSize(width: 46, height: 42)
        case (.medium, .iconOnly):
            basePanelSize = NSSize(width: 56, height: 48)
        case (.large, .iconOnly):
            basePanelSize = NSSize(width: 72, height: 60)
        case (.small, .textOnly):
            basePanelSize = NSSize(width: 92, height: 38)
        case (.medium, .textOnly):
            basePanelSize = NSSize(width: 118, height: 46)
        case (.large, .textOnly):
            basePanelSize = NSSize(width: 146, height: 58)
        case (.small, .iconAndText):
            basePanelSize = NSSize(width: 138, height: 44)
        case (.medium, .iconAndText):
            basePanelSize = NSSize(width: 172, height: 54)
        case (.large, .iconAndText):
            basePanelSize = NSSize(width: 210, height: 66)
        }

        panelSize = NSSize(
            width: (basePanelSize.width * scaleFactor).rounded(.up),
            height: (basePanelSize.height * scaleFactor).rounded(.up)
        )
        horizontalPadding = baseHorizontalPadding * scaleFactor
        verticalPadding = baseVerticalPadding * scaleFactor
        spacing = max(4, baseSpacing * scaleFactor)
        symbolSize = baseSymbolSize * scaleFactor
        symbolCornerRadius = baseSymbolCornerRadius * scaleFactor
        symbolFontSize = baseSymbolFontSize * scaleFactor
        titleFontSize = baseTitleFontSize * scaleFactor
        subtitleFontSize = baseSubtitleFontSize * scaleFactor
        bubbleCornerRadius = baseBubbleCornerRadius * scaleFactor
        bubbleStrokeOpacity = contentStyle == .iconAndText ? 0.18 : 0
    }
}

private struct InputIndicatorView: View {
    let symbol: String
    let title: String
    let subtitle: String
    let tint: Color
    let contentStyle: SwitchIndicatorContentStyle
    let metrics: InputIndicatorMetrics

    var body: some View {
        content
        .frame(
            width: max(1, metrics.panelSize.width - metrics.horizontalPadding * 2),
            height: max(1, metrics.panelSize.height - metrics.verticalPadding * 2),
            alignment: .center
        )
        .padding(.horizontal, metrics.horizontalPadding)
        .padding(.vertical, metrics.verticalPadding)
        .frame(width: metrics.panelSize.width, height: metrics.panelSize.height)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: metrics.bubbleCornerRadius))
        .overlay {
            if metrics.bubbleStrokeOpacity > 0 {
                RoundedRectangle(cornerRadius: metrics.bubbleCornerRadius)
                    .strokeBorder(.secondary.opacity(metrics.bubbleStrokeOpacity))
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch contentStyle {
        case .iconOnly:
            symbolView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .textOnly:
            textStack(alignment: .center)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .iconAndText:
            HStack(spacing: metrics.spacing) {
                symbolView
                textStack(alignment: .leading)
                Spacer(minLength: 0)
            }
        }
    }

    private var symbolView: some View {
        Text(symbol)
            .font(.system(size: metrics.symbolFontSize, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: metrics.symbolSize, height: metrics.symbolSize)
            .background(tint, in: RoundedRectangle(cornerRadius: metrics.symbolCornerRadius))
    }

    private func textStack(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(title)
                .font(.system(size: metrics.titleFontSize, weight: .semibold))
                .lineLimit(1)
            if contentStyle == .iconAndText {
                Text(subtitle)
                    .font(.system(size: metrics.subtitleFontSize))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
