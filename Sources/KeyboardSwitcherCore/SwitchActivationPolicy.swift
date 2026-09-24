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

/// One rule: input sources whose id starts with `sourceIDPrefix` are entered with `strategy`.
public struct ActivationRecipe: Codable, Equatable, Sendable {
    public var sourceIDPrefix: String
    public var strategy: SwitchActivationStrategy
    /// Milliseconds between the Kana key and the select. nil uses `kanaToSelectDelay`.
    public var delayMs: Int?

    public init(sourceIDPrefix: String, strategy: SwitchActivationStrategy, delayMs: Int? = nil) {
        self.sourceIDPrefix = sourceIDPrefix
        self.strategy = strategy
        self.delayMs = delayMs
    }
}

public enum SwitchActivationPolicy {
    /// Input methods measured to need more than a plain select.
    /// azooKey and WeType switch reliably without it (12 of 12 and 9 of 9), so they are not listed.
    public static let builtInRecipes = [
        ActivationRecipe(sourceIDPrefix: "com.google.inputmethod.Japanese", strategy: .kanaThenSelect),
        // azooKey keeps its own alphanumeric/kana mode across selections. Once left in
        // alphanumeric, a plain select shows azooKey in the menu bar while keys stay latin.
        ActivationRecipe(sourceIDPrefix: "dev.ensan.inputmethod.azooKeyMac", strategy: .kanaThenSelect),
    ]

    public static let delayRangeMs = 0...500

    /// The user's recipes win over the built-in ones, so a `select` recipe can switch one off.
    public static func recipe(for target: InputSourceInfo, userRecipes: [ActivationRecipe] = []) -> ActivationRecipe? {
        (userRecipes + builtInRecipes).first { target.id.hasPrefix($0.sourceIDPrefix) }
    }

    public static func strategy(for target: InputSourceInfo, userRecipes: [ActivationRecipe] = []) -> SwitchActivationStrategy {
        recipe(for: target, userRecipes: userRecipes)?.strategy ?? .select
    }

    public static func kanaToSelectDelay(for target: InputSourceInfo, userRecipes: [ActivationRecipe] = []) -> TimeInterval {
        guard let delayMs = recipe(for: target, userRecipes: userRecipes)?.delayMs else { return kanaToSelectDelay }
        return TimeInterval(min(max(delayMs, delayRangeMs.lowerBound), delayRangeMs.upperBound)) / 1000
    }

    /// `kVK_JIS_Kana`. Recognised on every keyboard, not only JIS ones.
    public static let kanaKeyCode = 104

    /// Time the Kana switch needs before the slot's source is selected. 20 ms lost one switch
    /// in six on azooKey; 60 ms lost none on Google Japanese Input or azooKey.
    public static let kanaToSelectDelay: TimeInterval = 0.06

    public static func needsKanaPrelude(target: InputSourceInfo, current: InputSourceInfo?, userRecipes: [ActivationRecipe] = []) -> Bool {
        // Kana only switches to Japanese sources; a recipe naming anything else is ignored.
        guard strategy(for: target, userRecipes: userRecipes) == .kanaThenSelect, target.primaryLanguage == "ja" else { return false }
        // Inside Japanese the system no longer switches on Kana; the app would get the key.
        return current?.primaryLanguage != "ja"
    }

    /// Selects `target` for a switch that does not come from the event tap (the settings window,
    /// `keyboardctl switch`): when the input method needs it, the Kana key is posted first and
    /// `select` runs after the recipe's delay; otherwise `select` runs at once with no wait.
    /// `current` is only read for input methods that have a Kana recipe.
    public static func selectWithKanaPrelude(
        target: InputSourceInfo,
        current: () -> InputSourceInfo?,
        userRecipes: [ActivationRecipe] = [],
        postKana: () -> Void,
        wait: (TimeInterval, @escaping () -> Void) -> Void,
        select: @escaping () -> Void
    ) {
        guard strategy(for: target, userRecipes: userRecipes) == .kanaThenSelect,
              needsKanaPrelude(target: target, current: current(), userRecipes: userRecipes) else {
            select()
            return
        }
        postKana()
        wait(kanaToSelectDelay(for: target, userRecipes: userRecipes), select)
    }
}
