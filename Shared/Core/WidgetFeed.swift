import Foundation

/// A compact word record for widgets, read from widget_words.tsv (widgets have a tight memory budget).
struct WidgetWord: Hashable, Sendable, Identifiable {
    let id: Int
    let hanzi: String
    let pinyin: String
    let meaning: String
    let levels: [String: Int]
    let topics: [String]
    let frequency: Int
    let sentence: String
    let sentencePinyin: String
    let sentenceEnglish: String

    static let placeholder = WidgetWord(id: 0, hanzi: "朋友", pinyin: "péng you", meaning: "friend",
                                        levels: ["h26": 1], topics: ["people"], frequency: 300,
                                        sentence: "他是我最好的朋友。", sentencePinyin: "tā shì wǒ zuì hǎo de péng you",
                                        sentenceEnglish: "He is my best friend.")
}

enum WidgetSource: String, Codable, CaseIterable, Sendable {
    case smart, today, learning, level, saved

    var title: String {
        switch self {
        case .smart: return "Smart mix"
        case .today: return "Today's new words"
        case .learning: return "Words I'm learning"
        case .level: return "My HSK level"
        case .saved: return "Saved words"
        }
    }
}

enum WidgetFeed {
    static func loadWords(bundle: Bundle = .main) -> [WidgetWord] {
        guard let url = bundle.url(forResource: "widget_words", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var out: [WidgetWord] = []
        out.reserveCapacity(11_500)
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard f.count >= 10, let id = Int(f[0]) else { continue }
            var lv: [String: Int] = [:]
            for pair in f[4].split(separator: ",") {
                let kv = pair.split(separator: ":")
                if kv.count == 2, let n = Int(kv[1]) { lv[String(kv[0])] = n }
            }
            out.append(WidgetWord(id: id, hanzi: f[1], pinyin: f[2], meaning: f[3], levels: lv,
                                  topics: f[5].split(separator: ",").map(String.init), frequency: Int(f[6]) ?? 99_999,
                                  sentence: f[7], sentencePinyin: f[8], sentenceEnglish: f[9]))
        }
        return out
    }

    /// The words a widget rotates through, in a stable order for the day.
    static func pool(source: WidgetSource, state: UserState, words: [WidgetWord], today: Int) -> [WidgetWord] {
        let byID = Dictionary(words.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let settings = state.settings
        let key = settings.syllabus.rawValue

        func levelWords(limit: Int, unlearnedOnly: Bool) -> [WidgetWord] {
            words.filter { $0.levels[key] == settings.level && (!unlearnedOnly || state.cards[$0.id] == nil) }
                .sorted { $0.frequency < $1.frequency }
                .prefix(limit).map { $0 }
        }
        let todayIDs = (state.plan?.day == today ? state.plan?.newWordIDs : nil) ?? []
        let learning = state.cards.filter { !$0.value.isKnown }
            .sorted { $0.value.due < $1.value.due }
            .prefix(60).compactMap { byID[$0.key] }

        var result: [WidgetWord]
        switch source {
        case .today:
            result = todayIDs.compactMap { byID[$0] }
        case .learning:
            result = learning
        case .saved:
            result = (state.lists.first?.wordIDs ?? []).compactMap { byID[$0] }
        case .level:
            result = levelWords(limit: 400, unlearnedOnly: false)
        case .smart:
            var seen = Set<Int>()
            result = []
            for w in todayIDs.compactMap({ byID[$0] }) + learning where seen.insert(w.id).inserted {
                result.append(w)
            }
            if result.count < 12 {
                for w in levelWords(limit: 40, unlearnedOnly: true) where seen.insert(w.id).inserted {
                    result.append(w)
                    if result.count >= 30 { break }
                }
            }
        }
        if result.isEmpty { result = levelWords(limit: 200, unlearnedOnly: false) }
        if result.isEmpty { result = Array(words.prefix(50)) }
        return stableShuffle(result, seed: UInt64(today))
    }

    /// Picks the word for a given time slot. Slots advance every `intervalMinutes`.
    static func word(at date: Date, pool: [WidgetWord], intervalMinutes: Int, offset: Int) -> WidgetWord? {
        guard !pool.isEmpty else { return nil }
        return pool[slotIndex(at: date, intervalMinutes: intervalMinutes, offset: offset, count: pool.count)]
    }

    static func slotIndex(at date: Date, intervalMinutes: Int, offset: Int, count: Int) -> Int {
        let minutes = Int(date.timeIntervalSince1970 / 60)
        let slot = minutes / max(intervalMinutes, 1)
        return ((slot + offset) % count + count) % count
    }

    /// Start of the slot containing `date`.
    static func slotStart(_ date: Date, intervalMinutes: Int) -> Date {
        let step = Double(max(intervalMinutes, 1) * 60)
        return Date(timeIntervalSince1970: floor(date.timeIntervalSince1970 / step) * step)
    }

    static func stableShuffle<T>(_ items: [T], seed: UInt64) -> [T] {
        var rng = SplitMix64(seed: seed &+ 0x9E37_79B9_7F4A_7C15)
        var a = items
        if a.count < 2 { return a }
        for i in stride(from: a.count - 1, to: 0, by: -1) {
            let j = Int(rng.next() % UInt64(i + 1))
            a.swapAt(i, j)
        }
        return a
    }
}

struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
