import Foundation
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

struct LauncherDefaultTests {
    private func roundTrip(_ config: SwitcherConfig) throws -> (SwitcherConfig, String) {
        let data = try JSONEncoder().encode(config)
        return (try JSONDecoder().decode(SwitcherConfig.self, from: data), String(decoding: data, as: UTF8.self))
    }

    @Test("a config without the key opens launchers in English, and English is never written")
    func missingKeyIsEnglish() throws {
        let (decoded, json) = try roundTrip(.default)

        #expect(decoded.launcherDefault == .english)
        #expect(!json.contains("launcherDefault"))
    }

    @Test("a slot or Same as other apps survives a save")
    func roundTrips() throws {
        for value in [LauncherDefault.slot(.chinese), .sameAsOtherApps] {
            var config = SwitcherConfig.default
            config.launcherDefault = value
            #expect(try roundTrip(config).0.launcherDefault == value)
        }
    }

    @Test("a kind from a newer build reads as English instead of failing the file")
    func unknownKindIsEnglish() throws {
        var config = SwitcherConfig.default
        config.launcherDefault = .sameAsOtherApps
        let json = String(decoding: try JSONEncoder().encode(config), as: UTF8.self)
            .replacingOccurrences(of: "\"apps\"", with: "\"future\"")

        let decoded = try JSONDecoder().decode(SwitcherConfig.self, from: Data(json.utf8))
        #expect(decoded.launcherDefault == .english)
    }

    @Test("the launcher slot follows the choice; a deleted slot falls back to English")
    func resolvesTheSlot() {
        var config = SwitcherConfig.default
        config.launcherDefault = .slot(.japanese)
        #expect(AppActivationSettings(config: config).launcherSlot == .japanese)

        config.launcherDefault = .slot(InputRole(rawValue: "gone"))
        #expect(AppActivationSettings(config: config).launcherSlot == .english)

        config.launcherDefault = .sameAsOtherApps
        #expect(AppActivationSettings(config: config).launcherSlot == nil)
    }

    @Test("Same as other apps gives a launcher the default slot")
    func sameAsOtherAppsUsesDefaultSlot() {
        var config = SwitcherConfig.default
        config.launcherDefault = .sameAsOtherApps
        config.appDefaultSlot = .chinese
        let settings = AppActivationSettings(config: config)

        #expect(settings.target(for: "com.raycast.macos", rememberedSourceID: nil) == .slot(.chinese))
    }

    @Test("Spotlight on macOS 27 is shown under its own name")
    func spotlightDisplayName() {
        #expect(LauncherCatalog.displayName(for: "com.apple.campo") == "Spotlight (Siri AI)")
        #expect(LauncherCatalog.displayName(for: "com.raycast.macos") == nil)
    }
}
