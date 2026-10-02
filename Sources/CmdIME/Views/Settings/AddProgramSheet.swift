import KeyboardSwitcherCore
import SwiftUI

/// The Add Program sheet of the rule board: the name a program is started with, and the lane.
/// What is typed is checked by core `ProgramName.normalized`; nothing is read from a terminal.
struct AddProgramSheet: View {
    @ObservedObject var model: AppModel
    /// The lanes a program can be added to: every existing slot and "Keep as is".
    let lanes: [AppRuleBoard.Lane]
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""
    /// Nil until the user picks a lane; until then the first one.
    @State private var chosenTarget: AppRuleTarget?

    private static let width: CGFloat = 360
    private static let padding: CGFloat = 16
    private static let nameExample = "claude"
    /// Names a tap fills in. They are suggestions, not rules: nothing exists until Add.
    private static let commonNames = ["zsh", "bash", "fish", "claude", "codex", "pi", "vim", "ssh"]

    var body: some View {
        let look = AppRuleLaneLook(config: model.config)
        VStack(alignment: .leading, spacing: DesignTokens.Layout.panelGap) {
            Text("Add Program")
                .font(DesignTokens.Typography.title)
            TextField(text: $input, prompt: Text(verbatim: Self.nameExample)) { Text("Program name") }
                .textFieldStyle(.roundedBorder)
                .font(DesignTokens.Typography.body.monospaced())
                .autocorrectionDisabled()
                .labelsHidden()
                .accessibilityLabel("Program name")
                .onSubmit(add)
            TriggerKeycapFlow(spacing: 6) {
                ForEach(Self.commonNames, id: \.self) { name in
                    Button { input = name } label: {
                        Text(verbatim: name).font(DesignTokens.Typography.auxiliary.monospaced())
                    }
                    .controlSize(.small)
                }
            }
            Text(status)
                .font(DesignTokens.Typography.auxiliary)
                .foregroundStyle(isRefused ? DesignTokens.Colors.warning : DesignTokens.Colors.textMuted)
                .fixedSize(horizontal: false, vertical: true)
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

    private var normalized: String? {
        ProgramName.normalized(userInput: input)
    }

    private var isEmpty: Bool {
        input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Something was typed and it is not a program name.
    private var isRefused: Bool { !isEmpty && normalized == nil }

    private var target: AppRuleTarget {
        chosenTarget ?? lanes.first?.target ?? .keepAsIs
    }

    /// What the rule will match, or why there is none yet.
    private var status: String {
        guard let normalized else {
            return isEmpty
                ? String(localized: "Type the command the program is started with, such as \(Self.nameExample). Upper and lower case count.")
                : String(localized: "A program name has no spaces and no slashes.")
        }
        return model.config.programRule(for: normalized) == nil
            ? String(localized: "Programs started as \(normalized)")
            : String(localized: "\(normalized) already has a rule; this replaces it.")
    }

    private func add() {
        guard let normalized else { return }
        model.setProgramRule(ProgramRule(name: normalized, target: target))
        dismiss()
    }
}
