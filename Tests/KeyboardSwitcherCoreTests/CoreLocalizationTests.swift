import Foundation
import Testing
@testable import KeyboardSwitcherCore

struct CoreLocalizationTests {
    @Test("Only the CmdIME executable localizes, even in a bundle identifying as CmdIME")
    func executableGate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.shunmei.cmd-ime", "CFBundleExecutable": "CmdIME"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        let strings = ["Selected %@.": "已选中 %@。", "Tap %@ alone": "%@ だけをタップ"]
        try PropertyListSerialization.data(fromPropertyList: strings, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Localizable.strings"))
        let bundle = try #require(Bundle(path: directory.path))

        #expect(CoreLocalization.resolve("Selected %@.", arguments: ["中文"], bundle: bundle,
                                         executablePath: "/Applications/CmdIME.app/Contents/MacOS/CmdIME") == "已选中 中文。")
        #expect(CoreLocalization.resolve("Tap %@ alone", arguments: ["左 Command"], bundle: bundle,
                                         executablePath: "/Applications/CmdIME.app/Contents/MacOS/CmdIME") == "左 Command だけをタップ")
        for executable in ["/Applications/CmdIME.app/Contents/MacOS/keyboardctl", "/usr/local/bin/keyboardctl", "CmdIMETests", "cmdime", ""] {
            #expect(CoreLocalization.resolve("Selected %@.", arguments: ["中文"], bundle: bundle,
                                             executablePath: executable) == "Selected 中文.")
        }
        #expect(CoreLocalization.resolve("Missing %@", arguments: ["100%"], bundle: bundle,
                                         executablePath: "CmdIME") == "Missing 100%")
    }

    @Test("English CLI messages and persisted defaults remain unchanged")
    func englishFallback() throws {
        #expect(CoreLocalization.text("Selected %@.", "50% input") == "Selected 50% input.")
        #expect(CoreLocalization.text("100% ready") == "100% ready")
        #expect(SettingsTransferError.newerVersion(found: 9, supported: 2).errorDescription ==
                "These settings come from a newer CmdIME (config version 9; this one reads up to 2). Update CmdIME, then import them.")
        #expect(SwitcherConfig.default.slots.map(\.name) == ["English", "Chinese", "Japanese"])
        let trigger = try ShortcutParser.parse("double-left-command")
        #expect(trigger.displayName == "double-left-command")
        #expect(SetupTriggerPhrase(trigger: trigger).instruction == "Double-tap Left Command alone")
    }
}
