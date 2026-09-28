import Foundation

/// Word knowledge for correcting typos, loaded from the files in `Resources/Language`:
/// which words exist, how common each is, and which words tend to follow which.
public final class LanguageModel {
    /// Every word accepted as correctly spelled (lowercase).
    public let lexicon: Set<String>
    /// Candidate words and how often they're used.
    public let unigrams: [String: Double]
    public let unigramTotal: Double
    /// "previous\u{1}word" → how often `word` followed `previous` ("<s>" = sentence start).
    let bigrams: [String: Double]
    let bigramTotals: [String: Double]
    /// Each candidate word, and the word with any one letter removed, → candidate words.
    /// Lets typos within about two edits be found with a handful of lookups.
    let deleteIndex: [String: [String]]

    public init(directory: URL) throws {
        func lines(_ name: String) throws -> [Substring] {
            let text = try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
            return text.split(separator: "\n")
        }

        lexicon = Set(try lines("lexicon.txt").map(String.init))

        var unigrams: [String: Double] = [:]
        var total = 0.0
        for line in try lines("unigrams.tsv") {
            let parts = line.split(separator: "\t")
            guard parts.count == 2, let count = Double(parts[1]) else { continue }
            unigrams[String(parts[0])] = count
            total += count
        }
        self.unigrams = unigrams
        unigramTotal = total

        var bigrams: [String: Double] = [:]
        var totals: [String: Double] = [:]
        for line in try lines("bigrams.tsv") {
            let parts = line.split(separator: "\t")
            guard parts.count == 3, let count = Double(parts[2]) else { continue }
            bigrams["\(parts[0])\u{1}\(parts[1])"] = count
            totals[String(parts[0]), default: 0] += count
        }
        self.bigrams = bigrams
        bigramTotals = totals

        var index: [String: [String]] = [:]
        for word in unigrams.keys {
            index[word, default: []].append(word)
            for delete in LanguageModel.deletes(of: word) where delete.count > 0 {
                index[delete, default: []].append(word)
            }
        }
        deleteIndex = index
    }

    /// `word` with each single letter removed.
    static func deletes(of word: String) -> Set<String> {
        let chars = Array(word)
        guard chars.count > 1 else { return [] }
        var out = Set<String>()
        for i in chars.indices {
            var copy = chars
            copy.remove(at: i)
            out.insert(String(copy))
        }
        return out
    }

    /// Candidate words within roughly two edits of `typed` (lowercase).
    public func candidates(for typed: String) -> Set<String> {
        var queries: Set<String> = [typed]
        let first = LanguageModel.deletes(of: typed)
        queries.formUnion(first)
        for d in first { queries.formUnion(LanguageModel.deletes(of: d)) }
        var found = Set<String>()
        for q in queries {
            if let words = deleteIndex[q] { found.formUnion(words) }
        }
        return found
    }

    /// How likely `word` is, given the word before it (or nil when unknown).
    public func probability(of word: String, after previous: String?, contextWeight: Double) -> Double {
        let unigram = (unigrams[word] ?? 0.5) / unigramTotal
        guard let previous, contextWeight > 0, let total = bigramTotals[previous], total > 0 else { return unigram }
        let bigram = (bigrams["\(previous)\u{1}\(word)"] ?? 0) / total
        return contextWeight * bigram + (1 - contextWeight) * unigram
    }
}
