import AppKit
import KeyboardSwitcherCore
import SwiftUI

enum DesignTokens {
    enum Colors {
        static let canvas = Color(red: 0.08, green: 0.08, blue: 0.095)
        static let surface = Color(red: 0.095, green: 0.095, blue: 0.11)
        static let surfaceRaised = Color(red: 0.135, green: 0.135, blue: 0.15)
        static let surfaceInset = Color(red: 0.070, green: 0.070, blue: 0.085)
        static let keycapTop = Color(red: 0.185, green: 0.185, blue: 0.215)
        static let keycapBottom = Color(red: 0.115, green: 0.115, blue: 0.135)
        static let separator = Color.white.opacity(0.07)
        static let separatorStrong = Color.white.opacity(0.12)
        static let textPrimary = Color(red: 0.96, green: 0.96, blue: 0.97)
        static let textSecondary = Color(red: 0.72, green: 0.72, blue: 0.76)
        static let textMuted = Color(red: 154 / 255, green: 154 / 255, blue: 163 / 255)
        static let accent = Color(red: 0.21, green: 0.48, blue: 0.90)
        static let actionFill = Color(red: 40 / 255, green: 104 / 255, blue: 199 / 255)
        static let success = Color(red: 0.27, green: 0.77, blue: 0.42)
        static let warning = Color(red: 0.77, green: 0.48, blue: 0.14)
        static let danger = Color(red: 0.89, green: 0.31, blue: 0.28)

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
            .font(.system(size: size * 0.48, weight: .semibold, design: .monospaced))
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

    private let title: String
    private let systemImage: String?
    private let tint: Color
    private let warning: Bool
    private let showsChevron: Bool
    private let content: Content

    init(
        title: String,
        systemImage: String? = nil,
        tint: Color = DesignTokens.Colors.accent,
        warning: Bool = false,
        showsChevron: Bool = true,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.warning = warning
        self.showsChevron = showsChevron
        self.content = content()
    }

    private var effectiveTint: Color { warning ? DesignTokens.Colors.warning : tint }

    var body: some View {
        Menu {
            content
        } label: {
            HStack(spacing: DesignTokens.Spacing.xs) {
                if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .lineLimit(1)
            }
            .font(.caption.weight(.semibold))
            .padding(.leading, DesignTokens.Spacing.sm)
            .padding(.trailing, showsChevron ? DesignTokens.Spacing.lg : DesignTokens.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: DesignTokens.Layout.fieldHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .foregroundStyle(isEnabled ? (warning ? effectiveTint : DesignTokens.Colors.textPrimary) : DesignTokens.Colors.textMuted)
        .frame(minHeight: DesignTokens.Layout.fieldHeight)
        .background {
            ConsoleControlChrome(tint: effectiveTint, highlighted: isEnabled && isHovered, warning: warning)
        }
        .overlay(alignment: .trailing) {
            if showsChevron {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(isEnabled && isHovered ? effectiveTint : DesignTokens.Colors.textMuted)
                    .padding(.trailing, DesignTokens.Spacing.sm)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.quickFade, reduceMotion: reduceMotion), value: isHovered)
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion), value: warning)
        .accessibilityLabel(title)
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
    @State private var isHovered = false
    let configuration: ButtonStyleConfiguration
    let prominent: Bool

    private var isPressed: Bool { isEnabled && configuration.isPressed }

    private var foreground: Color {
        if !isEnabled { return DesignTokens.Colors.textMuted.opacity(0.55) }
        return prominent ? .white : DesignTokens.Colors.textPrimary
    }

    private var fill: Color {
        if prominent { return DesignTokens.Colors.actionFill.opacity(isEnabled ? 1 : 0.28) }
        return Color.white.opacity(!isEnabled ? 0.035 : (isPressed ? 0.11 : (isHovered ? 0.095 : 0.07)))
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
                        if prominent && isEnabled {
                            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                                .fill(isPressed ? Color.black.opacity(0.10) : Color.white.opacity(isHovered ? 0.04 : 0))
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                            .stroke(Color.white.opacity(isEnabled ? 0.12 : 0.05), lineWidth: 1)
                    )
            )
            // Leave focus and activation to the enclosing native Button.
            .scaleEffect(isPressed && !reduceMotion ? 0.98 : 1)
            .animation(isEnabled && !reduceMotion ? DesignTokens.Motion.keyPress : nil, value: isPressed)
            .animation(isEnabled ? DesignTokens.Motion.stateChange : nil, value: isHovered)
            .onHover { isHovered = isEnabled && $0 }
            .onChange(of: isEnabled) { if !$0 { isHovered = false } }
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
