import Foundation

/// Progress rules shared by the app and the widgets, so both count the same way.
extension UserState {
    /// Words due for review today, oldest first (no daily cap).
    func dueIDs(today: Int) -> [Int] {
        cards.filter { $0.value.due <= today && !$0.value.mastered }
            .sorted { ($0.value.due, $0.value.stability) < ($1.value.due, $1.value.stability) }
            .map(\.key)
    }

    /// Consecutive study days ending today (or yesterday, if today has no activity yet).
    func streak(today: Int) -> Int {
        var d = today
        if (log[d]?.reviews ?? 0) + (log[d]?.learned ?? 0) == 0 { d -= 1 }
        var n = 0
        while let l = log[d], l.reviews + l.learned > 0 { n += 1; d -= 1 }
        return n
    }

    /// New words planned for today that have not been learned yet.
    func newRemaining(today: Int) -> Int {
        guard let plan, plan.day == today else { return settings.newPerDay }
        return plan.newWordIDs.filter { cards[$0] == nil }.count
    }

    /// Marks a word as already known: it leaves the review queue for months.
    mutating func markKnown(_ wordID: Int, today: Int, fsrs: FSRS = FSRS()) {
        let wasNew = cards[wordID] == nil
        var c = cards[wordID] ?? fsrs.first(.easy, today: today)
        c.mastered = true
        c.stability = max(c.stability, 120)
        c.due = today + 120
        c.lastReview = today
        cards[wordID] = c
        if wasNew {
            var l = log[today] ?? DayLog()
            l.learned += 1
            log[today] = l
        }
        updated = Date()
    }
}
