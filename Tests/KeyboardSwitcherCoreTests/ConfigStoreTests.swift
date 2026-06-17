import XCTest
@testable import KeyboardSwitcherCore

final class ConfigStoreTests: XCTestCase {
    func testDefaultConfigContainsThreeRoleBindings() {
        let config = SwitcherConfig.default

        let roles = Set(config.bindings.compactMap(\.action.role))

        XCTAssertEqual(roles, Set(InputRole.allCases))
    }

    func testConfigRoundTripsThroughJSON() throws {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("config.json")
        let store = ConfigStore(url: url)
        let config = SwitcherConfig.default

        try store.save(config)
        let loaded = try store.load()

        XCTAssertEqual(loaded, config)
    }

    func testLegacyConfigDefaultsMenuBarIconToVisible() throws {
        let json = """
        {
          "version": 1,
          "bindings": [],
          "inputSources": {}
        }
        """

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.showMenuBarIcon)
    }

    func testLegacyConfigDefaultsSwitchIndicatorToVisible() throws {
        let json = """
        {
          "version": 1,
          "bindings": [],
          "inputSources": {}
        }
        """

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))

        XCTAssertTrue(config.showSwitchIndicator)
        XCTAssertEqual(config.switchIndicatorSize, .medium)
        XCTAssertEqual(config.switchIndicatorColorStyle, .role)
    }

    func testUpsertSwitchBindingReplacesExistingRoleBinding() {
        var config = SwitcherConfig.default
        let trigger = KeyTrigger(kind: .oneShotModifier, keyCode: 58, keyName: "left-option")

        config.upsertSwitchBinding(trigger: trigger, role: .japanese)

        let japaneseBindings = config.bindings.filter { binding in
            binding.action.type == .switchInputSource && binding.action.role == .japanese
        }

        XCTAssertEqual(japaneseBindings.map(\.trigger), [trigger])
    }
}
