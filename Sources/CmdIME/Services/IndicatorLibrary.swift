import AppKit
import KeyboardSwitcherCore

/// Themes and imported fonts as the app sees them. Owns both stores (whose
/// directories sit beside the config file) and the font registrar. Creating it
/// registers the imported fonts, so it is touched once at launch.
@MainActor
final class IndicatorLibrary: ObservableObject {
    static let unusableFontMessage = "Not a usable font file."

    @Published private(set) var listing: IndicatorThemeListing
    @Published private(set) var fonts: [IndicatorFontRegistrar.Entry] = []
    /// The last failure of a theme or font operation, shown inline by the settings.
    @Published var message: String?

    private let themeStore: IndicatorThemeStore
    private let fontStore: FontStore
    private let registrar = IndicatorFontRegistrar()

    var themes: [IndicatorTheme] { listing.themes }
    var themesDirectory: URL { themeStore.directory }
    var fontsDirectory: URL { fontStore.directory }
    var importedFamilies: [String] {
        Array(Set(fonts.filter(\.isLoaded).flatMap(\.families)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    init(configStore: ConfigStore) {
        themeStore = IndicatorThemeStore(configStore: configStore)
        fontStore = FontStore(configStore: configStore)
        listing = themeStore.listing()
        reloadFonts()
    }

    func theme(id: String?) -> IndicatorTheme {
        themes.first { $0.id == id }
            ?? themes.first { $0.id == BuiltInIndicatorThemes.defaultID }
            ?? BuiltInIndicatorThemes.all[0]
    }

    func themeNames(using family: String) -> [String] {
        themes.filter { $0.typography.displayFamily?.caseInsensitiveCompare(family) == .orderedSame }.map(\.name)
    }

    // MARK: - Themes

    func reloadThemes() {
        listing = themeStore.listing()
    }

    /// Saves an editable copy, with `change` already applied, and returns it; nil
    /// when it could not be written.
    func duplicate(_ theme: IndicatorTheme, applying change: (inout IndicatorTheme) -> Void = { _ in }) -> IndicatorTheme? {
        var copy = themeStore.duplicate(of: theme, existing: themes)
        change(&copy)
        return save(copy) ? copy : nil
    }

    @discardableResult
    func save(_ theme: IndicatorTheme) -> Bool {
        perform {
            try themeStore.saving(theme)
            reloadThemes()
        }
    }

    func importTheme(from url: URL) -> IndicatorTheme? {
        var imported: IndicatorTheme?
        perform {
            imported = try themeStore.importing(from: url, existing: themes)
            reloadThemes()
        }
        return imported
    }

    /// A built-in is exported as its editable copy: a file with a reserved id could
    /// not be imported again.
    func exportTheme(_ theme: IndicatorTheme, to url: URL) {
        let exported = theme.isBuiltIn ? themeStore.duplicate(of: theme, existing: themes) : theme
        perform { try themeStore.exporting(exported, to: url) }
    }

    /// Moves the theme file to the Trash: an edited theme has no original elsewhere,
    /// so a slip stays recoverable from Finder. False when nothing was removed.
    @discardableResult
    func removeTheme(id: String) -> Bool {
        perform {
            try themeStore.removing(id: id, toTrash: true)
            reloadThemes()
        }
    }

    // MARK: - Fonts

    func reloadFonts() {
        do {
            fonts = try fontStore.list().map(registrar.register)
        } catch {
            message = error.localizedDescription
        }
    }

    /// Copies each file in, checks that it really holds fonts, then registers it for
    /// this process. A file with no usable font is removed again.
    func importFonts(from urls: [URL]) {
        message = nil
        for url in urls {
            do {
                let font = try fontStore.importing(from: url)
                if registrar.families(in: font.url).isEmpty {
                    try? fontStore.removing(font)
                    message = Self.unusableFontMessage
                }
            } catch {
                message = error.localizedDescription
            }
        }
        reloadFonts()
    }

    /// No confirmation: the original file is elsewhere. Themes that used the family
    /// fall back to the system font and say so.
    func removeFont(_ entry: IndicatorFontRegistrar.Entry) {
        registrar.unregister(entry.font)
        perform { try fontStore.removing(entry.font) }
        reloadFonts()
    }

    func revealInFinder(_ directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([directory])
    }

    @discardableResult
    private func perform(_ work: () throws -> Void) -> Bool {
        do {
            try work()
            message = nil
            return true
        } catch {
            message = error.localizedDescription
            return false
        }
    }
}
