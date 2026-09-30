import Foundation
import Testing
@testable import KeyboardSwitcherCore

final class AppBundleScanTests {
    private let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppBundleScanTests-\(UUID().uuidString)")
        for path in [
            "Applications/Notes.app/Contents/MacOS",
            "Applications/Vendor Suite/Editor.app/Contents",
            "Applications/Vendor Suite/Extras/Helper.app",
            "Applications/One/Two/Three/Four/TooDeep.app",
            "Applications/Utilities/Terminal.app",
            "Applications/.Hidden.app",
        ] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(path), withIntermediateDirectories: true)
        }
        FileManager.default.createFile(atPath: root.appendingPathComponent("Applications/Readme.pdf").path, contents: Data())
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    private func names(_ urls: [URL]) -> [String] {
        urls.map(\.lastPathComponent).sorted()
    }

    @Test("apps in vendor subfolders are found, bundles are not entered and hidden items are skipped")
    func findsNestedApps() {
        let apps = AppBundleScan.appBundles(in: [root.appendingPathComponent("Applications")])

        #expect(names(apps) == ["Editor.app", "Helper.app", "Notes.app", "Terminal.app"])
    }

    @Test("folders deeper than the limit are not searched")
    func respectsDepth() {
        let apps = AppBundleScan.appBundles(in: [root.appendingPathComponent("Applications")], maxDepth: 4)

        #expect(names(apps).contains("TooDeep.app"))
        #expect(!names(AppBundleScan.appBundles(in: [root.appendingPathComponent("Applications")], maxDepth: 1)).contains("Helper.app"))
    }

    @Test("an app reachable from two roots is listed once")
    func overlappingRootsListOnce() {
        let apps = AppBundleScan.appBundles(in: [
            root.appendingPathComponent("Applications"),
            root.appendingPathComponent("Applications/Utilities"),
        ])

        #expect(names(apps).filter { $0 == "Terminal.app" }.count == 1)
    }

    @Test("only .app file URLs count as apps")
    func tellsAppsFromOtherFiles() {
        #expect(AppBundleScan.isAppBundle(URL(fileURLWithPath: "/Applications/Safari.app")))
        #expect(AppBundleScan.isAppBundle(URL(fileURLWithPath: "/Applications/Odd.APP")))
        #expect(!AppBundleScan.isAppBundle(URL(fileURLWithPath: "/Users/me/Readme.pdf")))
        #expect(!AppBundleScan.isAppBundle(URL(string: "https://example.com/x.app")!))
    }
}
