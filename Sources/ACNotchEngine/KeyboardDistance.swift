/// Edit distance that knows the keyboard and how people actually mistype on a laptop:
/// hitting a neighbouring key, swapping two letters, doubling or dropping a repeated
/// letter all cost less than an unrelated mistake. So "hwllo" is closer to "hello"
/// than to "hollo", and "helo" is a cheap slip from "hello".
public enum KeyboardDistance {
    private static let rows = ["qwertyuiop", "asdfghjkl", "zxcvbnm"].map { Array($0) }

    private static let position: [Character: (row: Int, col: Int)] = {
        var map: [Character: (row: Int, col: Int)] = [:]
        for (r, row) in rows.enumerated() {
            for (c, key) in row.enumerated() { map[key] = (r, c) }
        }
        return map
    }()

    /// On a staggered keyboard, a key touches its row neighbours and two keys in each adjacent row.
    public static func adjacent(_ a: Character, _ b: Character) -> Bool {
        guard let p = position[a], let q = position[b] else { return false }
        if p.row == q.row { return abs(p.col - q.col) == 1 }
        if q.row == p.row + 1 { return q.col == p.col || q.col == p.col - 1 }
        if q.row == p.row - 1 { return q.col == p.col || q.col == p.col + 1 }
        return false
    }

    /// What each kind of slip costs. Tuned on the benchmark's tuning set (see docs/WORK_LOG.md).
    public struct Costs {
        /// Hitting the key next to the right one.
        public var adjacentSubstitution = 0.78
        /// One vowel for another ("seperate"): a spelling slip rather than a finger slip.
        public var vowelSubstitution = 1.0
        /// Any other wrong letter: rare on a real keyboard.
        public var substitution = 1.6
        /// Two neighbouring letters swapped ("teh").
        public var transposition = 0.6
        /// An extra copy of the letter before it ("fulll").
        public var repeatInsertion = 0.75
        /// An extra letter from a key next to its neighbour ("helkl").
        public var neighborInsertion = 0.96
        /// Any other extra letter.
        public var insertion = 1.25
        /// A letter left out ("hould").
        public var deletion = 0.64
        /// One of a pair of repeated letters left out ("ocasion", "helo").
        public var doubledDeletion = 0.64
        /// Extra cost when the first letter differs (unless the first two are just swapped).
        public var firstLetter = 0.16
        public init() {}
    }

    public static var costs = Costs()

    /// Cost of turning `typed` into `intended`.
    public static func between(_ typed: String, _ intended: String) -> Double {
        let s = Array(typed), t = Array(intended)
        if s.isEmpty || t.isEmpty { return Double(max(s.count, t.count)) }
        let c = costs
        var d = Array(repeating: Array(repeating: 0.0, count: t.count + 1), count: s.count + 1)
        for i in 1...s.count { d[i][0] = d[i - 1][0] + insertionCost(s, i - 1, c) }
        for j in 1...t.count { d[0][j] = d[0][j - 1] + deletionCost(t, j - 1, c) }
        for i in 1...s.count {
            for j in 1...t.count {
                let sub = s[i - 1] == t[j - 1] ? 0
                    : adjacent(s[i - 1], t[j - 1]) ? c.adjacentSubstitution
                    : (vowels.contains(s[i - 1]) && vowels.contains(t[j - 1])) ? c.vowelSubstitution
                    : c.substitution
                var best = min(d[i - 1][j] + insertionCost(s, i - 1, c),
                               d[i][j - 1] + deletionCost(t, j - 1, c),
                               d[i - 1][j - 1] + sub)
                if i > 1, j > 1, s[i - 1] == t[j - 2], s[i - 2] == t[j - 1] {
                    best = min(best, d[i - 2][j - 2] + c.transposition)
                }
                d[i][j] = best
            }
        }
        var total = d[s.count][t.count]
        // A different first letter, unless it's just the first two letters swapped.
        if s[0] != t[0], !(s.count > 1 && t.count > 1 && s[0] == t[1] && s[1] == t[0]) { total += c.firstLetter }
        return total
    }

    private static let vowels: Set<Character> = ["a", "e", "i", "o", "u", "y"]

    /// The typist pressed `s[k]` though it isn't in the intended word.
    private static func insertionCost(_ s: [Character], _ k: Int, _ c: Costs) -> Double {
        if k > 0, s[k] == s[k - 1] { return c.repeatInsertion }
        if (k > 0 && adjacent(s[k], s[k - 1])) || (k + 1 < s.count && adjacent(s[k], s[k + 1])) {
            return c.neighborInsertion
        }
        return c.insertion
    }

    /// The typist skipped `t[k]`, a letter of the intended word.
    private static func deletionCost(_ t: [Character], _ k: Int, _ c: Costs) -> Double {
        if (k > 0 && t[k] == t[k - 1]) || (k + 1 < t.count && t[k] == t[k + 1]) { return c.doubledDeletion }
        return c.deletion
    }
}
