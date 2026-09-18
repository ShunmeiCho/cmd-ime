import SwiftUI

/// Selected state of every swatch, chip and theme cell in the indicator settings: a
/// fixed high-contrast ring with a gap plus a checkmark badge. The option's own
/// colour is never used for the ring or a glow, so a dark or pale option still
/// shows that it is selected.
struct SelectionRing: ViewModifier {
    static let ringWidth: CGFloat = 2
    static let ringGap: CGFloat = 2
    static let badgeSize: CGFloat = 13

    let isSelected: Bool
    let cornerRadius: CGFloat
    var showsBadge = true

    func body(content: Content) -> some View {
        let outset = Self.ringGap + Self.ringWidth
        content
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: cornerRadius + outset, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.textPrimary, lineWidth: Self.ringWidth)
                        .padding(-outset)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelected, showsBadge {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: Self.badgeSize, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(Color.white, DesignTokens.Colors.actionFill)
                        .background(Circle().fill(DesignTokens.Colors.surfaceRaised).padding(1))
                        .offset(x: outset + 2, y: -(outset + 2))
                        .accessibilityHidden(true)
                }
            }
    }
}

extension View {
    func selectionRing(_ isSelected: Bool, cornerRadius: CGFloat, showsBadge: Bool = true) -> some View {
        modifier(SelectionRing(isSelected: isSelected, cornerRadius: cornerRadius, showsBadge: showsBadge))
    }
}

/// A colour option: the swatch, the fixed selection affordance, a name for assistive tech.
struct IndicatorSwatchButton: View {
    static let size: CGFloat = 20
    static let cornerRadius: CGFloat = 5

    let color: Color
    let name: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
                        .strokeBorder(DesignTokens.Colors.separatorStrong, lineWidth: 1)
                )
                .frame(width: Self.size, height: Self.size)
                .selectionRing(isSelected, cornerRadius: Self.cornerRadius)
                .padding(SelectionRing.ringGap + SelectionRing.ringWidth)
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
