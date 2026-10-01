import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct SystemInputIndicatorTests {
    @Test("a missing key means macOS shows its badge")
    func missingKeyShows() {
        #expect(SystemInputIndicator.isHidden(storedValue: nil) == false)
    }

    @Test("a Boolean or number false hides the badge, true shows it")
    func booleansAndNumbers() {
        #expect(SystemInputIndicator.isHidden(storedValue: false) == true)
        #expect(SystemInputIndicator.isHidden(storedValue: true) == false)
        #expect(SystemInputIndicator.isHidden(storedValue: NSNumber(value: 0)) == true)
        #expect(SystemInputIndicator.isHidden(storedValue: NSNumber(value: 1)) == false)
    }

    @Test("the string a bare defaults write leaves is read as hidden")
    func stringsFromDefaultsWrite() {
        #expect(SystemInputIndicator.isHidden(storedValue: "0") == true)
        #expect(SystemInputIndicator.isHidden(storedValue: "NO") == true)
        #expect(SystemInputIndicator.isHidden(storedValue: "false") == true)
        #expect(SystemInputIndicator.isHidden(storedValue: "1") == false)
        #expect(SystemInputIndicator.isHidden(storedValue: "YES") == false)
    }
}
