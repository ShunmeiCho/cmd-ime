#if os(macOS)
import XCTest
@testable import KeyboardSwitcherCore

final class InputSourceRefreshTests: XCTestCase {
    private func helper(_ body: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("scanner")
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    @MainActor
    func testFreshScanPassesArgumentsAndAcceptsAnEmptyList() async throws {
        let executable = try helper(#"[ "$#" = 2 ] && [ "$1" = scan ] && [ "$2" = --json ] || exit 7; printf '[]'"#)
        let result = try await MacInputSourceService().refreshedInputSources(using: executable)
        XCTAssertEqual(result.sources, [])
        XCTAssertNil(result.fallbackReason)
    }

    @MainActor
    func testFreshScanFallsBackWhenHelperIsMissingOrCannotLaunch() async throws {
        let service = MacInputSourceService()
        let missing = try await service.refreshedInputSources(using: nil)
        XCTAssertEqual(missing.fallbackReason, "The bundled keyboardctl scanner is unavailable.")
        XCTAssertEqual(missing.sources, try service.listInputSources())

        let absent = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let failed = try await service.refreshedInputSources(using: absent)
        XCTAssertNotNil(failed.fallbackReason)
        XCTAssertEqual(failed.sources, try service.listInputSources())
    }

    @MainActor
    func testFreshScanFallsBackOnNonzeroExitEvenWithValidJSON() async throws {
        let executable = try helper("printf '[]'; exit 7")
        let result = try await MacInputSourceService().refreshedInputSources(using: executable)
        XCTAssertEqual(result.fallbackReason, "The input-source scanner exited with status 7.")
    }

    @MainActor
    func testFreshScanFallsBackOnInvalidJSON() async throws {
        let executable = try helper("printf 'not JSON'")
        let result = try await MacInputSourceService().refreshedInputSources(using: executable)
        XCTAssertNotNil(result.fallbackReason)
    }

    @MainActor
    func testFreshScanTimesOutAndFallsBack() async throws {
        // exec ensures timeout cleanup only has the one scanner process to stop.
        let executable = try helper("exec /bin/sleep 30")
        let result = try await MacInputSourceService().refreshedInputSources(using: executable)
        XCTAssertEqual(result.fallbackReason, "The input-source scanner did not finish in time.")
    }

    @MainActor
    func testFreshScanCancellationPropagatesWithoutFallback() async throws {
        let executable = try helper("exec /bin/sleep 30")
        let task = Task { @MainActor in
            try await MacInputSourceService().refreshedInputSources(using: executable)
        }
        try await Task.sleep(for: .milliseconds(75))
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancellation must not return a stale fallback list")
        } catch is CancellationError {
            // Expected: an obsolete refresh cannot overwrite a newer snapshot.
        }
    }
}
#endif
