import Foundation

/// How a switch has to be made for the input method to become active in the focused app.
///
/// `TISSelectInputSource` from a background process changes the system's current source, but
/// Google Japanese Input stays detached from the focused app once that app has typed under a
/// keyboard layout: the menu bar shows Hiragana and Latin letters come out. The Kana key goes through the system's own switching path and
/// does attach the input method, but it picks the last-used Japanese source, so the slot's
/// source is selected right after it. The order matters: selecting first makes the system
/// treat Kana as an ordinary key and pass it to the app.
public enum SwitchActivationStrategy: String, Codable, Sendable {
    /// `TISSelectInputSource` alone. Enough for every input method measured except the ones listed below.
    case select
    /// Kana key first, then the slot's source.
    case kanaThenSelect
}

public enum SwitchActivationPolicy {
    /// Input methods measured to need more than a plain select, by source-id prefix.
    /// azooKey and WeType switch reliably without it (12 of 12 and 9 of 9), so they are not listed.
    public static let builtInStrategies: [(idPrefix: String, strategy: SwitchActivationStrategy)] = [
        ("com.google.inputmethod.Japanese", .kanaThenSelect),
    ]

    public static func strategy(for target: InputSourceInfo) -> SwitchActivationStrategy {
        builtInStrategies.first { target.id.hasPrefix($0.idPrefix) }?.strategy ?? .select
    }

    /// `kVK_JIS_Kana`. Recognised on every keyboard, not only JIS ones.
    public static let kanaKeyCode = 104

    /// Time the Kana switch needs before the slot's source is selected. 20 ms lost one switch
    /// in six on azooKey; 60 ms lost none on Google Japanese Input or azooKey.
    public static let kanaToSelectDelay: TimeInterval = 0.06

    public static func needsKanaPrelude(target: InputSourceInfo, current: InputSourceInfo?) -> Bool {
        guard strategy(for: target) == .kanaThenSelect, target.primaryLanguage == "ja" else { return false }
        // Inside Japanese the system no longer switches on Kana; the app would get the key.
        return current?.primaryLanguage != "ja"
    }
}
