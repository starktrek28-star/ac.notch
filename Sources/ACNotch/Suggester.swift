import ACNotchEngine
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

/// Decides what each word should become. Uses AC Notch's own engine (word frequencies,
/// the previous word, keyboard-aware slips), consulting Apple's spell checker for words it
/// knows (names you've taught it, rarer words) and for extra candidates. All on-device.
final class Suggester {
    private let checker = NSSpellChecker.shared
    private let tag = NSSpellChecker.uniqueSpellDocumentTag()
    private var ignored = Set<String>()
    /// Loaded in the background at launch (about a second); until then, Apple's checker alone.
    private var corrector: Corrector?

    init() {
        ignored = Set(UserDefaults.standard.stringArray(forKey: "learnedWords") ?? [])
        guard let directory = Bundle.main.resourceURL?.appendingPathComponent("Language") else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let model = try LanguageModel(directory: directory)
                DispatchQueue.main.async { self.corrector = Corrector(model: model) }
            } catch {
                DispatchQueue.main.async { Diagnostics.log("language data failed to load: \(error)") }
            }
        }
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

    /// - Parameter previous: the word before, lowercase; "<s>" at a sentence start; nil if unknown.
    func analyze(_ word: String, previous: String? = nil) -> Analysis {
        let lower = word.lowercased()
        var autocorrection: String?
        var misspelled = false

        if !ignored.contains(lower) {
            misspelled = !appleKnows(word)
            if let corrector {
                autocorrection = corrector.correction(
                    for: word, previous: previous,
                    extraCandidates: misspelled ? appleGuesses(word) : [],
                    isKnownElsewhere: { [weak self] in self?.appleKnows($0) ?? false })
            } else if misspelled, word.count >= 2 {
                let range = NSRange(location: 0, length: (word as NSString).length)
                autocorrection = checker.correction(forWordRange: range, in: word, language: checker.language(),
                                                    inSpellDocumentWithTag: tag).map { matchCase($0, to: word) }
            }
        }
        if autocorrection == word { autocorrection = nil }

        // One pill: the word you'll get when you press space.
        let options: [StripOption]
        if let autocorrection {
            options = [StripOption(text: autocorrection, kind: .correction, highlighted: true)]
        } else {
            options = [StripOption(text: word, kind: .typed, quoted: misspelled && word.count > 1)]
        }
        return Analysis(options: options, autocorrection: autocorrection)
    }

    private func appleKnows(_ word: String) -> Bool {
        checker.checkSpelling(of: word, startingAt: 0, language: nil, wrap: false,
                              inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound
    }

    private func appleGuesses(_ word: String) -> [String] {
        let range = NSRange(location: 0, length: (word as NSString).length)
        return checker.guesses(forWordRange: range, in: word, language: checker.language(),
                               inSpellDocumentWithTag: tag) ?? []
    }

    /// Makes a suggestion follow the capitalisation of what was typed.
    private func matchCase(_ suggestion: String, to typed: String) -> String {
        guard let first = typed.first, first.isUppercase else { return suggestion }
        return suggestion.prefix(1).uppercased() + suggestion.dropFirst()
    }
}
