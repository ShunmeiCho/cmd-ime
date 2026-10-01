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

    @Test("with the bubble on, a shown badge is hidden and a hidden one is left alone")
    func bubbleOnHides() {
        #expect(SystemInputIndicator.sync(bubbleOn: true, isHidden: false, hiddenByCmdIME: false) == .hide)
        #expect(SystemInputIndicator.sync(bubbleOn: true, isHidden: true, hiddenByCmdIME: false) == .keep)
        #expect(SystemInputIndicator.sync(bubbleOn: true, isHidden: true, hiddenByCmdIME: true) == .keep)
    }

    @Test("with the bubble off, only a badge CmdIME hid comes back")
    func bubbleOffRestoresOnlyItsOwn() {
        #expect(SystemInputIndicator.sync(bubbleOn: false, isHidden: true, hiddenByCmdIME: true) == .restore)
        #expect(SystemInputIndicator.sync(bubbleOn: false, isHidden: true, hiddenByCmdIME: false) == .keep)
        #expect(SystemInputIndicator.sync(bubbleOn: false, isHidden: false, hiddenByCmdIME: true) == .keep)
    }
}
