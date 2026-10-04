import Testing
@testable import KeyboardSwitcherCore

struct LauncherCatalogTests {
    @Test("Raycast, Spotlight and Alfred are launchers; an ordinary app is not")
    func knowsTheLaunchers() {
        for id in ["com.raycast.macos", "com.apple.campo", "com.apple.Spotlight", "com.runningwithcrayons.Alfred"] {
            #expect(LauncherCatalog.isLauncher(id))
        }
        #expect(!LauncherCatalog.isLauncher("com.apple.controlcenter"))
    }

    @Test("a launcher counts as an app though it is an accessory app; another accessory app does not")
    func launcherCountsAsApp() {
        #expect(LauncherCatalog.countsAsApp(bundleID: "com.raycast.macos", isRegularApp: false))
        #expect(LauncherCatalog.countsAsApp(bundleID: "com.apple.Safari", isRegularApp: true))
        #expect(!LauncherCatalog.countsAsApp(bundleID: "com.apple.controlcenter", isRegularApp: false))
        #expect(!LauncherCatalog.countsAsApp(bundleID: nil, isRegularApp: false))
    }
}

struct LauncherPresenceTests {
    @Test("a launcher read shows the panel, another app hides it")
    func showsAndHides() {
        var presence = LauncherPresence()

        let shown = presence.record(.launcher(29))
        let repeated = presence.record(.launcher(29))
        #expect(shown && !repeated)
        #expect(presence.launcherPID == 29)
        let hidden = presence.record(.other)
        #expect(hidden)
        #expect(presence.launcherPID == nil)
    }

    @Test("one failed read keeps a showing panel; two in a row hide it")
    func oneFailureDoesNotFlap() {
        var presence = LauncherPresence()
        _ = presence.record(.launcher(29))

        let first = presence.record(.failed)
        #expect(!first)
        #expect(presence.launcherPID == 29)
        let second = presence.record(.failed)
        #expect(second)
        #expect(presence.launcherPID == nil)
    }

    @Test("a good read between failures starts the count again")
    func goodReadResetsFailures() {
        var presence = LauncherPresence()
        _ = presence.record(.launcher(29))

        _ = presence.record(.failed)
        _ = presence.record(.launcher(29))
        let afterReset = presence.record(.failed)
        #expect(!afterReset)
        #expect(presence.launcherPID == 29)
    }

    @Test("a different launcher replaces the one showing")
    func switchesLaunchers() {
        var presence = LauncherPresence()
        _ = presence.record(.launcher(29))

        let replaced = presence.record(.launcher(719))
        #expect(replaced)
        #expect(presence.launcherPID == 719)
    }
}
