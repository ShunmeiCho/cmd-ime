import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct SystemInputSourceSettingsTests {
    @Test("the setting is read from the keys macOS writes")
    func keysMatchWhatMacOSWrites() {
        #expect(SystemInputSourceSettings.domain == "com.apple.HIToolbox")
        #expect(SystemInputSourceSettings.globalPropertiesKey == "AppleGlobalTextInputProperties")
        #expect(SystemInputSourceSettings.perDocumentKey == "TextInputGlobalPropertyPerContextInput")
    }

    @Test("an absent properties dictionary means the system setting is off")
    func absentMeansOff() {
        #expect(SystemInputSourceSettings.isPerDocumentSwitchingOn(globalProperties: nil) == false)
        #expect(SystemInputSourceSettings.isPerDocumentSwitchingOn(globalProperties: [String: Any]()) == false)
    }

    @Test("the stored flag is read as on or off", arguments: [(NSNumber(value: true), true), (NSNumber(value: 1), true), (NSNumber(value: 0), false)])
    func storedFlagIsRead(stored: NSNumber, expected: Bool) {
        let properties: [String: Any] = [SystemInputSourceSettings.perDocumentKey: stored]

        #expect(SystemInputSourceSettings.isPerDocumentSwitchingOn(globalProperties: properties) == expected)
    }

    @Test("a value of an unexpected type is treated as off")
    func unexpectedTypeIsOff() {
        let properties: [String: Any] = [SystemInputSourceSettings.perDocumentKey: "yes"]

        #expect(SystemInputSourceSettings.isPerDocumentSwitchingOn(globalProperties: properties) == false)
    }
}
