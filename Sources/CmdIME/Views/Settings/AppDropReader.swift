import AppKit
import KeyboardSwitcherCore
import SwiftUI
import UniformTypeIdentifiers

/// Drags and drops on the rule board. An app dragged inside the settings window travels as a
/// private type, declared in Info.plist by both build scripts, so dropping it into another app
/// inserts nothing; .app bundles come from Finder and the Dock as file URLs. Anything else is
/// refused before the drop, so macOS slides it back instead of pretending it landed.
enum AppDropReader {
    /// Any app dragged inside the window: an app-list row or a rule chip.
    static let appType = UTType(exportedAs: "com.shunmei.cmd-ime.app-reference")
    /// Carried by rule chips only, so the app list takes a chip back (to remove its rule) but not
    /// one of its own rows.
    static let ruleType = UTType(exportedAs: "com.shunmei.cmd-ime.app-rule")

    static let laneTypes: [UTType] = [appType, .fileURL]
    static let listTypes: [UTType] = [ruleType]

    /// The provider an app row (`isRule == false`) or a rule chip hands to a drag.
    static func provider(appID: String, name: String, isRule: Bool) -> NSItemProvider {
        let provider = NSItemProvider()
        let data = Data(AppDragPayload.encode(appID: appID, name: name).utf8)
        for type in isRule ? [ruleType, appType] : [appType] {
            provider.registerDataRepresentation(forTypeIdentifier: type.identifier, visibility: .all) { completion in
                completion(data, nil)
                return nil
            }
        }
        return provider
    }

    /// Whether a drag over a lane holds an app. For files, the drag pasteboard is read directly,
    /// since an item provider only says "a file"; if it cannot be read the drop is let through and
    /// `read` reports anything that turns out not to be an app.
    static func laneAccepts(_ info: DropInfo) -> Bool {
        if info.hasItemsConforming(to: [appType, .applicationBundle]) { return true }
        guard info.hasItemsConforming(to: [.fileURL]) else { return false }
        return dragPasteboardHoldsApp() ?? true
    }

    private static func dragPasteboardHoldsApp() -> Bool? {
        let urls = NSPasteboard(name: .drag).readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
        guard let urls, !urls.isEmpty else { return nil }
        return urls.contains(where: AppBundleScan.isAppBundle)
    }

    /// Calls `found` on the main actor once for each app in the drop, and `notAnApp` for a file
    /// that is not one.
    static func read(
        _ providers: [NSItemProvider],
        found: @escaping @MainActor @Sendable (String, String?) -> Void,
        notAnApp: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        for provider in providers {
            if let type = [ruleType, appType].first(where: { provider.hasItemConformingToTypeIdentifier($0.identifier) }) {
                _ = provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data, let app = AppDragPayload.decode(String(decoding: data, as: UTF8.self)) else { return }
                    Task { @MainActor in found(app.appID, app.name) }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let app = InstalledApp(bundleURL: url) else {
                        Task { @MainActor in notAnApp() }
                        return
                    }
                    let id = app.id, name = app.name
                    Task { @MainActor in found(id, name) }
                }
            }
        }
    }
}

/// A drop target on the rule board that lights up only for what it takes.
struct AppDropTarget: DropDelegate {
    let types: [UTType]
    let accepts: (DropInfo) -> Bool
    @Binding var isTargeted: Bool
    let found: @MainActor @Sendable (String, String?) -> Void
    var notAnApp: @MainActor @Sendable () -> Void = {}

    func validateDrop(info: DropInfo) -> Bool { accepts(info) }

    func dropEntered(info: DropInfo) { isTargeted = accepts(info) }

    func dropExited(info: DropInfo) { isTargeted = false }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: accepts(info) ? .copy : .forbidden)
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard accepts(info) else { return false }
        AppDropReader.read(info.itemProviders(for: types), found: found, notAnApp: notAnApp)
        return true
    }
}
