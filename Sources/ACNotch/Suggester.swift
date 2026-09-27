import AppKit

/// One slot in the strip. The first option is the main one: what you get when you press space.
struct StripOption: Equatable {
    enum Kind: Equatable {
        case typed       // the word exactly as typed; picking it keeps it
        case correction  // what will replace the word when you press space
        case suggestion  // alternative spelling or completion
        case original    // shown after an autocorrect; picking it undoes the correction
        case info        // a status message, not clickable
    }

    var text: String
    var kind: Kind
    var highlighted = false
    var quoted = false
    /// Pressing Tab picks this option.
    var acceptsTab = false

    var label: String { quoted ? "\u{201C}\(text)\u{201D}" : text }
    /// What's drawn, including the small Tab hint.
    var displayText: String { acceptsTab ? label + " \u{21E5}" : label }
}

struct Analysis {
    var options: [StripOption]
    var autocorrection: String?
}

/// Wraps Apple's built-in spell checker (on-device, no network).
final class Suggester {
    private let checker = NSSpellChecker.shared
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()
    private var ignored = Set<String>()

    /// Fixes the spell checker doesn't make on its own but iPhones do.
    private static let special: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
        "cant": "can't", "isnt": "isn't", "wasnt": "wasn't",
        "arent": "aren't", "werent": "weren't", "havent": "haven't",
        "hasnt": "hasn't", "couldnt": "couldn't", "wouldnt": "wouldn't",
        "shouldnt": "shouldn't", "thats": "that's", "whats": "what's",
        "youre": "you're", "theyre": "they're",
    ]

    init() {
        ignored = Set(UserDefaults.standard.stringArray(forKey: "learnedWords") ?? [])
    }

    /// Stop correcting this word for the rest of the session.
    func ignore(_ word: String) {
        ignored.insert(word.lowercased())
        checker.ignoreWord(word, inSpellDocumentWithTag: tag)
    }

    /// The user put back a word autocorrect changed. Like iPhone, stop correcting it; after
    /// the second time, remember it for good.
    func rejected(_ word: String) {
        ignore(word)
        let key = word.lowercased()
        let defaults = UserDefaults.standard
        var counts = defaults.dictionary(forKey: "rejectCounts") as? [String: Int] ?? [:]
        counts[key, default: 0] += 1
        defaults.set(counts, forKey: "rejectCounts")
        if counts[key, default: 0] >= 2 {
            var learned = Set(defaults.stringArray(forKey: "learnedWords") ?? [])
            learned.insert(key)
            defaults.set(Array(learned), forKey: "learnedWords")
        }
    }

    func analyze(_ word: String) -> Analysis {
        let lower = word.lowercased()
        let hasLetters = word.contains { $0.isLetter }
        let isAcronym = word.count > 1 && word == word.uppercased() && hasLetters
        let eligible = hasLetters && !isAcronym && !word.contains { $0.isNumber } && !ignored.contains(lower)

        let range = NSRange(location: 0, length: (word as NSString).length)
        let language = checker.language()

        var autocorrection: String?
        var misspelled = false

        if eligible, let fix = Suggester.special[lower] {
            let fixed = matchCase(fix, to: word)
            if fixed != word { autocorrection = fixed }
        } else if eligible, word.count >= 2 {
            let found = checker.checkSpelling(of: word, startingAt: 0, language: nil, wrap: false,
                                              inSpellDocumentWithTag: tag, wordCount: nil)
            misspelled = found.location != NSNotFound
            if misspelled {
                autocorrection = checker.correction(forWordRange: range, in: word, language: language,
                                                    inSpellDocumentWithTag: tag).map { matchCase($0, to: word) }
                // Apple's Mac spell checker often declines to autocorrect. Like iPhone, fix it
                // anyway when a guess is a near miss on the keyboard (neighbour keys, swapped letters).
                if autocorrection == nil, word.count >= 3 {
                    let guesses = checker.guesses(forWordRange: range, in: word, language: language,
                                                  inSpellDocumentWithTag: tag) ?? []
                    let limit: Double = word.count >= 6 ? 2 : word.count >= 4 ? 1.5 : 1
                    let best = guesses.prefix(8)
                        .filter { !$0.contains(" ") && !$0.contains("-") }
                        .map { ($0, KeyboardDistance.between(lower, $0.lowercased())) }
                        .min { $0.1 < $1.1 }
                    if let best, best.1 <= limit { autocorrection = matchCase(best.0, to: word) }
                }
            }
        }

        // One pill: the word you'll get when you press space.
        let options: [StripOption]
        if let autocorrection {
            options = [StripOption(text: autocorrection, kind: .correction, highlighted: true)]
        } else {
            options = [StripOption(text: word, kind: .typed, quoted: misspelled)]
        }
        return Analysis(options: options, autocorrection: autocorrection)
    }

    /// Makes a suggestion follow the capitalisation of what was typed.
    private func matchCase(_ suggestion: String, to typed: String) -> String {
        guard let first = typed.first, first.isUppercase else { return suggestion }
        return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
    }
}

/// Edit distance that knows the keyboard: hitting a neighbouring key or swapping two letters
/// costs less than an unrelated mistake, so "hwllo" is closer to "hello" than to "hollo".
enum KeyboardDistance {
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { Array($0) }

    private static let position: [Character: (row: Int, col: Int)] = {
        var map: [Character: (row: Int, col: Int)] = [:]
        for (r, row) in rows.enumerated() {
            for (c, key) in row.enumerated() { map[key] = (r, c) }
        }
        return map
    }()

    /// On a staggered keyboard, a key touches its row neighbours and two keys in each adjacent row.
    static func adjacent(_ a: Character, _ b: Character) -> Bool {
        guard let p = position[a], let q = position[b] else { return false }
        if p.row == q.row { return abs(p.col - q.col) == 1 }
        if q.row == p.row + 1 { return q.col == p.col || q.col == p.col - 1 }
        if q.row == p.row - 1 { return q.col == p.col || q.col == p.col + 1 }
        return false
    }

    static func between(_ a: String, _ b: String) -> Double {
        let s = Array(a), t = Array(b)
        if s.isEmpty || t.isEmpty { return Double(max(s.count, t.count)) }
        var d = Array(repeating: Array(repeating: 0.0, count: t.count + 1), count: s.count + 1)
        for i in 0...s.count { d[i][0] = Double(i) }
        for j in 0...t.count { d[0][j] = Double(j) }
        for i in 1...s.count {
            for j in 1...t.count {
                let substitution = s[i - 1] == t[j - 1] ? 0 : (adjacent(s[i - 1], t[j - 1]) ? 0.5 : 1)
                var best = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + substitution)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    best = min(best, d[i - 2][j - 2] + 0.6)
                }
                d[i][j] = best
            }
        }
        return d[s.count][t.count]
    }
}
