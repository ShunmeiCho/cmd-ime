import Foundation
import KeyboardSwitcherCore

/// Config-only Program Rule edits. This command never queries or switches a terminal pane.
extension CLI {
    private static let programRuleUsage = "Usage: keyboardctl program-rule list | set <name> <slot|keep> | remove <name>"

    func manageProgramRule() throws {
        let store = ConfigStore(url: configURL)
        switch try argument(at: 1, name: "list, set or remove") {
        case "list":
            guard args.count == 2 else { throw CLIError.invalidArgument(Self.programRuleUsage) }
            let config = try loadConfig(from: store)
            guard !config.programRules.isEmpty else {
                print("No program rules. Add one with \"keyboardctl program-rule set <name> <slot|keep>\".")
                return
            }
            print("name\ttarget")
            for rule in config.programRules {
                print("\(rule.name)\t\(targetDescription(rule.target, in: config))")
            }
        case "set":
            guard args.count == 4 else { throw CLIError.invalidArgument(Self.programRuleUsage) }
            let typed = try argument(at: 2, name: "name")
            guard let name = ProgramName.normalized(userInput: typed) else {
                throw CLIError.invalidArgument("\(typed) is not a program name. Give a name of at most 64 characters, without a path or arguments.")
            }
            let config = try loadConfig(from: store)
            let query = try argument(at: 3, name: "slot or keep")
            let target: AppRuleTarget = query == Self.keepWord
                ? .keepAsIs
                : .slot(try requireSlot(query, in: config).id)
            try save(config.setting(ProgramRule(name: name, target: target)), to: store)
            print("\(name): \(targetDescription(target, in: config))")
        case "remove":
            guard args.count == 3 else { throw CLIError.invalidArgument(Self.programRuleUsage) }
            let typed = try argument(at: 2, name: "name")
            // Also permit removal of a non-normalized rule written by hand.
            let name = ProgramName.normalized(userInput: typed) ?? typed
            let config = try loadConfig(from: store)
            guard config.programRule(for: name) != nil else {
                throw CLIError.invalidArgument("No rule for \(name). Run \"keyboardctl program-rule list\".")
            }
            try save(config.removingProgramRule(for: name), to: store)
            print("Removed the rule for \(name)")
        case let operation:
            throw CLIError.unknownCommand("program-rule \(operation)")
        }
    }
}
