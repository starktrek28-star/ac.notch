import ACNotchEngine
import Foundation
#if canImport(AppKit)
import AppKit
#endif

// Scores autocorrect variants on held-out typo sets and prints a Markdown table.
// Usage: acbench [repo root]   (default: current directory)

let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
let model = try LanguageModel(directory: root.appendingPathComponent("Resources/Language"))

func rows(_ name: String) throws -> [[String]] {
    let text = try String(contentsOf: root.appendingPathComponent("Benchmark/data/\(name)"), encoding: .utf8)
    return text.split(separator: "\n").filter { !$0.hasPrefix("#") }.map { $0.split(separator: "\t").map(String.init) }
}
let misspellings = try rows("misspellings.tsv")   // typo, intended
let synthetic = try rows("synthetic.tsv")         // previous, typo, intended
let correct = try rows("correct.tsv")             // previous, word

/// A way of correcting a word: (typed, previous word) → correction or nil.
typealias Variant = (name: String, correct: (String, String?) -> String?)

struct Score { var fixed = 0, wrong = 0, total = 0 }
func score(_ v: Variant) -> (real: Score, typos: Score, changed: Int) {
    var real = Score(), typos = Score(), changed = 0
    for r in misspellings where r.count == 2 {
        real.total += 1
        if let out = v.correct(r[0], nil) { if out.lowercased() == r[1] { real.fixed += 1 } else { real.wrong += 1 } }
    }
    for r in synthetic where r.count == 3 {
        typos.total += 1
        if let out = v.correct(r[1], r[0]) { if out.lowercased() == r[2] { typos.fixed += 1 } else { typos.wrong += 1 } }
    }
    for r in correct where r.count == 2 {
        if v.correct(r[1], r[0]) != nil { changed += 1 }
    }
    return (real, typos, changed)
}

func pct(_ n: Int, _ d: Int) -> String { String(format: "%.1f%%", d == 0 ? 0 : 100 * Double(n) / Double(d)) }

var variants: [Variant] = []

var noContext = Corrector.Config()
noContext.contextWeight = 0
let plain = Corrector(model: model, config: noContext)
variants.append((name: "Engine: frequency only", correct: { typed, _ in plain.correction(for: typed, previous: nil) }))

let contextual = Corrector(model: model)
variants.append((name: "Engine: frequency + context", correct: { typed, previous in contextual.correction(for: typed, previous: previous) }))

#if canImport(AppKit)
let checker = NSSpellChecker.shared
let tag = NSSpellChecker.uniqueSpellDocumentTag()
func appleKnows(_ word: String) -> Bool {
    checker.checkSpelling(of: word, startingAt: 0, language: nil, wrap: false,
                          inSpellDocumentWithTag: tag, wordCount: nil).location == NSNotFound
}
func appleGuesses(_ word: String) -> [String] {
    let range = NSRange(location: 0, length: (word as NSString).length)
    return checker.guesses(forWordRange: range, in: word, language: checker.language(), inSpellDocumentWithTag: tag) ?? []
}

/// What the app did before this engine: Apple's own correction, then the closest keyboard slip.
let special = ["i": "I", "im": "I'm", "ive": "I've", "dont": "don't", "doesnt": "doesn't", "didnt": "didn't",
               "cant": "can't", "isnt": "isn't", "wasnt": "wasn't", "arent": "aren't", "werent": "weren't",
               "havent": "haven't", "hasnt": "hasn't", "couldnt": "couldn't", "wouldnt": "wouldn't",
               "shouldnt": "shouldn't", "thats": "that's", "whats": "what's", "youre": "you're", "theyre": "they're"]
variants.insert((name: "Before (Apple spell checker + keyboard fallback)", correct: { typed, _ in
    let lower = typed.lowercased()
    if let fix = special[lower] { return fix == typed ? nil : fix }
    guard typed.count >= 2, !appleKnows(typed) else { return nil }
    let range = NSRange(location: 0, length: (typed as NSString).length)
    if let c = checker.correction(forWordRange: range, in: typed, language: checker.language(), inSpellDocumentWithTag: tag) {
        return c
    }
    guard typed.count >= 3 else { return nil }
    let limit: Double = typed.count >= 6 ? 2 : typed.count >= 4 ? 1.5 : 1
    let best = appleGuesses(typed).prefix(8).filter { !$0.contains(" ") && !$0.contains("-") }
        .map { ($0, KeyboardDistance.between(lower, $0.lowercased())) }.min { $0.1 < $1.1 }
    if let best, best.1 <= limit { return best.0 }
    return nil
}), at: 0)

func appleCorrection(_ word: String) -> String? {
    let range = NSRange(location: 0, length: (word as NSString).length)
    return checker.correction(forWordRange: range, in: word, language: checker.language(), inSpellDocumentWithTag: tag)
}
// How the app combines the engine with Apple's spell checker. (Session 1 compared stricter and
// looser combinations; see docs/WORK_LOG.md. Add rows here to compare again.)
for (label, overrideUpTo, bonus) in [("what the app uses", 1.0, 0.0)] {
    var cfg = Corrector.Config()
    cfg.overrideElsewhereUpTo = overrideUpTo
    cfg.preferredBonus = bonus
    let combined = Corrector(model: model, config: cfg)
    variants.append((name: "Engine + Apple, \(label)", correct: { typed, previous in
        let misspelled = !appleKnows(typed)
        return combined.correction(for: typed, previous: previous,
                                   extraCandidates: misspelled ? appleGuesses(typed) : [],
                                   preferred: misspelled && bonus > 0 ? appleCorrection(typed) : nil,
                                   isKnownElsewhere: appleKnows)
    }))
}
#endif

print("| Variant | Real misspellings fixed | …changed to the wrong word | Laptop typos fixed | …wrong word | Correct words wrongly changed |")
print("| --- | --- | --- | --- | --- | --- |")
for v in variants {
    let (real, typos, changed) = score(v)
    print("| \(v.name) | \(pct(real.fixed, real.total)) | \(pct(real.wrong, real.total)) | \(pct(typos.fixed, typos.total)) | \(pct(typos.wrong, typos.total)) | \(pct(changed, correct.count)) |")
}
print("\n\(misspellings.count) real misspellings, \(synthetic.count) laptop typos in context, \(correct.count) correct words.")

if CommandLine.arguments.contains("--show") {
    print("\nCorrect words changed:")
    for r in correct where r.count == 2 { if let o = contextual.correction(for: r[1], previous: r[0]) { print("  \(r[0]) \(r[1]) → \(o)") } }
    print("\nLaptop typos fixed wrongly (sample):")
    for r in synthetic.prefix(1500) where r.count == 3 { if let o = contextual.correction(for: r[1], previous: r[0]), o.lowercased() != r[2] { print("  \(r[0]) \(r[1]) → \(o) (meant \(r[2]))") } }
}

if CommandLine.arguments.contains("--tune") {
    print("\nerrorWeight contextWeight | real fixed / wrong | typos fixed / wrong | correct changed")
    for ew in [5.0, 7.0, 9.0, 11.0] {
        for cw in [0.8, 0.9, 0.95] {
            var cfg = Corrector.Config()
            cfg.errorWeight = ew
            cfg.contextWeight = cw
            let c = Corrector(model: model, config: cfg)
            let (real, typos, changed) = score((name: "", correct: { t, p in c.correction(for: t, previous: p) }))
            print("\(ew) \(cw) | \(pct(real.fixed, real.total)) / \(pct(real.wrong, real.total)) | \(pct(typos.fixed, typos.total)) / \(pct(typos.wrong, typos.total)) | \(pct(changed, correct.count))")
        }
    }
}

if CommandLine.arguments.contains("--real") {
    print("\nReal misspellings fixed wrongly (sample):")
    var n = 0
    for r in misspellings where r.count == 2 {
        if let o = contextual.correction(for: r[0], previous: nil), o.lowercased() != r[1] {
            n += 1
            if n % 12 == 0 { print("  \(r[0]) → \(o) (meant \(r[1]); known candidate: \(model.unigrams[r[1]] != nil))") }
        }
    }
}

if CommandLine.arguments.contains("--costs") {
    print("\nfirstLetter vowel | real fixed / wrong | typos fixed / wrong | correct changed")
    for fl in [0.0, 0.2, 0.35, 0.5] {
        for vs in [0.6, 0.8, 1.0] {
            KeyboardDistance.costs.firstLetter = fl
            KeyboardDistance.costs.vowelSubstitution = vs
            let (real, typos, changed) = score((name: "", correct: { t, p in contextual.correction(for: t, previous: p) }))
            print("\(fl) \(vs) | \(pct(real.fixed, real.total)) / \(pct(real.wrong, real.total)) | \(pct(typos.fixed, typos.total)) / \(pct(typos.wrong, typos.total)) | \(pct(changed, correct.count))")
        }
    }
}

if CommandLine.arguments.contains("--confidence") {
    print("\nconfidentCost margin | real fixed / wrong | typos fixed / wrong | correct changed")
    for cc in [0.6, 1.0, 1.5] {
        for m in [0.0, 1.0, 2.0, 3.0, 4.0] {
            var cfg = Corrector.Config()
            cfg.confidentCost = cc
            cfg.margin = m
            let c = Corrector(model: model, config: cfg)
            let (real, typos, changed) = score((name: "", correct: { t, p in c.correction(for: t, previous: p) }))
            print("\(cc) \(m) | \(pct(real.fixed, real.total)) / \(pct(real.wrong, real.total)) | \(pct(typos.fixed, typos.total)) / \(pct(typos.wrong, typos.total)) | \(pct(changed, correct.count))")
        }
    }
}

if CommandLine.arguments.contains("--why") {
    // Where do laptop-typo misses come from?
    var missingCandidate = 0, outscored = 0, gated = 0, ok = 0
    var examples: [String: [String]] = [:]
    for r in synthetic where r.count == 3 {
        let (prev, typo, intended) = (r[0], r[1], r[2])
        let out = contextual.correction(for: typo, previous: prev)
        if out?.lowercased() == intended { ok += 1; continue }
        let cands = model.candidates(for: typo)
        let cost = KeyboardDistance.between(typo, intended)
        let limit = contextual.config.maxCost(typo.count)
        let bucket: String
        if !cands.contains(intended) { missingCandidate += 1; bucket = "not a candidate" }
        else if out == nil { gated += 1; bucket = cost > limit ? "over cost limit" : "left alone (not confident)" }
        else { outscored += 1; bucket = "outscored" }
        if (examples[bucket]?.count ?? 0) < 25 {
            examples[bucket, default: []].append("\(prev) \(typo) → \(out ?? "–") (meant \(intended), cost \(String(format: "%.1f", cost)))")
        }
    }
    print("\nok \(ok)  not-a-candidate \(missingCandidate)  outscored \(outscored)  left-alone \(gated)")
    for (k, v) in examples { print("\n[\(k)]"); v.forEach { print("  " + $0) } }
}
