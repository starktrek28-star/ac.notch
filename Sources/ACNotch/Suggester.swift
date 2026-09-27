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
