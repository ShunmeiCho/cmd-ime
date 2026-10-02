import KeyboardSwitcherCore
import SwiftUI

/// One program with a rule (CONTEXT.md, Program Rule). Its options button (a menu reachable with
/// Tab), its right-click menu, the close button and the accessibility actions move or remove it.
struct ProgramRuleChip: View {
    @ObservedObject var model: AppModel
    let rule: ProgramRule
    /// Where it can be moved.
    let lanes: [AppRuleBoard.Lane]

    var body: some View {
        HStack(spacing: 5) {
            label
            Menu {
                actions
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Move or remove")
            .accessibilityLabel("Options for \(rule.name)")
            Button {
                model.removeProgramRule(for: rule.name)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
            .accessibilityLabel("Remove the rule for \(rule.name)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(DesignTokens.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(DesignTokens.Colors.separator, lineWidth: 1))
        .opacity(model.config.programRulesPaused ? Self.pausedOpacity : 1)
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
    }

    private static let pausedOpacity = 0.5

    /// Terminal glyph and the program's name: one accessibility element carrying the same actions
    /// as the menu.
    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "terminal")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityHidden(true)
            Text(verbatim: rule.name)
                .font(DesignTokens.Typography.body.monospaced())
                .lineLimit(1)
        }
        .help(rule.name)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(rule.name)
        .accessibilityActions { accessibilityActions }
    }

    @ViewBuilder
    private var actions: some View {
        let look = AppRuleLaneLook(config: model.config)
        Menu("Move To") {
            ForEach(lanes.filter { $0.target != rule.target }, id: \.target) { lane in
                Button(look.title(lane)) { move(to: lane.target) }
            }
        }
        Divider()
        Button("Remove Rule") { model.removeProgramRule(for: rule.name) }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        let look = AppRuleLaneLook(config: model.config)
        ForEach(lanes.filter { $0.target != rule.target }, id: \.target) { lane in
            Button("Move to \(look.title(lane))") { move(to: lane.target) }
        }
        Button("Remove rule") { model.removeProgramRule(for: rule.name) }
    }

    private func move(to target: AppRuleTarget) {
        model.setProgramRule(ProgramRule(name: rule.name, target: target))
    }
}
