import Foundation

// MARK: - Bundled dictionary data

/// Which official HSK word list the learner follows.
enum Syllabus: String, Codable, CaseIterable, Identifiable, Sendable {
    case hsk2026 = "h26"
    case hsk30 = "h30"
    case hsk20 = "h20"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .hsk2026: return "HSK 2026 exam list"
        case .hsk30: return "HSK 3.0 (2021 standard)"
        case .hsk20: return "HSK 2.0 (classic)"
        }
    }

    var shortTitle: String {
        switch self {
        case .hsk2026: return "HSK 2026"
        case .hsk30: return "HSK 3.0"
        case .hsk20: return "HSK 2.0"
        }
    }

    /// Levels offered by the list. Level 7 stands for the combined 7–9 band.
    var levels: [Int] {
        switch self {
        case .hsk20: return [1, 2, 3, 4, 5, 6]
        default: return [1, 2, 3, 4, 5, 6, 7]
        }
    }

    static func levelName(_ level: Int) -> String { level >= 7 ? "HSK 7–9" : "HSK \(level)" }
}

struct Word: Codable, Identifiable, Hashable, Sendable {
    let id: Int
    /// Simplified form.
    let s: String
    /// Pinyin with tone marks, syllables separated by spaces.
    let p: String
    /// Meanings, most common first.
    let m: [String]
    /// Level per syllabus key ("h26", "h30", "h20").
    let lv: [String: Int]
    /// Frequency rank (lower is more common).
    let f: Int
    let t: String?
    let pos: [String]?
    let cl: [String]?
    let alt: [AltReading]?
    let tp: [String]?
    let ex: [Int]?

    struct AltReading: Codable, Hashable, Sendable {
        let p: String
        let m: [String]
    }

    var hanzi: String { s }
    var pinyin: String { p }
    var meaning: String { m.first ?? "" }
    var traditional: String? { t }
    var characters: [String] { s.map { String($0) }.filter { $0.unicodeScalars.first.map { CharacterSet.han.contains($0) } ?? false } }
    var exampleIDs: [Int] { ex ?? [] }
    var topics: [String] { tp ?? [] }

    func level(in syllabus: Syllabus) -> Int? { lv[syllabus.rawValue] }

    /// Level in the chosen list, falling back to the nearest other list so every word has a label.
    func displayLevel(in syllabus: Syllabus) -> Int {
        lv[syllabus.rawValue] ?? lv["h26"] ?? lv["h30"] ?? lv["h20"] ?? 7
    }
}

struct WordFile: Codable, Sendable {
    let v: Int
    let topics: [[String]]
    let words: [Word]
}

struct Topic: Identifiable, Hashable, Sendable {
    let id: String
    let title: String

    var symbol: String {
        switch id {
        case "grammar": return "text.alignleft"
        case "numbers": return "clock"
        case "people": return "person.2"
        case "food": return "fork.knife"
        case "home": return "house"
        case "travel": return "airplane"
        case "school": return "book"
        case "health": return "heart.text.square"
        case "nature": return "leaf"
        case "feelings": return "face.smiling"
        case "shopping": return "bag"
        case "talk": return "bubble.left.and.bubble.right"
        case "hobbies": return "figure.run"
        case "society": return "building.columns"
        case "idioms": return "scroll"
        default: return "square.grid.2x2"
        }
    }
}

/// One token of an example sentence: text, pinyin, and the HSK word id it links to (0 = none).
struct SentenceToken: Codable, Hashable, Sendable {
    let text: String
    let pinyin: String
    let wordID: Int

    init(from decoder: Decoder) throws {
        var c = try decoder.unkeyedContainer()
        text = try c.decode(String.self)
        pinyin = try c.decode(String.self)
        wordID = try c.decode(Int.self)
    }

    init(text: String, pinyin: String, wordID: Int) {
        self.text = text
        self.pinyin = pinyin
        self.wordID = wordID
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(text)
        try c.encode(pinyin)
        try c.encode(wordID)
    }

    var isHan: Bool { !pinyin.isEmpty }
}

struct Sentence: Codable, Hashable, Identifiable, Sendable {
    let zh: String
    let en: String
    let t: [SentenceToken]
    /// Tatoeba sentence id, used for attribution.
    let src: Int

    var id: Int { src }
    var tokens: [SentenceToken] { t }
    var pinyin: String { t.map(\.pinyin).filter { !$0.isEmpty }.joined(separator: " ") }
}

struct CharInfo: Codable, Hashable, Sendable {
    /// Stroke count.
    let n: Int
    let p: String
    let m: String
    /// Components.
    let c: String?
    /// Radical.
    let r: String?
    /// Etymology type: "i" ideographic, "g" pictographic, "s" sound + meaning.
    let et: String?
    let h: String?
    let se: String?
    let ph: String?

    var etymologyText: String? {
        switch et {
        case "s":
            var parts: [String] = []
            if let se { parts.append("Meaning from \(se)\(h.map { " (\($0))" } ?? "")") }
            if let ph { parts.append("sound from \(ph)") }
            return parts.isEmpty ? nil : parts.joined(separator: ", ") + "."
        case "g":
            return h.map { "Picture: \($0)" } ?? "A picture of the thing it names."
        case "i":
            return h.map { "Idea: \($0)" }
        default:
            return h
        }
    }
}

// MARK: - Learner state

/// Memory state of one word, scheduled with FSRS.
struct CardState: Codable, Hashable, Sendable {
    var stability: Double
    var difficulty: Double
    /// Day number (see `StudyDay`) when the card is next due.
    var due: Int
    /// Day number of the last review.
    var lastReview: Int
    var reps: Int
    var lapses: Int
    /// Day number when the word was first learned.
    var learned: Int
    /// User marked it "I already know this".
    var mastered: Bool = false

    var isKnown: Bool { mastered || stability >= 21 }
}

struct DayLog: Codable, Hashable, Sendable {
    var reviews: Int = 0
    var correct: Int = 0
    var learned: Int = 0
    var seconds: Int = 0
}

struct WordList: Codable, Hashable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var wordIDs: [Int]
    var created: Date = Date()
}

struct UserSettings: Codable, Hashable, Sendable {
    var syllabus: Syllabus = .hsk2026
    var level: Int = 1
    var newPerDay: Int = 5
    var reviewCap: Int = 100
    var topics: [String] = []
    var showPinyinFirst: Bool = false
    var showTraditional: Bool = false
    var toneColors: Bool = true
    var writingPractice: Bool = true
    var listeningQuiz: Bool = true
    var speechRate: Double = 0.42
    var reminderOn: Bool = false
    var reminderHour: Int = 9
    var reminderMinute: Int = 0
    var haptics: Bool = true
    var retention: Double = 0.9
}

struct DailyPlan: Codable, Hashable, Sendable {
    var day: Int
    var newWordIDs: [Int]
}

struct UserState: Codable, Sendable {
    var version: Int = 1
    var onboarded: Bool = false
    var settings = UserSettings()
    var cards: [Int: CardState] = [:]
    var log: [Int: DayLog] = [:]
    var lists: [WordList] = [WordList(name: "Saved", wordIDs: [])]
    var plan: DailyPlan?
    /// Widget "Next" taps shift the rotation by this many places.
    var widgetOffset: Int = 0
    var updated: Date = Date()

    var savedIDs: Set<Int> { Set(lists.first?.wordIDs ?? []) }
}

// MARK: - Helpers

extension CharacterSet {
    static let han: CharacterSet = {
        var s = CharacterSet()
        s.insert(charactersIn: "\u{3400}"..."\u{4DBF}")
        s.insert(charactersIn: "\u{4E00}"..."\u{9FFF}")
        s.insert(charactersIn: "\u{F900}"..."\u{FAFF}")
        return s
    }()
}

/// Study days roll over at 4 a.m. local time, so a late-night session still counts for the same day.
enum StudyDay {
    static let rolloverHour = 4

    static func number(for date: Date = Date(), calendar: Calendar = .current) -> Int {
        let shifted = date.addingTimeInterval(TimeInterval(-rolloverHour * 3600))
        let comps = calendar.dateComponents([.year, .month, .day], from: shifted)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: comps) ?? shifted
        return Int(floor(midnight.timeIntervalSince1970 / 86_400))
    }

    static func date(for day: Int, calendar: Calendar = .current) -> Date {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let d = Date(timeIntervalSince1970: TimeInterval(day) * 86_400)
        let comps = utc.dateComponents([.year, .month, .day], from: d)
        return calendar.date(from: comps) ?? d
    }
}
