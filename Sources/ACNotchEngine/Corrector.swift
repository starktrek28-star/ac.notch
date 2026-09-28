import Foundation

/// Decides whether a typed word is a typo and, if so, what it should become.
///
/// Scoring is the classic "noisy channel": prefer the candidate that is both a likely
/// word here (how common it is, and how often it follows the previous word) and a
/// likely slip of the fingers from what was typed (keyboard-aware edit distance).
public final class Corrector {
    public struct Config {
        /// How strongly the keyboard distance counts against a candidate (per unit of cost, in log space).
        public var errorWeight = 7.0
        /// How much the previous word matters (0 = ignore context).
        public var contextWeight = 0.9
        /// Largest keyboard distance still worth correcting, by word length.
        public var maxCost: (Int) -> Double = { length in
            length <= 3 ? 1.0 : length <= 5 ? 1.5 : length <= 8 ? 2.0 : 2.5
        }
        /// For capitalised words (probably names): only the smallest slips.
        public var capitalizedMaxCost = 0.6
        /// For bigger slips (cost above `confidentCost`), the best candidate must beat the
        /// runner-up by this much (log score), or the word is left alone: a wrong fix is
        /// worse than none.
        public var confidentCost = 1.0
        public var margin = 3.0
        /// When another dictionary (the system's) knows the typed word but ours doesn't, it still
        /// gets corrected if the fix is a slip no bigger than this. That dictionary accepts many
        /// rare words that are far more often typos ("hee", "wll"). Capitalised words are always
        /// left alone (names). 0 = always trust the other dictionary. 1.0 measured best on macOS
        /// (see docs/WORK_LOG.md).
        public var overrideElsewhereUpTo = 1.0
        /// A candidate suggested by the other spell checker as its own correction gets this bonus.
        public var preferredBonus = 0.0
        public init() {}
    }

    public let model: LanguageModel
    public var config: Config

    /// Fixes iPhone makes that the dictionaries treat as real words or miss.
    static let special: [String: String] = [
        "i": "I", "im": "I'm", "ive": "I've", "id": "I'd", "ill": "I'll",
        "dont": "don't", "doesnt": "doesn't", "didnt": "didn't", "cant": "can't", "wont": "won't",
        "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't", "werent": "weren't",
        "havent": "haven't", "hasnt": "hasn't", "hadnt": "hadn't", "couldnt": "couldn't",
        "wouldnt": "wouldn't", "shouldnt": "shouldn't", "thats": "that's", "whats": "what's",
        "youre": "you're", "theyre": "they're", "theres": "there's", "heres": "here's",
        "youve": "you've", "theyve": "they've", "weve": "we've", "youll": "you'll",
        "lets": "let's", "shes": "she's", "hes": "he's",
    ]
    /// Of the special fixes, the ones that are also real words: only corrected when the
    /// previous word makes the contraction clearly more likely.
    static let ambiguous: Set<String> = ["id", "ill", "wont", "lets", "shes", "hes", "cant"]

    public init(model: LanguageModel, config: Config = Config()) {
        self.model = model
        self.config = config
    }

    /// The correction for `typed`, or nil to leave it alone.
    /// - Parameters:
    ///   - previous: the word before it, lowercase, "<s>" at the start of a sentence, nil if unknown.
    ///   - extraCandidates: more suggestions to consider (e.g. from the system spell checker).
    ///   - isKnownElsewhere: another opinion on whether `typed` is a real word (names the user
    ///     taught the system, words the dictionary lacks).
    public func correction(for typed: String, previous: String? = nil,
                           extraCandidates: [String] = [],
                           preferred: String? = nil,
                           isKnownElsewhere: ((String) -> Bool)? = nil) -> String? {
        let lower = typed.lowercased()
        guard typed.contains(where: \.isLetter), !typed.contains(where: \.isNumber) else { return nil }
        // English only: accented letters mean another language (or a deliberate "café").
        guard typed.unicodeScalars.allSatisfy({ $0.isASCII }) else { return nil }
        if typed.count > 1, typed == typed.uppercased() { return nil }   // acronyms

        if let fix = Corrector.special[lower] {
            if Corrector.ambiguous.contains(lower) {
                let fixP = model.probability(of: fix.lowercased(), after: previous, contextWeight: config.contextWeight)
                let asIsP = model.probability(of: lower, after: previous, contextWeight: config.contextWeight)
                guard previous != nil, fixP > asIsP * 3 else { return nil }
            }
            let fixed = Corrector.matchCase(fix, to: typed)
            return fixed == typed ? nil : fixed
        }

        if model.lexicon.contains(lower) { return nil }
        let knownElsewhere = isKnownElsewhere?(typed) ?? false
        if knownElsewhere, config.overrideElsewhereUpTo <= 0 || typed.first?.isUppercase == true { return nil }
        guard lower.count >= 2 else { return nil }

        var candidates = model.candidates(for: lower)
        let preferredLower = preferred?.lowercased()
        for extra in extraCandidates + [preferred].compactMap({ $0 }) {
            let e = extra.lowercased()
            if !e.contains(" "), model.lexicon.contains(e) { candidates.insert(e) }
        }

        var limit = config.maxCost(lower.count)
        // A capitalised word the dictionary doesn't know is most likely a name. Mid-sentence,
        // leave it alone; at the start of a sentence, only fix an obvious slip ("Teh"),
        // never turn "Sami" into "Same".
        if typed.first?.isUppercase == true {
            if let previous, previous != "<s>" { return nil }
            limit = min(limit, config.capitalizedMaxCost)
        }
        var best: (word: String, score: Double, cost: Double)?
        var runnerUp = -Double.infinity
        for candidate in candidates where candidate != lower {
            let cost = KeyboardDistance.between(lower, candidate)
            guard cost <= limit else { continue }
            let p = model.probability(of: candidate, after: previous, contextWeight: config.contextWeight)
            var score = log(p) - config.errorWeight * cost
            if candidate == preferredLower { score += config.preferredBonus }
            if let current = best, score <= current.score {
                runnerUp = max(runnerUp, score)
            } else {
                if let current = best { runnerUp = max(runnerUp, current.score) }
                best = (candidate, score, cost)
            }
        }
        guard let best else { return nil }
        if knownElsewhere, best.cost > config.overrideElsewhereUpTo { return nil }
        if best.cost > config.confidentCost, best.score - runnerUp < config.margin { return nil }
        return Corrector.matchCase(best.word, to: typed)
    }

    /// Makes a correction follow the capitalisation of what was typed.
    public static func matchCase(_ word: String, to typed: String) -> String {
        guard let first = typed.first, first.isUppercase else { return word }
        return word.prefix(1).uppercased() + word.dropFirst()
    }
}
