import Foundation
import Observation
import SwiftUI
import WidgetKit

/// App-wide state: the learner's progress plus the loaded dictionary.
@Observable
@MainActor
final class AppModel {
    var state: UserState
    var lexiconReady = false
    var loadError: String?
    var today: Int = StudyDay.number()
    /// Set by a widget tap or a link; the root view presents this word.
    var presentedWordID: Int?
    /// Set by a widget tap; the root view switches to this tab.
    var requestedTab: Tab?
    /// A note shown once on Today, e.g. after moving up a level.
    var banner: String?
    /// Debug builds only: a screen opened for automated screenshots.
    var debugScreen: String?

    let lexicon = Lexicon.shared
    private var saveTask: Task<Void, Never>?
    private var widgetReloadPending = false

    init(state: UserState? = nil) {
        self.state = state ?? SharedStore.load()
        Haptics.enabled = self.state.settings.haptics
        Speech.shared.rate = Float(self.state.settings.speechRate)
    }

    // MARK: Loading and saving

    func loadLexicon() async {
        if lexiconReady { return }
        do {
            try await Task.detached(priority: .userInitiated) { try Lexicon.shared.load() }.value
            lexiconReady = true
            #if DEBUG
            if ScreenshotMode.isActive { ScreenshotMode.apply(to: self); return }
            #endif
            ensurePlan()
        } catch {
            loadError = "The word list could not be loaded (\(error)). Reinstalling the app usually fixes this."
        }
    }

    /// Called when the app becomes active: picks up widget changes and a new study day.
    func refresh() {
        #if DEBUG
        if ScreenshotMode.isActive { return }
        #endif
        let disk = SharedStore.load()
        if disk.updated > state.updated { state = disk }
        today = StudyDay.number()
        if lexiconReady { ensurePlan() }
    }

    func save() {
        #if DEBUG
        if ScreenshotMode.isActive { return }
        #endif
        state.updated = Date()
        saveTask?.cancel()
        let snapshot = state
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
            await Task.detached(priority: .utility) { SharedStore.save(snapshot) }.value
            self?.reloadWidgets()
        }
    }

    func saveNow() {
        #if DEBUG
        if ScreenshotMode.isActive { return }
        #endif
        saveTask?.cancel()
        state.updated = Date()
        SharedStore.save(state)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func reloadWidgets() {
        guard !widgetReloadPending else { return }
        widgetReloadPending = true
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            WidgetCenter.shared.reloadAllTimelines()
            self?.widgetReloadPending = false
        }
    }

    var settings: UserSettings {
        get { state.settings }
        set {
            let old = state.settings
            var newValue = newValue
            if !newValue.syllabus.levels.contains(newValue.level) { newValue.level = newValue.syllabus.levels.last ?? 1 }
            state.settings = newValue
            Haptics.enabled = newValue.haptics
            Speech.shared.rate = Float(newValue.speechRate)
            if old.syllabus != newValue.syllabus || old.level != newValue.level || old.topics != newValue.topics
                || old.newPerDay != newValue.newPerDay {
                rebuildTodayPlan()
            }
            save()
            if old.reminderOn != newValue.reminderOn || old.reminderHour != newValue.reminderHour
                || old.reminderMinute != newValue.reminderMinute {
                Task { await rescheduleReminders() }
            }
        }
    }

    // MARK: Daily plan

    /// Words not yet learned at the learner's level, most frequent first.
    func upcomingNewWords(limit: Int, excluding: Set<Int> = []) -> [Word] {
        guard lexiconReady else { return [] }
        let s = state.settings
        var level = s.level
        var out: [Word] = []
        while out.count < limit, level <= (s.syllabus.levels.last ?? 7) {
            let candidates = lexicon.words(level: level, syllabus: s.syllabus, topics: Set(s.topics))
            for w in candidates where state.cards[w.id] == nil && !excluding.contains(w.id) && !out.contains(where: { $0.s == w.s }) {
                out.append(w)
                if out.count >= limit { break }
            }
            level += 1
        }
        // topics filter can run dry; fall back to the whole level
        if out.count < limit && !s.topics.isEmpty {
            for w in lexicon.words(level: s.level, syllabus: s.syllabus) where state.cards[w.id] == nil && !excluding.contains(w.id)
                && !out.contains(where: { $0.id == w.id }) {
                out.append(w)
                if out.count >= limit { break }
            }
        }
        return out
    }

    func ensurePlan() {
        guard lexiconReady else { return }
        today = StudyDay.number()
        if state.plan?.day != today {
            let words = upcomingNewWords(limit: state.settings.newPerDay)
            state.plan = DailyPlan(day: today, newWordIDs: words.map(\.id))
            maybeAdvanceLevel()
            save()
            Task { await rescheduleReminders() }
        }
    }

    /// Keeps words already learned today, refills the rest under the new settings.
    func rebuildTodayPlan() {
        guard lexiconReady else { return }
        let kept = (state.plan?.day == today ? state.plan?.newWordIDs : nil)?.filter { state.cards[$0] != nil } ?? []
        let need = max(0, state.settings.newPerDay - kept.count)
        let fresh = upcomingNewWords(limit: need, excluding: Set(kept))
        state.plan = DailyPlan(day: today, newWordIDs: kept + fresh.map(\.id))
    }

    func addMoreNewWords(_ n: Int) {
        let current = todayPlanIDs
        let more = upcomingNewWords(limit: n, excluding: Set(current))
        state.plan = DailyPlan(day: today, newWordIDs: current + more.map(\.id))
        save()
    }

    private func maybeAdvanceLevel() {
        let s = state.settings
        let levelWords = lexicon.words(level: s.level, syllabus: s.syllabus)
        guard !levelWords.isEmpty else { return }
        let learned = levelWords.filter { state.cards[$0.id] != nil }.count
        if learned == levelWords.count, s.level < (s.syllabus.levels.last ?? 7) {
            state.settings.level += 1
            banner = "You have met every word in \(Syllabus.levelName(s.level)). Moving on to \(Syllabus.levelName(s.level + 1))."
        }
    }

    var todayPlanIDs: [Int] { state.plan?.day == today ? (state.plan?.newWordIDs ?? []) : [] }
    var todayWords: [Word] { todayPlanIDs.compactMap { lexicon.word($0) } }
    var newRemaining: [Word] { todayWords.filter { state.cards[$0.id] == nil } }

    // MARK: Reviews

    var reviewsDoneToday: Int { state.log[today]?.reviews ?? 0 }

    /// Words due now, oldest first, limited by the daily cap.
    var dueWordIDs: [Int] {
        let cap = state.settings.reviewCap
        let reviews = state.dueIDs(today: today)
        if cap <= 0 { return reviews }
        let doneReviews = max(0, reviewsDoneToday - (state.log[today]?.learned ?? 0))
        return Array(reviews.prefix(max(0, cap - doneReviews)))
    }

    var dueCount: Int { dueWordIDs.count }

    func card(_ id: Int) -> CardState? { state.cards[id] }

    var fsrs: FSRS {
        var f = FSRS()
        f.requestRetention = state.settings.retention
        return f
    }

    /// Records an answer. Returns the updated card.
    @discardableResult
    func record(_ wordID: Int, grade: Grade) -> CardState {
        let isNew = state.cards[wordID] == nil
        let card = isNew ? fsrs.first(grade, today: today) : fsrs.review(state.cards[wordID]!, grade, today: today)
        state.cards[wordID] = card
        var log = state.log[today] ?? DayLog()
        log.reviews += 1
        if grade != .again { log.correct += 1 }
        if isNew { log.learned += 1 }
        state.log[today] = log
        save()
        return card
    }

    func addStudyTime(seconds: Int) {
        var log = state.log[today] ?? DayLog()
        log.seconds += seconds
        state.log[today] = log
        save()
    }

    func markKnown(_ wordID: Int) {
        state.markKnown(wordID, today: today, fsrs: fsrs)
        save()
    }

    func forget(_ wordID: Int) {
        state.cards[wordID] = nil
        save()
    }

    func startLearning(_ wordID: Int) {
        if state.cards[wordID] == nil {
            var ids = todayPlanIDs
            if !ids.contains(wordID) { ids.append(wordID) }
            state.plan = DailyPlan(day: today, newWordIDs: ids)
            save()
        }
    }

    // MARK: Saved lists

    func isSaved(_ id: Int) -> Bool { state.lists.first?.wordIDs.contains(id) ?? false }

    func toggleSaved(_ id: Int) {
        if state.lists.isEmpty { state.lists = [WordList(name: "Saved", wordIDs: [])] }
        if let i = state.lists[0].wordIDs.firstIndex(of: id) {
            state.lists[0].wordIDs.remove(at: i)
        } else {
            state.lists[0].wordIDs.insert(id, at: 0)
        }
        save()
    }

    // MARK: Stats

    enum WordStatus { case new, learning, known }

    func status(_ id: Int) -> WordStatus {
        guard let c = state.cards[id] else { return .new }
        return c.isKnown ? .known : .learning
    }

    var streak: Int { state.streak(today: today) }

    var bestStreak: Int {
        let days = state.log.filter { $0.value.reviews + $0.value.learned > 0 }.keys.sorted()
        var best = 0, run = 0, prev = Int.min
        for d in days {
            run = (d == prev + 1) ? run + 1 : 1
            best = max(best, run)
            prev = d
        }
        return best
    }

    var studiedToday: Bool { (state.log[today]?.reviews ?? 0) > 0 }

    func levelProgress(_ level: Int) -> (known: Int, learning: Int, total: Int) {
        let words = lexicon.words(level: level, syllabus: state.settings.syllabus)
        var k = 0, l = 0
        for w in words {
            if let c = state.cards[w.id] { if c.isKnown { k += 1 } else { l += 1 } }
        }
        return (k, l, words.count)
    }

    /// Reviews due on each of the next `days` days (index 0 = today, including overdue).
    /// Later days only count words already scheduled, so they are a lower bound.
    func forecast(days: Int = 14) -> [Int] {
        var out = Array(repeating: 0, count: days)
        for c in state.cards.values where !c.mastered {
            let i = max(0, c.due - today)
            if i < days { out[i] += 1 }
        }
        return out
    }

    var retention30: Double? {
        var r = 0, ok = 0
        for d in (today - 29)...today { if let l = state.log[d] { r += l.reviews; ok += l.correct } }
        return r > 0 ? Double(ok) / Double(r) : nil
    }

    // MARK: Reminders

    func rescheduleReminders() async {
        let s = state.settings
        guard s.reminderOn, lexiconReady else { Reminders.cancelAll(); return }
        let upcoming = upcomingNewWords(limit: s.newPerDay * 14, excluding: Set(todayPlanIDs))
        let ahead = forecast(days: 14)
        var lines: [(String, String)] = []
        for day in 0..<14 {
            let w: Word? = day == 0 ? (newRemaining.first ?? todayWords.first) : upcoming.dropFirst((day - 1) * s.newPerDay).first
            let due = day == 0 ? dueCount : ahead[day]
            let reviewsText = due > 0 ? "\(due) review\(due == 1 ? "" : "s") waiting." : "A few minutes keeps your streak going."
            if let w {
                lines.append(("\(w.s)  \(Pinyin.joined(w.p))", "\(w.meaning). \(reviewsText)"))
            } else {
                lines.append(("Time for Chinese", reviewsText))
            }
        }
        await Reminders.schedule(hour: s.reminderHour, minute: s.reminderMinute, lines: lines)
    }

    // MARK: Reset / export

    func resetProgress() {
        let keepSettings = state.settings
        state = UserState()
        state.settings = keepSettings
        state.onboarded = true
        ensurePlan()
        rebuildTodayPlan()
        saveNow()
    }

    func exportData() -> Data {
        (try? JSONEncoder.inkstone.encode(state)) ?? Data()
    }

    func importData(_ data: Data) -> Bool {
        guard let s = try? JSONDecoder.inkstone.decode(UserState.self, from: data) else { return false }
        state = s
        ensurePlan()
        saveNow()
        return true
    }
}
