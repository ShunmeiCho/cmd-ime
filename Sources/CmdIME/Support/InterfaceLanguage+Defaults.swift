import Foundation
import KeyboardSwitcherCore

extension InterfaceLanguage {
    /// A bare `swift run` binary has no bundle id, so no defaults domain of its own to keep the choice.
    static var isChoosable: Bool { Bundle.main.bundleIdentifier != nil }

    /// CmdIME's own choice, read from its persistent domain: the merged value would also hold the
    /// macOS-wide language list and read as a choice the user never made.
    static var stored: InterfaceLanguage {
        guard let bundleID = Bundle.main.bundleIdentifier else { return .system }
        let value = UserDefaults.standard.persistentDomain(forName: bundleID)?[defaultsKey] as? [String]
        return InterfaceLanguage(stored: value)
    }

    /// Writes only CmdIME's own domain, never the macOS-wide setting; System removes the key.
    func store() {
        if let storedValue {
            UserDefaults.standard.set(storedValue, forKey: Self.defaultsKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }
}
