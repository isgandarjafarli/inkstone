import SwiftUI
import WidgetKit

struct WatchWordProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchWordEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (WatchWordEntry) -> Void) {
        completion(makeEntries(limit: 1).entries.first ?? .preview)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchWordEntry>) -> Void) {
        let (entries, end) = makeEntries(limit: 144)
        completion(Timeline(entries: entries.isEmpty ? [.preview] : entries, policy: .after(end)))
    }

    /// One entry per rotation slot from now until the study day ends (or 144 slots).
    private func makeEntries(limit: Int) -> (entries: [WatchWordEntry], end: Date) {
        let now = Date()
        let today = StudyDay.number(for: now)
        let nextDay = StudyDay.date(for: today + 1).addingTimeInterval(TimeInterval(StudyDay.rolloverHour * 3600))
        let feed = WatchStore.loadFeed()
        let prefs = WatchStore.loadPrefs()
        let pool = WatchWords.pool(feed: feed, prefs: prefs, today: today, done: WatchStore.loadDone(day: today))
        let minutes = max(prefs.interval, 5)

        func entry(_ date: Date, _ w: WidgetWord) -> WatchWordEntry {
            WatchWordEntry(date: date, word: w, showPinyin: prefs.showPinyin, showMeaning: prefs.showMeaning,
                           toneColors: feed?.toneColors ?? true, toneHanzi: feed?.toneHanzi ?? true)
        }

        var entries: [WatchWordEntry] = []
        var t = now
        while t < nextDay && entries.count < limit {
            if let w = WidgetFeed.word(at: t, pool: pool, intervalMinutes: minutes, offset: prefs.offset) {
                entries.append(entry(t, w))
            }
            t = WidgetFeed.slotStart(t, intervalMinutes: minutes).addingTimeInterval(TimeInterval(minutes * 60))
        }
        return (entries, min(nextDay, t))
    }
}

struct WatchWordWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InkstoneWatchWord", provider: WatchWordProvider()) { entry in
            WatchWordView(entry: entry)
        }
        .configurationDisplayName("Word")
        .description("A new word every few minutes. Choose how often in the Inkstone watch app.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct WatchTodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchTodayEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (WatchTodayEntry) -> Void) {
        completion(current().0)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchTodayEntry>) -> Void) {
        let (e, end) = current()
        completion(Timeline(entries: [e], policy: .after(end)))
    }

    private func current() -> (WatchTodayEntry, Date) {
        let now = Date()
        let today = StudyDay.number(for: now)
        let nextDay = StudyDay.date(for: today + 1).addingTimeInterval(TimeInterval(StudyDay.rolloverHour * 3600))
        let feed = WatchStore.loadFeed()
        let done = WatchStore.loadDone(day: today)
        let current = feed?.day == today
        let e = WatchTodayEntry(date: now, due: WatchWords.dueCount(feed: feed, today: today, done: done),
                                newLeft: current ? (feed?.newLeft ?? 0) : 0, streak: feed?.streak ?? 0)
        return (e, nextDay)
    }
}

struct WatchTodayWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "InkstoneWatchToday", provider: WatchTodayProvider()) { entry in
            WatchTodayView(entry: entry)
        }
        .configurationDisplayName("Reviews due")
        .description("How many words are waiting for review today.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryCorner, .accessoryInline])
    }
}

@main
struct InkstoneWatchWidgets: WidgetBundle {
    init() { FontRegistry.ensure() }

    var body: some Widget {
        WatchWordWidget()
        WatchTodayWidget()
    }
}
