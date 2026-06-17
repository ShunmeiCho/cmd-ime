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

public final class MacInputSourceService: InputSourceService {
    private var handleCache = InputSourceHandleCache<TISInputSource>()

    public init() {}

    public func listInputSources() throws -> [InputSourceInfo] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        // The source set was just enumerated; drop cached handles so the next
        // selection rebuilds against the current set.
        handleCache.invalidate()
        return list.compactMap { item -> InputSourceInfo? in
            let source = item as! TISInputSource
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

    private func handleMap() -> [String: TISInputSource] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        var map: [String: TISInputSource] = [:]
        for item in list {
            let source = item as! TISInputSource
            if let id = stringProperty(source, kTISPropertyInputSourceID) {
                map[id] = source
            }
        }
        return map
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
