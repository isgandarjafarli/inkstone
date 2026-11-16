import Foundation
import WidgetKit

/// What one word widget shows at one moment.
struct WordEntry: TimelineEntry {
    let date: Date
    let word: WidgetWord
    let level: String
    let showPinyin: Bool
    let showMeaning: Bool
    let toneColors: Bool
    let due: Int
    let newLeft: Int
    let streak: Int

    var url: URL { URL(string: "inkstone://word/\(word.id)")! }

    static let preview = WordEntry(date: Date(), word: .placeholder, level: "HSK 1", showPinyin: true,
                                   showMeaning: true, toneColors: true, due: 12, newLeft: 5, streak: 4)
}

/// What the Today widget shows.
struct TodayEntry: TimelineEntry {
    let date: Date
    let due: Int
    let newLeft: Int
    let newPlanned: Int
    let streak: Int
    let studiedToday: Bool

    static let preview = TodayEntry(date: Date(), due: 12, newLeft: 3, newPlanned: 5, streak: 4, studiedToday: false)
}
