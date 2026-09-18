import XCTest
@testable import KeyboardSwitcherCore

final class FontStoreTests: XCTestCase {
    private var root: URL!
    private var store: FontStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = FontStore(configStore: ConfigStore(url: root.appendingPathComponent("config.json")))
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    /// The store handles files, not font data, so any bytes will do.
    private func makeFile(_ name: String, bytes: Int = 16) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(repeating: 1, count: bytes).write(to: url)
        return url
    }

    func testMissingDirectoryListsAsEmpty() throws {
        XCTAssertEqual(store.directory.path, root.appendingPathComponent("fonts").path)
        XCTAssertEqual(try store.list(), [])
    }

    func testImportCopiesListsAndNeverOverwrites() throws {
        let source = try makeFile("Söhne Buch.OTF")
        let first = try store.importing(from: source)
        let second = try store.importing(from: source)

        XCTAssertEqual(first.fileName, "Söhne Buch.otf")
        XCTAssertEqual(second.fileName, "Söhne Buch-2.otf")
        XCTAssertEqual(first.url.deletingLastPathComponent().path, store.directory.path)
        XCTAssertEqual(try store.list(), [second, first])
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testImportRejectsWrongTypeMissingAndOversizedFiles() throws {
        XCTAssertThrowsError(try store.importing(from: try makeFile("font.woff2"))) {
            XCTAssertEqual($0 as? FontStoreError, .unsupportedType("woff2"))
        }
        XCTAssertThrowsError(try store.importing(from: root.appendingPathComponent("absent.ttf"))) {
            XCTAssertEqual($0 as? FontStoreError, .notFound("absent.ttf"))
        }
        // A sparse file reports the size without writing 40 MB.
        let large = try makeFile("large.ttc", bytes: 0)
        let handle = try FileHandle(forWritingTo: large)
        try handle.truncate(atOffset: UInt64(FontStore.maxFileBytes + 1))
        try handle.close()
        XCTAssertThrowsError(try store.importing(from: large)) {
            XCTAssertEqual($0 as? FontStoreError, .tooLarge(FontStore.maxFileBytes + 1))
        }
        XCTAssertEqual(try store.list(), [])
        for error in [FontStoreError.unsupportedType("x"), .tooLarge(1), .invalidName("x"), .notFound("x"), .copyFailed("x")] {
            XCTAssertFalse(try XCTUnwrap(error.errorDescription).isEmpty)
        }
    }

    func testFileNameSanitising() {
        XCTAssertEqual(FontStore.sanitizedFileName(" Inter.TTF "), "Inter.ttf")
        XCTAssertEqual(FontStore.sanitizedFileName("源ノ角ゴシック.otf"), "源ノ角ゴシック.otf")
        for name in ["", ".hidden.ttf", "../evil.ttf", "a/b.ttf", "a:b.ttf", "a\0.ttf", "..", "noextension", ".ttf", "font.exe"] {
            XCTAssertNil(FontStore.sanitizedFileName(name), name)
        }
    }

    func testRemoveDeletesOnlyInsideTheDirectory() throws {
        let outside = try makeFile("Keep.ttf")
        let imported = try store.importing(from: outside)

        let forged = ImportedFont(fileName: "../Keep.ttf", url: outside)
        XCTAssertThrowsError(try store.removing(forged)) {
            XCTAssertEqual($0 as? FontStoreError, .invalidName("../Keep.ttf"))
        }
        // The url of a font value is not trusted: only the name inside the directory is removed.
        try store.removing(ImportedFont(fileName: imported.fileName, url: outside))

        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try store.list(), [])
        XCTAssertThrowsError(try store.removing(imported)) {
            XCTAssertEqual($0 as? FontStoreError, .notFound("Keep.ttf"))
        }
    }

    func testListIgnoresForeignHiddenAndLinkedFiles() throws {
        let outside = try makeFile("Outside.ttf")
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        for name in ["Dropped.TTF", "readme.txt", ".DS_Store", ".secret.ttf"] {
            try Data([1]).write(to: store.directory.appendingPathComponent(name))
        }
        try FileManager.default.createDirectory(at: store.directory.appendingPathComponent("Folder.ttf"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: store.directory.appendingPathComponent("Link.ttf"), withDestinationURL: outside)

        let fonts = try store.list()

        XCTAssertEqual(fonts.map(\.fileName), ["Dropped.TTF"])
        try store.removing(fonts[0])
        XCTAssertEqual(try store.list(), [])
    }
}
