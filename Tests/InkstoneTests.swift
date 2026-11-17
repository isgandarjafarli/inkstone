import XCTest
@testable import Inkstone

/// The app's bundled data. (On Linux, where only the core logic is checked, it comes from a folder.)
#if canImport(SwiftUI)
let resources = Bundle.main
#else
let resources = Bundle(path: ProcessInfo.processInfo.environment["INKSTONE_RES"] ?? "")!
#endif

final class FSRSTests: XCTestCase {
    let f = FSRS()

    func testFirstAnswerSetsSensibleIntervals() {
        let again = f.first(.again, today: 100)
        let good = f.first(.good, today: 100)
        let easy = f.first(.easy, today: 100)
        XCTAssertEqual(again.due, 100, "a forgotten new word comes back the same day")
        XCTAssertGreaterThan(good.due, 100)
        XCTAssertGreaterThan(easy.due, good.due)
        XCTAssertEqual(good.reps, 1)
    }

    func testIntervalsGrowWithSuccessAndShrinkAfterLapse() {
        var c = f.first(.good, today: 0)
        var last = 0
        for _ in 0..<4 {
            let day = c.due
            c = f.review(c, .good, today: day)
            let ivl = c.due - day
            XCTAssertGreaterThanOrEqual(ivl, last)
            last = ivl
        }
        XCTAssertGreaterThan(last, 20, "four good reviews should reach weeks")
        let before = c.stability
        let lapsed = f.review(c, .again, today: c.due)
        XCTAssertLessThan(lapsed.stability, before)
        XCTAssertEqual(lapsed.lapses, c.lapses + 1)
    }

    func testDifficultyStaysInRange() {
        var c = f.first(.again, today: 0)
        for i in 0..<20 { c = f.review(c, i % 2 == 0 ? .again : .hard, today: c.due) }
        XCTAssertLessThanOrEqual(c.difficulty, 10)
        XCTAssertGreaterThanOrEqual(c.difficulty, 1)
    }

    func testPreviewOrdersGrades() {
        let c = f.review(f.first(.good, today: 0), .good, today: 3)
        let p = f.preview(c, today: c.due)
        XCTAssertLessThanOrEqual(p[.again]!, p[.hard]!)
        XCTAssertLessThanOrEqual(p[.hard]!, p[.good]!)
        XCTAssertLessThanOrEqual(p[.good]!, p[.easy]!)
    }

    func testHigherRetentionMeansShorterIntervals() {
        var strict = FSRS(); strict.requestRetention = 0.95
        var relaxed = FSRS(); relaxed.requestRetention = 0.85
        XCTAssertLessThan(strict.interval(for: 30), relaxed.interval(for: 30))
    }
}

final class PinyinTests: XCTestCase {
    func testTones() {
        XCTAssertEqual(Pinyin.tone(of: "mā"), 1)
        XCTAssertEqual(Pinyin.tone(of: "má"), 2)
        XCTAssertEqual(Pinyin.tone(of: "mǎ"), 3)
        XCTAssertEqual(Pinyin.tone(of: "mà"), 4)
        XCTAssertEqual(Pinyin.tone(of: "ma"), 5)
        XCTAssertEqual(Pinyin.tone(of: "lǜ"), 4)
    }

    func testPlainAndNumbered() {
        XCTAssertEqual(Pinyin.plain("péng you"), "pengyou")
        XCTAssertEqual(Pinyin.numbered("péng you").replacingOccurrences(of: " ", with: ""), "peng2you5")
        XCTAssertEqual(Pinyin.syllables("péng you"), ["péng", "you"])
    }

    func testJoinedFormUsesApostrophes() {
        XCTAssertEqual(Pinyin.joined("péng you"), "péngyou")
        XCTAssertEqual(Pinyin.joined("Xī ān"), "Xī'ān")
        XCTAssertEqual(Pinyin.joined("tiān ān mén"), "tiān'ānmén")
        XCTAssertEqual(Pinyin.joined("hǎo"), "hǎo")
    }
}

final class LexiconTests: XCTestCase {
    override class func setUp() {
        super.setUp()
        try? Lexicon.shared.load(bundle: resources)
    }

    func testLoadsEverything() {
        let lex = Lexicon.shared
        XCTAssertTrue(lex.isLoaded)
        XCTAssertGreaterThan(lex.words.count, 11_000)
        XCTAssertGreaterThan(lex.sentences.count, 10_000)
        XCTAssertGreaterThan(lex.chars.count, 2_500)
    }

    func testEveryLevelHasWords() {
        for syllabus in Syllabus.allCases {
            for level in syllabus.levels {
                XCTAssertFalse(Lexicon.shared.words(level: level, syllabus: syllabus).isEmpty, "\(syllabus) level \(level)")
            }
        }
    }

    func testLevelOneIsMostlyCommonWords() {
        let first = Lexicon.shared.words(level: 1, syllabus: .hsk2026).prefix(20).map(\.s)
        XCTAssertTrue(first.contains("的") || first.contains("我"), "\(first)")
    }

    func testWordDetailData() throws {
        let lex = Lexicon.shared
        let w = try XCTUnwrap(lex.word(hanzi: "朋友"))
        XCTAssertEqual(w.p, "péng you")
        XCTAssertFalse(lex.sentences(for: w).isEmpty)
        let strokes = try XCTUnwrap(lex.strokes(for: "朋"))
        XCTAssertEqual(strokes.strokes.count, 8)
        XCTAssertEqual(strokes.medians.count, 8)
        XCTAssertNotNil(lex.charInfo("朋"))
    }

    func testSentencesContainTheirWord() {
        let lex = Lexicon.shared
        var checked = 0, misses: [String] = []
        for w in lex.words(level: 1, syllabus: .hsk2026).prefix(150) {
            for s in lex.sentences(for: w) {
                checked += 1
                if !s.zh.contains(w.s) { misses.append("\(w.s): \(s.zh)") }
            }
        }
        XCTAssertGreaterThan(checked, 100)
        XCTAssertTrue(misses.isEmpty, misses.prefix(5).joined(separator: "\n"))
    }

    func testSearch() {
        let lex = Lexicon.shared
        XCTAssertEqual(lex.search("pengyou", syllabus: .hsk2026).first?.s, "朋友")
        XCTAssertEqual(lex.search("peng2you5", syllabus: .hsk2026).first?.s, "朋友")
        XCTAssertTrue(lex.search("friend", syllabus: .hsk2026).prefix(5).contains { $0.s == "朋友" })
        XCTAssertEqual(lex.search("朋友", syllabus: .hsk2026).first?.s, "朋友")
        XCTAssertTrue(lex.search("   ", syllabus: .hsk2026).isEmpty)
    }

    func testDistractorsAreDistinct() throws {
        let lex = Lexicon.shared
        let w = try XCTUnwrap(lex.word(hanzi: "朋友"))
        let d = lex.distractors(for: w, syllabus: .hsk2026)
        XCTAssertEqual(d.count, 3)
        XCTAssertFalse(d.contains { $0.id == w.id })
        XCTAssertEqual(Set(d.map { $0.meaning.lowercased() }).count, 3)
    }
}

final class WidgetFeedTests: XCTestCase {
    static var words: [WidgetWord] = []

    override class func setUp() {
        super.setUp()
        words = WidgetFeed.loadWords(bundle: resources)
    }

    func testWordsLoad() {
        XCTAssertGreaterThan(Self.words.count, 11_000)
    }

    func testSmartPoolStartsWithTodaysWords() throws {
        let friend = try XCTUnwrap(Self.words.first { $0.hanzi == "朋友" })
        var s = UserState()
        s.plan = DailyPlan(day: 500, newWordIDs: [friend.id])
        let pool = WidgetFeed.pool(source: .smart, state: s, words: Self.words, today: 500)
        XCTAssertTrue(pool.contains(friend))
        XCTAssertGreaterThanOrEqual(pool.count, 12)
    }

    func testEmptySavedListFallsBackToLevel() {
        let pool = WidgetFeed.pool(source: .saved, state: UserState(), words: Self.words, today: 1)
        XCTAssertFalse(pool.isEmpty)
    }

    func testRotationIsStableWithinASlotAndMovesWithOffset() {
        let pool = Array(Self.words.prefix(40))
        let t = Date(timeIntervalSince1970: 1_800_000_000)
        let a = WidgetFeed.word(at: t, pool: pool, intervalMinutes: 30, offset: 0)
        let b = WidgetFeed.word(at: t.addingTimeInterval(60), pool: pool, intervalMinutes: 30, offset: 0)
        let c = WidgetFeed.word(at: t, pool: pool, intervalMinutes: 30, offset: 1)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testShuffleIsDeterministic() {
        let items = Array(0..<50)
        XCTAssertEqual(WidgetFeed.stableShuffle(items, seed: 9), WidgetFeed.stableShuffle(items, seed: 9))
        XCTAssertNotEqual(WidgetFeed.stableShuffle(items, seed: 9), WidgetFeed.stableShuffle(items, seed: 10))
    }
}

final class ProgressTests: XCTestCase {
    func testStreakCountsBackFromYesterdayIfTodayIsEmpty() {
        var s = UserState()
        for d in [7, 8, 9] { s.log[d] = DayLog(reviews: 3, correct: 3, learned: 0, seconds: 60) }
        XCTAssertEqual(s.streak(today: 10), 3)
        s.log[10] = DayLog(reviews: 1, correct: 1, learned: 0, seconds: 10)
        XCTAssertEqual(s.streak(today: 10), 4)
        XCTAssertEqual(s.streak(today: 12), 0)
    }

    func testMarkKnownCountsNewWordOnce() {
        var s = UserState()
        s.markKnown(42, today: 5)
        s.markKnown(42, today: 5)
        XCTAssertEqual(s.log[5]?.learned, 1)
        XCTAssertTrue(s.cards[42]!.mastered)
        XCTAssertTrue(s.dueIDs(today: 5).isEmpty)
    }

    func testDueOrder() {
        var s = UserState()
        let f = FSRS()
        var a = f.first(.good, today: 0); a.due = 3
        var b = f.first(.good, today: 0); b.due = 1
        s.cards = [1: a, 2: b]
        XCTAssertEqual(s.dueIDs(today: 3), [2, 1])
        XCTAssertEqual(s.dueIDs(today: 2), [2])
    }

    func testStateRoundTripsThroughJSON() throws {
        var s = UserState()
        s.cards[7] = FSRS().first(.good, today: 3)
        s.plan = DailyPlan(day: 3, newWordIDs: [7, 8])
        let data = try JSONEncoder.inkstone.encode(s)
        let back = try JSONDecoder.inkstone.decode(UserState.self, from: data)
        XCTAssertEqual(back.cards[7]?.due, s.cards[7]?.due)
        XCTAssertEqual(back.plan?.newWordIDs, [7, 8])
    }

    func testStudyDayRollsOverAtFourAM() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Helsinki")!
        let lateNight = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 2))!
        let evening = cal.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 21))!
        let morning = cal.date(from: DateComponents(year: 2026, month: 3, day: 10, hour: 5))!
        XCTAssertEqual(StudyDay.number(for: lateNight, calendar: cal), StudyDay.number(for: evening, calendar: cal))
        XCTAssertEqual(StudyDay.number(for: morning, calendar: cal), StudyDay.number(for: evening, calendar: cal) + 1)
    }
}

final class CompatibilityTests: XCTestCase {
    /// A progress file written before a setting existed must still load, with the new setting at
    /// its default, instead of failing and losing the learner's progress.
    func testOlderProgressFilesLoadWithDefaults() throws {
        var state = UserState()
        state.cards[42] = FSRS().first(.good, today: 100)
        state.settings.level = 3
        var json = try JSONSerialization.jsonObject(with: JSONEncoder.inkstone.encode(state)) as! [String: Any]
        var settings = json["settings"] as! [String: Any]
        settings.removeValue(forKey: "toneHanzi")
        settings["someFutureSetting"] = true
        json["settings"] = settings
        json.removeValue(forKey: "widgetOffset")
        let data = try JSONSerialization.data(withJSONObject: json)
        let loaded = try JSONDecoder.inkstone.decode(UserState.self, from: data)
        XCTAssertEqual(loaded.settings.level, 3)
        XCTAssertTrue(loaded.settings.toneHanzi)
        XCTAssertEqual(loaded.widgetOffset, 0)
        XCTAssertEqual(loaded.cards[42]?.reps, 1)
    }

    func testDamagedCardsFailInsteadOfLoadingEmpty() {
        let data = Data(#"{"onboarded": true, "cards": {"1": {"oops": 1}}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder.inkstone.decode(UserState.self, from: data))
    }
}

final class WatchTests: XCTestCase {
    func testFeedListsWhatTheWatchNeeds() {
        var s = UserState()
        let f = FSRS()
        s.cards[1] = f.first(.good, today: 100)          // learning
        var known = f.first(.good, today: 90)
        known.mastered = true
        s.cards[2] = known                               // known: not in the learning list
        var due = f.first(.good, today: 95)
        due.due = 100
        s.cards[3] = due                                 // due today
        s.plan = DailyPlan(day: 100, newWordIDs: [7, 8])
        s.lists = [WordList(name: "Saved", wordIDs: [9])]
        let feed = WatchFeed(state: s, today: 100, upcomingIDs: [10, 11])
        XCTAssertEqual(feed.todayIDs, [7, 8])
        XCTAssertTrue(feed.learningIDs.contains(1))
        XCTAssertFalse(feed.learningIDs.contains(2))
        XCTAssertEqual(feed.dueIDs, [3])
        XCTAssertEqual(feed.allIDs, [1, 3, 7, 8, 9, 10, 11])
        let round = try? JSONDecoder().decode(WatchFeed.self, from: JSONEncoder().encode(feed))
        XCTAssertEqual(round, feed)
    }

    // The watch's word lists are not part of the iPhone app, so these run in the Linux check only.
    #if !canImport(SwiftUI)
    func testWatchPoolUsesThePhoneListsOrFallsBackToHSK1() {
        let noPhone = WatchWords.pool(feed: nil, prefs: WatchPrefs(), today: 100, bundle: resources)
        XCTAssertGreaterThan(noPhone.count, 50)
        XCTAssertTrue(noPhone.allSatisfy { $0.levels["h26"] == 1 })

        let words = WidgetFeed.loadWords(bundle: resources)
        let ids = words.filter { $0.levels["h26"] == 2 }.prefix(5).map(\.id)
        var s = UserState()
        s.plan = DailyPlan(day: 100, newWordIDs: ids)
        let feed = WatchFeed(state: s, today: 100, upcomingIDs: [])
        var prefs = WatchPrefs()
        prefs.source = .today
        let pool = WatchWords.pool(feed: feed, prefs: prefs, today: 100, bundle: resources)
        XCTAssertEqual(Set(pool.map(\.id)), Set(ids))
        XCTAssertEqual(pool.map(\.id), WatchWords.pool(feed: feed, prefs: prefs, today: 100, bundle: resources).map(\.id),
                       "stable within a day")
    }

    func testWatchPrefsSurviveNewFields() throws {
        let data = Data(#"{"interval": 30}"#.utf8)
        let p = try JSONDecoder().decode(WatchPrefs.self, from: data)
        XCTAssertEqual(p.interval, 30)
        XCTAssertEqual(p.source, .smart)
    }
    #endif

    func testStrokePackReadsCharacters() throws {
        let url = try XCTUnwrap(resources.url(forResource: "strokes", withExtension: "pack"))
        let pack = try StrokePack(url: url)
        XCTAssertTrue(pack.has("永"))
        XCTAssertEqual(pack.strokes(for: "永")?.strokes.count, 5)
        XCTAssertFalse(pack.has("A"))
    }
}

#if canImport(SwiftUI)
final class HandwritingTests: XCTestCase {
    func testMatchesItsOwnMedianAndRejectsReversedOrDistantStrokes() throws {
        try? Lexicon.shared.load(bundle: resources)
        let strokes = try XCTUnwrap(CharacterStrokes(character: "一", data: Lexicon.shared.strokes(for: "一")))
        let median = strokes.medians[0]
        XCTAssertTrue(Geometry.strokeMatches(drawn: median, median: median, leniency: 1))
        XCTAssertFalse(Geometry.strokeMatches(drawn: median.reversed(), median: median, leniency: 1), "wrong direction")
        let far = median.map { CGPoint(x: $0.x, y: $0.y + 500) }
        XCTAssertFalse(Geometry.strokeMatches(drawn: far, median: median, leniency: 1), "wrong place")
        let wobbly = median.enumerated().map { CGPoint(x: $1.x, y: $1.y + ($0 % 2 == 0 ? 25 : -25)) }
        XCTAssertTrue(Geometry.strokeMatches(drawn: wobbly, median: median, leniency: 1), "a slightly shaky stroke still counts")
    }

    func testSVGParserBuildsClosedOutlines() throws {
        try? Lexicon.shared.load(bundle: resources)
        let data = try XCTUnwrap(Lexicon.shared.strokes(for: "永"))
        for d in data.strokes {
            let path = SVGPath.parse(d)
            XCTAssertFalse(path.isEmpty)
            let box = path.boundingRect
            XCTAssertTrue(box.minX >= -50 && box.maxX <= 1100 && box.minY >= -200 && box.maxY <= 1100, "\(box)")
        }
    }
}
#endif
