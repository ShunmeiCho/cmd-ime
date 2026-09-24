import Foundation
import KeyboardSwitcherCore

#if os(macOS)
import AppKit
import Carbon
#endif

enum CLIError: Error, LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingArgument(String)
    case unknownSlot(String, available: [String])
    case invalidArgument(String)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            "Missing command."
        case let .unknownCommand(command):
            "Unknown command: \(command)."
        case let .missingArgument(argument):
            "Missing argument: \(argument)."
        case let .unknownSlot(query, available):
            "unknown slot \"\(query)\". Slots: \(available.joined(separator: ", ")). Run \"keyboardctl slots\"."
        case let .invalidArgument(message):
            message
        case .unsupportedPlatform:
            "keyboardctl currently supports macOS only."
        }
    }
}

/// A role's configured preference paired with the match `keyboardctl
/// diagnose` computed for it, via the same `InputSourceMatcher.match` the
/// switch pipeline uses.
private struct RoleDiagnosis {
    let slot: SwitchSlot
    let duplicateSlots: [String]
    let preference: RoleInputSourcePreference
    let result: InputSourceMatchResult
}

/// `--json` payload for `keyboardctl diagnose`.
private struct DiagnosisReport: Encodable {
    struct SlotEntry: Encodable {
        let slot: String
        let name: String
        let duplicateSlots: [String]
        let preferredIDs: [String]
        let fallbackLanguage: String?
        let languagePrefixes: [String]
        let nameContains: [String]
        let matchedSourceID: String?
        let matchedSourceName: String?
        let matchedSourceLanguages: [String]?
        let matchTier: String
        let matchedValue: String?
    }

    let currentInputSourceID: String?
    let currentInputSourceName: String?
    let slots: [SlotEntry]

    init(current: InputSourceInfo?, roles: [RoleDiagnosis]) {
        currentInputSourceID = current?.id
        currentInputSourceName = current?.localizedName
        slots = roles.map { diagnosis in
            SlotEntry(
                slot: diagnosis.slot.id.rawValue,
                name: diagnosis.slot.name,
                duplicateSlots: diagnosis.duplicateSlots,
                preferredIDs: diagnosis.preference.preferredIDs,
                fallbackLanguage: diagnosis.preference.fallbackLanguage,
                languagePrefixes: diagnosis.preference.languagePrefixes,
                nameContains: diagnosis.preference.nameContains,
                matchedSourceID: diagnosis.result.source?.id,
                matchedSourceName: diagnosis.result.source?.localizedName,
                matchedSourceLanguages: diagnosis.result.source?.languages,
                matchTier: diagnosis.result.tier.rawValue,
                matchedValue: diagnosis.result.matchedValue
            )
        }
    }
}

struct CLI {
    var args: [String]
    var configURL: URL

    init(args: [String]) {
        var remaining = args
        var configURL = ConfigStore.defaultURL
        if remaining.first == "--config" {
            remaining.removeFirst()
            if let path = remaining.first {
                configURL = URL(fileURLWithPath: path)
                remaining.removeFirst()
            }
        }
        self.args = remaining
        self.configURL = configURL
    }

    func run() throws {
        guard let command = args.first else {
            printUsage()
            return
        }

        switch command {
        case "help", "--help", "-h":
            printUsage()
        case "path":
            print(configURL.path)
        case "scan":
            try scan(json: args.contains("--json"))
        case "init":
            try initialize(force: args.contains("--force"))
        case "show":
            try show()
        case "switch":
            try switchRole()
        case "source":
            try sourceCommand(Array(args.dropFirst()))
        case "diagnose":
            try diagnose(json: args.contains("--json"))
        case "lab":
            try runLab()
        case "listen":
            try listen()
        case "slots":
            try listSlots()
        case "slot":
            try manageSlot()
        case "bind":
            try bind()
        case "remap":
            try remap()
        case "quit":
            try quitApp()
        default:
            guard SourceCommandPolicy.looksLikeInputSourceID(command, knownCommands: Self.knownCommands) else {
                throw CLIError.unknownCommand(command)
            }
            try sourceCommand(args)
        }
    }

    private func scan(json: Bool) throws {
        #if os(macOS)
        let service = MacInputSourceService()
        let sources = try service.listInputSources()
        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            print(String(decoding: try encoder.encode(sources), as: UTF8.self))
            return
        }

        for source in sources {
            let selectable = source.isSelectCapable ? "yes" : "no"
            let languages = source.languages.joined(separator: ",")
            print("\(source.id)\t\(source.localizedName)\t\(languages)\tselectable=\(selectable)")
        }
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func initialize(force: Bool) throws {
        #if os(macOS)
        let service = MacInputSourceService()
        let store = ConfigStore(url: configURL)
        if FileManager.default.fileExists(atPath: configURL.path), !force {
            print("Config already exists: \(configURL.path)")
            print("Use --force to overwrite it.")
            return
        }

        let sources = try service.listInputSources()
        // A config written by the CLI is not a GUI first run: keep the setup guide hidden.
        let config = SwitcherConfig.detected(from: sources).completingSetup()
        try save(config, to: store)
        print("Wrote \(configURL.path)")
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func show() throws {
        let config = try loadConfig()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        print(String(decoding: try encoder.encode(config), as: UTF8.self))
    }

    private func switchRole() throws {
        #if os(macOS)
        let service = MacInputSourceService()
        let config = try loadConfig()
        let role = try requireSlot(argument(at: 1, name: "slot"), in: config).id
        let sources = try service.listInputSources()
        guard let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: config) else {
            throw InputSourceServiceError.notFound(role.rawValue)
        }
        // Same Kana prelude as the event tap. Without Accessibility trust the post does nothing
        // and the select below proceeds as a plain select.
        SwitchActivationPolicy.selectWithKanaPrelude(
            target: source,
            current: { try? service.currentInputSource() },
            userRecipes: ActivationRecipeStore().load().recipes,
            postKana: EventTapMonitor.postKanaKeyEvent,
            wait: { delay, then in
                // Run the loop rather than sleep: a blocked loop keeps TIS's cached current source stale,
                // so the confirmation below would still read the source from before the Kana switch.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: delay))
                then()
            },
            select: {}
        )
        let current = try service.selectInputSourceAndConfirm(id: source.id)
        guard let current, current.id == source.id else {
            fputs(InputSourceInfo.verificationMessage(requested: source, current: current) + "\n", stderr)
            exit(1)
        }
        print("Selected \(source.localizedName) for \(role.rawValue)")
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func diagnose(json: Bool) throws {
        #if os(macOS)
        let service = MacInputSourceService()
        let config = try loadConfig()
        let sources = try service.listInputSources()
        let current = try service.currentInputSource()

        let reports = config.slots.map { slot -> RoleDiagnosis in
            let preference = config.preference(for: slot.id)
            let result = InputSourceMatcher.match(for: slot.id, sources: sources, config: config)
            let duplicates = config.duplicateSlotIDs(for: slot.id, sources: sources).map(\.rawValue)
            return RoleDiagnosis(slot: slot, duplicateSlots: duplicates, preference: preference, result: result)
        }

        if json {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let payload = DiagnosisReport(current: current, roles: reports)
            print(String(decoding: try encoder.encode(payload), as: UTF8.self))
            return
        }

        print("Current input source: \(current.map { "\($0.localizedName) (\($0.id))" } ?? "unknown")")
        for report in reports {
            print("")
            print("[\(report.slot.id.rawValue)] \(report.slot.name)")
            if !report.duplicateSlots.isEmpty {
                print("  duplicate with: \(report.duplicateSlots.joined(separator: ", "))")
            }
            print("  preferredIDs: \(report.preference.preferredIDs.joined(separator: ", "))")
            if let language = report.preference.fallbackLanguage {
                print("  fallbackLanguage: \(language)")
            }
            print("  languagePrefixes: \(report.preference.languagePrefixes.joined(separator: ", "))")
            print("  nameContains: \(report.preference.nameContains.joined(separator: ", "))")
            if let source = report.result.source {
                print("  matched: \(source.localizedName) (\(source.id)) languages=\(source.languages.joined(separator: ","))")
            } else {
                print("  matched: none")
            }
            let matchedValueText = report.result.matchedValue.map { " (\($0))" } ?? ""
            print("  reason: \(report.result.tier.rawValue)\(matchedValueText)")
        }
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func listen() throws {
        #if os(macOS)
        let config = try loadConfig()
        let monitor = EventTapMonitor(config: config)
        monitor.onMessage = { print($0) }
        try monitor.start()
        RunLoop.main.run()
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func bind() throws {
        let trigger = try ShortcutParser.parse(argument(at: 1, name: "trigger"))
        let store = ConfigStore(url: configURL)
        var config = try loadConfig(from: store)
        let role = try requireSlot(argument(at: 2, name: "slot"), in: config).id
        let displaced = config.bindings.compactMap { binding -> InputRole? in
            guard binding.trigger == trigger, binding.action.type == .switchInputSource,
                  let previous = binding.action.role, previous != role else { return nil }
            return previous
        }
        config.upsertSwitchBinding(trigger: trigger, role: role)
        try save(config, to: store)
        for previous in Set(displaced).sorted(by: { $0.rawValue < $1.rawValue }) where !config.bindings.contains(where: {
            $0.enabled && $0.action.type == .switchInputSource && $0.action.role == previous
        }) {
            fputs("note: \(trigger.displayName) was bound to \(previous.rawValue); it now has no trigger\n", stderr)
        }
        print("Bound \(trigger.displayName) to \(role.rawValue)")
    }

    private func remap() throws {
        let trigger = try ShortcutParser.parse(argument(at: 1, name: "trigger"))
        let output = try ShortcutParser.parse(argument(at: 2, name: "output"))
        let store = ConfigStore(url: configURL)
        var config = try loadConfig(from: store)
        config.upsertRemapBinding(trigger: trigger, output: output)
        try save(config, to: store)
        print("Remapped \(trigger.displayName) to \(output.displayName)")
    }

    private func requireSlot(_ query: String, in config: SwitcherConfig) throws -> SwitchSlot {
        guard let slot = config.slot(matching: query) else {
            throw CLIError.unknownSlot(query, available: config.slots.map { $0.id.rawValue })
        }
        return slot
    }

    private func save(_ config: SwitcherConfig, to store: ConfigStore) throws {
        if let backupURL = try store.save(config) {
            fputs("note: config upgraded to version \(config.version) (customizable slots); backup: \(backupURL.path); slot ids english/chinese/japanese unchanged. Run \"keyboardctl slots\".\n", stderr)
        }
    }

    private func triggerDescription(for slot: SwitchSlot, in config: SwitcherConfig) -> String {
        let triggers = config.bindings.filter {
            $0.enabled && $0.action.type == .switchInputSource && $0.action.role == slot.id
        }.map { $0.trigger.displayName }
        return triggers.isEmpty ? "No trigger" : triggers.joined(separator: ", ")
    }

    private func listSlots() throws {
        #if os(macOS)
        let config = try loadConfig()
        let sources = try MacInputSourceService().listInputSources()
        print("id\tname\ttrigger\tmatched-source")
        for slot in config.slots {
            let result = InputSourceMatcher.match(for: slot.id, sources: sources, config: config)
            var match = result.source.map { "\($0.localizedName) (\($0.id))" } ?? "Not matched"
            if result.source != nil && result.tier != .preferredID {
                match += " [fallback: \(result.tier.rawValue)]"
            }
            print("\(slot.id.rawValue)\t\(slot.name)\t\(triggerDescription(for: slot, in: config))\t\(match)")
        }
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func manageSlot() throws {
        let operation = try argument(at: 1, name: "add or remove")
        let store = ConfigStore(url: configURL)
        switch operation {
        case "remove":
            let query = try argument(at: 2, name: "slot")
            guard args.count == 3 else { throw CLIError.invalidArgument("Usage: keyboardctl slot remove <slot>") }
            let config = try loadConfig(from: store)
            let slot = try requireSlot(query, in: config)
            try save(config.removingSlot(slot.id), to: store)
            print("Removed \(slot.id.rawValue)")
        case "add":
            #if os(macOS)
            var sourceQuery: String?
            var name: String?
            var index = 2
            while index < args.count {
                if args[index] == "--name" {
                    guard name == nil else { throw CLIError.invalidArgument("Specify --name only once.") }
                    name = try argument(at: index + 1, name: "name after --name")
                    index += 2
                } else {
                    guard sourceQuery == nil, !args[index].hasPrefix("--") else {
                        throw CLIError.invalidArgument("Usage: keyboardctl slot add [<number|source-id>] [--name N]")
                    }
                    sourceQuery = args[index]
                    index += 1
                }
            }
            let config = try loadConfig(from: store)
            let sources = try MacInputSourceService().listInputSources()
            let choices = config.unassignedSources(from: sources)
            guard let sourceQuery else {
                for (index, source) in choices.enumerated() {
                    print("\(index + 1)\t\(source.localizedName)\t\(source.id)")
                }
                if choices.isEmpty { print("No unassigned input sources. Add one in System Settings > Keyboard > Input Sources.") }
                else { print("Run keyboardctl slot add <number|source-id> [--name N].") }
                return
            }
            let source: InputSourceInfo
            if let exact = sources.first(where: { $0.id == sourceQuery }) {
                source = exact
            } else if let number = Int(sourceQuery), number > 0, number <= choices.count {
                source = choices[number - 1]
            } else {
                throw CLIError.invalidArgument("Unknown input source or choice \"\(sourceQuery)\". Run \"keyboardctl slot add\" to list choices.")
            }
            let added = try config.addingSlot(for: source, name: name)
            try save(added.config, to: store)
            print("Added \(added.slot.id.rawValue) (\(added.slot.name)); trigger: \(triggerDescription(for: added.slot, in: added.config))")
            #else
            throw CLIError.unsupportedPlatform
            #endif
        default:
            throw CLIError.unknownCommand("slot \(operation)")
        }
    }

    private func quitApp() throws {
        #if os(macOS)
        let runningApps = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.shunmei.cmd-ime"
        )

        for app in runningApps {
            app.terminate()
        }

        Thread.sleep(forTimeInterval: 0.4)

        let stillRunning = NSRunningApplication.runningApplications(
            withBundleIdentifier: "com.shunmei.cmd-ime"
        )
        if !stillRunning.isEmpty {
            for app in stillRunning {
                app.forceTerminate()
            }
        }

        let terminatedByProcessName = terminateByProcessName()
        if runningApps.isEmpty && !terminatedByProcessName {
            print("CmdIME is not running")
        } else {
            print("Quit CmdIME")
        }
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private func terminateByProcessName() -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        process.arguments = ["-x", "CmdIME"]

        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
    #endif


    /// Types into TextEdit through each slot's own trigger and reads the text back.
    private func runLab() throws {
        #if os(macOS)
        let attempts = value(after: "--attempts").flatMap(Int.init) ?? 2
        let settle = value(after: "--settle").flatMap(Int.init) ?? 400
        var runner = LabRunner(config: try loadConfig(), attempts: max(1, attempts), settleMs: max(100, settle))
        runner.restMs = value(after: "--rest").flatMap(Int.init) ?? 0
        runner.forcesDirect = args.contains("--direct")
        runner.skipsBaseline = args.contains("--no-baseline")
        runner.reselectMs = value(after: "--reselect").flatMap(Int.init) ?? 0
        runner.refocuses = args.contains("--refocus")
        runner.warmupKeyCode = value(after: "--warmup").flatMap(Int.init) ?? 0
        runner.warmupModifierKeyCode = value(after: "--warmup-mod").flatMap(Int.init) ?? 0
        runner.leavesLatinMode = args.contains("--latin-first")
        if let slots = value(after: "--slots") {
            runner.onlySlots = Set(slots.split(separator: ",").map(String.init))
        }
        try runner.run(json: args.contains("--json"))
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func value(after flag: String) -> String? {
        guard let index = args.firstIndex(of: flag), args.index(after: index) < args.endIndex else { return nil }
        return args[args.index(after: index)]
    }

    // MARK: - source

    /// Every word `run()` dispatches on. A first argument that is not one of these and looks
    /// like an input source id is read as one, so `keyboardctl <id>` works like `im-select <id>`.
    private static let knownCommands: Set<String> = [
        "help", "--help", "-h", "path", "scan", "init", "show", "switch", "source",
        "diagnose", "listen", "slots", "slot", "bind", "remap", "quit",
    ]

    /// Reads or sets the input source by id. Editor plugins call this on every mode change,
    /// so the read path prints the id and nothing else: Neovim merges a child's stderr into
    /// stdout, and one stray line there would be stored as the "current input source".
    private func sourceCommand(_ arguments: [String]) throws {
        #if os(macOS)
        let json = arguments.contains("--json")
        let quiet = arguments.contains("--quiet")
        let service = MacInputSourceService()

        switch SourceCommandPolicy.parse(arguments) {
        case .read:
            guard let current = try service.currentInputSource() else {
                exit(4)
            }
            if json {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                print(String(decoding: try encoder.encode(current), as: UTF8.self))
            } else {
                print(current.id)
            }
        case let .select(id, waitMilliseconds):
            try selectSource(id: id, waitMilliseconds: waitMilliseconds, json: json, quiet: quiet, service: service)
        }
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    #if os(macOS)
    private func selectSource(
        id: String,
        waitMilliseconds: Int?,
        json: Bool,
        quiet: Bool,
        service: MacInputSourceService
    ) throws {
        func fail(_ message: String, code: Int32) -> Never {
            if !quiet { fputs("error: \(message)\n", stderr) }
            exit(code)
        }

        let previous = try? service.currentInputSource()
        let sources = try service.listInputSources()
        if let rejection = SourceCommandPolicy.rejection(
            for: id,
            selectable: sources.map(\.id),
            keyboardSources: try service.keyboardInputSourceIDs(),
            isInstalled: service.isInstalled(id: id)
        ) {
            fail(rejection.message, code: 1)
        }
        guard let target = sources.first(where: { $0.id == id }) else {
            fail(SourceCommandPolicy.Rejection.unknown(id: id).message, code: 1)
        }

        let recipes = ActivationRecipeStore().load().recipes
        let strategy = SwitchActivationPolicy.strategy(for: target, userRecipes: recipes)
        // The Kana key is posted as a keyboard event, which a process without Accessibility
        // trust cannot do. Selecting anyway looks like success and types Latin letters.
        if strategy == .kanaThenSelect, !AXIsProcessTrusted() {
            fail(
                "\"\(target.localizedName)\" needs a Kana key press before it activates, and this "
                    + "process may not post keyboard events. Grant Accessibility to the program that "
                    + "runs keyboardctl, or switch from CmdIME itself.",
                code: 5
            )
        }

        if previous?.id == id {
            report(target: target, previous: previous, changed: false, confirmed: true, strategy: strategy, json: json)
            return
        }

        SwitchActivationPolicy.selectWithKanaPrelude(
            target: target,
            current: { try? service.currentInputSource() },
            userRecipes: recipes,
            postKana: EventTapMonitor.postKanaKeyEvent,
            wait: { delay, then in
                // Running the loop, not sleeping: a blocked loop keeps TIS's cached current
                // source stale, so the confirmation below would read the value from before.
                RunLoop.current.run(until: Date(timeIntervalSinceNow: delay))
                then()
            },
            select: {}
        )

        do {
            try service.selectInputSource(id: id)
        } catch {
            fail("macOS refused to select \"\(id)\": \(error.localizedDescription)", code: 2)
        }

        guard waitMilliseconds != 0 else {
            report(target: target, previous: previous, changed: true, confirmed: false, strategy: strategy, json: json)
            return
        }

        let budget = Double(waitMilliseconds ?? 60) / 1000
        let deadline = Date(timeIntervalSinceNow: budget)
        var reselected = false
        while Date() < deadline {
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005))
            let current = try? service.currentInputSource()
            if current?.id == id {
                report(target: target, previous: previous, changed: true, confirmed: true, strategy: strategy, json: json)
                return
            }
            // Someone else switched while we were confirming: an editor firing on Esc and i can
            // do that inside this window. Pushing our target back would fight the newer request.
            guard SourceCommandPolicy.shouldRetrySelection(
                current: current?.id,
                target: id,
                previous: previous?.id
            ) else {
                report(target: target, previous: previous, changed: true, confirmed: false, strategy: strategy, json: json)
                return
            }
            if !reselected {
                reselected = true
                try? service.selectInputSource(id: id)
            }
        }
        let current = try? service.currentInputSource()
        fail(InputSourceInfo.verificationMessage(requested: target, current: current ?? nil), code: 3)
    }

    private func report(
        target: InputSourceInfo,
        previous: InputSourceInfo?,
        changed: Bool,
        confirmed: Bool,
        strategy: SwitchActivationStrategy,
        json: Bool
    ) {
        guard json else { return }
        let payload: [String: Any] = [
            "id": target.id,
            "localizedName": target.localizedName,
            "previousID": previous?.id as Any,
            "changed": changed,
            "confirmed": confirmed,
            "strategy": strategy == .kanaThenSelect ? "kanaThenSelect" : "select",
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: data, as: UTF8.self))
        }
    }
    #endif

    private func argument(at index: Int, name: String) throws -> String {
        guard args.indices.contains(index) else {
            throw CLIError.missingArgument(name)
        }
        return args[index]
    }

    private func loadConfig() throws -> SwitcherConfig {
        try loadConfig(from: ConfigStore(url: configURL))
    }

    private func loadConfig(from store: ConfigStore) throws -> SwitcherConfig {
        let result = try store.loadOrRecover()
        if let backupURL = result.recoveredBackupURL {
            fputs(
                "warning: config was unreadable; backed it up to \(backupURL.path) and reset to defaults.\n",
                stderr
            )
        } else if result.config.unreadableBindingCount > 0 {
            fputs(
                "warning: \(result.config.unreadableBindingCount) binding(s) in the config were "
                    + "use an action this version does not have (from a newer CmdIME, or since removed) "
                    + "and are not active. Everything else was kept.\n",
                stderr
            )
        }
        return result.configForCLI
    }

    private func printUsage() {
        print(
            """
            keyboardctl

            Usage:
              keyboardctl scan [--json]
              keyboardctl init [--force]
              keyboardctl slots
              keyboardctl slot add [<number|source-id>] [--name N]
              keyboardctl slot remove <slot>
              keyboardctl show
              keyboardctl switch <slot>
              keyboardctl lab [--slots a,b] [--attempts N] [--settle MS] [--rest MS] [--latin-first] [--json]\n              keyboardctl source [--json]
              keyboardctl source <input-source-id> [<wait-ms>] [--quiet] [--json]
              keyboardctl diagnose [--json]
              keyboardctl listen
              keyboardctl bind <trigger> <slot>
              keyboardctl remap <trigger> <output>
              keyboardctl quit
              keyboardctl path

            Examples (slot IDs depend on detected sources; run keyboardctl slots):
              keyboardctl init
              keyboardctl bind left-command english
              keyboardctl bind right-command chinese
              keyboardctl bind option+j japanese
              keyboardctl remap right-control escape
              keyboardctl source                          # print the current input source id
              keyboardctl source com.apple.keylayout.ABC  # select it by id, prints nothing
              keyboardctl quit
            """
        )
    }
}

do {
    try CLI(args: Array(CommandLine.arguments.dropFirst())).run()
} catch {
    fputs("error: \(error.localizedDescription)\n", stderr)
    exit(1)
}
