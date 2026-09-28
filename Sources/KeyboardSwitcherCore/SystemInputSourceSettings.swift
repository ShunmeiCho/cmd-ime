import Foundation

/// The macOS setting "Automatically switch to a document's input source" (Keyboard >
/// Input Sources). When on, macOS re-selects a remembered source whenever focus moves to
/// another window or field, which fights App Memory's per-app restore.
public enum SystemInputSourceSettings {
    static let domain = "com.apple.HIToolbox"
    static let globalPropertiesKey = "AppleGlobalTextInputProperties"
    static let perDocumentKey = "TextInputGlobalPropertyPerContextInput"

    /// Reads the stored global text-input properties. The key is absent until the user
    /// turns the setting on for the first time, and absent means off.
    static func isPerDocumentSwitchingOn(globalProperties: Any?) -> Bool {
        guard let properties = globalProperties as? [String: Any],
              let value = properties[perDocumentKey] as? NSNumber else {
            return false
        }
        return value.boolValue
    }

    #if os(macOS)
    public static func isPerDocumentSwitchingOn() -> Bool {
        let domain = Self.domain as CFString
        CFPreferencesAppSynchronize(domain)
        return isPerDocumentSwitchingOn(
            globalProperties: CFPreferencesCopyAppValue(globalPropertiesKey as CFString, domain)
        )
    }
    #endif
}
