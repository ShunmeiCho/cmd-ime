import XCTest
@testable import KeyboardSwitcherCore

final class SourceCommandPolicyTests: XCTestCase {
    func testNoArgumentsReadsTheCurrentSource() {
        XCTAssertEqual(SourceCommandPolicy.parse([]), .read)
        XCTAssertEqual(SourceCommandPolicy.parse(["current"]), .read)
        XCTAssertEqual(SourceCommandPolicy.parse(["--json"]), .read)
    }

    func testAnIDSelectsItWithOrWithoutTheVerb() {
        let id = "com.apple.keylayout.ABC"
        XCTAssertEqual(SourceCommandPolicy.parse([id]), .select(id: id, waitMilliseconds: nil))
        XCTAssertEqual(SourceCommandPolicy.parse(["select", id]), .select(id: id, waitMilliseconds: nil))
        XCTAssertEqual(SourceCommandPolicy.parse([id, "--quiet"]), .select(id: id, waitMilliseconds: nil))
    }

    func testWaitIsReadFromTheSecondArgumentAndNeverRejected() {
        let id = "com.apple.keylayout.ABC"
        XCTAssertEqual(SourceCommandPolicy.parse([id, "120"]), .select(id: id, waitMilliseconds: 120))
        XCTAssertEqual(SourceCommandPolicy.parse([id, "-5"]), .select(id: id, waitMilliseconds: 0))
        XCTAssertEqual(SourceCommandPolicy.parse([id, "soon"]), .select(id: id, waitMilliseconds: nil))
    }

    func testOnlyADottedUnknownTokenIsTreatedAsAnID() {
        let commands: Set<String> = ["scan", "source", "switch"]
        XCTAssertTrue(SourceCommandPolicy.looksLikeInputSourceID("com.apple.keylayout.ABC", knownCommands: commands))
        XCTAssertFalse(SourceCommandPolicy.looksLikeInputSourceID("nonsense", knownCommands: commands))
        XCTAssertFalse(SourceCommandPolicy.looksLikeInputSourceID("scan", knownCommands: commands))
        XCTAssertFalse(SourceCommandPolicy.looksLikeInputSourceID("--json", knownCommands: commands))
    }

    func testRejectionTellsInstalledAndDisabledApartFromUnknown() {
        let keyboard: Set<String> = ["com.apple.keylayout.ABC"]
        XCTAssertNil(SourceCommandPolicy.rejection(
            for: "com.apple.keylayout.ABC",
            selectable: ["com.apple.keylayout.ABC"],
            keyboardSources: keyboard,
            isInstalled: true
        ))
        XCTAssertEqual(
            SourceCommandPolicy.rejection(
                for: "com.apple.keylayout.Dvorak", selectable: [], keyboardSources: keyboard, isInstalled: true
            ),
            .installedButNotEnabled(id: "com.apple.keylayout.Dvorak")
        )
        XCTAssertEqual(
            SourceCommandPolicy.rejection(
                for: "com.example.nope", selectable: [], keyboardSources: keyboard, isInstalled: false
            ),
            .unknown(id: "com.example.nope")
        )
    }

    func testAPaletteSourceIsRejectedEvenThoughItIsSelectable() {
        XCTAssertEqual(
            SourceCommandPolicy.rejection(
                for: "com.apple.CharacterPaletteIM",
                selectable: ["com.apple.CharacterPaletteIM"],
                keyboardSources: ["com.apple.keylayout.ABC"],
                isInstalled: true
            ),
            .notAKeyboardSource(id: "com.apple.CharacterPaletteIM")
        )
    }

    func testRetryStopsWhenSomethingElseMovedTheInputSource() {
        XCTAssertFalse(SourceCommandPolicy.shouldRetrySelection(current: "target", target: "target", previous: "abc"))
        XCTAssertTrue(SourceCommandPolicy.shouldRetrySelection(current: "abc", target: "target", previous: "abc"))
        XCTAssertFalse(SourceCommandPolicy.shouldRetrySelection(current: "someone.else", target: "target", previous: "abc"))
        XCTAssertTrue(SourceCommandPolicy.shouldRetrySelection(current: nil, target: "target", previous: "abc"))
    }
}
