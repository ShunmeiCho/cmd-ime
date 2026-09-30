import Foundation

/// What the running app does after config.json changed on disk. The app's own saves
/// change it too; they decode to the settings already applied and so read as
/// `unchanged`, which is how the app tells its own writes from anyone else's.
public enum ConfigReloadDecision: Equatable, Sendable {
    /// Same settings as the ones applied (the app's own save), or no file at all. A
    /// missing file is left alone: the next save writes it again.
    case unchanged
    /// Someone else wrote different settings (`keyboardctl`, an editor, an import).
    case apply(SwitcherConfig)
    /// The file does not decode, often because an editor is halfway through a save.
    /// The app keeps its settings and never moves this file aside, unlike at launch.
    case unreadable(String)
}

public enum ConfigReload {
    public static func decide(fileData: Data?, applied: SwitcherConfig) -> ConfigReloadDecision {
        guard let fileData else { return .unchanged }
        let onDisk: SwitcherConfig
        do {
            // The same in-memory migration `ConfigStore.loadOrRecover` applies at launch.
            onDisk = try JSONDecoder().decode(SwitcherConfig.self, from: fileData).migrated()
        } catch {
            return .unreadable(error.localizedDescription)
        }
        // The unreadable-binding count describes one load and is never written, so the
        // app's own save of a config that lost a binding must still read as unchanged.
        var comparable = onDisk
        comparable.unreadableBindingCount = applied.unreadableBindingCount
        return comparable == applied ? .unchanged : .apply(onDisk)
    }
}
