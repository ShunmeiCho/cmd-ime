import Foundation

public protocol InputSourceService: AnyObject {
    func listInputSources() throws -> [InputSourceInfo]
    func currentInputSource() throws -> InputSourceInfo?
    func selectInputSource(id: String) throws
}

public extension InputSourceService {
    @discardableResult
    func selectInputSourceAndConfirm(
        id: String,
        retryDelays: [TimeInterval] = [0.015, 0.035]
    ) throws -> InputSourceInfo? {
        try selectInputSource(id: id)
        if let current = try currentInputSource(), current.id == id {
            return current
        }

        for delay in retryDelays {
            Thread.sleep(forTimeInterval: delay)
            if let current = try currentInputSource(), current.id == id {
                return current
            }
            try selectInputSource(id: id)
        }

        return try currentInputSource()
    }

    /// Non-blocking variant of `selectInputSourceAndConfirm(id:retryDelays:)`.
    /// Retries are handed to `schedule` instead of sleeping, so the caller's thread
    /// (e.g. an event tap callback) is never blocked. `schedule` must run its work on
    /// the thread that is allowed to make TIS calls (the main thread). Before each
    /// retry `shouldContinue` is consulted; when it returns false the attempt is
    /// abandoned and `completion` is never called.
    func selectInputSourceAndConfirm(
        id: String,
        retryDelays: [TimeInterval],
        schedule: @escaping InputSourceRetryScheduler,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping (Result<InputSourceInfo?, Error>) -> Void
    ) {
        do {
            try selectInputSource(id: id)
            if let current = try currentInputSource(), current.id == id {
                completion(.success(current))
                return
            }
        } catch {
            completion(.failure(error))
            return
        }
        confirmAfterRetries(
            id: id,
            remainingDelays: retryDelays[...],
            schedule: schedule,
            shouldContinue: shouldContinue,
            completion: completion
        )
    }

    private func confirmAfterRetries(
        id: String,
        remainingDelays: ArraySlice<TimeInterval>,
        schedule: @escaping InputSourceRetryScheduler,
        shouldContinue: @escaping () -> Bool,
        completion: @escaping (Result<InputSourceInfo?, Error>) -> Void
    ) {
        guard let delay = remainingDelays.first else {
            completion(Result { try currentInputSource() })
            return
        }
        schedule(delay) {
            guard shouldContinue() else {
                return
            }
            do {
                if let current = try self.currentInputSource(), current.id == id {
                    completion(.success(current))
                    return
                }
                try self.selectInputSource(id: id)
            } catch {
                completion(.failure(error))
                return
            }
            self.confirmAfterRetries(
                id: id,
                remainingDelays: remainingDelays.dropFirst(),
                schedule: schedule,
                shouldContinue: shouldContinue,
                completion: completion
            )
        }
    }
}

/// Runs `work` after `delay` seconds. Implementations used with TIS-backed services
/// must run `work` on the main thread.
public typealias InputSourceRetryScheduler = (_ delay: TimeInterval, _ work: @escaping () -> Void) -> Void

/// A refresh can still return an in-process list when the fresh scan fails.
public struct InputSourceRefreshResult: Equatable, Sendable {
    public let sources: [InputSourceInfo]
    public let fallbackReason: String?
}

public enum InputSourceServiceError: Error, LocalizedError, Equatable {
    case notFound(String)
    case missingProperty(String)
    case selectionFailed(id: String, status: Int32)

    public var errorDescription: String? {
        switch self {
        case let .notFound(id):
            "Input source not found: \(id)."
        case let .missingProperty(property):
            "Input source is missing property: \(property)."
        case let .selectionFailed(id, status):
            "Failed to select input source \(id), OSStatus \(status)."
        }
    }
}

/// Caches resolved handles by id and rebuilds the full map only on a miss, so
/// repeated lookups (e.g. rapid input-source switches) avoid re-enumerating every
/// source on each call. Call `invalidate()` whenever the source set may have changed.
struct InputSourceHandleCache<Handle> {
    private var handles: [String: Handle] = [:]

    init() {}

    /// Returns the handle for `id`. `rebuild` is called at most once, only when the
    /// id is not already cached.
    mutating func handle(for id: String, rebuild: () -> [String: Handle]) -> Handle? {
        if let cached = handles[id] {
            return cached
        }
        handles = rebuild()
        return handles[id]
    }

    mutating func invalidate() {
        handles.removeAll()
    }
}

#if os(macOS)
import Carbon
import Darwin

public final class MacInputSourceService: InputSourceService {
    public static let freshScanTimeout: Duration = .seconds(2)
    private var handleCache = InputSourceHandleCache<TISInputSource>()

    public init() {}

    /// Call for enabled-source notifications and explicit refreshes, not key events.
    /// Pass the bundled keyboardctl URL. A nil URL or failed helper uses the native
    /// list and reports why; cancellation propagates without starting a fallback.
    @MainActor
    public func refreshedInputSources(using executableURL: URL?) async throws -> InputSourceRefreshResult {
        try Task.checkCancellation()
        handleCache.invalidate()
        do {
            guard let executableURL else {
                throw FreshScanError.helperUnavailable
            }
            let data = try await Self.scanOutput(using: executableURL)
            return InputSourceRefreshResult(
                sources: try InputSourceMatcher.decodeScanJSON(data), fallbackReason: nil
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return InputSourceRefreshResult(
                sources: try listInputSources(), fallbackReason: error.localizedDescription
            )
        }
    }

    private enum FreshScanError: Error, LocalizedError {
        case helperUnavailable
        case timedOut
        case unsuccessfulExit(Int32)

        var errorDescription: String? {
            switch self {
            case .helperUnavailable: "The bundled keyboardctl scanner is unavailable."
            case .timedOut: "The input-source scanner did not finish in time."
            case let .unsuccessfulExit(status): "The input-source scanner exited with status \(status)."
            }
        }
    }

    @MainActor
    private static func scanOutput(using executableURL: URL) async throws -> Data {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cmd-ime-source-scan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let outputURL = directory.appendingPathComponent("sources.json")
        try Data().write(to: outputURL)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }

        // A file avoids pipe-buffer deadlock when a scanner writes a large list.
        let process = Process()
        process.executableURL = executableURL
        process.arguments = ["scan", "--json"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        defer {
            if process.isRunning {
                // Only terminate the scanner started above, on timeout/cancellation.
                kill(process.processIdentifier, SIGKILL)
                process.waitUntilExit()
            }
        }
        let deadline = ContinuousClock.now + freshScanTimeout
        while process.isRunning {
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else { throw FreshScanError.timedOut }
            try await Task.sleep(for: .milliseconds(25))
        }
        try Task.checkCancellation()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw FreshScanError.unsuccessfulExit(process.terminationStatus)
        }
        return try Data(contentsOf: outputURL)
    }

    public func listInputSources() throws -> [InputSourceInfo] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        // The source set was just enumerated; drop cached handles so the next
        // selection rebuilds against the current set.
        handleCache.invalidate()
        return list.compactMap { item -> InputSourceInfo? in
            let source = item as! TISInputSource
            guard isEnabledAndSelectCapable(source) else { return nil }
            return inputSourceInfo(from: source)
        }
    }

    public func currentInputSource() throws -> InputSourceInfo? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else {
            return nil
        }
        return inputSourceInfo(from: source)
    }

    public func selectInputSource(id: String) throws {
        // Fast path: reuse a cached handle so rapid switches avoid re-enumerating
        // every input source on each call.
        if let source = handleCache.handle(for: id, rebuild: handleMap),
           isEnabledAndSelectCapable(source),
           TISSelectInputSource(source) == noErr {
            return
        }

        // Cache miss, or a stale cached handle that failed to select: rebuild once.
        handleCache.invalidate()
        guard let source = handleCache.handle(for: id, rebuild: handleMap) else {
            throw InputSourceServiceError.notFound(id)
        }
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw InputSourceServiceError.selectionFailed(id: id, status: status)
        }
    }

    /// Ids that can actually be typed into. The selectable set also holds palette sources
    /// (Character Viewer, Press and Hold), which accept selection but produce no keystrokes.
    public func keyboardInputSourceIDs() throws -> Set<String> {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        var ids = Set<String>()
        for item in list {
            let source = item as! TISInputSource
            guard isEnabledAndSelectCapable(source),
                  let id = stringProperty(source, kTISPropertyInputSourceID),
                  let category = stringProperty(source, kTISPropertyInputSourceCategory),
                  category == (kTISCategoryKeyboardInputSource as String) else { continue }
            ids.insert(id)
        }
        return ids
    }

    /// Whether this source is a plain keyboard layout rather than an input method.
    ///
    /// Recovery needs it: an external process cannot ask another app's editor whether a
    /// composition is open, but a keyboard layout has no composition to open, so a layout being
    /// current is a dependable "nothing is being composed".
    public func isKeyboardLayout(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first,
              let type = stringProperty(source, kTISPropertyInputSourceType) else { return false }
        return type == (kTISTypeKeyboardLayout as String)
    }

    /// Whether the system knows this id at all, enabled or not. Without this, a disabled
    /// input source and a typo produce the same answer, and the user is told the wrong fix.
    public func isInstalled(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as NSArray? else {
            return false
        }
        return list.count > 0
    }

    private func handleMap() -> [String: TISInputSource] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        var map: [String: TISInputSource] = [:]
        for item in list {
            let source = item as! TISInputSource
            guard isEnabledAndSelectCapable(source) else { continue }
            if let id = stringProperty(source, kTISPropertyInputSourceID) {
                map[id] = source
            }
        }
        return map
    }

    private func isEnabledAndSelectCapable(_ source: TISInputSource) -> Bool {
        InputSourceMatcher.isEnabledAndSelectCapable(
            isEnabled: boolProperty(source, kTISPropertyInputSourceIsEnabled),
            isSelectCapable: boolProperty(source, kTISPropertyInputSourceIsSelectCapable)
        )
    }

    private func inputSourceInfo(from source: TISInputSource) -> InputSourceInfo? {
        guard let id = stringProperty(source, kTISPropertyInputSourceID) else {
            return nil
        }
        let name = stringProperty(source, kTISPropertyLocalizedName) ?? id
        let languages = stringArrayProperty(source, kTISPropertyInputSourceLanguages) ?? []
        let selectCapable = boolProperty(source, kTISPropertyInputSourceIsSelectCapable) ?? false
        return InputSourceInfo(
            id: id,
            localizedName: name,
            languages: languages,
            isSelectCapable: selectCapable
        )
    }

    private func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(raw).takeUnretainedValue() as String
    }

    private func stringArrayProperty(_ source: TISInputSource, _ key: CFString) -> [String]? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        return Unmanaged<CFArray>.fromOpaque(raw).takeUnretainedValue() as? [String]
    }

    private func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool? {
        guard let raw = TISGetInputSourceProperty(source, key) else {
            return nil
        }
        let value = Unmanaged<CFBoolean>.fromOpaque(raw).takeUnretainedValue()
        return CFBooleanGetValue(value)
    }
}
#endif
