import Testing
@testable import KeyboardSwitcherCore

struct SettingsNavigationTests {
    @Test func opensOnSetupWhileTheFirstRunIsPending() {
        let navigation = SettingsNavigation(isSetupPending: true)

        #expect(navigation.selection == .setup)
    }

    @Test func opensOnSlotsOnceSetupIsDone() {
        let navigation = SettingsNavigation(isSetupPending: false)

        #expect(navigation.selection == .slots)
    }

    @Test func listsSetupFirstOnlyWhileItIsPending() {
        let pending = SettingsNavigation(isSetupPending: true)
        let done = SettingsNavigation(isSetupPending: false)

        #expect(pending.visiblePages == [.setup, .slots, .indicator, .general, .about])
        #expect(done.visiblePages == [.slots, .indicator, .general, .about])
    }

    @Test func leavingSetupForAnotherPageKeepsItListed() {
        var navigation = SettingsNavigation(isSetupPending: true)

        navigation.select(.slots)

        #expect(navigation.selection == .slots)
        #expect(navigation.visiblePages.first == .setup)
    }

    @Test func finishOrSkipSelectsSlotsAndRemovesSetup() {
        var navigation = SettingsNavigation(isSetupPending: true)

        navigation.completeSetup()

        #expect(navigation.selection == .slots)
        #expect(!navigation.visiblePages.contains(.setup))
    }

    @Test func replayListsSetupAgainAndSelectsIt() {
        var navigation = SettingsNavigation(isSetupPending: false)
        navigation.select(.general)

        navigation.replaySetup()

        #expect(navigation.selection == .setup)
        #expect(navigation.visiblePages.first == .setup)
    }

    @Test func aPageTheSidebarDoesNotListCannotBeSelected() {
        var navigation = SettingsNavigation(isSetupPending: false)

        navigation.select(.setup)

        #expect(navigation.selection == .slots)
    }
}
