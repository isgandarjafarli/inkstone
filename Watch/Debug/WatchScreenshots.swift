#if DEBUG
import SwiftUI
import WidgetKit

/// Automated screenshots of the watch app (debug builds only). Launch with `-screenshot <name>`.
enum WatchScreenshots {
    static var name: String? { UserDefaults.standard.string(forKey: "screenshot") }
    static var isActive: Bool { name != nil }

    @MainActor
    static func apply(to model: WatchModel) {
        guard let name else { return }
        let words = WatchWords.load(ids: [], level: ("h26", 1), levelLimit: 300).level
        func pick(_ hanzi: [String]) -> [WidgetWord] { hanzi.compactMap { h in words.first { $0.hanzi == h } } }
        let featured = pick(["朋友", "喜欢", "好", "漂亮", "睡觉", "衣服", "学习", "今天"])
        model.pool = featured + words.filter { w in !featured.contains(where: { $0.id == w.id }) }.prefix(30)
        model.reviews = Array(pick(["喜欢", "朋友", "漂亮"]) + words.prefix(11))
        model.loaded = true
        // Pretend the iPhone has sent its data, so the screens show their normal state.
        model.feed = WatchFeed(state: UserState(), today: model.today, upcomingIDs: [])
        model.prefs.offset = -WidgetFeed.slotIndex(at: Date(), intervalMinutes: max(model.prefs.interval, 5), offset: 0,
                                                    count: max(model.pool.count, 1))
        if name != "watch-home" { model.debugScreen = name }
    }
}

struct WatchDebugScreen: View {
    @Environment(WatchModel.self) private var model
    let name: String

    var body: some View {
        switch name {
        case "watch-carousel":
            NavigationStack { CarouselView(startID: model.pool.first?.id) }
        case "watch-review":
            NavigationStack { ReviewView() }
        case "watch-write":
            WriteView(initialDone: 5)
        case "watch-settings":
            NavigationStack { WatchSettingsView() }
        case "watch-face":
            WatchFaceGallery(word: model.pool.first ?? .placeholder, second: model.pool.dropFirst(2).first ?? .placeholder)
        default:
            Text("Unknown screenshot: \(name)")
        }
    }
}

/// The complications drawn the way a watch face would show them, for screenshots.
struct WatchFaceGallery: View {
    let word: WidgetWord
    let second: WidgetWord

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .top) {
                WatchWordView(entry: WatchWordEntry(date: Date(), word: second), familyOverride: .accessoryCircular)
                    .frame(width: 46, height: 46)
                Spacer()
                Text("10:09")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            WatchWordView(entry: WatchWordEntry(date: Date(), word: word), familyOverride: .accessoryRectangular)
                .frame(height: 58)
            HStack {
                WatchTodayView(entry: WatchTodayEntry(date: Date(), due: 14, newLeft: 3, streak: 12), familyOverride: .accessoryCircular)
                    .frame(width: 46, height: 46)
                Spacer()
                WatchWordView(entry: WatchWordEntry(date: Date(), word: WidgetWord.placeholder), familyOverride: .accessoryInline)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}
#endif
