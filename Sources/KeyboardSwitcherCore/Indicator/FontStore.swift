import Foundation

public struct ImportedFont: Equatable, Identifiable, Sendable {
    public let fileName: String
    public let url: URL

    public var id: String { fileName }
}

public enum FontStoreError: Error, Equatable, LocalizedError {
    case unsupportedType(String)
    case tooLarge(Int)
    case invalidName(String)
    case notFound(String)
    case copyFailed(String)
    case removeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedType: "Only .ttf, .otf and .ttc files can be imported."
        case .tooLarge: "This font file is larger than \(FontStore.maxFileBytes / (1024 * 1024)) MB."
        case let .invalidName(name): "\(name.debugDescription) cannot be used as a font file name."
        case let .notFound(name): "The font file \(name.debugDescription) was not found."
        case let .copyFailed(reason): "Could not copy the font: \(reason)"
        case let .removeFailed(reason): "Could not remove the font: \(reason)"
        }
    }
}

/// File operations on the fonts directory beside the config file. Registering the
/// fonts with the system is the app's job; nothing here installs anything.
public struct FontStore {
    public static let allowedExtensions = ["ttf", "otf", "ttc"]
    public static let maxFileBytes = 40 * 1024 * 1024

    public let directory: URL

    public init(configStore: ConfigStore) {
        directory = configStore.fontsDirectoryURL
    }

    /// Font files in the directory, sorted by name. Hidden files, symbolic links and
    /// other file types are ignored; a missing directory lists as empty.
    public func list() throws -> [ImportedFont] {
        try FileManager.default.indicatorStoreFiles(in: directory, extensions: Self.allowedExtensions)
            // Rebuilt from the directory so listed and imported URLs compare equal
            // (the file manager reports /private/var for /var).
            .map { ImportedFont(fileName: $0.lastPathComponent, url: directory.appendingPathComponent($0.lastPathComponent)) }
    }

    /// Copies the file into the directory. An existing name is never overwritten:
    /// the copy becomes "Name-2.ttf", "Name-3.ttf", and so on. A symbolic link is
    /// resolved first, so the font itself is size-checked and copied, never the link;
    /// the copy keeps the name the user picked.
    public func importing(from pickedURL: URL) throws(FontStoreError) -> ImportedFont {
        let fileManager = FileManager.default
        let source = pickedURL.resolvingSymlinksInPath()
        let fileExtension = pickedURL.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(fileExtension) else { throw .unsupportedType(pickedURL.pathExtension) }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw .notFound(pickedURL.lastPathComponent)
        }
        if let size = fileManager.indicatorFileSize(at: source), size > Self.maxFileBytes { throw .tooLarge(size) }
        guard let fileName = Self.sanitizedFileName(pickedURL.lastPathComponent) else {
            throw .invalidName(pickedURL.lastPathComponent)
        }

        let stem = (fileName as NSString).deletingPathExtension
        var destination = directory.appendingPathComponent(fileName)
        var suffix = 2
        while fileManager.fileExists(atPath: destination.path) {
            destination = directory.appendingPathComponent("\(stem)-\(suffix).\(fileExtension)")
            suffix += 1
        }
        do {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw .copyFailed(error.localizedDescription)
        }
        return ImportedFont(fileName: destination.lastPathComponent, url: destination)
    }

    /// Deletes by file name inside the directory; the font's `url` is not trusted.
    public func removing(_ font: ImportedFont) throws(FontStoreError) {
        // Sanitising only lowercases the extension, so a hand-dropped "Name.TTF" stays removable.
        guard Self.sanitizedFileName(font.fileName)?.caseInsensitiveCompare(font.fileName) == .orderedSame else {
            throw .invalidName(font.fileName)
        }
        let target = directory.appendingPathComponent(font.fileName)
        guard FileManager.default.fileExists(atPath: target.path) else { throw .notFound(font.fileName) }
        do {
            try FileManager.default.removeItem(at: target)
        } catch {
            throw .removeFailed(error.localizedDescription)
        }
    }

    /// A plain file name with an allowed, lowercased extension. Path separators,
    /// hidden names, "..", ":" and NUL are rejected; Unicode letters are kept.
    public static func sanitizedFileName(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let forbidden = CharacterSet(charactersIn: "/:\\\0").union(.controlCharacters)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("."), !trimmed.contains(".."),
              trimmed.unicodeScalars.allSatisfy({ !forbidden.contains($0) }) else { return nil }
        let fileExtension = (trimmed as NSString).pathExtension.lowercased()
        let stem = (trimmed as NSString).deletingPathExtension
        guard allowedExtensions.contains(fileExtension), !stem.isEmpty else { return nil }
        return "\(stem).\(fileExtension)"
    }
}
