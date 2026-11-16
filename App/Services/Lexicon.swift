import Foundation

/// Stroke outlines and medians for one character (Make Me a Hanzi data, 1024-unit box, y up, baseline at 900).
struct StrokeData: Codable, Sendable {
    /// SVG path strings, one per stroke.
    let s: [String]
    /// Median polylines, one per stroke, as [[x, y]] points.
    let m: [[[Double]]]
    /// Indices of strokes that belong to the radical.
    let r: [Int]

    var strokes: [String] { s }
    var medians: [[[Double]]] { m }
    var radicalStrokes: Set<Int> { Set(r) }
}

enum LexiconError: Error { case missing(String) }

/// The bundled dictionary: words, example sentences, characters and stroke data.
final class Lexicon: @unchecked Sendable {
    static let shared = Lexicon()

    private(set) var words: [Word] = []
    private(set) var byID: [Int: Word] = [:]
    private(set) var byHanzi: [String: Word] = [:]
    private(set) var topics: [Topic] = []
    private(set) var sentences: [Sentence] = []
    private(set) var chars: [String: CharInfo] = [:]
    private(set) var isLoaded = false

    private var strokeIndex: [String: [Int]] = [:]
    private var strokeDataStart = 0
    private var strokeURL: URL?
    private var strokeCache: [String: StrokeData] = [:]
    private var charToWords: [String: [Int]] = [:]
    /// Toneless, spaceless pinyin per word index, for fast search.
    private var plainPinyin: [String] = []
    private var numberedPinyin: [String] = []
    private let lock = NSLock()

    func load(bundle: Bundle = .main) throws {
        if isLoaded { return }
        func url(_ name: String, _ ext: String) throws -> URL {
            guard let u = bundle.url(forResource: name, withExtension: ext) else { throw LexiconError.missing("\(name).\(ext)") }
            return u
        }
        let dec = JSONDecoder()
        let file = try dec.decode(WordFile.self, from: Data(contentsOf: url("words", "json")))
        let sents = try dec.decode([Sentence].self, from: Data(contentsOf: url("sentences", "json")))
        let ch = try dec.decode([String: CharInfo].self, from: Data(contentsOf: url("chars", "json")))

        // stroke pack: 4-byte little-endian index length, JSON index, then the blobs
        let packURL = try url("strokes", "pack")
        let handle = try FileHandle(forReadingFrom: packURL)
        defer { try? handle.close() }
        let lenData = handle.readData(ofLength: 4)
        guard lenData.count == 4 else { throw LexiconError.missing("strokes.pack header") }
        let indexLength = lenData.withUnsafeBytes { Int(UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self))) }
        let indexData = handle.readData(ofLength: indexLength)
        let index = try dec.decode([String: [Int]].self, from: indexData)

        var byID: [Int: Word] = [:]
        var byHanzi: [String: Word] = [:]
        var c2w: [String: [Int]] = [:]
        for w in file.words {
            byID[w.id] = w
            if let existing = byHanzi[w.s] {
                if w.f < existing.f { byHanzi[w.s] = w }
            } else {
                byHanzi[w.s] = w
            }
            for c in Set(w.characters) { c2w[c, default: []].append(w.id) }
        }
        lock.lock()
        self.words = file.words
        self.byID = byID
        self.byHanzi = byHanzi
        self.topics = file.topics.compactMap { $0.count == 2 ? Topic(id: $0[0], title: $0[1]) : nil }
        self.sentences = sents
        self.chars = ch
        self.strokeIndex = index
        self.strokeDataStart = 4 + indexLength
        self.strokeURL = packURL
        self.charToWords = c2w
        self.plainPinyin = file.words.map { Pinyin.plain($0.p) }
        self.numberedPinyin = file.words.map { Pinyin.numbered($0.p).replacingOccurrences(of: " ", with: "").lowercased() }
        self.isLoaded = true
        lock.unlock()
    }

    func word(_ id: Int) -> Word? { byID[id] }
    func word(hanzi: String) -> Word? { byHanzi[hanzi] }

    /// Words of one level, most frequent first.
    func words(level: Int, syllabus: Syllabus, topics: Set<String> = []) -> [Word] {
        words.filter { $0.lv[syllabus.rawValue] == level && (topics.isEmpty || !topics.isDisjoint(with: $0.topics)) }
            .sorted { $0.f < $1.f }
    }

    func words(topic: String, syllabus: Syllabus, maxLevel: Int) -> [Word] {
        words.filter { $0.topics.contains(topic) && ($0.lv[syllabus.rawValue] ?? 99) <= maxLevel }
            .sorted { ($0.lv[syllabus.rawValue] ?? 9, $0.f) < ($1.lv[syllabus.rawValue] ?? 9, $1.f) }
    }

    func sentences(for word: Word) -> [Sentence] {
        word.exampleIDs.compactMap { $0 < sentences.count ? sentences[$0] : nil }
    }

    func charInfo(_ c: String) -> CharInfo? { chars[c] }

    /// Words containing a character, ordered by level then frequency.
    func wordsContaining(_ c: String, syllabus: Syllabus, limit: Int = 12) -> [Word] {
        (charToWords[c] ?? []).compactMap { byID[$0] }
            .filter { $0.s != c }
            .sorted { ($0.displayLevel(in: syllabus), $0.f) < ($1.displayLevel(in: syllabus), $1.f) }
            .prefix(limit).map { $0 }
    }

    func strokes(for c: String) -> StrokeData? {
        guard let scalar = c.unicodeScalars.first else { return nil }
        let key = String(scalar.value, radix: 16)
        lock.lock(); defer { lock.unlock() }
        if let cached = strokeCache[key] { return cached }
        guard let url = strokeURL, let entry = strokeIndex[key], entry.count == 2,
              let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(strokeDataStart + entry[0]))
            let data = handle.readData(ofLength: entry[1])
            let sd = try JSONDecoder().decode(StrokeData.self, from: data)
            strokeCache[key] = sd
            return sd
        } catch {
            return nil
        }
    }

    /// Search by characters, pinyin (with or without tones, with or without spaces) or English.
    func search(_ query: String, syllabus: Syllabus, limit: Int = 80) -> [Word] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        let hasHan = q.unicodeScalars.contains { CharacterSet.han.contains($0) }
        var scored: [(Int, Word)] = []
        if hasHan {
            for w in words where w.s.contains(q) || (w.t?.contains(q) ?? false) {
                let score = (w.s == q ? 0 : (w.s.hasPrefix(q) ? 1 : 2)) * 100_000 + w.f
                scored.append((score, w))
            }
        } else {
            let pq = Pinyin.plain(q)
            let numbered = q.replacingOccurrences(of: " ", with: "").lowercased()
            let lowerQ = q.lowercased()
            for (i, w) in words.enumerated() {
                let pw = plainPinyin[i]
                var score: Int?
                if pw == pq || numberedPinyin[i] == numbered {
                    score = 0
                } else if pq.count >= 2 && pw.hasPrefix(pq) {
                    score = 1
                } else if lowerQ.count >= 3, let hit = w.m.firstIndex(where: { meaningMatches($0, lowerQ) }) {
                    score = 2 + hit
                }
                if let s = score { scored.append((s * 100_000 + w.f, w)) }
            }
        }
        _ = syllabus
        return scored.sorted { $0.0 < $1.0 }.prefix(limit).map { $0.1 }
    }

    private func meaningMatches(_ meaning: String, _ q: String) -> Bool {
        let m = meaning.lowercased()
        guard let r = m.range(of: q) else { return false }
        // whole-word-ish match: start of string or preceded by a non-letter
        if r.lowerBound == m.startIndex { return true }
        let before = m[m.index(before: r.lowerBound)]
        return !before.isLetter
    }

    /// Distractor meanings for multiple-choice questions: same level, same rough part of speech.
    func distractors(for word: Word, syllabus: Syllabus, count: Int = 3) -> [Word] {
        let level = word.displayLevel(in: syllabus)
        let pos = word.pos?.first
        let pool = words.filter {
            $0.id != word.id && $0.displayLevel(in: syllabus) == level && $0.s != word.s
                && $0.meaning.lowercased() != word.meaning.lowercased()
                && !$0.s.contains(word.s) && !word.s.contains($0.s)
        }
        let samePos = pool.filter { $0.pos?.first == pos }
        var source = samePos.count >= count * 3 ? samePos : pool
        source.shuffle()
        var out: [Word] = []
        var seenMeanings = Set([word.meaning.lowercased()])
        for w in source where seenMeanings.insert(w.meaning.lowercased()).inserted {
            out.append(w)
            if out.count == count { break }
        }
        return out
    }
}
