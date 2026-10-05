import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct PeekBindingTests {
    private func trigger(_ text: String) throws -> KeyTrigger {
        try ShortcutParser.parse(text)
    }

    @Test("setting a peek trigger adds one showIndicator binding and keeps the slot bindings")
    func setsThePeekTrigger() throws {
        let config = try SwitcherConfig.default.replacingPeekBinding(with: trigger("option+p"))

        #expect(config.peekBinding?.trigger == (try trigger("option+p")))
        #expect(config.peekBinding?.action == .showIndicator)
        #expect(config.bindings.filter { $0.action.type == .switchInputSource } == SwitcherConfig.default.bindings)
    }

    @Test("a second peek trigger replaces the first, and nil removes it")
    func replacesAndRemoves() throws {
        let first = try SwitcherConfig.default.replacingPeekBinding(with: trigger("option+p"))
        let second = try first.replacingPeekBinding(with: trigger("double-right-option"))

        #expect(second.bindings.filter { $0.action.type == .showIndicator }.count == 1)
        #expect(second.peekBinding?.trigger == (try trigger("double-right-option")))
        #expect(try second.replacingPeekBinding(with: nil).peekBinding == nil)
    }

    @Test("a trigger a slot already answers to is refused")
    func refusesATakenTrigger() throws {
        // The legacy defaults tap Left Command for English.
        #expect(throws: PeekBindingError.self) {
            try SwitcherConfig.default.replacingPeekBinding(with: trigger("left-command"))
        }
    }

    @Test("a double tap of a key whose single tap is a slot's is a different trigger")
    func doubleTapBesideASingleTapIsAllowed() throws {
        let config = try SwitcherConfig.default.replacingPeekBinding(with: trigger("double-left-command"))

        #expect(config.peekBinding?.trigger.gesture == .doubleTap)
    }

    @Test("macOS's own input-source shortcut is refused")
    func refusesTheReservedShortcut() throws {
        #expect(throws: PeekBindingError.reservedByMacOS(try trigger("control+space"))) {
            try SwitcherConfig.default.replacingPeekBinding(with: trigger("control+space"), reserved: MacInputSourceShortcuts.defaults)
        }
    }

    @Test("the CLI's bind takes the trigger from the slot that had it and reports it")
    func upsertDisplaces() throws {
        var config = SwitcherConfig.default

        let displaced = config.upsertPeekBinding(trigger: try trigger("left-command"))

        #expect(displaced.map(\.action.role) == [.english])
        #expect(config.peekBinding?.trigger == (try trigger("left-command")))
        #expect(!config.bindings.contains { $0.action.role == .english })
    }

    @Test("conflict messages name a peek owner by what it does")
    func ownerDescription() throws {
        let config = try SwitcherConfig.default.replacingPeekBinding(with: trigger("option+p"))
        let peek = try #require(config.peekBinding)

        #expect(config.ownerDescription(of: peek) == SwitcherConfig.peekDisplayName)
        #expect(config.ownerDescription(of: KeyBinding(trigger: try trigger("right-control"), action: .sendKey(try trigger("escape")))) == "a key remap")
    }

    @Test("a peek binding survives a save and reload")
    func roundTrip() throws {
        let config = try SwitcherConfig.default.replacingPeekBinding(with: trigger("option+p"))

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.peekBinding == config.peekBinding)
        #expect(decoded.unreadableBindingCount == 0)
    }
}
