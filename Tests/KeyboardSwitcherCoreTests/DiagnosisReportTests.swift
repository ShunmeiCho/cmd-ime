import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct DiagnosisReportTests {
    private let abc = InputSourceInfo(
        id: "com.apple.keylayout.ABC", localizedName: "ABC", languages: ["en"], isSelectCapable: true
    )

    private func englishOnlyConfig() -> SwitcherConfig {
        var config = SwitcherConfig.default
        config.slots = [SwitchSlot(id: InputRole(rawValue: "english"), name: "English", tintHex: "#000000")]
        config.inputSources = [
            "english": RoleInputSourcePreference(preferredIDs: ["com.apple.keylayout.ABC"]),
        ]
        return config
    }

    @Test("the text names the current source, the memory setting and each slot's match")
    func textReport() {
        let report = DiagnosisReport(
            current: abc, config: englishOnlyConfig(), sources: [abc], systemPerDocumentSwitching: true
        )

        let lines = report.text.components(separatedBy: "\n")

        #expect(lines.first == "Current input source: ABC (com.apple.keylayout.ABC)")
        #expect(lines.contains("Remember input source per app: off"))
        #expect(lines.contains { $0.hasPrefix("macOS \"Automatically switch") })
        #expect(lines.contains("[english] English"))
        #expect(lines.contains("  matched: ABC (com.apple.keylayout.ABC) languages=en"))
    }

    @Test("a slot with no matching source says so, and an unknown current source reads unknown")
    func missingMatch() {
        let report = DiagnosisReport(
            current: nil, config: englishOnlyConfig(), sources: [], systemPerDocumentSwitching: false
        )

        #expect(report.text.hasPrefix("Current input source: unknown"))
        #expect(report.text.contains("  matched: none"))
        #expect(!report.text.contains("Automatically switch"))
    }

    @Test("Copy Diagnostics starts with the versions, the listener state and both permissions")
    func appSummary() {
        let summary = DiagnosisReport.appSummary(
            appVersion: "0.12.0", build: "42",
            macOSVersion: OperatingSystemVersion(majorVersion: 27, minorVersion: 2, patchVersion: 0),
            keyboardControl: "Active", accessibilityGranted: true, inputMonitoringGranted: false
        )

        #expect(summary.components(separatedBy: "\n") == [
            "CmdIME 0.12.0 (42)",
            "macOS 27.2",
            "Keyboard control: Active",
            "Accessibility: granted",
            "Input Monitoring: not granted",
        ])
    }

    @Test("the JSON keeps the keys keyboardctl diagnose --json has always printed")
    func jsonKeys() throws {
        let report = DiagnosisReport(
            current: abc, config: englishOnlyConfig(), sources: [abc], systemPerDocumentSwitching: false
        )

        let object = try #require(
            JSONSerialization.jsonObject(with: Data(report.json.utf8)) as? [String: Any]
        )
        let slots = try #require(object["slots"] as? [[String: Any]])

        #expect(Set(object.keys).isSuperset(of: [
            "currentInputSourceID", "currentInputSourceName", "rememberInputSourcePerApp",
            "systemPerDocumentSwitching", "slots",
        ]))
        #expect(slots.first?["matchedSourceID"] as? String == "com.apple.keylayout.ABC")
    }
}
