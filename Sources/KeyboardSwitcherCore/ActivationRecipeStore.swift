import Foundation

/// Reads the user's activation recipes from `activation-recipes.json` beside the config file.
/// A separate file on purpose: older versions ignore it, and saving settings never rewrites it.
///
///     { "recipes": [ { "sourceIDPrefix": "com.example.inputmethod", "strategy": "kanaThenSelect", "delayMs": 60 } ] }
public struct ActivationRecipeStore {
    public struct LoadResult: Equatable, Sendable {
        public var recipes: [ActivationRecipe]
        /// Entries that were skipped, worded for the status line.
        public var problems: [String]
    }

    public let url: URL

    public init(url: URL = ActivationRecipeStore.defaultURL) {
        self.url = url
    }

    public static var defaultURL: URL {
        ConfigStore.defaultURL.deletingLastPathComponent().appendingPathComponent("activation-recipes.json")
    }

    /// A missing file is the normal case and yields no recipes and no problems.
    public func load() -> LoadResult {
        guard let data = try? Data(contentsOf: url) else { return LoadResult(recipes: [], problems: []) }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = object["recipes"] as? [Any] else {
            return LoadResult(recipes: [], problems: ["\(url.lastPathComponent) is not valid: expected {\"recipes\": [...]}"])
        }
        var recipes: [ActivationRecipe] = []
        var problems: [String] = []
        // Entry by entry, so one bad recipe does not discard the rest.
        for (index, entry) in entries.enumerated() {
            guard JSONSerialization.isValidJSONObject(entry),
                  let entryData = try? JSONSerialization.data(withJSONObject: entry),
                  let recipe = try? JSONDecoder().decode(ActivationRecipe.self, from: entryData) else {
                problems.append("Recipe \(index + 1) was skipped: it needs \"sourceIDPrefix\" and a known \"strategy\".")
                continue
            }
            // An empty prefix would match every input source.
            guard !recipe.sourceIDPrefix.trimmingCharacters(in: .whitespaces).isEmpty else {
                problems.append("Recipe \(index + 1) was skipped: \"sourceIDPrefix\" is empty.")
                continue
            }
            recipes.append(recipe)
        }
        return LoadResult(recipes: recipes, problems: problems)
    }
}
