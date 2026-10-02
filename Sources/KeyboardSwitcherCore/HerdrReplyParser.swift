import Foundation

/// Reads Herdr JSON without performing any I/O. Unrecognized or malformed replies return nil.
public enum HerdrReplyParser {
    public struct FocusedPane: Equatable, Sendable {
        public let paneID: String
        public let tabID: String
        public let workspaceID: String
        public let agent: String?
    }

    public struct SelectedMachine: Equatable, Sendable {
        public let label: String
        public let target: String
    }

    public enum Event: Equatable, Sendable {
        case paneFocused(paneID: String, workspaceID: String)
        case tabFocused(tabID: String, workspaceID: String)
        case workspaceFocused(workspaceID: String)
        case subscriptionStarted
        case unknown
    }

    /// Requires exactly one focused pane with all three IDs; ambiguous focus is not guessed.
    public static func focusedPane(from data: Data) -> FocusedPane? {
        guard let reply = try? JSONDecoder().decode(Reply<PaneList>.self, from: data) else { return nil }
        let focused = reply.result.panes.filter(\.focused)
        guard focused.count == 1, let pane = focused.first,
              !pane.paneID.isEmpty, !pane.tabID.isEmpty, !pane.workspaceID.isEmpty else { return nil }
        return FocusedPane(paneID: pane.paneID, tabID: pane.tabID, workspaceID: pane.workspaceID, agent: pane.agent)
    }

    /// Returns the foreground group leader's argv0 verbatim, or name only if argv0 is absent/null.
    /// Does not normalize case, strip paths, inspect argv, or choose a child when the leader is missing.
    public static func program(from data: Data) -> String? {
        guard let reply = try? JSONDecoder().decode(Reply<ProcessResult>.self, from: data) else { return nil }
        let info = reply.result.info
        let leaders = info.processes.filter { $0.pid == info.foregroundProcessGroupID }
        guard leaders.count == 1, let leader = leaders.first,
              let program = leader.argv0 ?? leader.name, !program.isEmpty else { return nil }
        return program
    }

    /// Accepts a single event/acknowledgement line. Malformed and unsupported lines are unknown.
    public static func event(from line: String) -> Event {
        guard let reply = try? JSONDecoder().decode(EventReply.self, from: Data(line.utf8)) else { return .unknown }
        if let event = reply.event {
            guard let data = reply.data, let workspaceID = data.workspaceID, !workspaceID.isEmpty else {
                return .unknown
            }
            switch event {
            case "pane_focused":
                guard let paneID = data.paneID, !paneID.isEmpty else { return .unknown }
                return .paneFocused(paneID: paneID, workspaceID: workspaceID)
            case "tab_focused":
                guard let tabID = data.tabID, !tabID.isEmpty else { return .unknown }
                return .tabFocused(tabID: tabID, workspaceID: workspaceID)
            case "workspace_focused":
                return .workspaceFocused(workspaceID: workspaceID)
            default:
                return .unknown
            }
        }
        return reply.result?.type == "subscription_started" ? .subscriptionStarted : .unknown
    }

    /// Machine list replies are bare arrays. Requires one selection, regardless of enabled status.
    public static func selectedMachine(from data: Data) -> SelectedMachine? {
        guard let machines = try? JSONDecoder().decode([Machine].self, from: data) else { return nil }
        let selected = machines.filter(\.selected)
        guard selected.count == 1, let machine = selected.first,
              !machine.label.isEmpty, !machine.target.isEmpty else { return nil }
        return SelectedMachine(label: machine.label, target: machine.target)
    }
}

private extension HerdrReplyParser {
    struct Reply<Result: Decodable>: Decodable {
        let result: Result
    }

    struct PaneList: Decodable {
        let panes: [Pane]
    }

    struct Pane: Decodable {
        let focused: Bool
        let paneID: String
        let tabID: String
        let workspaceID: String
        let agent: String?

        enum CodingKeys: String, CodingKey {
            case focused, agent
            case paneID = "pane_id"
            case tabID = "tab_id"
            case workspaceID = "workspace_id"
        }
    }

    struct ProcessResult: Decodable {
        let info: ProcessInfo

        enum CodingKeys: String, CodingKey {
            case processInfo = "process_info"
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            if container.contains(.processInfo) {
                info = try container.decode(ProcessInfo.self, forKey: .processInfo)
            } else {
                info = try ProcessInfo(from: decoder)
            }
        }
    }

    struct ProcessInfo: Decodable {
        let foregroundProcessGroupID: Int
        let processes: [ForegroundProcess]

        enum CodingKeys: String, CodingKey {
            case foregroundProcessGroupID = "foreground_process_group_id"
            case processes = "foreground_processes"
        }
    }

    struct ForegroundProcess: Decodable {
        let pid: Int
        let argv0: String?
        let name: String?
    }

    struct EventReply: Decodable {
        let event: String?
        let data: EventData?
        let result: EventResult?
    }

    struct EventData: Decodable {
        let paneID: String?
        let tabID: String?
        let workspaceID: String?

        enum CodingKeys: String, CodingKey {
            case paneID = "pane_id"
            case tabID = "tab_id"
            case workspaceID = "workspace_id"
        }
    }

    struct EventResult: Decodable {
        let type: String
    }

    struct Machine: Decodable {
        let selected: Bool
        let label: String
        let target: String
    }
}
