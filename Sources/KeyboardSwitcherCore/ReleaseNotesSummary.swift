import Foundation

/// The few lines of a release's Markdown notes worth showing beside "Update Now":
/// the opening sentence and the title of each change.
public struct ReleaseNotesSummary: Equatable, Sendable {
    public var headline: String?
    public var items: [String]

    public init(headline: String? = nil, items: [String] = []) {
        self.headline = headline
        self.items = items
    }

    public var isEmpty: Bool { headline == nil && items.isEmpty }

    public static let maxItems = 6
    public static let maxItemLength = 110

    /// Sections from these headings on are boilerplate or caveats, not what changed.
    private static let closingHeadings = ["download and install", "known limits"]

    public static func parse(_ markdown: String) -> ReleaseNotesSummary {
        var headline: String?
        var items: [String] = []
        var isInCodeBlock = false

        for rawLine in markdown.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("```") { isInCodeBlock.toggle(); continue }
            guard !isInCodeBlock, !line.isEmpty else { continue }
            if line.hasPrefix("#") {
                let title = line.drop { $0 == "#" || $0 == " " }.lowercased()
                if closingHeadings.contains(where: title.hasPrefix) { break }
                continue
            }
            // Only top-level bullets: an indented one continues the item above it.
            if rawLine.hasPrefix("- ") || rawLine.hasPrefix("* ") {
                if items.count < maxItems { items.append(itemTitle(String(line.dropFirst(2)))) }
            } else if headline == nil, items.isEmpty, !rawLine.hasPrefix(" ") {
                headline = plainText(line)
            }
        }
        return ReleaseNotesSummary(headline: headline, items: items)
    }

    /// `**Title.** Explanation…` becomes `Title`; a bullet without a bold lead keeps its first sentence.
    private static func itemTitle(_ text: String) -> String {
        if text.hasPrefix("**"), let end = text.dropFirst(2).range(of: "**") {
            return trimmed(plainText(String(text.dropFirst(2)[..<end.lowerBound])))
        }
        let plain = plainText(text)
        let sentence = plain.range(of: ". ").map { String(plain[..<$0.lowerBound]) } ?? plain
        return trimmed(sentence)
    }

    private static func trimmed(_ text: String) -> String {
        var result = text.trimmingCharacters(in: .whitespaces)
        while result.hasSuffix(".") { result.removeLast() }
        guard result.count > maxItemLength else { return result }
        return result.prefix(maxItemLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func plainText(_ text: String) -> String {
        text.replacingOccurrences(of: #"\[([^\]]+)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: "**", with: "")
            .replacingOccurrences(of: "`", with: "")
    }
}
