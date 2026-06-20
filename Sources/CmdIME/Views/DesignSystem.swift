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
        static let textMuted = Color(red: 0.52, green: 0.52, blue: 0.56)
        static let accent = Color(red: 0.21, green: 0.48, blue: 0.90)
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
            }
        }
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let label: String
    var detail: String?
    var role: InputRole?
    var isPressed = false
    var isBound = true

    init(_ label: String, detail: String? = nil, role: InputRole? = nil, isPressed: Bool = false, isBound: Bool = true) {
        self.label = label
        self.detail = detail
        self.role = role
        self.isPressed = isPressed
        self.isBound = isBound
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(.callout, design: .monospaced).weight(.semibold))
            if let detail {
                Text(detail)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
                    .padding(.top, 2)
            }
        }
            .foregroundStyle(foregroundColor)
            .frame(minWidth: 42, minHeight: 30)
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                    .fill(keycapFill)
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.keycap, style: .continuous)
                            .stroke(borderColor, lineWidth: isBound ? 1.2 : 1)
                    )
            )
            .shadow(color: glowColor, radius: isPressed ? 10 : 4, y: isPressed ? 1 : 3)
            .scaleEffect(reduceMotion ? 1 : (isPressed ? 0.94 : 1))
            .offset(y: reduceMotion ? 0 : (isPressed ? 1 : 0))
            .animation(isPressed ? DesignTokens.Motion.keyPress : DesignTokens.Motion.keyRelease, value: isPressed)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabelText)
            .accessibilityValue(isPressed ? "Active" : (isBound ? "Bound" : "Unbound"))
    }

    private var accent: Color {
        role.map(DesignTokens.Colors.role) ?? DesignTokens.Colors.accent
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
        return isPressed ? accent.opacity(0.64) : (role.map { DesignTokens.Colors.role($0).opacity(0.44) } ?? DesignTokens.Colors.separatorStrong)
    }

    private var glowColor: Color {
        isPressed ? accent.opacity(0.38) : DesignTokens.Shadow.keycap
    }

    private var accessibilityLabelText: String {
        let keyText = [readableKeyName(label), detail].compactMap(\.self).joined(separator: " ")
        if let role {
            return "\(role.displayName) key \(keyText)"
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
            .foregroundStyle(DesignTokens.Colors.role(role))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                    .fill(DesignTokens.Colors.role(role).opacity(isActive ? 0.24 : 0.16))
                    .overlay(
                        RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                            .stroke(DesignTokens.Colors.role(role).opacity(isActive ? 0.72 : 0.42), lineWidth: 1)
                    )
            )
            .shadow(color: DesignTokens.Colors.role(role).opacity(isActive ? 0.28 : 0), radius: 12, y: 4)
            .scaleEffect(reduceMotion ? 1 : (isActive ? 1.02 : 1))
            .animation(DesignTokens.Motion.stateChange, value: isActive)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(role.displayName) role")
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

struct ConsoleButtonStyle: ButtonStyle {
    var prominent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.caption.weight(.semibold))
            .foregroundStyle(prominent ? Color.white : DesignTokens.Colors.textPrimary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                    .fill(prominent ? DesignTokens.Colors.accent : Color.white.opacity(configuration.isPressed ? 0.11 : 0.07))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                            .stroke(Color.white.opacity(prominent ? 0.10 : 0.12), lineWidth: 1)
                    )
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(DesignTokens.Motion.keyPress, value: configuration.isPressed)
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
        }
    }

    var displayName: String {
        switch self {
        case .english:
            "English"
        case .chinese:
            "Chinese"
        case .japanese:
            "Japanese"
        }
    }
}
