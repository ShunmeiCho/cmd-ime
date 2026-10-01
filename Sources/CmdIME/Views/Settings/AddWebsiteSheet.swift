import KeyboardSwitcherCore
import SwiftUI

/// The Add Website sheet of the rule board: a domain, whether its subdomains count, and the lane.
/// What is typed is reduced to a domain by core `WebsiteHost.normalized`; nothing is read from a
/// browser.
struct AddWebsiteSheet: View {
    @ObservedObject var model: AppModel
    /// The lanes a website can be added to: every existing slot and "Keep as is".
    let lanes: [AppRuleBoard.Lane]
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    /// Nil until the user flips the switch; until then it follows what was typed.
    @State private var subdomainsChoice: Bool?
    /// Nil until the user picks a lane; until then the first one.
    @State private var chosenTarget: AppRuleTarget?

    private static let width: CGFloat = 360
    private static let padding: CGFloat = 16
    private static let domainExample = "example.com"

    var body: some View {
        let look = AppRuleLaneLook(config: model.config)
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("Add Website")
                .font(DesignTokens.Typography.title)
            TextField(text: $input, prompt: Text(verbatim: Self.domainExample)) { Text("Domain") }
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .accessibilityLabel("Domain")
                .onSubmit(add)
            Text(status)
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(isRefused ? DesignTokens.Colors.warning : DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("Include subdomains")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Toggle("Include subdomains", isOn: Binding(
                    get: { includesSubdomains }, set: { subdomainsChoice = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(DesignTokens.Colors.success)
                .controlSize(.small)
                .disabled(!canHaveSubdomains)
            }
            HStack {
                Text("Slot")
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Picker("Slot", selection: Binding(get: { target }, set: { chosenTarget = $0 })) {
                    ForEach(lanes, id: \.target) { lane in
                        Text(look.title(lane)).tag(lane.target)
                    }
                }
                .labelsHidden()
                .fixedSize()
            }
            HStack {
                Spacer(minLength: DesignTokens.Layout.rowGap)
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Add", action: add)
                    .buttonStyle(ConsoleButtonStyle(prominent: true))
                    .keyboardShortcut(.defaultAction)
                    .disabled(normalized == nil)
            }
        }
        .padding(Self.padding)
        .frame(width: Self.width)
        .buttonStyle(ConsoleButtonStyle())
        .font(DesignTokens.Typography.body)
        .foregroundStyle(DesignTokens.Colors.textPrimary)
    }

    private var normalized: (domain: String, includesSubdomains: Bool)? {
        WebsiteHost.normalized(userInput: input)
    }

    private var isEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Something was typed and it is not a website.
    private var isRefused: Bool { !isEmpty && normalized == nil }

    /// An IP address has no subdomains (`WebsiteHost.normalized` says so).
    private var canHaveSubdomains: Bool { normalized?.includesSubdomains ?? true }

    private var includesSubdomains: Bool { canHaveSubdomains && (subdomainsChoice ?? true) }

    private var target: AppRuleTarget {
        chosenTarget ?? lanes.first?.target ?? .keepAsIs
    }

    /// The domain the rule will be saved for, or why there is none yet.
    private var status: String {
        guard let normalized else {
            return isEmpty
                ? String(localized: "Type a domain such as \(Self.domainExample), or paste a page address.")
                : String(localized: "That is not a website.")
        }
        return includesSubdomains
            ? String(localized: "\(normalized.domain) and its subdomains")
            : String(localized: "\(normalized.domain) only")
    }

    private func add() {
        guard let normalized else { return }
        model.setWebsiteRule(WebsiteRule(domain: normalized.domain, includesSubdomains: includesSubdomains, target: target))
        dismiss()
    }
}
