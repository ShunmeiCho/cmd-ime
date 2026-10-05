import Foundation
import Testing
@testable import KeyboardSwitcherCore

@Suite("macOS input source shortcuts")
struct MacInputSourceShortcutsTests {
    private func entry(enabled: Int, keyCode: Int = 49, mask: Int) -> [String: Any] {
        ["enabled": NSNumber(value: enabled),
         "value": ["parameters": [NSNumber(value: 32), NSNumber(value: keyCode), NSNumber(value: mask)],
                   "type": "standard"]]
    }

    @Test("a never-changed setting reserves Control+Space and Control+Option+Space")
    func missingEntriesUseDefaults() {
        #expect(MacInputSourceShortcuts.enabledChords(hotKeys: nil) == MacInputSourceShortcuts.defaults)
        #expect(MacInputSourceShortcuts.enabledChords(hotKeys: [String: Any]()) == MacInputSourceShortcuts.defaults)
    }

    @Test("shortcuts turned off in System Settings reserve nothing")
    func disabledEntriesReserveNothing() throws {
        let hotKeys: [String: Any] = ["60": entry(enabled: 0, mask: 0x40000), "61": entry(enabled: 0, mask: 0xC0000)]
        let chords = MacInputSourceShortcuts.enabledChords(hotKeys: hotKeys)

        #expect(chords.isEmpty)
        #expect(!(try ShortcutParser.parse("control+space")).isReserved(by: chords))
        let config = try SwitcherConfig.default.replacingToggleBinding(
            with: ShortcutParser.parse("control+space"), slots: .english, .chinese, reserved: chords
        )
        #expect(config.toggleBinding?.trigger == (try ShortcutParser.parse("control+space")))
    }

    @Test("a shortcut moved to another chord reserves that chord instead")
    func movedEntryReservesItsChord() throws {
        let hotKeys: [String: Any] = ["60": entry(enabled: 1, keyCode: 49, mask: 0x120000), "61": entry(enabled: 0, mask: 0xC0000)]
        let chords = MacInputSourceShortcuts.enabledChords(hotKeys: hotKeys)

        #expect(chords == [SystemChord(keyCode: 49, modifiers: [.command, .shift])])
        #expect(try ShortcutParser.parse("command+shift+space").isReserved(by: chords))
        #expect(!(try ShortcutParser.parse("control+space")).isReserved(by: chords))
        #expect(throws: PeekBindingError.reservedByMacOS(try ShortcutParser.parse("command+shift+space"))) {
            try SwitcherConfig.default.replacingPeekBinding(with: ShortcutParser.parse("command+shift+space"), reserved: chords)
        }
    }

    @Test("a cleared chord reserves nothing")
    func clearedEntryReservesNothing() {
        let hotKeys: [String: Any] = ["60": entry(enabled: 1, keyCode: 65535, mask: 0), "61": entry(enabled: 0, mask: 0xC0000)]
        #expect(MacInputSourceShortcuts.enabledChords(hotKeys: hotKeys).isEmpty)
    }
}
