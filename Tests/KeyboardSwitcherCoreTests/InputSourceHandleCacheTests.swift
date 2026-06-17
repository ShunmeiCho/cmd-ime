import XCTest
@testable import KeyboardSwitcherCore

final class InputSourceHandleCacheTests: XCTestCase {
    func testReturnsCachedHandleWithoutRebuilding() {
        var cache = InputSourceHandleCache<String>()
        var rebuildCount = 0
        let rebuild = { () -> [String: String] in
            rebuildCount += 1
            return ["a": "handle-a", "b": "handle-b"]
        }

        XCTAssertEqual(cache.handle(for: "a", rebuild: rebuild), "handle-a")
        XCTAssertEqual(cache.handle(for: "a", rebuild: rebuild), "handle-a")
        XCTAssertEqual(cache.handle(for: "b", rebuild: rebuild), "handle-b")

        // One rebuild populated the whole map; cached hits do not rebuild.
        XCTAssertEqual(rebuildCount, 1)
    }

    func testInvalidateForcesRebuild() {
        var cache = InputSourceHandleCache<String>()
        var rebuildCount = 0
        let rebuild = { () -> [String: String] in
            rebuildCount += 1
            return ["a": "handle-a"]
        }

        _ = cache.handle(for: "a", rebuild: rebuild)
        cache.invalidate()
        _ = cache.handle(for: "a", rebuild: rebuild)

        XCTAssertEqual(rebuildCount, 2)
    }

    func testMissingIdReturnsNil() {
        var cache = InputSourceHandleCache<String>()
        let rebuild = { ["a": "handle-a"] }

        XCTAssertNil(cache.handle(for: "missing", rebuild: rebuild))
        XCTAssertEqual(cache.handle(for: "a", rebuild: rebuild), "handle-a")
    }
}
