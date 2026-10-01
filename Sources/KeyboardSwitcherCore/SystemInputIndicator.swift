import Foundation

/// The badge macOS 14 and later draw under the text cursor whenever the input source changes,
/// CmdIME's own switches included: the change itself raises it, so nothing in the switch path
/// can leave it out. The only off switch is the hidden global preference
/// `TSMLanguageIndicatorEnabled` (where `defaults write -g` writes), and a missing key means the
/// badge shows. Apps already open keep showing it until they relaunch; with it off, Control+Space
/// falls back to the older chooser in the middle of the screen.
public enum SystemInputIndicator {
    static let preferenceKey = "TSMLanguageIndicatorEnabled"

    /// Reads a stored value however it was written: a Boolean (CmdIME, `-bool`), a number
    /// (`-int`), or a string (a bare `defaults write ... 0` stores "0").
    static func isHidden(storedValue: Any?) -> Bool {
        switch storedValue {
        case let flag as Bool:
            return !flag
        case let number as NSNumber:
            return !number.boolValue
        case let text as String:
            return ["0", "false", "no"].contains(text.lowercased())
        default:
            return false
        }
    }

    public enum Sync: Equatable {
        case hide, restore, keep
    }

    /// macOS's badge stays hidden while CmdIME's bubble is on, so a switch shows one bubble, and
    /// comes back when the bubble goes off. Restoring undoes only a value CmdIME wrote: a badge the
    /// user hid by hand stays hidden.
    public static func sync(bubbleOn: Bool, isHidden: Bool, hiddenByCmdIME: Bool) -> Sync {
        if bubbleOn { return isHidden ? .keep : .hide }
        return isHidden && hiddenByCmdIME ? .restore : .keep
    }

    #if os(macOS)
    public enum WriteError: Error {
        /// macOS still reports the old value after the write (a configuration profile can pin it).
        case notApplied
    }

    private static var key: CFString { preferenceKey as CFString }

    // The SDK header says the App functions take no kCFPreferencesAnyApplication, but HIToolbox
    // itself reads this key that way (macOS 27.2), so reading it the same way shows what macOS sees.

    public static func isHidden() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        return isHidden(storedValue: CFPreferencesCopyAppValue(key, kCFPreferencesAnyApplication))
    }

    /// Hiding writes `false`. Showing removes the key, so macOS is back on its default instead of
    /// holding an explicit `true` the user never chose.
    public static func setHidden(_ hidden: Bool) throws {
        CFPreferencesSetAppValue(key, hidden ? kCFBooleanFalse : nil, kCFPreferencesAnyApplication)
        guard CFPreferencesAppSynchronize(kCFPreferencesAnyApplication), isHidden() == hidden else {
            throw WriteError.notApplied
        }
    }
    #endif
}
