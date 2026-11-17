import Foundation
import Observation

enum QuizKind: String, Codable, Sendable {
    /// First meeting with a new word: everything shown, no answer needed.
    case learn
    /// See the word, pick its meaning from four.
    case meaningChoice
    /// See the meaning, pick the word from four.
    case wordChoice
    /// Hear the word, pick it from four.
    case listening
    /// See the word, pick the right tones.
    case tones
    /// See the word, recall it, then grade yourself.
    case recall
    /// See the meaning and pinyin, write the characters stroke by stroke.
    case writing

    var title: String {
        switch self {
        case .learn: return "New word"
        case .meaningChoice: return "What does it mean?"
        case .wordChoice: return "Which word is it?"
        case .listening: return "What did you hear?"
        case .tones: return "Which tones?"
        case .recall: return "Do you remember?"
        case .writing: return "Write it"
        }
    }

    var isAutoGraded: Bool { self != .recall && self != .learn }
}

struct SessionItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let wordID: Int
    let kind: QuizKind
    /// True for a word that is being learned in this session.
    let isNew: Bool
    /// True for a repeat after a mistake in this session.
    let isRetry: Bool
}

struct SessionResult: Sendable {
    var answered = 0
    var firstTryCorrect = 0
    var learned: [Int] = []
    var reviewed: [Int] = []
    var missed: [Int] = []
}

/// One study session: today's due reviews plus new words, with mistakes coming back before the end.
@Observable
@MainActor
final class StudySession {
    private(set) var queue: [SessionItem] = []
    private(set) var position = 0
    private(set) var result = SessionResult()
    private(set) var finished = false
    let started = Date()
    private var attempted = Set<Int>()

    var current: SessionItem? { position < queue.count ? queue[position] : nil }
    var total: Int { queue.count }
    var progress: Double { queue.isEmpty ? 1 : Double(position) / Double(queue.count) }

    init(newWords: [Word], dueIDs: [Int], model: AppModel) {
        let s = model.state.settings
        var reviews: [SessionItem] = dueIDs.map { id in
            SessionItem(wordID: id, kind: Self.reviewKind(for: id, model: model), isNew: false, isRetry: false)
        }
        reviews.shuffle()
        var items: [SessionItem] = []
        // Interleave: learn a new word, do two reviews, quiz the new word a little later.
        var pendingQuizzes: [(SessionItem, Int)] = []
        var r = reviews.makeIterator()
        for w in newWords {
            items.append(SessionItem(wordID: w.id, kind: .learn, isNew: true, isRetry: false))
            for _ in 0..<2 { if let next = r.next() { items.append(next) } }
            pendingQuizzes.append((SessionItem(wordID: w.id, kind: .meaningChoice, isNew: true, isRetry: false), items.count + 2))
            // release quizzes whose slot has come
            pendingQuizzes.removeAll { pq in
                if pq.1 <= items.count { items.append(pq.0); return true }
                return false
            }
        }
        while let next = r.next() { items.append(next) }
        items.append(contentsOf: pendingQuizzes.map(\.0))
        // A second, harder check for new words at the end: pick the word from its meaning.
        for w in newWords {
            let kind: QuizKind = s.listeningQuiz ? .listening : .wordChoice
            items.append(SessionItem(wordID: w.id, kind: Bool.random() ? kind : .wordChoice, isNew: true, isRetry: false))
        }
        queue = items
    }

    #if DEBUG
    /// A session with exactly these items (for screenshots).
    init(debugItems: [SessionItem]) {
        queue = debugItems
    }
    #endif

    static func reviewKind(for id: Int, model: AppModel) -> QuizKind {
        guard let card = model.card(id), let word = model.lexicon.word(id) else { return .recall }
        let s = model.state.settings
        if s.writingPractice && word.characters.count <= 2 && word.characters.count == word.s.count
            && card.reps >= 3 && card.reps % 3 == 0 {
            return .writing
        }
        if card.stability < 2 { return Bool.random() ? .meaningChoice : .wordChoice }
        if card.stability < 6 {
            let options: [QuizKind] = s.listeningQuiz ? [.wordChoice, .listening, .recall, .tones] : [.wordChoice, .recall, .tones]
            return options.randomElement()!
        }
        let options: [QuizKind] = s.listeningQuiz ? [.recall, .recall, .listening, .tones] : [.recall, .recall, .tones]
        return options.randomElement()!
    }

    /// Learn card dismissed.
    func acknowledgeLearn() {
        advance()
    }

    /// Records an answer for the current item and moves on.
    func answer(_ grade: Grade, model: AppModel) {
        guard let item = current else { return }
        let firstAttempt = attempted.insert(item.wordID).inserted
        // A new word's first graded answer creates its card; later answers in the same session
        // are same-day repeats, which FSRS treats gently.
        model.record(item.wordID, grade: grade)
        result.answered += 1
        if firstAttempt && grade != .again { result.firstTryCorrect += 1 }
        if item.isNew {
            if !result.learned.contains(item.wordID) { result.learned.append(item.wordID) }
        } else if !result.reviewed.contains(item.wordID) {
            result.reviewed.append(item.wordID)
        }
        if grade == .again {
            if !result.missed.contains(item.wordID) { result.missed.append(item.wordID) }
            // bring it back 3 to 5 items later as a recall-style check
            let retryKind: QuizKind = item.kind == .writing ? .writing : (item.kind == .recall ? .wordChoice : .recall)
            let retry = SessionItem(wordID: item.wordID, kind: retryKind, isNew: item.isNew, isRetry: true)
            let insertAt = min(queue.count, position + 1 + Int.random(in: 3...5))
            queue.insert(retry, at: insertAt)
        }
        advance()
    }

    func skip() { advance() }

    private func advance() {
        position += 1
        if position >= queue.count { finished = true }
    }

    func end() { finished = true }
}
