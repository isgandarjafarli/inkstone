import Foundation

/// Watch-only choices: what the watch face shows and how often it changes.
struct WatchPrefs: Codable, Equatable, Sendable {
    var source: WidgetSource = .smart
    /// Minutes between words on the watch face.
    var interval: Int = 15
    var showPinyin = true
    var showMeaning = true
    /// "Next" taps shift the rotation by this many places.
    var offset = 0

    static let intervals = [5, 15, 30, 60]

    init() {}

    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func read<T: Decodable>(_ key: CodingKeys, _ value: inout T) {
            if let v = try? c.decodeIfPresent(T.self, forKey: key) { value = v }
        }
        read(.source, &source); read(.interval, &interval); read(.showPinyin, &showPinyin)
        read(.showMeaning, &showMeaning); read(.offset, &offset)
    }
}

/// Files the watch app and its complications share (in the watch's own App Group).
enum WatchStore {
    private static var feedURL: URL { SharedStore.containerURL.appendingPathComponent("watch_feed.json") }
    private static var prefsURL: URL { SharedStore.containerURL.appendingPathComponent("watch_prefs.json") }
    private static var doneURL: URL { SharedStore.containerURL.appendingPathComponent("watch_done.json") }

    static func loadFeed() -> WatchFeed? {
        guard let data = try? Data(contentsOf: feedURL) else { return nil }
        return try? JSONDecoder().decode(WatchFeed.self, from: data)
    }

    static func saveFeed(_ feed: WatchFeed) {
        if let data = try? JSONEncoder().encode(feed) { try? data.write(to: feedURL, options: .atomic) }
    }

    static func loadPrefs() -> WatchPrefs {
        guard let data = try? Data(contentsOf: prefsURL),
              let p = try? JSONDecoder().decode(WatchPrefs.self, from: data) else { return WatchPrefs() }
        return p
    }

    static func savePrefs(_ prefs: WatchPrefs) {
        if let data = try? JSONEncoder().encode(prefs) { try? data.write(to: prefsURL, options: .atomic) }
    }

    /// Words reviewed or marked known on the watch today, so they leave the lists before the
    /// phone sends a fresh feed.
    static func loadDone(day: Int) -> Set<Int> {
        guard let data = try? Data(contentsOf: doneURL),
              let d = try? JSONDecoder().decode(DoneList.self, from: data), d.day == day else { return [] }
        return Set(d.ids)
    }

    static func saveDone(_ ids: Set<Int>, day: Int) {
        if let data = try? JSONEncoder().encode(DoneList(day: day, ids: Array(ids))) {
            try? data.write(to: doneURL, options: .atomic)
        }
    }

    private struct DoneList: Codable { var day: Int; var ids: [Int] }
}

/// Builds the watch's word lists from the feed, reading only the rows it needs from the word file.
enum WatchWords {
    /// Reads the words with the given ids, plus up to `levelLimit` of the most frequent words at a level.
    static func load(ids: Set<Int>, level: (key: String, value: Int)?, levelLimit: Int = 200,
                     bundle: Bundle = .main) -> (byID: [Int: WidgetWord], level: [WidgetWord]) {
        guard let url = bundle.url(forResource: "widget_words", withExtension: "tsv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return ([:], []) }
        var byID: [Int: WidgetWord] = [:]
        var levelWords: [WidgetWord] = []
        let levelTag = level.map { "\($0.key):\($0.value)" }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tab = line.firstIndex(of: "\t"), let id = Int(line[line.startIndex..<tab]) else { continue }
            let wanted = ids.contains(id)
            var atLevel = false
            if let levelTag, line.contains(levelTag) {
                let f = line.split(separator: "\t", omittingEmptySubsequences: false)
                atLevel = f.count > 4 && f[4].split(separator: ",").contains { $0 == levelTag }
            }
            guard wanted || atLevel, let w = parse(line) else { continue }
            if wanted { byID[id] = w }
            if atLevel { levelWords.append(w) }
        }
        levelWords.sort { $0.frequency < $1.frequency }
        return (byID, Array(levelWords.prefix(levelLimit)))
    }

    private static func parse(_ line: Substring) -> WidgetWord? {
        let f = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
        guard f.count >= 10, let id = Int(f[0]) else { return nil }
        var lv: [String: Int] = [:]
        for pair in f[4].split(separator: ",") {
            let kv = pair.split(separator: ":")
            if kv.count == 2, let n = Int(kv[1]) { lv[String(kv[0])] = n }
        }
        return WidgetWord(id: id, hanzi: f[1], pinyin: f[2], meaning: f[3], levels: lv,
                          topics: f[5].split(separator: ",").map(String.init), frequency: Int(f[6]) ?? 99_999,
                          sentence: f[7], sentencePinyin: f[8], sentenceEnglish: f[9])
    }

    /// The words the watch face rotates through today, in a stable order for the day.
    static func pool(feed: WatchFeed?, prefs: WatchPrefs, today: Int, done: Set<Int> = [], bundle: Bundle = .main) -> [WidgetWord] {
        let source = prefs.source
        let needLevel = feed == nil || source == .level
        let key = feed?.syllabus ?? Syllabus.hsk2026.rawValue
        let lvl = feed?.level ?? 1
        let loaded = load(ids: feed?.allIDs ?? [], level: needLevel ? (key, lvl) : nil, bundle: bundle)
        func words(_ ids: [Int]) -> [WidgetWord] { ids.compactMap { loaded.byID[$0] } }

        var result: [WidgetWord] = []
        if let feed {
            switch source {
            case .today: result = words(feed.todayIDs)
            case .learning: result = words(feed.learningIDs)
            case .saved: result = words(feed.savedIDs)
            case .level: result = loaded.level
            case .smart:
                var seen = Set<Int>()
                for w in words(feed.todayIDs) + words(feed.learningIDs.filter { !done.contains($0) })
                where seen.insert(w.id).inserted { result.append(w) }
                if result.count < 12 {
                    for w in words(feed.upcomingIDs) where seen.insert(w.id).inserted {
                        result.append(w)
                        if result.count >= 30 { break }
                    }
                }
            }
        }
        if result.isEmpty { result = loaded.level.isEmpty ? load(ids: [], level: (key, lvl), bundle: bundle).level : loaded.level }
        if result.isEmpty { result = [.placeholder] }
        return WidgetFeed.stableShuffle(result, seed: UInt64(today))
    }

    /// Today's reviews, in order, without the ones already done on the watch.
    static func reviews(feed: WatchFeed?, today: Int, done: Set<Int>) -> [WidgetWord] {
        guard let feed, feed.day == today else { return [] }
        let ids = feed.dueIDs.filter { !done.contains($0) }
        let loaded = load(ids: Set(ids), level: nil)
        return ids.compactMap { loaded.byID[$0] }
    }

    /// Reviews still due today, as the watch face should count them.
    static func dueCount(feed: WatchFeed?, today: Int, done: Set<Int>) -> Int {
        guard let feed, feed.day == today else { return 0 }
        return feed.dueIDs.filter { !done.contains($0) }.count
    }
}
