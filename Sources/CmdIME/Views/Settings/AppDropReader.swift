import AppKit
import KeyboardSwitcherCore
import UniformTypeIdentifiers

/// Reads the apps out of a drop on the rule board: an app or rule chip dragged inside the window
/// (an `AppDragPayload` text) or .app bundles from Finder and the Dock (file URLs). Anything else
/// is ignored.
enum AppDropReader {
    static let types: [UTType] = [.fileURL, .utf8PlainText]

    /// The provider an app row or rule chip hands to a drag.
    static func provider(appID: String, name: String) -> NSItemProvider {
        NSItemProvider(object: AppDragPayload.encode(appID: appID, name: name) as NSString)
    }

    /// Calls `found` on the main actor once for each app in the drop, and returns whether the
    /// drop could hold one, which is what `onDrop` reports back.
    static func read(
        _ providers: [NSItemProvider],
        acceptsFiles: Bool = true,
        found: @escaping @MainActor @Sendable (String, String?) -> Void
    ) -> Bool {
        var accepted = false
        for provider in providers {
            if acceptsFiles, provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                accepted = true
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url, let app = InstalledApp(bundleURL: url) else { return }
                    let id = app.id, name = app.name
                    Task { @MainActor in found(id, name) }
                }
            } else if provider.canLoadObject(ofClass: String.self) {
                accepted = true
                _ = provider.loadObject(ofClass: String.self) { text, _ in
                    guard let text, let app = AppDragPayload.decode(text) else { return }
                    Task { @MainActor in found(app.appID, app.name) }
                }
            }
        }
        return accepted
    }
}
