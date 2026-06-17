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

#if os(macOS)
import Carbon

public final class MacInputSourceService: InputSourceService {
    public init() {}

    public func listInputSources() throws -> [InputSourceInfo] {
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
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
        let list = TISCreateInputSourceList(nil, false).takeRetainedValue() as NSArray
        for item in list {
            let source = item as! TISInputSource
            guard stringProperty(source, kTISPropertyInputSourceID) == id else {
                continue
            }

            let status = TISSelectInputSource(source)
            guard status == noErr else {
                throw InputSourceServiceError.selectionFailed(id: id, status: status)
            }
            return
        }

        throw InputSourceServiceError.notFound(id)
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
