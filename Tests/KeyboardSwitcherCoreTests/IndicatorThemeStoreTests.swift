import XCTest
@testable import KeyboardSwitcherCore

final class IndicatorThemeStoreTests: XCTestCase {
    private var root: URL!
    private var store: IndicatorThemeStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = IndicatorThemeStore(configStore: ConfigStore(url: root.appendingPathComponent("config.json")))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ json: String, as fileName: String) throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data(json.utf8).write(to: store.directory.appendingPathComponent(fileName))
    }

    func testDirectoriesAreDerivedFromTheConfigURL() {
        let config = ConfigStore(url: URL(fileURLWithPath: "/tmp/custom/place/settings.json"))
        XCTAssertEqual(config.themesDirectoryURL.path, "/tmp/custom/place/themes")
        XCTAssertEqual(config.fontsDirectoryURL.path, "/tmp/custom/place/fonts")
        XCTAssertEqual(store.directory.path, root.appendingPathComponent("themes").path)
    }

    func testMissingDirectoryListsBuiltInsOnly() {
        let listing = store.listing()
        XCTAssertEqual(listing.themes, BuiltInIndicatorThemes.all)
        XCTAssertTrue(listing.rejected.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testBadFilesAreRejectedWhileNeighboursLoad() throws {
        try write(#"{"schemaVersion": 1, "name": "Zebra"}"#, as: "zebra.json")
        try write(#"{"schemaVersion": 1, "name": "Apple"}"#, as: "apple.json")
        try write(#"{"schemaVersion": 1, "id": "apple"}"#, as: "b-duplicate.json")
        try write("{", as: "broken.json")
        try write(String(repeating: " ", count: IndicatorTheme.maxFileBytes + 1), as: "huge.json")
        try write("ignored", as: "notes.txt")

        let listing = store.listing()

        XCTAssertEqual(listing.themes.dropFirst(BuiltInIndicatorThemes.all.count).map(\.name), ["Apple", "Zebra"])
        XCTAssertEqual(listing.rejected, [
            .init(fileName: "b-duplicate.json", issue: .duplicateID("apple")),
            .init(fileName: "broken.json", issue: .notJSON),
            .init(fileName: "huge.json", issue: .unreadable("the file is larger than 64 KB")),
        ])
    }

    func testBuiltInsCannotBeSavedOrRemovedAndUnsafeIDsAreRejected() {
        let glass = BuiltInIndicatorThemes.all[0]
        XCTAssertThrowsError(try store.saving(glass)) {
            XCTAssertEqual($0 as? IndicatorThemeStoreError, .builtInIsReadOnly("builtin.glass"))
        }
        XCTAssertThrowsError(try store.removing(id: "builtin.glass")) {
            XCTAssertEqual($0 as? IndicatorThemeStoreError, .builtInIsReadOnly("builtin.glass"))
        }
        for id in ["../escape", "a/b", "", "UPPER"] {
            XCTAssertThrowsError(try store.saving(IndicatorTheme(id: id, name: "x")), id) {
                XCTAssertEqual($0 as? IndicatorThemeStoreError, .invalidName(id))
            }
        }
        XCTAssertThrowsError(try store.removing(id: "absent")) {
            XCTAssertEqual($0 as? IndicatorThemeStoreError, .notFound("absent"))
        }
        XCTAssertEqual(IndicatorThemeStore.sanitizedID(" My Theme/2 "), "my-theme-2")
        XCTAssertNil(IndicatorThemeStore.sanitizedID("../.."))
    }

    func testDuplicateNamesCopiesWithoutWriting() {
        let glass = BuiltInIndicatorThemes.all[0]
        let first = store.duplicate(of: glass, existing: BuiltInIndicatorThemes.all)
        XCTAssertEqual([first.id, first.name], ["glass-copy", "Glass Copy"])
        XCTAssertFalse(first.isBuiltIn)
        let second = store.duplicate(of: glass, existing: BuiltInIndicatorThemes.all + [first])
        XCTAssertEqual(second.id, "glass-copy-2")
        let third = store.duplicate(of: first, existing: [first, second])
        XCTAssertEqual(third.id, "glass-copy-copy")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }

    func testSaveExportImportRoundTripAndRemove() throws {
        var theme = store.duplicate(of: BuiltInIndicatorThemes.all[3], existing: BuiltInIndicatorThemes.all)
        theme.typography.textScale = 1.3
        let saved = try store.saving(theme)
        XCTAssertEqual(saved.lastPathComponent, "paper-two-inks-copy.json")
        XCTAssertEqual(store.listing().themes.last, theme)

        let exported = root.appendingPathComponent("shared.json")
        try store.exporting(theme, to: exported)
        let imported = try store.importing(from: exported, existing: store.listing().themes)
        XCTAssertEqual(imported.id, "paper-two-inks-copy-2")
        var expected = theme
        expected.id = imported.id
        XCTAssertEqual(imported, expected)
        XCTAssertEqual(store.listing().themes.count, BuiltInIndicatorThemes.all.count + 2)

        try store.removing(id: theme.id)
        XCTAssertEqual(store.listing().themes.last?.id, imported.id)
    }

    func testImportValidatesBeforeCopying() throws {
        let source = root.appendingPathComponent("bad.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(#"{"schemaVersion": 1, "surface": "velvet"}"#.utf8).write(to: source)
        XCTAssertThrowsError(try store.importing(from: source, existing: [])) {
            XCTAssertEqual($0 as? IndicatorThemeStoreError, .invalid(.unknownValue(key: "surface", value: "velvet")))
        }
        XCTAssertThrowsError(try store.importing(from: root.appendingPathComponent("absent.json"), existing: [])) {
            XCTAssertEqual($0 as? IndicatorThemeStoreError, .notFound("absent.json"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.path))
    }
}
