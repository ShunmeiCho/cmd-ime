import Foundation

/// How a switch has to be made for the input method to become active in the focused app.
///
/// `TISSelectInputSource` from a background process changes the system's current source, but
/// some Japanese input methods (measured: Google Japanese Input) stay detached from the
/// focused app when the previous source was a keyboard layout: the menu bar shows Hiragana
/// and Latin letters come out. The Kana key goes through the system's own switching path and
/// does attach the input method, but it picks the last-used Japanese source, so the slot's
/// source is selected right after it. The order matters: selecting first makes the system
/// treat Kana as an ordinary key and pass it to the app.
public enum SwitchActivationPolicy {
    /// `kVK_JIS_Kana`. Recognised on every keyboard, not only JIS ones.
    public static let kanaKeyCode = 104

    /// Time the Kana switch needs before the slot's source is selected. 20 ms lost one switch
    /// in six on azooKey; 60 ms lost none on Google Japanese Input or azooKey.
    public static let kanaToSelectDelay: TimeInterval = 0.06

    public static func needsKanaPrelude(target: InputSourceInfo, current: InputSourceInfo?) -> Bool {
        guard target.primaryLanguage == "ja", !isKeyboardLayout(target) else { return false }
        // Inside Japanese the system no longer switches on Kana; the app would get the key.
        return current?.primaryLanguage != "ja"
    }

    private static func isKeyboardLayout(_ source: InputSourceInfo) -> Bool {
        source.id.hasPrefix("com.apple.keylayout.")
    }
}
