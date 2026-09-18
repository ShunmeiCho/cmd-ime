import Foundation
import KeyboardSwitcherCore

#if os(macOS)
import AppKit
#endif

enum CLIError: Error, LocalizedError {
    case missingCommand
    case unknownCommand(String)
    case missingArgument(String)
    case unsupportedPlatform

    var errorDescription: String? {
        switch self {
        case .missingCommand:
            "Missing command."
        case let .unknownCommand(command):
            "Unknown command: \(command)."
        case let .missingArgument(argument):
            "Missing argument: \(argument)."
        case .unsupportedPlatform:
            "keyboardctl currently supports macOS only."
        }
    }
}

/// A role's configured preference paired with the match `keyboardctl
/// diagnose` computed for it, via the same `InputSourceMatcher.match` the
/// switch pipeline uses.
private struct RoleDiagnosis {
    let role: InputRole
    let preference: RoleInputSourcePreference
    let result: InputSourceMatchResult
}

/// `--json` payload for `keyboardctl diagnose`.
private struct DiagnosisReport: Encodable {
    struct RoleEntry: Encodable {
        let role: String
        let preferredIDs: [String]
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
    let roles: [RoleEntry]

    init(current: InputSourceInfo?, roles: [RoleDiagnosis]) {
        currentInputSourceID = current?.id
        currentInputSourceName = current?.localizedName
        self.roles = roles.map { diagnosis in
            RoleEntry(
                role: diagnosis.role.rawValue,
                preferredIDs: diagnosis.preference.preferredIDs,
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
        case "diagnose":
            try diagnose(json: args.contains("--json"))
        case "listen":
            try listen()
        case "bind":
            try bind()
        case "remap":
            try remap()
        case "quit":
            try quitApp()
        default:
            throw CLIError.unknownCommand(command)
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

        var config = SwitcherConfig.default
        let sources = try service.listInputSources()
        for role in InputRole.allCases {
            if let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: config) {
                config.pinInputSourceID(source.id, for: role)
            }
        }
        try store.save(config)
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
        let roleName = try argument(at: 1, name: "role")
        guard let role = InputRole(rawValue: roleName) else {
            throw CLIError.missingArgument("role must be english, chinese, or japanese")
        }
        let config = try loadConfig()
        let sources = try service.listInputSources()
        guard let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: config) else {
            throw InputSourceServiceError.notFound(role.rawValue)
        }
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

        let reports = InputRole.allCases.map { role -> RoleDiagnosis in
            let preference = config.preference(for: role)
            let result = InputSourceMatcher.match(for: role, sources: sources, config: config)
            return RoleDiagnosis(role: role, preference: preference, result: result)
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
            print("[\(report.role.rawValue)]")
            print("  preferredIDs: \(report.preference.preferredIDs.joined(separator: ", "))")
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
        let roleName = try argument(at: 2, name: "role")
        guard let role = InputRole(rawValue: roleName) else {
            throw CLIError.missingArgument("role must be english, chinese, or japanese")
        }
        let store = ConfigStore(url: configURL)
        var config = try loadConfig(from: store)
        config.upsertSwitchBinding(trigger: trigger, role: role)
        try store.save(config)
        print("Bound \(trigger.displayName) to \(role.rawValue)")
    }

    private func remap() throws {
        let trigger = try ShortcutParser.parse(argument(at: 1, name: "trigger"))
        let output = try ShortcutParser.parse(argument(at: 2, name: "output"))
        let store = ConfigStore(url: configURL)
        var config = try loadConfig(from: store)
        config.upsertRemapBinding(trigger: trigger, output: output)
        try store.save(config)
        print("Remapped \(trigger.displayName) to \(output.displayName)")
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
        }
        return result.config
    }

    private func printUsage() {
        print(
            """
            keyboardctl

            Usage:
              keyboardctl scan [--json]
              keyboardctl init [--force]
              keyboardctl show
              keyboardctl switch <english|chinese|japanese>
              keyboardctl diagnose [--json]
              keyboardctl listen
              keyboardctl bind <trigger> <english|chinese|japanese>
              keyboardctl remap <trigger> <output>
              keyboardctl quit
              keyboardctl path

            Examples:
              keyboardctl init
              keyboardctl bind left-command english
              keyboardctl bind right-command chinese
              keyboardctl bind option+j japanese
              keyboardctl remap right-control escape
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
