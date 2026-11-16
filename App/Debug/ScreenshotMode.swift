#if DEBUG
import SwiftUI
import WidgetKit

/// Automated screenshots (debug builds only). Launch with `-screenshot <name>` to open one screen
/// filled with believable demo progress. Nothing is written to the real progress file.
enum ScreenshotMode {
    static var name: String? { UserDefaults.standard.string(forKey: "screenshot") }
    static var isActive: Bool { name != nil }

    /// Onboarding step to open, for names like "onboarding-2".
    static var onboardingStep: Int? {
        guard let name, name.hasPrefix("onboarding") else { return nil }
        return Int(name.split(separator: "-").last ?? "") ?? 0
    }

    @MainActor
    static func apply(to model: AppModel) {
        guard let name else { return }
        model.state = demoState(model: model, onboarded: !name.hasPrefix("onboarding"))
        switch name {
        case "today": model.requestedTab = .today
        case "review": model.requestedTab = .review
        case "words": model.requestedTab = .library
        case "progress": model.requestedTab = .progress
        case "word": model.presentedWordID = model.lexicon.word(hanzi: "朋友")?.id
        case "word-long": model.presentedWordID = model.lexicon.word(hanzi: "图书馆")?.id
        default:
            if !name.hasPrefix("onboarding") { model.debugScreen = name }
        }
    }

    @MainActor
    static func demoState(model: AppModel, onboarded: Bool) -> UserState {
        let lex = model.lexicon
        let today = model.today
        var s = UserState()
        s.onboarded = onboarded
        s.settings.level = 2
        s.settings.newPerDay = 5
        let fsrs = FSRS()
        var rng = SplitMix64(seed: 42)

        // Most of HSK 1 learned over the last six weeks; some known well, some still shaky, a few due today.
        let l1 = lex.words(level: 1, syllabus: .hsk2026)
        for (i, w) in l1.prefix(240).enumerated() {
            var c = fsrs.first(.good, today: today - 42 + i / 6)
            let r = Int(rng.next() % 100)
            c.reps = 2 + r % 6
            c.lastReview = today - 1 - r % 9
            if r < 45 {
                c.stability = 25 + Double(r)
                c.due = today + 5 + r % 30
            } else if r < 88 {
                c.stability = 3 + Double(r % 10)
                c.due = today + 1 + r % 9
            } else {
                c.stability = 2
                c.due = today - r % 3
            }
            s.cards[w.id] = c
        }
        // Today's plan at HSK 2: five new words, two already learned.
        let l2 = lex.words(level: 2, syllabus: .hsk2026).filter { s.cards[$0.id] == nil }
        let plan = Array(l2.prefix(5))
        s.plan = DailyPlan(day: today, newWordIDs: plan.map(\.id))
        for w in plan.prefix(2) { s.cards[w.id] = fsrs.first(.good, today: today) }

        // A 12-day streak, with an older patchy history.
        for d in 0..<140 {
            let day = today - d
            let active = d < 12 || (d > 12 && rng.next() % 3 != 0)
            guard active else { continue }
            let reviews = 8 + Int(rng.next() % 38)
            s.log[day] = DayLog(reviews: reviews, correct: reviews * 85 / 100, learned: 5, seconds: 300 + reviews * 12)
        }
        s.log[today] = DayLog(reviews: 14, correct: 12, learned: 2, seconds: 380)

        let saved = ["朋友", "喜欢", "图书馆", "一路平安", "漂亮", "咖啡"].compactMap { lex.word(hanzi: $0)?.id }
        s.lists = [WordList(name: "Saved", wordIDs: saved)]
        return s
    }
}

struct DebugRoute: Identifiable { let id: String }

/// Screens that the tab bar cannot reach directly.
struct DebugScreenView: View {
    @Environment(AppModel.self) private var model
    let name: String

    var body: some View {
        switch name {
        case "char":
            NavigationStack { CharacterDetailView(char: "朋").inkDestinations() }
        case "settings":
            SettingsView()
        case "widgets-lock":
            WidgetGallery(page: .lock)
        case "widgets-home":
            WidgetGallery(page: .home)
        case "widgets-large":
            WidgetGallery(page: .large)
        case let n where n.hasPrefix("session-"):
            SessionView(session: debugSession(kind: String(n.dropFirst("session-".count))))
        default:
            Text("Unknown screenshot: \(name)")
        }
    }

    private func debugSession(kind: String) -> StudySession {
        let word = model.lexicon.word(hanzi: kind == "writing" ? "朋友" : "喜欢") ?? model.lexicon.words[0]
        let k: QuizKind = switch kind {
        case "learn": .learn
        case "meaning": .meaningChoice
        case "word": .wordChoice
        case "listening": .listening
        case "tones": .tones
        case "writing": .writing
        default: .recall
        }
        return StudySession(debugItems: [SessionItem(wordID: word.id, kind: k, isNew: k == .learn, isRetry: false)])
    }
}

/// The widgets drawn inside the app at their real sizes (iPhone 16 Pro), for screenshots.
struct WidgetGallery: View {
    enum Page { case lock, home, large }
    let page: Page
    @State private var words: [String: WidgetWord] = [:]

    private func entry(_ hanzi: String) -> WordEntry {
        let w = words[hanzi] ?? .placeholder
        let lv = w.levels["h26"] ?? w.levels.values.min() ?? 1
        return WordEntry(date: Date(), word: w, level: Syllabus.levelName(lv), showPinyin: true, showMeaning: true,
                         toneColors: true, due: 14, newLeft: 3, streak: 12)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                switch page {
                case .lock:
                    lockScreen
                    standBy
                case .home:
                    homeSmall
                    home(.systemMedium, "朋友", height: 170)
                case .large:
                    home(.systemLarge, "图书馆", height: 382)
                }
            }
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
        }
        .background(LinearGradient(colors: [Color(light: 0xB9C7D6, dark: 0x1C2633), Color(light: 0xE6D7C8, dark: 0x2E2620)],
                                   startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .task {
            let all = WidgetFeed.loadWords()
            var map: [String: WidgetWord] = [:]
            for w in all where ["朋友", "好", "图书馆", "一路平安", "喜欢"].contains(w.hanzi) && map[w.hanzi] == nil { map[w.hanzi] = w }
            words = map
        }
    }

    private var lockScreen: some View {
        VStack(spacing: 8) {
            WordWidgetView(entry: entry("朋友"), familyOverride: .accessoryInline)
                .font(.system(size: 15, weight: .semibold))
            Text("9:41").font(.system(size: 92, weight: .semibold, design: .rounded))
            HStack(spacing: 12) {
                WordWidgetView(entry: entry("朋友"), familyOverride: .accessoryRectangular).frame(width: 172, height: 76)
                WordWidgetView(entry: entry("好"), familyOverride: .accessoryCircular).frame(width: 76, height: 76)
                TodayWidgetView(entry: TodayEntry(date: Date(), due: 14, newLeft: 3, newPlanned: 5, streak: 12, studiedToday: true),
                                familyOverride: .accessoryCircular).frame(width: 76, height: 76)
            }
            HStack(spacing: 12) {
                WordWidgetView(entry: entry("一路平安"), familyOverride: .accessoryRectangular).frame(width: 172, height: 76)
                TodayWidgetView(entry: TodayEntry(date: Date(), due: 14, newLeft: 3, newPlanned: 5, streak: 12, studiedToday: true),
                                familyOverride: .accessoryRectangular).frame(width: 172, height: 76)
            }
        }
        .foregroundStyle(.white)
        .padding(.vertical, 24).padding(.horizontal, 10)
        .frame(maxWidth: 393)
        .background(LinearGradient(colors: [Color(light: 0x2B3A4A, dark: 0x2B3A4A), Color(light: 0x13181D, dark: 0x13181D)],
                                   startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 36, style: .continuous))
        .environment(\.colorScheme, .dark)
        .padding(.horizontal, 12)
    }

    private var standBy: some View {
        HStack(spacing: 16) {
            WordWidgetView(entry: entry("朋友"), familyOverride: .systemSmall, forceStandBy: true)
                .frame(width: 170, height: 170)
            WordWidgetView(entry: entry("好"), familyOverride: .systemSmall, forceStandBy: true)
                .frame(width: 170, height: 170)
        }
        .foregroundStyle(.white)
        .padding(16)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .environment(\.colorScheme, .dark)
    }

    private var homeSmall: some View {
        HStack(spacing: 22) {
            tile(WordWidgetView(entry: entry("好"), familyOverride: .systemSmall), width: 170, height: 170)
            tile(WordWidgetView(entry: entry("一路平安"), familyOverride: .systemSmall), width: 170, height: 170)
        }
    }

    private func home(_ family: WidgetFamily, _ hanzi: String, height: CGFloat) -> some View {
        tile(WordWidgetView(entry: entry(hanzi), familyOverride: family), width: 364, height: height)
    }

    private func tile(_ content: some View, width: CGFloat, height: CGFloat) -> some View {
        content
            .padding(16)
            .frame(width: width, height: height)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
    }
}
#endif
