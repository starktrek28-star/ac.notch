#!/usr/bin/env python3
"""Builds AC Notch's language data and typo benchmark from public sources.

Inputs (downloaded separately, not committed; see docs/WORK_LOG.md for URLs):
  --freq      hermitdave/FrequencyWords en_50k.txt          (CC BY-SA 4.0, OpenSubtitles 2018)
  --scowl     SCOWL 2020.12.07 "final" directory            (SCOWL licence, permissive)
  --tatoeba   Tatoeba eng_sentences.tsv                     (CC BY 2.0 FR)
  --wiki      concatenated raw Wikipedia "Lists of common misspellings" A–Z pages (CC BY-SA 4.0)

Outputs:
  Resources/Language/lexicon.txt    every word we accept as correctly spelled (lowercase)
  Resources/Language/unigrams.tsv   word<TAB>count, the candidate vocabulary with frequencies
  Resources/Language/bigrams.tsv    previous<TAB>word<TAB>count ("<s>" = start of sentence)
  Benchmark/data/*.tsv              held-out test sets (never used to build the model)
"""
import argparse, bz2, collections, glob, os, random, re, unicodedata, zlib

ap = argparse.ArgumentParser()
ap.add_argument("--freq", required=True)
ap.add_argument("--scowl", required=True)
ap.add_argument("--tatoeba", required=True)
ap.add_argument("--wiki", required=True)
ap.add_argument("--out", default=".")
args = ap.parse_args()

WORD = re.compile(r"[a-z]+(?:'[a-z]+)?")
lang_dir = os.path.join(args.out, "Resources", "Language")
bench_dir = os.path.join(args.out, "Benchmark", "data")
os.makedirs(lang_dir, exist_ok=True)
os.makedirs(bench_dir, exist_ok=True)

# ---- Lexicon: what counts as a real word -------------------------------------------------
regions = ["english", "american", "british", "british_z", "canadian", "australian", "variant_1"]
kinds = {"words": 70, "upper": 70, "contractions": 70, "abbreviations": 70, "proper-names": 80}
lexicon = set()
for region in regions:
    for kind, max_size in kinds.items():
        for path in glob.glob(os.path.join(args.scowl, f"{region}-{kind}.*")):
            if int(path.rsplit(".", 1)[1]) > max_size:
                continue
            with open(path, encoding="latin-1") as f:
                for line in f:
                    w = line.strip().lower()
                    # "café" is also accepted typed plainly as "cafe".
                    folded = unicodedata.normalize("NFKD", w).encode("ascii", "ignore").decode()
                    for form in {w, folded}:
                        if WORD.fullmatch(form):
                            lexicon.add(form)
for w in "i a".split():
    lexicon.add(w)

# ---- Unigrams: candidate vocabulary ranked by how often people use each word -----------
unigrams = {}
with open(args.freq, encoding="utf-8") as f:
    for line in f:
        parts = line.split()
        if len(parts) != 2:
            continue
        w, c = parts[0].lower(), int(parts[1])
        if WORD.fullmatch(w) and w in lexicon and w not in unigrams:
            unigrams[w] = c

# ---- Tatoeba: split once, train the context model on 90%, test on the rest -------------
def split_of(sentence_id):
    return "test" if zlib.crc32(sentence_id.encode()) % 10 == 0 else "train"

bigrams = collections.Counter()
tatoeba_unigrams = collections.Counter()
test_sentences = []
with open(args.tatoeba, encoding="utf-8") as f:
    for line in f:
        parts = line.rstrip("\n").split("\t")
        if len(parts) < 3:
            continue
        sid, text = parts[0], parts[2]
        if split_of(sid) == "test":
            test_sentences.append(text)
            continue
        tokens = ["<s>"] + WORD.findall(text.lower().replace("’", "'"))
        tatoeba_unigrams.update(tokens[1:])
        for a, b in zip(tokens, tokens[1:]):
            if b in unigrams or ("'" in b and b in lexicon):
                bigrams[(a, b)] += 1

# The subtitle frequency list splits contractions ("don" + "t"), so estimate their
# frequency from the sentences, scaled to the subtitle counts.
scale = unigrams["the"] / max(tatoeba_unigrams["the"], 1)
for w, c in tatoeba_unigrams.items():
    if "'" in w and w in lexicon and w not in unigrams and c >= 3:
        unigrams[w] = int(c * scale)

kept = [(k, c) for k, c in bigrams.items() if c >= 2]
kept.sort(key=lambda kc: -kc[1])
kept = kept[:250_000]

with open(os.path.join(lang_dir, "lexicon.txt"), "w") as f:
    f.write("\n".join(sorted(lexicon)) + "\n")
with open(os.path.join(lang_dir, "unigrams.tsv"), "w") as f:
    for w, c in sorted(unigrams.items(), key=lambda wc: -wc[1]):
        f.write(f"{w}\t{c}\n")
with open(os.path.join(lang_dir, "bigrams.tsv"), "w") as f:
    for (a, b), c in kept:
        f.write(f"{a}\t{b}\t{c}\n")

# ---- Benchmark 1: real human misspellings (Wikipedia) -------------------------------------
LCM = re.compile(r"^\*\s*\{\{search link\|\"?([^|\"]+)\"?\|[^}]*\}\}\s*\((.+)\)\s*$")
real = {}
with open(args.wiki, encoding="utf-8") as f:
    for line in f:
        m = LCM.match(line.strip())
        if not m:
            continue
        wrong = m.group(1).strip().lower()
        right = re.sub(r"\[\[(?:[^|\]]*\|)?([^\]]*)\]\]", r"\1", m.group(2)).split(",")[0].strip().lower()
        if WORD.fullmatch(wrong) and WORD.fullmatch(right) and wrong != right and wrong not in lexicon:
            real.setdefault(wrong, right)
with open(os.path.join(bench_dir, "misspellings.tsv"), "w") as f:
    f.write("# typo\tintended — Wikipedia: Lists of common misspellings (CC BY-SA 4.0)\n")
    for wrong, right in sorted(real.items()):
        f.write(f"{wrong}\t{right}\n")

# ---- Benchmark 2: laptop-style typos in context (synthetic, from held-out sentences) ------
ROWS = ["qwertyuiop", "asdfghjkl", "zxcvbnm"]
POS = {ch: (r, c) for r, row in enumerate(ROWS) for c, ch in enumerate(row)}
def neighbours(ch):
    if ch not in POS:
        return []
    r, c = POS[ch]
    out = []
    for rr, cc in [(r, c - 1), (r, c + 1), (r - 1, c), (r - 1, c + 1), (r + 1, c - 1), (r + 1, c)]:
        if 0 <= rr < 3 and 0 <= cc < len(ROWS[rr]):
            out.append(ROWS[rr][cc])
    return out

def make_typo(word, rng):
    for _ in range(20):
        op = rng.choices(["sub", "swap", "drop", "insert", "double"], [35, 25, 20, 10, 10])[0]
        i = rng.randrange(len(word))
        if op == "sub" and neighbours(word[i]):
            t = word[:i] + rng.choice(neighbours(word[i])) + word[i + 1:]
        elif op == "swap" and i < len(word) - 1 and word[i] != word[i + 1]:
            t = word[:i] + word[i + 1] + word[i] + word[i + 2:]
        elif op == "drop" and len(word) > 3:
            t = word[:i] + word[i + 1:]
        elif op == "insert" and neighbours(word[i]):
            t = word[:i] + rng.choice(neighbours(word[i])) + word[i:]
        elif op == "double":
            t = word[:i] + word[i] + word[i:]
        else:
            continue
        if t != word and t not in lexicon:
            return t
    return None

rng = random.Random(20260928)
rng.shuffle(test_sentences)
synthetic, correct = [], []
for text in test_sentences:
    raw = re.findall(r"[A-Za-z]+(?:'[A-Za-z]+)?", text.replace("’", "'"))
    if not raw:
        continue
    idx = rng.randrange(len(raw))
    prev = raw[idx - 1].lower() if idx > 0 else "<s>"
    word = raw[idx]
    if len(correct) < 3000:
        correct.append((prev, word))
    elif len(synthetic) < 3000 and word.islower() and len(word) >= 3 and word in unigrams:
        typo = make_typo(word, rng)
        if typo:
            synthetic.append((prev, typo, word))
    if len(synthetic) >= 3000 and len(correct) >= 3000:
        break

with open(os.path.join(bench_dir, "synthetic.tsv"), "w") as f:
    f.write("# previous\ttypo\tintended — synthetic keyboard typos in held-out Tatoeba sentences (CC BY 2.0 FR)\n")
    for prev, typo, word in synthetic:
        f.write(f"{prev}\t{typo}\t{word}\n")
with open(os.path.join(bench_dir, "correct.tsv"), "w") as f:
    f.write("# previous\tword — correctly spelled words from held-out Tatoeba sentences; must not change\n")
    for prev, word in correct:
        f.write(f"{prev}\t{word}\n")

print(f"lexicon {len(lexicon)}  unigrams {len(unigrams)}  bigrams {len(kept)}  "
      f"misspellings {len(real)}  synthetic {len(synthetic)}  correct {len(correct)}")
