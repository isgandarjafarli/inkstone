import SwiftUI
import WidgetKit

/// Words are parsed once per widget process; the file is small and read-only.
enum WidgetData {
    private static var cached: [WidgetWord]?
    private static let lock = NSLock()

    static var words: [WidgetWord] {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let w = WidgetFeed.loadWords()
        cached = w
        return w
    }
}

struct WordProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> WordEntry { .preview }

    func snapshot(for configuration: WordWidgetIntent, in context: Context) async -> WordEntry {
        if context.isPreview && !SharedStore.load().onboarded { return .preview }
        return makeEntries(configuration, now: Date(), limit: 1).entries.first ?? .preview
    }

    func timeline(for configuration: WordWidgetIntent, in context: Context) async -> Timeline<WordEntry> {
        let (entries, end) = makeEntries(configuration, now: Date(), limit: 72)
        return Timeline(entries: entries.isEmpty ? [.preview] : entries, policy: .after(end))
    }

    /// Builds entries from now until the next study day starts (when the word pool changes).
    private func makeEntries(_ config: WordWidgetIntent, now: Date, limit: Int) -> (entries: [WordEntry], end: Date) {
        let state = SharedStore.load()
        let today = StudyDay.number(for: now)
        let nextDay = StudyDay.date(for: today + 1).addingTimeInterval(TimeInterval(StudyDay.rolloverHour * 3600))
        let words = WidgetData.words
        let pool = WidgetFeed.pool(source: config.source.source, state: state, words: words, today: today)
        guard !pool.isEmpty else { return ([], nextDay) }

        let key = state.settings.syllabus.rawValue
        let due = state.dueIDs(today: today).count
        let cap = state.settings.reviewCap
        let shownDue = cap > 0 ? min(due, cap) : due
        let newLeft = state.newRemaining(today: today)
        let streak = state.streak(today: today)

        func entry(_ date: Date, _ w: WidgetWord) -> WordEntry {
            let lv = w.levels[key] ?? w.levels.values.min()
            return WordEntry(date: date, word: w, level: lv.map(Syllabus.levelName) ?? "",
                             showPinyin: config.showPinyin, showMeaning: config.showMeaning,
                             toneColors: state.settings.toneColors, due: shownDue, newLeft: newLeft, streak: streak)
        }

        let minutes = config.rotation.minutes
        if minutes >= 1440 {
            let i = ((today + state.widgetOffset) % pool.count + pool.count) % pool.count
            return ([entry(now, pool[i])], nextDay)
        }

        var entries: [WordEntry] = []
        var t = now
        while t < nextDay && entries.count < limit {
            if let w = WidgetFeed.word(at: t, pool: pool, intervalMinutes: minutes, offset: state.widgetOffset) {
                entries.append(entry(t, w))
            }
            t = WidgetFeed.slotStart(t, intervalMinutes: minutes).addingTimeInterval(TimeInterval(minutes * 60))
        }
        let end = min(nextDay, t)
        return (entries, end)
    }
}

struct WordWidget: Widget {
    let kind = "InkstoneWord"

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: WordWidgetIntent.self, provider: WordProvider()) { entry in
            WordWidgetView(entry: entry)
        }
        .configurationDisplayName("Word")
        .description("A new Chinese word on your lock screen or home screen, with pinyin and meaning.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline, .accessoryCircular,
                            .systemSmall, .systemMedium, .systemLarge])
    }
}

// MARK: - Today widget (progress at a glance)

struct TodayProvider: TimelineProvider {
    func placeholder(in context: Context) -> TodayEntry { .preview }

    func getSnapshot(in context: Context, completion: @escaping (TodayEntry) -> Void) {
        completion(context.isPreview && !SharedStore.load().onboarded ? .preview : current().0)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TodayEntry>) -> Void) {
        let (e, end) = current()
        completion(Timeline(entries: [e], policy: .after(end)))
    }

    private func current() -> (TodayEntry, Date) {
        let state = SharedStore.load()
        let now = Date()
        let today = StudyDay.number(for: now)
        let nextDay = StudyDay.date(for: today + 1).addingTimeInterval(TimeInterval(StudyDay.rolloverHour * 3600))
        let due = state.dueIDs(today: today).count
        let cap = state.settings.reviewCap
        let planned = (state.plan?.day == today ? state.plan?.newWordIDs.count : nil) ?? state.settings.newPerDay
        let log = state.log[today]
        let e = TodayEntry(date: now, due: cap > 0 ? min(due, cap) : due, newLeft: state.newRemaining(today: today),
                           newPlanned: planned, streak: state.streak(today: today),
                           studiedToday: (log?.reviews ?? 0) + (log?.learned ?? 0) > 0)
        return (e, nextDay)
    }
}

struct TodayWidget: Widget {
    let kind = "InkstoneToday"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: TodayProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName("Today's study")
        .description("Reviews due, new words left and your streak.")
        .supportedFamilies([.accessoryCircular, .accessoryInline, .accessoryRectangular, .systemSmall])
    }
}

@main
struct InkstoneWidgetBundle: WidgetBundle {
    init() { FontRegistry.ensure() }

    var body: some Widget {
        WordWidget()
        TodayWidget()
    }
}
