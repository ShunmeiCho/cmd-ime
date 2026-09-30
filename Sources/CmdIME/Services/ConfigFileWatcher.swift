import Foundation

/// Calls `onChange` on the main thread shortly after config.json is written by anyone,
/// the app itself included (`ConfigReload` tells those writes apart). It watches the
/// folder, because a save that replaces the file atomically gives it a new inode, and
/// the file, because an editor that writes in place leaves the folder untouched.
@MainActor
final class ConfigFileWatcher {
    /// Bursts of events from one save (write, rename, attribute change) collapse into one call.
    private static let settleDelay: TimeInterval = 0.3

    private let fileURL: URL
    private let onChange: @MainActor () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?

    init(fileURL: URL, onChange: @escaping @MainActor () -> Void) {
        self.fileURL = fileURL
        self.onChange = onChange
        let directory = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        directorySource = Self.source(for: directory, events: .write) { [weak self] in
            self?.watchFile()
            self?.scheduleChange()
        }
        watchFile()
    }

    func stop() {
        pendingChange?.cancel()
        directorySource?.cancel()
        fileSource?.cancel()
        directorySource = nil
        fileSource = nil
    }

    /// Re-armed on every folder event: after an atomic save the old descriptor points
    /// at a file that is no longer config.json.
    private func watchFile() {
        fileSource?.cancel()
        fileSource = Self.source(for: fileURL, events: [.write, .extend, .delete, .rename]) { [weak self] in
            self?.scheduleChange()
        }
    }

    private func scheduleChange() {
        pendingChange?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.onChange() }
        }
        pendingChange = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.settleDelay, execute: work)
    }

    /// Nil when the path cannot be opened (no file yet); the folder source covers its creation.
    private static func source(
        for url: URL,
        events: DispatchSource.FileSystemEvent,
        handler: @escaping @MainActor () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: events, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}
