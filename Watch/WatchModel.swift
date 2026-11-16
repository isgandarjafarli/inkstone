import Foundation
import Observation
import WatchKit
import WidgetKit
import AVFoundation

/// The watch app's state: the word lists from the iPhone, the watch's own settings, and what
/// was done on the watch today.
@Observable
@MainActor
final class WatchModel {
    var feed: WatchFeed?
    var prefs: WatchPrefs
    var today: Int = StudyDay.number()
    /// Words for the carousel and the watch face, in today's order.
    var pool: [WidgetWord] = []
    /// Reviews still to do on the watch today.
    var reviews: [WidgetWord] = []
    /// Words reviewed or marked known on the watch today.
    var done: Set<Int> = []
    /// Set by a complication tap: the carousel opens at this word.
    var openWordID: Int?
    var openReview = false
    /// Debug builds only: a screen opened for automated screenshots.
    var debugScreen: String?
    /// False until the word lists have been read for the first time.
    var loaded = false

    let strokes = StrokePack.bundled()
    private let speech = AVSpeechSynthesizer()

    init() {
        prefs = WatchStore.loadPrefs()
        feed = WatchStore.loadFeed()
        done = WatchStore.loadDone(day: today)
    }

    var dueCount: Int { reviews.count }
    var hasPhoneData: Bool { feed != nil }

    /// The word the watch face shows right now.
    var currentIndex: Int {
        guard !pool.isEmpty else { return 0 }
        return WidgetFeed.slotIndex(at: Date(), intervalMinutes: max(prefs.interval, 5), offset: prefs.offset, count: pool.count)
    }

    func reload() {
        #if DEBUG
        if WatchScreenshots.isActive { return }
        #endif
        let day = StudyDay.number()
        if day != today {
            today = day
            done = WatchStore.loadDone(day: day)
        }
        // Reading the word file takes a moment on the watch: do it off the main thread.
        let (feed, prefs, today, done) = (feed, prefs, today, done)
        Task.detached(priority: .userInitiated) {
            let pool = WatchWords.pool(feed: feed, prefs: prefs, today: today, done: done)
            let reviews = WatchWords.reviews(feed: feed, today: today, done: done)
            await MainActor.run {
                self.pool = pool
                self.reviews = reviews.filter { !self.done.contains($0.id) }
                self.loaded = true
            }
        }
    }

    func received(_ newFeed: WatchFeed) {
        feed = newFeed
        WatchStore.saveFeed(newFeed)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    func update(_ change: (inout WatchPrefs) -> Void) {
        change(&prefs)
        WatchStore.savePrefs(prefs)
        reload()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Shows the next word on the watch face.
    func nextOnWatchFace() {
        update { $0.offset += 1 }
    }

    func markKnown(_ word: WidgetWord) {
        WatchSync.shared.send(known: [word.id])
        finish(word.id)
        WKInterfaceDevice.current().play(.success)
    }

    func review(_ word: WidgetWord, remembered: Bool) {
        let grade = remembered ? Grade.good : Grade.again
        WatchSync.shared.send(reviews: [[word.id, grade.rawValue, today]])
        finish(word.id)
        WKInterfaceDevice.current().play(remembered ? .success : .retry)
    }

    private func finish(_ id: Int) {
        done.insert(id)
        WatchStore.saveDone(done, day: today)
        reviews.removeAll { $0.id == id }
        WidgetCenter.shared.reloadAllTimelines()
    }

    func speak(_ text: String) {
        speech.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: text)
        u.voice = AVSpeechSynthesisVoice(language: "zh-CN")
        u.rate = 0.42
        speech.speak(u)
    }

    /// Characters to practise writing: those of the watch face's words, starting with the one
    /// showing now, each once, and only those with stroke data.
    var writingItems: [WritingItem] {
        var seen = Set<String>()
        var out: [WritingItem] = []
        guard !pool.isEmpty else { return out }
        let start = min(currentIndex, pool.count - 1)
        for w in Array(pool[start...]) + Array(pool[..<start]) {
            for c in w.hanzi.map(String.init) where seen.insert(c).inserted && (strokes?.has(c) ?? false) {
                out.append(WritingItem(id: out.count, char: c, word: w))
            }
        }
        return out
    }
}

struct WritingItem: Identifiable, Hashable {
    let id: Int
    let char: String
    let word: WidgetWord
}
