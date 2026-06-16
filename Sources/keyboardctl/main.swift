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
        let config = try ConfigStore(url: configURL).loadOrDefault()
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
        let config = try ConfigStore(url: configURL).loadOrDefault()
        let sources = try service.listInputSources()
        guard let source = InputSourceMatcher.bestMatch(for: role, sources: sources, config: config) else {
            throw InputSourceServiceError.notFound(role.rawValue)
        }
        try service.selectInputSource(id: source.id)
        print("Selected \(source.localizedName) for \(role.rawValue)")
        #else
        throw CLIError.unsupportedPlatform
        #endif
    }

    private func listen() throws {
        #if os(macOS)
        let config = try ConfigStore(url: configURL).loadOrDefault()
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
        var config = try store.loadOrDefault()
        config.upsertSwitchBinding(trigger: trigger, role: role)
        try store.save(config)
        print("Bound \(trigger.displayName) to \(role.rawValue)")
    }

    private func remap() throws {
        let trigger = try ShortcutParser.parse(argument(at: 1, name: "trigger"))
        let output = try ShortcutParser.parse(argument(at: 2, name: "output"))
        let store = ConfigStore(url: configURL)
        var config = try store.loadOrDefault()
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

    private func printUsage() {
        print(
            """
            keyboardctl

            Usage:
              keyboardctl scan [--json]
              keyboardctl init [--force]
              keyboardctl show
              keyboardctl switch <english|chinese|japanese>
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
              keyboardctl remap caps-lock escape
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
