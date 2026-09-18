import CoreText
import Foundation
import KeyboardSwitcherCore

/// Makes imported font files usable by this process only. Nothing is installed
/// system-wide: registration uses the `.process` scope and ends with the process.
@MainActor
final class IndicatorFontRegistrar {
    struct Entry: Identifiable, Equatable {
        let font: ImportedFont
        let families: [String]
        /// False when CoreText refused the file; it is listed but cannot be used.
        let isLoaded: Bool

        var id: String { font.id }
    }

    private var registered: Set<URL> = []

    /// Family names in the file, read before the file is trusted; empty when it is not a font.
    func families(in url: URL) -> [String] {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] else {
            return []
        }
        let names = descriptors.compactMap { CTFontDescriptorCopyAttribute($0, kCTFontFamilyNameAttribute) as? String }
        return Array(Set(names)).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    func register(_ font: ImportedFont) -> Entry {
        let families = families(in: font.url)
        guard !families.isEmpty else { return Entry(font: font, families: [], isLoaded: false) }
        if registered.contains(font.url) { return Entry(font: font, families: families, isLoaded: true) }
        let isLoaded = CTFontManagerRegisterFontsForURL(font.url as CFURL, .process, nil)
        if isLoaded { registered.insert(font.url) }
        return Entry(font: font, families: families, isLoaded: isLoaded)
    }

    func unregister(_ font: ImportedFont) {
        guard registered.remove(font.url) != nil else { return }
        CTFontManagerUnregisterFontsForURL(font.url as CFURL, .process, nil)
    }
}
