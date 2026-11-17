import AppIntents
import WidgetKit

enum WordSourceOption: String, AppEnum {
    case smart, today, learning, level, saved

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Words"
    static var caseDisplayRepresentations: [WordSourceOption: DisplayRepresentation] = [
        .smart: DisplayRepresentation(title: "Smart mix", subtitle: "Today's words and words you are learning"),
        .today: DisplayRepresentation(title: "Today's new words"),
        .learning: DisplayRepresentation(title: "Words I'm learning"),
        .level: DisplayRepresentation(title: "My HSK level"),
        .saved: DisplayRepresentation(title: "Saved words"),
    ]

    var source: WidgetSource { WidgetSource(rawValue: rawValue) ?? .smart }
}

enum RotationOption: String, AppEnum {
    case m15 = "15", m30 = "30", h1 = "60", h3 = "180", h6 = "360", daily = "1440"

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Change every"
    static var caseDisplayRepresentations: [RotationOption: DisplayRepresentation] = [
        .m15: "15 minutes", .m30: "30 minutes", .h1: "Hour", .h3: "3 hours", .h6: "6 hours", .daily: "Day",
    ]

    var minutes: Int { Int(rawValue) ?? 30 }
}

struct WordWidgetIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Word"
    static var description = IntentDescription("Shows a Chinese word and changes it on a schedule.")

    @Parameter(title: "Words", default: .smart)
    var source: WordSourceOption

    @Parameter(title: "Change every", default: .m30)
    var rotation: RotationOption

    @Parameter(title: "Show pinyin", default: true)
    var showPinyin: Bool

    @Parameter(title: "Show meaning", default: true)
    var showMeaning: Bool

    init() {}
}

/// "Next" button on the home screen widget.
struct NextWordIntent: AppIntent {
    static var title: LocalizedStringResource = "Next word"
    static var isDiscoverable = false

    func perform() async throws -> some IntentResult {
        var s = SharedStore.load()
        s.widgetOffset += 1
        s.updated = Date()
        SharedStore.save(s)
        return .result()
    }
}

/// "I know it" button: marks the word as known and moves on.
struct KnowWordIntent: AppIntent {
    static var title: LocalizedStringResource = "I know this word"
    static var isDiscoverable = false

    @Parameter(title: "Word ID")
    var wordID: Int

    init() {}
    init(wordID: Int) { self.wordID = wordID }

    func perform() async throws -> some IntentResult {
        var s = SharedStore.load()
        var f = FSRS()
        f.requestRetention = s.settings.retention
        s.markKnown(wordID, today: StudyDay.number(), fsrs: f)
        s.widgetOffset += 1
        SharedStore.save(s)
        return .result()
    }
}
