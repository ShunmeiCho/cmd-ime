import Foundation

/// The pages of the settings window, in sidebar order. Adding a page is one case here;
/// the settings window then asks for its label and its content.
public enum SettingsPage: String, CaseIterable, Hashable, Sendable {
    /// The first-run setup guide. Listed only while it is pending or replayed.
    case setup
    case slots
    case indicator
    case general
    case about
}

/// Which pages the sidebar lists and which one is selected. The window keeps one value
/// for the session; the stored `hasCompletedSetup` only decides where it starts.
public struct SettingsNavigation: Equatable, Sendable {
    /// Setup is in the sidebar: the first run is still pending, or General replayed it.
    public private(set) var listsSetup: Bool
    public private(set) var selection: SettingsPage

    /// Opens on Setup while the first run is pending, else on Slots.
    public init(isSetupPending: Bool) {
        listsSetup = isSetupPending
        selection = isSetupPending ? .setup : .slots
    }

    public var visiblePages: [SettingsPage] {
        SettingsPage.allCases.filter { $0 != .setup || listsSetup }
    }

    /// A sidebar click or a jump from a page. A page the sidebar does not list is ignored.
    public mutating func select(_ page: SettingsPage) {
        guard visiblePages.contains(page) else { return }
        selection = page
    }

    /// Finish, Skip or Close: Setup leaves the sidebar and Slots is selected.
    public mutating func completeSetup() {
        listsSetup = false
        selection = .slots
    }

    /// General > Show Setup Guide: Setup returns for this session and is selected.
    public mutating func replaySetup() {
        listsSetup = true
        selection = .setup
    }
}
