import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct AppMemoryConfigTests {
    @Test("a config written before App Memory existed reads it as off")
    func missingKeyDecodesOff() throws {
        let json = Data(#"{"version": 3, "bindings": [], "inputSources": {}}"#.utf8)

        let config = try JSONDecoder().decode(SwitcherConfig.self, from: json)

        #expect(config.rememberInputSourcePerApp == false)
    }

    @Test("fresh and detected configs start with App Memory off")
    func freshConfigsAreOff() {
        #expect(SwitcherConfig.default.rememberInputSourcePerApp == false)
        #expect(SwitcherConfig.detected(from: []).rememberInputSourcePerApp == false)
    }

    @Test("turning App Memory on survives a save and reload")
    func roundTripKeepsTheSetting() throws {
        var config = SwitcherConfig.default
        config.rememberInputSourcePerApp = true

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: JSONEncoder().encode(config))

        #expect(decoded.rememberInputSourcePerApp == true)
    }
}
