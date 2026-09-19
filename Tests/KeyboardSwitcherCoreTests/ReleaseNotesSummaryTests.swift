import XCTest
@testable import KeyboardSwitcherCore

final class ReleaseNotesSummaryTests: XCTestCase {
    func testKeepsTheOpeningSentenceAndTheTitleOfEachChange() {
        let notes = """
        ## CmdIME v0.6.2 Preview

        Switching to Google Japanese Input now lands in Hiragana.

        ### Fixes

        - **Google Japanese Input no longer stays in Latin after a switch (#4).** After you had typed under ABC, it stayed detached.

        ### New

        - **Activation recipes.** Add a recipe to `activation-recipes.json`:

          ```json
          { "recipes": [ { "sourceIDPrefix": "- not a bullet" } ] }
          ```

          - A nested point that belongs to the item above.
        - A plain bullet with a [link](https://example.com). Second sentence.

        ### Known limits

        - The Kana key is a real key event.

        ### Download and install

        - not a change
        """
        XCTAssertEqual(ReleaseNotesSummary.parse(notes), ReleaseNotesSummary(
            headline: "Switching to Google Japanese Input now lands in Hiragana.",
            items: [
                "Google Japanese Input no longer stays in Latin after a switch (#4)",
                "Activation recipes",
                "A plain bullet with a link",
            ]
        ))
    }

    func testEmptyOrOverlongNotesStayWithinBounds() {
        XCTAssertTrue(ReleaseNotesSummary.parse("").isEmpty)
        XCTAssertTrue(ReleaseNotesSummary.parse("## Only a heading").isEmpty)
        let many = (1...20).map { "- " + String(repeating: "word ", count: 60) + "\($0)" }.joined(separator: "\n")
        let summary = ReleaseNotesSummary.parse(many)
        XCTAssertEqual(summary.items.count, ReleaseNotesSummary.maxItems)
        XCTAssertTrue(summary.items.allSatisfy { $0.count <= ReleaseNotesSummary.maxItemLength })
    }
}
