import Foundation

/// What the iPhone tells the watch: level, word lists and today's numbers. Word details are not
/// sent; the watch has its own copy of the word list and looks the ids up there.
struct WatchFeed: Codable, Equatable, Sendable {
    var day: Int
    var syllabus: String
    var level: Int
    var toneColors: Bool
    var toneHanzi: Bool
    /// Today's new words.
    var todayIDs: [Int]
    /// Words being learned, soonest due first.
    var learningIDs: [Int]
    var savedIDs: [Int]
    /// Reviews due today (capped by the daily review limit).
    var dueIDs: [Int]
    /// The next words at the learner's level that they have not started.
    var upcomingIDs: [Int]
    var newLeft: Int
    var streak: Int

    init(state: UserState, today: Int, upcomingIDs: [Int]) {
        let s = state.settings
        day = today
        syllabus = s.syllabus.rawValue
        level = s.level
        toneColors = s.toneColors
        toneHanzi = s.toneHanzi
        todayIDs = state.plan?.day == today ? (state.plan?.newWordIDs ?? []) : []
        learningIDs = state.cards.filter { !$0.value.isKnown }
            .sorted { ($0.value.due, $0.key) < ($1.value.due, $1.key) }
            .prefix(60).map(\.key)
        savedIDs = Array((state.lists.first?.wordIDs ?? []).prefix(200))
        let due = state.dueIDs(today: today)
        let cap = s.reviewCap > 0 ? min(s.reviewCap, 150) : 150
        dueIDs = Array(due.prefix(cap))
        self.upcomingIDs = Array(upcomingIDs.prefix(40))
        newLeft = state.newRemaining(today: today)
        streak = state.streak(today: today)
    }

    /// Every word id the watch needs to look up.
    var allIDs: Set<Int> {
        Set(todayIDs).union(learningIDs).union(savedIDs).union(dueIDs).union(upcomingIDs)
    }
}

/// Keys of the messages the watch sends back to the iPhone.
enum WatchMessage {
    /// [Int]: words the learner marked "I know it" on the watch.
    static let known = "known"
    /// [[Int]]: reviews done on the watch, as [word id, grade raw value, study day].
    static let reviews = "reviews"
    /// Application-context key for the encoded `WatchFeed`.
    static let feed = "feed"
}
