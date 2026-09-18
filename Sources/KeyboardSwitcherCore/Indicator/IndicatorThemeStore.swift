import Foundation

public struct IndicatorThemeListing: Equatable, Sendable {
    public struct Rejection: Equatable, Sendable {
        public let fileName: String
        public let issue: IndicatorThemeIssue
    }

    /// Built-ins first, then user themes by name.
    public let themes: [IndicatorTheme]
    public let rejected: [Rejection]
}

public enum IndicatorThemeStoreError: Error, Equatable, LocalizedError {
    case builtInIsReadOnly(String)
    case invalidName(String)
    case notFound(String)
    case invalid(IndicatorThemeIssue)
    case writeFailed(String)

    public var errorDescription: String? {
        switch self {
        case .builtInIsReadOnly: "Built-in themes cannot be changed. Duplicate the theme to edit it."
        case let .invalidName(name): "\(name.debugDescription) cannot be used as a theme id."
        case let .notFound(id): "The theme \(id.debugDescription) was not found."
        case let .invalid(issue): issue.message
        case let .writeFailed(reason): "Could not write the theme: \(reason)"
        }
    }
}

/// User themes as one JSON file each in the themes directory beside the config file.
public struct IndicatorThemeStore {
    static let fileExtension = "json"
    static let copySuffix = " Copy"

    public let directory: URL

    public init(configStore: ConfigStore) {
        directory = configStore.themesDirectoryURL
    }

    /// Never throws: a missing directory lists the built-ins only, and a bad file is
    /// reported in `rejected` while its neighbours load. Among duplicate ids the file
    /// that sorts first by name wins.
    public func listing() -> IndicatorThemeListing {
        let files = (try? FileManager.default.indicatorStoreFiles(in: directory, extensions: [Self.fileExtension])) ?? []
        var userThemes: [IndicatorTheme] = []
        var rejected: [IndicatorThemeListing.Rejection] = []
        for file in files {
            switch Self.reading(file) {
            case let .success(theme) where userThemes.contains(where: { $0.id == theme.id }):
                rejected.append(.init(fileName: file.lastPathComponent, issue: .duplicateID(theme.id)))
            case let .success(theme):
                userThemes.append(theme)
            case let .failure(issue):
                rejected.append(.init(fileName: file.lastPathComponent, issue: issue))
            }
        }
        let sorted = userThemes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return IndicatorThemeListing(themes: BuiltInIndicatorThemes.all + sorted, rejected: rejected)
    }

    /// An editable copy: id "<stem>-copy", then "-copy-2", and the name "<Name> Copy".
    /// Nothing is written until the copy is saved.
    public func duplicate(of theme: IndicatorTheme, existing: [IndicatorTheme]) -> IndicatorTheme {
        let stem = theme.isBuiltIn ? String(theme.id.dropFirst(IndicatorTheme.builtInPrefix.count)) : theme.id
        var copy = theme
        copy.id = Self.freeID(base: "\(IndicatorTheme.sanitizedID(stem) ?? "theme")-copy", existing: existing)
        copy.name = String(theme.name.prefix(IndicatorTheme.maxNameGraphemes - Self.copySuffix.count)) + Self.copySuffix
        return copy
    }

    /// Writes atomically and returns the file's URL. A listed theme is written back to
    /// the file it was read from, whatever that file is called; a new theme becomes
    /// "<id>.json", or "<id>-2.json" when that name already holds something else.
    @discardableResult
    public func saving(_ theme: IndicatorTheme) throws(IndicatorThemeStoreError) -> URL {
        let destination: URL
        if let source = try sourceFile(forID: theme.id) {
            destination = source
        } else {
            destination = try freeFileURL(forID: theme.id)
        }
        try Self.writing(theme, to: destination, creating: directory)
        return destination
    }

    /// Validates before anything is copied; an id that is already taken gets a suffix.
    public func importing(from source: URL, existing: [IndicatorTheme]) throws(IndicatorThemeStoreError) -> IndicatorTheme {
        guard FileManager.default.fileExists(atPath: source.path) else { throw .notFound(source.lastPathComponent) }
        var theme: IndicatorTheme
        switch Self.reading(source) {
        case let .success(decoded): theme = decoded
        case let .failure(issue): throw .invalid(issue)
        }
        if existing.contains(where: { $0.id == theme.id }) {
            theme.id = Self.freeID(base: theme.id, existing: existing)
        }
        try saving(theme)
        return theme
    }

    public func exporting(_ theme: IndicatorTheme, to destination: URL) throws(IndicatorThemeStoreError) {
        try Self.writing(theme, to: destination, creating: nil)
    }

    /// Removes the file the listed theme was read from. `toTrash` moves it to the
    /// user's Trash instead of deleting it, so a slip can be undone from Finder.
    public func removing(id: String, toTrash: Bool = false) throws(IndicatorThemeStoreError) {
        guard let target = try sourceFile(forID: id) else { throw .notFound(id) }
        do {
            if toTrash {
                try FileManager.default.trashItem(at: target, resultingItemURL: nil)
            } else {
                try FileManager.default.removeItem(at: target)
            }
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    public static func sanitizedID(_ raw: String) -> String? {
        IndicatorTheme.sanitizedID(raw)
    }

    // MARK: - Helpers

    private func validating(id: String) throws(IndicatorThemeStoreError) {
        guard !id.lowercased().hasPrefix(IndicatorTheme.builtInPrefix) else { throw .builtInIsReadOnly(id) }
        guard Self.sanitizedID(id) == id else { throw .invalidName(id) }
    }

    /// The file `listing()` reads this id from: the first by name among the files that
    /// decode to it. A hand-dropped file need not be called "<id>.json".
    private func sourceFile(forID id: String) throws(IndicatorThemeStoreError) -> URL? {
        try validating(id: id)
        let files = (try? FileManager.default.indicatorStoreFiles(in: directory, extensions: [Self.fileExtension])) ?? []
        return files.first { file in
            if case let .success(theme) = Self.reading(file) { return theme.id == id }
            return false
        }
    }

    /// Only an already-sanitised id names a file, so no id can point outside the
    /// directory. A name that is taken, by another id or by a rejected file, is never
    /// overwritten.
    private func freeFileURL(forID id: String) throws(IndicatorThemeStoreError) -> URL {
        try validating(id: id)
        func candidate(_ suffix: String) -> URL {
            directory.appendingPathComponent(id + suffix).appendingPathExtension(Self.fileExtension)
        }
        var destination = candidate("")
        var ordinal = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = candidate("-\(ordinal)")
            ordinal += 1
        }
        return destination
    }

    private static func reading(_ file: URL) -> Result<IndicatorTheme, IndicatorThemeIssue> {
        if let size = FileManager.default.indicatorFileSize(at: file), size > IndicatorTheme.maxFileBytes {
            return .failure(.unreadable("the file is larger than \(IndicatorTheme.maxFileBytes / 1024) KB"))
        }
        guard let data = try? Data(contentsOf: file) else { return .failure(.unreadable("the file cannot be opened")) }
        return IndicatorTheme.decoding(data, fileName: file.lastPathComponent)
    }

    private static func writing(
        _ theme: IndicatorTheme,
        to destination: URL,
        creating directory: URL?
    ) throws(IndicatorThemeStoreError) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            if let directory {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            }
            try encoder.encode(theme).write(to: destination, options: .atomic)
        } catch {
            throw .writeFailed(error.localizedDescription)
        }
    }

    private static func freeID(base: String, existing: [IndicatorTheme]) -> String {
        let taken = Set(existing.map(\.id))
        func candidate(_ suffix: String) -> String {
            String(base.prefix(IndicatorTheme.maxIDLength - suffix.count)) + suffix
        }
        var id = candidate("")
        var ordinal = 2
        while taken.contains(id) {
            id = candidate("-\(ordinal)")
            ordinal += 1
        }
        return id
    }
}
