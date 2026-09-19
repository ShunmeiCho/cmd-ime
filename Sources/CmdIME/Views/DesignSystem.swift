import AppKit
import KeyboardSwitcherCore
import SwiftUI

/// Light, dark, or whatever the system uses, for the settings window and its popovers.
enum AppearancePreference: String, CaseIterable {
    case system, light, dark

    static let defaultsKey = "appearance"

    static var stored: AppearancePreference {
        AppearancePreference(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .system
    }

    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
    }
}

enum DesignTokens {
    enum Colors {
        // Every colour follows the window's appearance. Surfaces are translucent because the
        // window sits on a system material; with Reduce Transparency they turn opaque.
        private static func dyn(_ light: NSColor, _ dark: NSColor) -> Color {
            Color(nsColor: NSColor(name: nil) { $0.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light })
        }
        private static func gray(_ white: CGFloat, _ alpha: CGFloat = 1) -> NSColor { NSColor(white: white, alpha: alpha) }
        private static func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: r, green: g, blue: b, alpha: a)
        }
        /// Reduce Transparency. `CMDIME_OPAQUE=1` forces it in debug builds, for screenshots.
        static var isOpaque: Bool {
            #if DEBUG
            if ProcessInfo.processInfo.environment["CMDIME_OPAQUE"] == "1" { return true }
            #endif
            return NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        }
        private static func translucent(_ glass: Color, opaque: Color) -> Color { isOpaque ? opaque : glass }

        /// Hover and fill tints: a darkening veil in light mode, a lightening one in dark mode.
        static func overlay(_ opacity: Double) -> Color { dyn(gray(0, opacity * 0.9), gray(1, opacity)) }

        static var canvas: Color { translucent(.clear, opaque: dyn(rgb(0.945, 0.945, 0.955), rgb(0.11, 0.11, 0.125))) }
        static var surface: Color { translucent(dyn(gray(1, 0.62), rgb(0.10, 0.10, 0.12, 0.50)),
                                                opaque: dyn(gray(1), rgb(0.155, 0.155, 0.175))) }
        static var surfaceRaised: Color { translucent(dyn(gray(1, 0.78), rgb(0.17, 0.17, 0.20, 0.72)),
                                                      opaque: dyn(rgb(0.975, 0.975, 0.98), rgb(0.20, 0.20, 0.225))) }
        static var surfaceInset: Color { translucent(dyn(gray(0, 0.06), gray(0, 0.30)),
                                                     opaque: dyn(rgb(0.915, 0.915, 0.93), rgb(0.085, 0.085, 0.10))) }
        static var keycapTop: Color { dyn(gray(1), rgb(0.235, 0.235, 0.265)) }
        static var keycapBottom: Color { dyn(rgb(0.90, 0.90, 0.92), rgb(0.155, 0.155, 0.18)) }
        static var separator: Color { dyn(gray(0, 0.09), gray(1, 0.08)) }
        static var separatorStrong: Color { dyn(gray(0, 0.16), gray(1, 0.14)) }
        static var textPrimary: Color { Color(nsColor: .labelColor) }
        static var textSecondary: Color { dyn(gray(0.27), rgb(0.74, 0.74, 0.78)) }
        static var textMuted: Color { dyn(gray(0.40), rgb(0.62, 0.62, 0.66)) }
        static let accent = Color(red: 0.21, green: 0.48, blue: 0.90)
        static let actionFill = Color(red: 40 / 255, green: 104 / 255, blue: 199 / 255)
        // Status colours double as text, so each has a darker light-mode value that keeps
        // at least 4.5:1 against the light surfaces; the dark values are the original ones.
        static var success: Color { dyn(rgb(0.07, 0.47, 0.20), rgb(0.27, 0.77, 0.42)) }
        static var warning: Color { dyn(rgb(0.62, 0.33, 0.00), rgb(0.77, 0.48, 0.14)) }
        static var danger: Color { dyn(rgb(0.76, 0.15, 0.12), rgb(0.89, 0.31, 0.28)) }
        /// Destructive button labels: at least 5.68:1 on the raised dark surface, and 5.9:1 on the light one.
        static var destructiveText: Color { dyn(rgb(0.72, 0.11, 0.09), rgb(1, 159 / 255, 150 / 255)) }

        static func role(_ role: InputRole) -> Color {
            switch role {
            case .english:
                Color(red: 0.30, green: 0.55, blue: 1.00)
            case .chinese:
                Color(red: 0.20, green: 0.66, blue: 0.33)
            case .japanese:
                Color(red: 0.89, green: 0.34, blue: 0.29)
            default:
                Color(nsColor: .secondaryLabelColor)
            }
        }
    }

    enum Typography {
        static let title = Font.system(size: 13, weight: .semibold)
        static let body = Font.system(size: 12)
        static let auxiliary = Font.system(size: 11)
        // AppKit bridge for the body role on short technical key labels.
        @MainActor static let bodyKeyNSFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
    }

    enum Radius {
        static let windowSurface: CGFloat = 14
        static let surface: CGFloat = 12
        static let card: CGFloat = 12
        static let control: CGFloat = 10
        static let keycap: CGFloat = 8
    }

    enum Spacing {
        static let xs: CGFloat = 6
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Shadow {
        static let surface = Color.black.opacity(0.46)
        static let keycap = Color.black.opacity(0.36)
        static let glow = Color.white.opacity(0.14)
    }

    enum Motion {
        static let instant = 0.08
        static let fast = 0.14
        static let normal = 0.20
        static let slow = 0.32

        static let keyPress = SwiftUI.Animation.easeOut(duration: instant)
        static let keyRelease = SwiftUI.Animation.spring(response: 0.18, dampingFraction: 0.82)
        static let stateChange = SwiftUI.Animation.easeOut(duration: normal)
        static let expandCollapse = SwiftUI.Animation.spring(response: 0.24, dampingFraction: 0.90)

        static let dragLift = SwiftUI.Animation.spring(response: 0.22, dampingFraction: 0.78)
        static let dragSettle = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.80)
        static let dragReturn = SwiftUI.Animation.spring(response: 0.32, dampingFraction: 0.90)

        static let quickFade = SwiftUI.Animation.easeOut(duration: fast)
        static let seatPulse = SwiftUI.Animation.easeOut(duration: slow)
        static let rejectShake = SwiftUI.Animation.linear(duration: slow)

        static func resolved(_ animation: SwiftUI.Animation, reduceMotion: Bool) -> SwiftUI.Animation? {
            reduceMotion ? nil : animation
        }
    }

    enum Layout {
        static let sectionGap: CGFloat = 20
        static let panelInset: CGFloat = 12
        static let panelGap: CGFloat = 12
        static let rowGap: CGFloat = 8
        static let panelHeaderHeight: CGFloat = 32
        static let sourcePanelWidth: CGFloat = 196
        static let slotRowGap: CGFloat = 9
        static let contentMaxWidth: CGFloat = 720
        static let labelColumn: CGFloat = 132
        static let fieldHeight: CGFloat = 28
        static let actionButton: CGFloat = 148
        static let compactButton: CGFloat = 86
        static let triggerPicker: CGFloat = 136
        static let ruleControl: CGFloat = 224
        static let segmentedControl: CGFloat = 318
    }
}

typealias CmdIMEDesign = DesignTokens

struct SlotLook {
    var slots: [SwitchSlot] = SwitchSlot.legacyDefaults

    func tint(for role: InputRole) -> Color {
        slots.first { $0.id == role }.flatMap { Color(cmdIMEHex: $0.tintHex) }
            ?? DesignTokens.Colors.role(role)
    }

    func name(for role: InputRole) -> String {
        slots.first { $0.id == role }?.name ?? role.rawValue
    }
}

private struct SlotLookKey: EnvironmentKey {
    static let defaultValue = SlotLook()
}

extension EnvironmentValues {
    var slotLook: SlotLook {
        get { self[SlotLookKey.self] }
        set { self[SlotLookKey.self] = newValue }
    }
}

struct SectionCard<Content: View>: View {
    private let title: String?
    private let detail: String?
    private let padding: CGFloat
    private let content: Content

    init(
        _ title: String? = nil,
        detail: String? = nil,
        padding: CGFloat = DesignTokens.Spacing.md,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.detail = detail
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
            if title != nil || detail != nil {
                VStack(alignment: .leading, spacing: 3) {
                    if let title {
                        Text(title)
                            .font(.headline.weight(.semibold))
                            .foregroundStyle(DesignTokens.Colors.textPrimary)
                    }
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(DesignTokens.Colors.textMuted)
                    }
                }
            }

            content
        }
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                    .fill(DesignTokens.Colors.surfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.card, style: .continuous)
                            .stroke(DesignTokens.Colors.separator, lineWidth: 1)
                    )
                    .shadow(color: DesignTokens.Shadow.surface, radius: 18, y: 10)
            )
    }
}

struct SettingsSectionHeader: View {
    let eyebrow: String
    let title: String
    let detail: String?

    init(_ title: String, eyebrow: String, detail: String? = nil) {
        self.eyebrow = eyebrow
        self.title = title
        self.detail = detail
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.xs) {
            Text(eyebrow.uppercased())
                .font(.caption.weight(.bold))
                .monospaced()
                .tracking(1.4)
                .foregroundStyle(DesignTokens.Colors.textMuted)

            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(DesignTokens.Colors.textPrimary)

            if let detail {
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
        }
    }
}

struct KeycapView: View {
    enum Appearance {
        case display
        case control
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.slotLook) private var slotLook

    let label: String
    var detail: String?
    var role: InputRole?
    var isPressed = false
    var isBound = true
    var appearance: Appearance = .control
    var expandsHorizontally = false

    init(_ label: String, detail: String? = nil, role: InputRole? = nil, isPressed: Bool = false,
         isBound: Bool = true, appearance: Appearance = .control, expandsHorizontally: Bool = false) {
        self.label = label
        self.detail = detail
        self.role = role
        self.isPressed = isPressed
        self.isBound = isBound
        self.appearance = appearance
        self.expandsHorizontally = expandsHorizontally
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DesignTokens.Typography.body.monospaced().weight(.semibold))
            if let detail {
                Text(detail)
                    .font(DesignTokens.Typography.auxiliary.monospaced().weight(.semibold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .padding(.top, 2)
            }
        }
            .foregroundStyle(foregroundColor)
            .frame(minWidth: 42, maxWidth: expandsHorizontally ? .infinity : nil, minHeight: 30)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                    .fill(appearance == .display ? AnyShapeStyle(DesignTokens.Colors.surfaceInset) : AnyShapeStyle(keycapFill))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                            .stroke(borderColor, lineWidth: isBound ? 1.2 : 1)
                    )
            )
            .shadow(color: appearance == .display ? .clear : glowColor,
                    radius: isPressed ? 10 : 4, y: isPressed ? 1 : 3)
            .scaleEffect(appearance == .display || reduceMotion ? 1 : (isPressed ? 0.94 : 1))
            .offset(y: appearance == .display || reduceMotion ? 0 : (isPressed ? 1 : 0))
            .animation(appearance == .display ? nil : (isPressed ? DesignTokens.Motion.keyPress : DesignTokens.Motion.keyRelease),
                       value: isPressed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityValue(isPressed ? "Active" : (isBound ? "Bound" : "Unbound"))
    }

    private var accent: Color {
        role.map { slotLook.tint(for: $0) } ?? DesignTokens.Colors.accent
    }

    private var foregroundColor: Color {
        if isPressed || isBound {
            return role == nil ? DesignTokens.Colors.textPrimary : accent
        }
        return DesignTokens.Colors.textMuted
    }

    private var keycapFill: LinearGradient {
        let top = isPressed ? accent.opacity(0.34) : DesignTokens.Colors.keycapTop
        let bottom = isPressed ? accent.opacity(0.18) : DesignTokens.Colors.keycapBottom
        return LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
    }

    private var borderColor: Color {
        guard isBound else {
            return DesignTokens.Colors.separator
        }
        return isPressed ? accent.opacity(0.64) : (role.map { slotLook.tint(for: $0).opacity(0.44) } ?? DesignTokens.Colors.separatorStrong)
    }

    private var glowColor: Color {
        isPressed ? accent.opacity(0.38) : DesignTokens.Shadow.keycap
    }

    private var accessibilityLabelText: String {
        let keyText = [readableKeyName(label), detail].compactMap(\.self).joined(separator: " ")
        if let role {
            return "\(slotLook.name(for: role)) key \(keyText)"
        }
        return "Key \(keyText)"
    }

    private func readableKeyName(_ value: String) -> String {
        switch value {
        case "⌘":
            "Command"
        case "⌥":
            "Option"
        case "⌃":
            "Control"
        case "⇧":
            "Shift"
        default:
            value
        }
    }
}

struct RoleBadge: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.slotLook) private var slotLook

    let role: InputRole
    let symbol: String
    var size: CGFloat = 36
    var isActive = false

    init(role: InputRole, symbol: String? = nil, size: CGFloat = 36, isActive: Bool = false) {
        self.role = role
        self.symbol = symbol ?? role.defaultSymbol
        self.size = size
        self.isActive = isActive
    }

    var body: some View {
        Text(symbol)
            .font(.system(size: size * 0.48, weight: .semibold))
            .foregroundStyle(slotLook.tint(for: role))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(slotLook.tint(for: role).opacity(isActive ? 0.24 : 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .stroke(slotLook.tint(for: role).opacity(isActive ? 0.72 : 0.42), lineWidth: 1)
                    )
            )
            .shadow(color: slotLook.tint(for: role).opacity(isActive ? 0.28 : 0), radius: 12, y: 4)
            .scaleEffect(reduceMotion ? 1 : (isActive ? 1.02 : 1))
            .animation(DesignTokens.Motion.stateChange, value: isActive)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(slotLook.name(for: role)) role")
            .accessibilityValue(isActive ? "Last switched" : "Available")
    }
}

struct StatusPill: View {
    let text: String
    let systemImage: String
    var tone: Tone = .success

    enum Tone: Equatable {
        case success
        case warning
        case danger
        case neutral

        var color: Color {
            switch self {
            case .success:
                DesignTokens.Colors.success
            case .warning:
                DesignTokens.Colors.warning
            case .danger:
                DesignTokens.Colors.danger
            case .neutral:
                DesignTokens.Colors.textMuted
            }
        }
    }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.xs) {
            Image(systemName: systemImage)
                .font(.caption.weight(.bold))
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .foregroundStyle(tone.color)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .padding(.vertical, DesignTokens.Spacing.xs)
        .background(
            Capsule(style: .continuous)
                .fill(tone.color.opacity(0.14))
                .overlay(
                    Capsule(style: .continuous)
                        .stroke(tone.color.opacity(0.28), lineWidth: 1)
                )
        )
        .animation(DesignTokens.Motion.stateChange, value: text)
        .animation(DesignTokens.Motion.stateChange, value: systemImage)
        .animation(DesignTokens.Motion.stateChange, value: tone)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// Native menu semantics with chrome outside the label: macOS may flatten menu labels.
/// The native control stays opaque so its keyboard handling/focus ring is not dimmed.
/// The decorative chevron never intercepts clicks. Full-frame label/content shapes request
/// a rectangular target; exact native hit testing and focus drawing still need macOS QA.
struct ConsoleMenuButton<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    @State private var isOpen = false

    private let title: String
    private let valueLabel: AnyView?
    private let systemImage: String?
    private let tint: Color
    private let warning: Bool
    private let showsChevron: Bool
    private let content: Content

    init(
        title: String,
        valueLabel: AnyView? = nil,
        systemImage: String? = nil,
        tint: Color = DesignTokens.Colors.accent,
        warning: Bool = false,
        showsChevron: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.valueLabel = valueLabel
        self.systemImage = systemImage
        self.tint = tint
        self.warning = warning
        self.showsChevron = showsChevron
        self.content = content()
    }

    private var effectiveTint: Color { warning ? DesignTokens.Colors.warning : tint }

    var body: some View {
        HStack(spacing: DesignTokens.Spacing.sm) {
            if let systemImage {
                Image(systemName: systemImage).fixedSize()
            }
            if let valueLabel {
                valueLabel
            } else if !title.isEmpty {
                Text(title)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 12)
                    .fixedSize()
                    .foregroundStyle(isEnabled && isHovered ? effectiveTint : DesignTokens.Colors.textMuted)
            }
        }
        .font(DesignTokens.Typography.body.weight(.semibold))
        .foregroundStyle(isEnabled ? (warning ? effectiveTint : DesignTokens.Colors.textPrimary) : DesignTokens.Colors.textMuted)
        .padding(.horizontal, DesignTokens.Spacing.sm)
        .frame(minHeight: DesignTokens.Layout.fieldHeight)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .background {
            ConsoleControlChrome(tint: effectiveTint, highlighted: isEnabled && isHovered, warning: warning)
        }
        .overlay {
            // A plain button over the whole field, opening the choices in a popover. A SwiftUI
            // `Menu` here only reacted to clicks on part of the field, and not at all in some
            // window states, so users saw a control that sometimes would not open.
            Button { isOpen.toggle() } label: { Color.clear.contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel(title)
                .accessibilityAddTraits(.isButton)
                .appearancePopover(isPresented: $isOpen, arrowEdge: .bottom) {
                    VStack(alignment: .leading, spacing: 1) { content }
                        .buttonStyle(ConsoleMenuRowStyle())
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.Colors.textPrimary)
                        .padding(6)
                        .frame(minWidth: 220, alignment: .leading)
                        .background(DesignTokens.Colors.surfaceRaised)
                        // Any choice closes the list, as a menu would.
                        .simultaneousGesture(TapGesture().onEnded { isOpen = false })
                }
        }
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.quickFade, reduceMotion: reduceMotion), value: isHovered)
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion), value: warning)
    }
}

/// One choice in a `ConsoleMenuButton` list: full-width, left-aligned, highlighted on hover.
struct ConsoleMenuRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ConsoleMenuRow(configuration: configuration)
    }
}

private struct ConsoleMenuRow: View {
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false
    let configuration: ButtonStyleConfiguration

    var body: some View {
        configuration.label
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .foregroundStyle(isEnabled
                ? (configuration.role == .destructive ? DesignTokens.Colors.danger : DesignTokens.Colors.textPrimary)
                : DesignTokens.Colors.textMuted.opacity(0.6))
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(isEnabled && (isHovered || configuration.isPressed) ? DesignTokens.Colors.actionFill.opacity(0.85) : .clear))
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
    }
}

/// Compact, color-only feedback for badge/refresh buttons; leaves activation to Button.
struct ConsoleControlButtonStyle: ButtonStyle {
    var tint: Color = DesignTokens.Colors.accent
    var warning: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        ConsoleControlButtonBody(configuration: configuration, tint: tint, warning: warning)
    }
}

private struct ConsoleControlButtonBody: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    @State private var isHovered = false

    let configuration: ButtonStyleConfiguration
    let tint: Color
    let warning: Bool

    private var effectiveTint: Color { warning ? DesignTokens.Colors.warning : tint }

    var body: some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(isEnabled ? effectiveTint : DesignTokens.Colors.textMuted)
            .padding(.horizontal, DesignTokens.Spacing.xs)
            .frame(minWidth: DesignTokens.Layout.fieldHeight, minHeight: DesignTokens.Layout.fieldHeight)
            .background {
                ConsoleControlChrome(
                    tint: effectiveTint,
                    highlighted: isEnabled && (isHovered || configuration.isPressed),
                    warning: warning,
                    pressed: isEnabled && configuration.isPressed
                )
            }
            .contentShape(Rectangle())
            .onHover { isHovered = $0 }
            .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.quickFade, reduceMotion: reduceMotion), value: isHovered)
            .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion), value: configuration.isPressed)
            .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion), value: warning)
    }
}

private struct ConsoleControlChrome: View {
    let tint: Color
    let highlighted: Bool
    let warning: Bool
    var pressed = false

    var body: some View {
        RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
            .fill(highlighted ? DesignTokens.Colors.surfaceRaised : DesignTokens.Colors.surfaceInset)
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                    .fill(tint.opacity(pressed ? 0.18 : 0))
            }
            .overlay {
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                    .stroke(highlighted ? tint : (warning ? tint.opacity(0.5) : DesignTokens.Colors.separatorStrong), lineWidth: 1)
            }
            .allowsHitTesting(false)
    }
}

struct ConsoleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        ConsoleButtonBody(configuration: configuration, prominent: prominent)
    }
}

private struct ConsoleButtonBody: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPointerInside = false
    let configuration: ButtonStyleConfiguration
    let prominent: Bool

    private var isPressed: Bool { isEnabled && configuration.isPressed }
    private var isHovered: Bool { isEnabled && isPointerInside }
    private var usesProminentFill: Bool { prominent && configuration.role != .destructive }

    private var foreground: Color {
        if !isEnabled { return DesignTokens.Colors.textMuted.opacity(0.55) }
        if configuration.role == .destructive {
            return DesignTokens.Colors.destructiveText
        }
        return usesProminentFill ? .white : DesignTokens.Colors.textPrimary
    }

    private var fill: Color {
        if usesProminentFill { return DesignTokens.Colors.actionFill.opacity(isEnabled ? 1 : 0.28) }
        return DesignTokens.Colors.overlay(!isEnabled ? 0.035 : (isPressed ? 0.11 : (isHovered ? 0.095 : 0.07)))
    }

    var body: some View {
        configuration.label
            .font(DesignTokens.Typography.body.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                    .fill(fill)
                    .overlay {
                        if usesProminentFill && isEnabled {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                                .fill(isPressed ? Color.black.opacity(0.10) : DesignTokens.Colors.overlay(isHovered ? 0.04 : 0))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                            .stroke(DesignTokens.Colors.overlay(isEnabled ? 0.12 : 0.05), lineWidth: 1)
                    )
            )
            // Leave focus and activation to the enclosing native Button.
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(isEnabled && !reduceMotion ? DesignTokens.Motion.keyPress : nil, value: isPressed)
            .animation(isEnabled ? DesignTokens.Motion.stateChange : nil, value: isHovered)
            .onHover { isPointerInside = $0 }
    }
}

extension InputRole {
    var defaultSymbol: String {
        switch self {
        case .english:
            "A"
        case .chinese:
            "中"
        case .japanese:
            "あ"
        default:
            String(rawValue.prefix(1)).uppercased()
        }
    }
}


// MARK: - Window material and floating surfaces

/// The system material behind the whole settings window, so the desktop shows through a little.
struct WindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .sidebar
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

extension View {
    /// The bars that float above the content (status, update): Liquid Glass on macOS 26 and later,
    /// the translucent surface before that, and an opaque one with Reduce Transparency.
    @ViewBuilder
    func floatingBarSurface() -> some View {
        let shape = RoundedRectangle(cornerRadius: DesignTokens.Radius.surface)
        if #available(macOS 26.0, *), !DesignTokens.Colors.isOpaque {
            glassEffect(.regular, in: shape)
        } else {
            background(shape.fill(DesignTokens.Colors.surface))
        }
    }
}


// MARK: - Appearance in popovers

/// Applies General > Appearance to whatever window hosts it. A popover is its own window and
/// ignores the settings window's appearance, so each one carries this too.
///
/// This sets `NSWindow.appearance` rather than SwiftUI's `preferredColorScheme`: passing nil to
/// that modifier does not undo an earlier light or dark, so "System" never came back.
private struct WindowAppearanceSetter: NSViewRepresentable {
    let preference: AppearancePreference

    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ nsView: NSView, context: Context) {
        let appearance = preference.nsAppearance
        // The view joins its window after this call, so apply on the next turn as well.
        nsView.window?.appearance = appearance
        DispatchQueue.main.async { nsView.window?.appearance = appearance }
    }
}

private struct AppearanceFollower: ViewModifier {
    @AppStorage(AppearancePreference.defaultsKey) private var stored = AppearancePreference.system.rawValue

    func body(content: Content) -> some View {
        content.background(WindowAppearanceSetter(preference: AppearancePreference(rawValue: stored) ?? .system))
    }
}

extension View {
    /// `popover` whose content follows General > Appearance.
    /// Makes the hosting window follow General > Appearance, including a return to "System".
    func followsAppearancePreference() -> some View { modifier(AppearanceFollower()) }

    func appearancePopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .top,
                                          @ViewBuilder content: @escaping () -> Content) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) { content().modifier(AppearanceFollower()) }
    }
}
