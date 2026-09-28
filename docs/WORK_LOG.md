# AC Notch work log

Handoff between scheduled work sessions (Sep 28 – Oct 1, 2026). Each session reads this first,
finishes anything marked unfinished, then does its own work and updates this file.

## Session 1 — Sep 28: accuracy engine, steps 1–2 + benchmark

Status: **done** (all three tasks)

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

### Benchmark on macOS (CI, `macos-14`) — the numbers that matter
"Before" = what the app shipped until today (Apple's spell checker + keyboard fallback).

| Variant | Real misspellings fixed | …wrong word | Laptop typos fixed | …wrong word | Correct words changed |
| --- | --- | --- | --- | --- | --- |
| Before | 72.0% | 13.2% | 69.9% | 8.8% | 0.1% |
| Engine alone | 70.3% | 14.5% | 94.2% | 4.8% | 0.4% |
| Engine + Apple, trusting Apple's dictionary | 69.9% | 10.6% | 75.7% | 2.3% | 0.0% |
| Engine + Apple, fix slips ≤0.6 even if Apple knows the word | 74.2% | 11.9% | 88.4% | 3.6% | 0.0% |
| **Engine + Apple, fix slips ≤1.0 even if Apple knows the word (shipped)** | **78.6%** | **13.1%** | **94.1%** | **4.8%** | **0.0%** |
| …plus a +2 bonus for Apple's own pick | 79.6% | 13.1% | 93.7% | 5.3% | 0.0% |
| …plus a +4 bonus | 79.9% | 13.4% | 92.8% | 6.3% | 0.0% |

Why "trusting Apple's dictionary" is weak: macOS accepts many rare strings that are far more often
typos ("hee", "wll"), so it blocked fixes. Capitalised words are still never overridden (names).
The bonus rows traded laptop-typo accuracy for real-misspelling accuracy; not worth it.
CI now runs only Before / engine / shipped (the Apple rows take ~10 min on the runner).

Caveat: the few weights above were tuned on the same test sets (coarse grid, 2–3 values each), so
the numbers are slightly optimistic. Session 2 should split off a separate tuning set.

### Performance note
Apple's `guesses` is slow (~9 ms per call on the M1 CI runner), so the app only asks for it when a
word is finished; the live preview while typing uses the engine alone (~0.1 ms per word).

### Raw data (not committed) — re-download to rebuild
- https://raw.githubusercontent.com/hermitdave/FrequencyWords/master/content/2018/en/en_50k.txt
- https://downloads.tatoeba.org/exports/per_language/eng/eng_sentences.tsv.bz2
- https://downloads.sourceforge.net/wordlist/scowl-2020.12.07.tar.gz (use `final/`)
- Wikipedia: `https://en.wikipedia.org/w/index.php?title=Wikipedia:Lists_of_common_misspellings/<A..Z>&action=raw`, concatenated
- Then: `python3 tools/build_language_data.py --freq … --scowl …/final --tatoeba eng_sentences.tsv --wiki wiki_lcm.txt`
- Local Swift for Linux: swift-6.0.3-RELEASE-ubuntu24.04 from download.swift.org; `swift test`,
  `swift build -c release --product acbench && .build/release/acbench .`

### Extra work Sep 28 (user request: push 94% toward 99.9%) — done
- Added a separate **tuning set** (`Benchmark/data/dev_*.tsv`, held-out sentences after the test
  sample; test files unchanged, same checksums) and split real misspellings into tuning/test halves.
- Every slip type got its own cost, plus per-length limits; `acbench --autotune` tunes them on the
  tuning set only (coordinate descent, 5 rounds), then scores the test set once.
- Tuned settings are the defaults now (`KeyboardDistance.Costs`, `Corrector.Config`).
- **macOS CI, the app as shipped (engine + Apple):**

| | Real misspellings fixed | …wrong | Laptop typos fixed | …wrong | Correct words changed |
| --- | --- | --- | --- | --- | --- |
| Before today | 72.0% | 13.2% | 69.9% | 8.8% | 0.1% |
| After session 1 | 78.6% | 13.1% | 94.1% | 4.8% | 0.0% |
| **Now** | **82.4%** | **10.3%** | **97.5%** | **2.1%** | **0.0%** |

  (Linux, engine alone, test halves: laptop typos 97.7% / 2.2% wrong, real 73.6% / 11.8%.)
- **Ceiling:** 67 of 3,000 laptop typos are still wrong; 43 of those are ties the typed letters
  can't settle ("pla" play/pal, "knw" know/knew, "ocket" pocket/rocket). With only the previous
  word as context the practical ceiling on this test is ~98.6%. Going beyond needs the words
  *after* the typo: re-checking a word once the next word is typed (iOS 17 does sentence-level
  correction). That's the natural next step, together with the step-5 language model.
- Caveat: the laptop-typo set is synthetic (my model of slips: 35% neighbour key, 25% swap,
  20% dropped letter, 10% extra neighbour key, 10% doubled letter). Tuning to it partly tunes to
  that assumption; the real-misspelling numbers (human data) improving too is a good sign.
- Tools: `acbench . --why` (miss breakdown), `--explain <prev> <typo>` (scores), `--ceiling`.

### Next (session 2)
- Sentence-level correction: re-check the previous word once the next one is typed (needs a test
  set with the following word) — the path from ~97.5% toward the ceiling and beyond.
- Step 3 laptop typo patterns (space/letter slips like "thequick", missing apostrophes beyond the list),
  step 4 personal learning (frequently typed words), step 5 small on-device model, measured.
- Check the Mac CI numbers: engine + Apple vs before.
