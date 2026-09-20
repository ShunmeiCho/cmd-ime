import Foundation

/// Finds the run of latin letters before the caret that recovery may act on, and decides whether
/// it reads as pinyin at all.
///
/// Recovering the wrong thing destroys what the user wrote, so both halves are deliberately
/// narrow: the run stops at anything that is not a plain letter or a single space, and a run that
/// cannot be segmented into pinyin syllables is refused rather than guessed at.
public enum PinyinRun {
    /// The letters immediately before the caret that recovery would replace, or nil when there is
    /// nothing safe to take. `text` is what precedes the caret, in order.
    public static func candidate(before text: String) -> Substring? {
        var start = text.endIndex
        var sawLetter = false
        var index = text.endIndex
        while index > text.startIndex {
            let previous = text.index(before: index)
            let character = text[previous]
            if character.isASCII, character.isLetter {
                sawLetter = true
                start = previous
                index = previous
                continue
            }
            // A single space between syllables is how people type "ni hao"; two in a row, or any
            // other character, ends the run. Anything non-latin ends it too.
            if character == " ", sawLetter, previous > text.startIndex,
               text[text.index(before: previous)].isASCII, text[text.index(before: previous)].isLetter {
                start = previous
                index = previous
                continue
            }
            break
        }
        guard sawLetter else { return nil }
        let run = text[start...]
        return run.isEmpty ? nil : run
    }

    /// Whether the run can be read as a sequence of pinyin syllables. Plausibility is not intent:
    /// plenty of English words segment as pinyin. The user asking for recovery is the authorization.
    public static func isPlausible(_ run: some StringProtocol) -> Bool {
        let letters = Array(run.lowercased().filter { $0 != " " && $0 != "'" })
        guard !letters.isEmpty, letters.allSatisfy({ $0.isASCII && $0.isLetter }) else { return false }
        // Counting segmentations rather than taking the longest prefix: "xian" is both one syllable
        // and "xi" + "an", and a greedy walk would reject strings the tonal ambiguity allows.
        var ways = [Int](repeating: 0, count: letters.count + 1)
        ways[0] = 1
        for position in 0..<letters.count where ways[position] > 0 {
            for length in 1...min(6, letters.count - position) {
                let syllable = String(letters[position..<(position + length)])
                if syllables.contains(syllable) {
                    ways[position + length] = min(2, ways[position + length] + ways[position])
                }
            }
        }
        return ways[letters.count] > 0
    }

    /// The 400-odd syllables of standard Mandarin, without tones. Anything outside the table is
    /// refused: a table that grows is better than a run that eats the user's English.
    static let syllables: Set<String> = {
        let initials = ["", "b", "p", "m", "f", "d", "t", "n", "l", "g", "k", "h", "j", "q", "x",
                        "zh", "ch", "sh", "r", "z", "c", "s", "y", "w"]
        let finals = ["a", "o", "e", "i", "u", "v", "ai", "ei", "ao", "ou", "an", "en", "ang",
                      "eng", "ong", "er", "ia", "ie", "iao", "iu", "ian", "in", "iang", "ing",
                      "iong", "ua", "uo", "uai", "ui", "uan", "un", "uang", "ueng", "ve", "van",
                      "vn", "io", "ei", "ar", "ir", "ur"]
        var table = Set<String>()
        for initial in initials {
            for final in finals {
                table.insert(initial + final)
            }
        }
        // Syllables that do not fall out of the grid, and the standalone vowels.
        table.formUnion(["n", "ng", "m", "hm", "hng", "ei", "e", "o", "a", "ai", "ao", "an", "ang",
                         "ou", "en", "eng", "er", "yi", "wu", "yu", "ye", "yue", "yuan", "yun",
                         "you", "wen", "weng", "yo"])
        return table
    }()
}
