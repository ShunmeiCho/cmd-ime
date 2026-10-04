import KeyboardSwitcherCore
import SwiftUI

/// One website with a rule (CONTEXT.md, Website Rule). Drag it to another lane. Its options button
/// (a menu reachable with Tab), its right-click menu, the close button and the accessibility
/// actions do the same without dragging.
struct WebsiteRuleChip: View {
    @ObservedObject var model: AppModel
    let rule: WebsiteRule
    /// Where it can be moved.
    let lanes: [AppRuleBoard.Lane]

    /// What a rule covering subdomains shows before its domain, as the user would type it.
    private static let subdomainMark = "*."

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
            .accessibilityLabel("Options for \(rule.domain)")
            Button {
                model.removeWebsiteRule(for: rule.domain)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
            .accessibilityLabel("Remove the rule for \(rule.domain)")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(DesignTokens.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(DesignTokens.Colors.separator, lineWidth: 1))
        .onDrag { AppDropReader.provider(websiteDomain: rule.domain) }
        .contextMenu { actions }
        .accessibilityElement(children: .contain)
    }

    /// Globe, the subdomain mark and the domain: one accessibility element carrying the same
    /// actions as the menu.
    private var label: some View {
        HStack(spacing: 5) {
            Image(systemName: "globe")
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.Colors.textSecondary)
                .accessibilityHidden(true)
            HStack(spacing: 0) {
                if rule.includesSubdomains {
                    Text(verbatim: Self.subdomainMark)
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
                Text(verbatim: WebsiteHost.displayName(ofDomain: rule.domain))
            }
            .lineLimit(1)
        }
        .help(description)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(description)
        .accessibilityActions { accessibilityActions }
    }

    private var description: String {
        rule.includesSubdomains ? String(localized: "\(rule.domain) and its subdomains") : rule.domain
    }

    @ViewBuilder
    private var actions: some View {
        let look = AppRuleLaneLook(config: model.config)
        // A section, not a submenu: on macOS 27 the "Move To" submenu closed as the pointer moved
        // onto it, so none of its lanes could be chosen (owner, 0.18.0).
        Section("Move To") {
            ForEach(lanes.filter { $0.target != rule.target }, id: \.target) { lane in
                Button(look.title(lane)) { model.dropWebsite(domain: rule.domain, on: lane.target) }
            }
        }
        Divider()
        Button("Remove Rule") { model.removeWebsiteRule(for: rule.domain) }
    }

    @ViewBuilder
    private var accessibilityActions: some View {
        let look = AppRuleLaneLook(config: model.config)
        ForEach(lanes.filter { $0.target != rule.target }, id: \.target) { lane in
            Button("Move to \(look.title(lane))") { model.dropWebsite(domain: rule.domain, on: lane.target) }
        }
        Button("Remove rule") { model.removeWebsiteRule(for: rule.domain) }
    }
}
