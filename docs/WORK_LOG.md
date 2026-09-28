# AC Notch work log

Handoff between scheduled work sessions (Sep 28 – Oct 1, 2026). Each session reads this first,
finishes anything marked unfinished, then does its own work and updates this file.

## Session 1 — Sep 28: accuracy engine, steps 1–2 + benchmark

Status: **in progress**

### Done
- **Correction engine** (`Sources/ACNotchEngine`, plain Swift so it builds and tests on Linux too):
  - `LanguageModel`: lexicon (194k words), unigram frequencies (39.9k candidate words), 250k bigrams
    for context; a delete-index finds candidates within ~2 edits with a few dozen lookups.
  - `KeyboardDistance`: weighted Damerau edit distance. Neighbouring keys 0.5, swapped letters 0.6,
    doubled/dropped repeated letters 0.5–0.6, vowel-for-vowel 0.8, +0.2 if the first letter differs.
  - `Corrector`: noisy-channel scoring, log P(word | previous word) − 7 × keyboard cost, with
    interpolation 0.9 bigram / 0.1 unigram. Leaves alone: known words, acronyms, words with digits
    or accents, capitalised words mid-sentence (names); sentence-start capitalised words only get
    tiny slips fixed. Confidence gate: slips costing more than 1.0 need a 3.0 log-score lead over
    the runner-up, or the word is left alone. Contractions list (dont → don't…), with ambiguous
    ones (cant, wont, ill, id, lets, hes, shes) only fixed when context favours them.
- **App wired to the engine** (`Suggester`): engine decides, Apple's spell checker supplies extra
  candidates and "is this a known word" (names the user taught macOS). Data loads in the
  background at launch; until then Apple's checker alone. `TypingController` tracks the previous
  word ("<s>" after . ! ? or Return, restored when backspacing into a word).
- **Language data** (`Resources/Language`, 5.8 MB, bundled into the app) built by
  `tools/build_language_data.py` — sources and licences in `Resources/Language/ATTRIBUTION.md`.
- **Benchmark** (`Benchmark/data`, `Sources/acbench`), run in CI on every push (Actions step summary):
  5,194 real misspellings (Wikipedia, CC BY-SA 4.0), 3,000 synthetic laptop typos in held-out
  Tatoeba sentences with the previous word, 3,000 correct words that must not change.
  Flags for local exploration: `--show`, `--real`, `--tune`, `--costs`, `--confidence`.
- Unit tests (`Tests/ACNotchEngineTests`), run in CI.

### Benchmark (Linux, engine alone — no Apple spell checker)
| Variant | Real misspellings fixed | …wrong word | Laptop typos fixed | …wrong word | Correct words changed |
| --- | --- | --- | --- | --- | --- |
| First engine draft (context, no name rule) | 69.8% | 19.6% | 94.8% | 5.2% | 1.5% |
| Final today: frequency only | 70.3% | 14.5% | 89.1% | 9.4% | 0.6% |
| **Final today: frequency + context** | **70.3%** | **14.5%** | **94.2%** | **4.8%** | **0.4%** |

Mac numbers, including the "before" baseline (Apple spell checker + keyboard fallback, what the app
shipped until now) and the combined engine + Apple, are printed by CI: see the latest run's summary.

Caveat: the few weights above were tuned on the same test sets (coarse grid, 2–3 values each), so
the numbers are slightly optimistic. Session 2 should split off a separate tuning set.

### Raw data (not committed) — re-download to rebuild
- https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
- https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
- https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.tar.gz (use `final/`)
- Wikipedia: `https://en.wikipedia.org/w/index.php?title=Wikipedia:Lists_of_common_misspellings/<A..Z>&action=raw`, concatenated
- Then: `python3 tools/build_language_data.py --freq … --scowl …/final --tatoeba eng_sentences.tsv --wiki wiki_lcm.txt`
- Local Swift for Linux: swift-6.0.3-RELEASE-ubuntu24.04 from download.swift.org; `swift test`,
  `swift build -c release --product acbench && .build/release/acbench .`

### Next (session 2)
- Separate tuning set from test set.
- Step 3 laptop typo patterns (space/letter slips like "thequick", missing apostrophes beyond the list),
  step 4 personal learning (frequently typed words), step 5 small on-device model, measured.
- Check the Mac CI numbers: engine + Apple vs before.
