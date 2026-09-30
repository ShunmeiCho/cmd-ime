import KeyboardSwitcherCore
import SwiftUI

/// What a lane is called and coloured, shared by the lanes and the menus that move apps into them.
struct AppRuleLaneLook {
    let config: SwitcherConfig

    func title(_ lane: AppRuleBoard.Lane) -> String {
        switch lane.target {
        case .keepAsIs: "Keep as is"
        case .slot(let id): lane.slotExists ? config.displayName(for: id) : "Slot deleted"
        }
    }

    func tint(_ lane: AppRuleBoard.Lane) -> Color {
        switch lane.target {
        case .keepAsIs: DesignTokens.Colors.textMuted
        case .slot(let id): lane.slotExists ? SlotLook(slots: config.slots).tint(for: id) : DesignTokens.Colors.warning
        }
    }

    /// The lanes an app can be moved to: every existing slot and "Keep as is".
    func destinations(_ lanes: [AppRuleBoard.Lane]) -> [AppRuleBoard.Lane] {
        lanes.filter(\.slotExists)
    }
}

/// One slot, or "Keep as is": a drop target holding the apps whose rule points here.
struct AppRuleLane: View {
    @ObservedObject var model: AppModel
    let lane: AppRuleBoard.Lane
    let lanes: [AppRuleBoard.Lane]
    @State private var isTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var look: AppRuleLaneLook { AppRuleLaneLook(config: model.config) }

    var body: some View {
        let tint = look.tint(lane)
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: lane.target == .keepAsIs ? "minus.circle" : "circle.fill")
                    .font(.system(size: lane.target == .keepAsIs ? 10 : 7))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
                Text(look.title(lane))
                    .font(DesignTokens.Typography.body.weight(.semibold))
                Spacer(minLength: DesignTokens.Layout.rowGap)
                if !lane.rules.isEmpty {
                    Text("\(lane.rules.count)")
                        .font(DesignTokens.Typography.auxiliary.monospacedDigit())
                        .foregroundStyle(DesignTokens.Colors.textMuted)
                }
            }
            if lane.rules.isEmpty {
                Text(placeholder)
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            } else {
                TriggerKeycapFlow(spacing: 6) {
                    ForEach(lane.rules, id: \.appID) { rule in
                        AppRuleChip(model: model, rule: rule, lanes: look.destinations(lanes))
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .fill(isTargeted ? tint.opacity(0.14) : DesignTokens.Colors.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Radius.control, style: .continuous)
                .strokeBorder(isTargeted ? tint.opacity(0.70) : DesignTokens.Colors.separator, lineWidth: 1)
        )
        .animation(DesignTokens.Motion.resolved(DesignTokens.Motion.stateChange, reduceMotion: reduceMotion), value: isTargeted)
        .onDrop(of: AppDropReader.types, isTargeted: $isTargeted) { providers in
            let target = lane.target
            return AppDropReader.read(providers) { [model] id, name in
                model.dropApp(appID: id, name: name, on: target)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(look.title(lane))
    }

    private var placeholder: String {
        if !lane.slotExists { return "Move these apps to another slot." }
        return lane.target == .keepAsIs ? "Drop apps here to leave their input source alone." : "Drop apps here."
    }
}

/// One app with a rule. Drag it to another lane or back to the app list; its menu, the close
/// button and the accessibility actions do the same without dragging.
struct AppRuleChip: View {
    @ObservedObject var model: AppModel
    let rule: AppRule
    /// Where it can be moved.
    let lanes: [AppRuleBoard.Lane]

    var body: some View {
        let app = InstalledApp(id: rule.appID, fallbackName: rule.name)
        let look = AppRuleLaneLook(config: model.config)
        HStack(spacing: 5) {
            Image(nsImage: app.icon)
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(app.name)
                .lineLimit(1)
                .foregroundStyle(app.isInstalled ? DesignTokens.Colors.textPrimary : DesignTokens.Colors.textMuted)
            if rule.rememberInstead {
                Image(systemName: "clock.arrow.circlepath")
                    .font(DesignTokens.Typography.auxiliary)
                    .foregroundStyle(DesignTokens.Colors.textSecondary)
                    .help("Remember: brings back the input source you last used here; the slot is used only the first time.")
            }
            Button {
                model.removeAppRule(for: rule.appID)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DesignTokens.Colors.textMuted)
            }
            .buttonStyle(.borderless)
            .help("Remove this rule")
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(DesignTokens.Colors.surfaceRaised))
        .overlay(Capsule().strokeBorder(DesignTokens.Colors.separator, lineWidth: 1))
        .help(app.isInstalled ? app.name : "\(app.name) is not installed")
        .onDrag { AppDropReader.provider(appID: rule.appID, name: app.name) }
        .contextMenu {
            Menu("Move To") {
                ForEach(lanes.filter { $0.target != rule.target }, id: \.target) { lane in
                    Button(look.title(lane)) { model.dropApp(appID: rule.appID, name: nil, on: lane.target) }
                }
            }
            if case .slot = rule.target {
                Toggle("Remember", isOn: rememberBinding)
            }
            Divider()
            Button("Remove Rule") { model.removeAppRule(for: rule.appID) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(app: app))
        .accessibilityActions {
            ForEach(lanes.filter { $0.target != rule.target }, id: \.target) { lane in
                Button("Move to \(look.title(lane))") { model.dropApp(appID: rule.appID, name: nil, on: lane.target) }
            }
            if case .slot = rule.target {
                Button(rule.rememberInstead ? "Stop remembering" : "Remember") { rememberBinding.wrappedValue.toggle() }
            }
            Button("Remove rule") { model.removeAppRule(for: rule.appID) }
        }
    }

    private var rememberBinding: Binding<Bool> {
        Binding(
            get: { rule.rememberInstead },
            set: { remember in
                var next = rule
                next.rememberInstead = remember
                model.setAppRule(next)
            }
        )
    }

    private func accessibilityLabel(app: InstalledApp) -> String {
        var parts = [app.name]
        if rule.rememberInstead { parts.append("remember") }
        if !app.isInstalled { parts.append("not installed") }
        return parts.joined(separator: ", ")
    }
}
