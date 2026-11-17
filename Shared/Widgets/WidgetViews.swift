import SwiftUI
import WidgetKit

// MARK: - Word widget

struct WordWidgetView: View {
    let entry: WordEntry
    /// Lets the app draw a widget at a chosen size (for previews and screenshots).
    var familyOverride: WidgetFamily? = nil
    /// Draws the StandBy layout outside StandBy (for previews and screenshots).
    var forceStandBy = false
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }
    @Environment(\.widgetRenderingMode) private var renderingMode
    @Environment(\.showsWidgetContainerBackground) private var showsBackground

    private var w: WidgetWord { entry.word }
    /// Tone colours only make sense in full colour (not on the lock screen, tinted home screens or StandBy at night).
    private var colored: Bool { entry.toneColors && renderingMode == .fullColor }
    private var coloredHanzi: Bool { entry.toneHanzi && renderingMode == .fullColor }

    var body: some View {
        Group {
            switch family {
            case .accessoryInline: inline
            case .accessoryCircular: circular
            case .accessoryRectangular: rectangular
            case .systemMedium: medium
            case .systemLarge: large
            default: showsBackground && !forceStandBy ? AnyView(small) : AnyView(standBy)
            }
        }
        .widgetURL(entry.url)
        .containerBackground(for: .widget) {
            if family.isAccessory { Color.clear } else { Ink.card }
        }
        .accessibilityElement(children: .contain)
    }

    // MARK: Lock screen

    private var inline: some View {
        var text = w.hanzi
        if entry.showPinyin { text += " \(Pinyin.joined(w.pinyin))" }
        if entry.showMeaning { text += " · \(w.meaning)" }
        return Text(text)
    }

    private var circular: some View {
        let n = w.hanzi.count
        let withPinyin = entry.showPinyin && n <= 2
        let size: CGFloat = switch n {
        case 1: withPinyin ? 30 : 38
        case 2: withPinyin ? 22 : 26
        case 3: 18
        default: 14
        }
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Text(w.hanzi)
                    .font(Ink.hanziFixed(size))
                    .lineLimit(n > 3 ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                if withPinyin {
                    Text(Pinyin.joined(w.pinyin))
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(5)
        }
        .accessibilityLabel(spoken)
    }

    private var rectangular: some View {
        let n = w.hanzi.count
        return Group {
            if n <= 2 {
                HStack(spacing: 8) {
                    Text(w.hanzi)
                        .font(Ink.hanziFixed(n == 1 ? 40 : 32))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .widgetAccentable()
                    details(pinyinSize: 15, lines: 2)
                }
            } else {
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(w.hanzi)
                            .font(Ink.hanziFixed(n <= 4 ? 24 : 19))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .widgetAccentable()
                        if entry.showPinyin {
                            Text(Pinyin.joined(w.pinyin)).font(.system(size: 13, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                    }
                    if entry.showMeaning {
                        Text(w.meaning).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func details(pinyinSize: CGFloat, lines: Int) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if entry.showPinyin {
                Text(Pinyin.joined(w.pinyin)).font(.system(size: pinyinSize, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
            }
            if entry.showMeaning {
                Text(w.meaning).font(.system(size: 13)).foregroundStyle(.secondary).lineLimit(entry.showPinyin ? lines : lines + 1)
            }
        }
    }

    // MARK: Home screen

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SealMark(size: 18)
                Spacer()
                if !entry.level.isEmpty { levelTag }
            }
            Spacer(minLength: 4)
            GridWord(text: w.hanzi, pinyin: w.pinyin, colored: coloredHanzi, maxCell: 62)
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
            Spacer(minLength: 4)
            VStack(alignment: .leading, spacing: 1) {
                if entry.showPinyin {
                    PinyinText(pinyin: w.pinyin, colored: colored, font: .system(size: 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if entry.showMeaning {
                    Text(w.meaning).font(.system(size: 13)).foregroundStyle(Ink.ink2).lineLimit(entry.showPinyin ? 1 : 2)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    /// StandBy shows the small widget full screen without a background: let the word fill it.
    private var standBy: some View {
        VStack(spacing: 6) {
            toneText(w.hanzi, pinyin: w.pinyin, colored: coloredHanzi, base: .primary)
                .font(Ink.hanziFixed(w.hanzi.count <= 2 ? 64 : 40))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .widgetAccentable()
            if entry.showPinyin {
                PinyinText(pinyin: w.pinyin, colored: colored, font: .system(size: 18, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if entry.showMeaning {
                Text(w.meaning).font(.system(size: 14)).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var medium: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 0) {
                GridWord(text: w.hanzi, pinyin: w.pinyin, colored: coloredHanzi, maxCell: 58)
                    .layoutPriority(1)
                Spacer(minLength: 6)
                if entry.showPinyin {
                    PinyinText(pinyin: w.pinyin, colored: colored, font: .system(size: 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                if entry.showMeaning {
                    Text(w.meaning).font(.system(size: 13)).foregroundStyle(Ink.ink2).lineLimit(2)
                }
            }
            .frame(width: 118, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)

            VStack(alignment: .leading, spacing: 4) {
                if w.sentence.isEmpty {
                    HStack(spacing: 6) {
                        if !entry.level.isEmpty { levelTag }
                        Text("Tap for stroke order").font(.caption).foregroundStyle(Ink.ink3)
                    }
                    Spacer(minLength: 0)
                } else {
                    sentenceText(size: 17)
                        .lineLimit(2)
                        .minimumScaleFactor(0.8)
                    if entry.showPinyin {
                        Text(w.sentencePinyin).font(.system(size: 11)).foregroundStyle(Ink.ink3).lineLimit(1)
                    }
                    if entry.showMeaning {
                        Text(w.sentenceEnglish).font(.system(size: 12)).foregroundStyle(Ink.ink2).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 6) {
                    Spacer(minLength: 0)
                    actions
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var large: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SealMark(size: 22)
                Text(AppInfo.name).font(.caption.weight(.semibold)).foregroundStyle(Ink.ink2)
                Spacer()
                if !entry.level.isEmpty { levelTag }
            }
            Spacer(minLength: 10)
            HStack(alignment: .bottom, spacing: 14) {
                GridWord(text: w.hanzi, pinyin: w.pinyin, colored: coloredHanzi, maxCell: 84)
                    .layoutPriority(1)
                Spacer(minLength: 0)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(spoken)
            Spacer(minLength: 8)
            if entry.showPinyin {
                PinyinText(pinyin: w.pinyin, colored: colored, font: .system(size: 22, weight: .semibold))
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            if entry.showMeaning {
                Text(w.meaning).font(.system(size: 16)).foregroundStyle(Ink.ink2).lineLimit(2)
            }
            if !w.sentence.isEmpty {
                Rectangle().fill(Ink.hairline).frame(height: 0.5).padding(.vertical, 10)
                sentenceText(size: 19).lineLimit(2).minimumScaleFactor(0.8)
                if entry.showPinyin {
                    Text(w.sentencePinyin).font(.system(size: 12)).foregroundStyle(Ink.ink3).lineLimit(1)
                        .padding(.top, 2)
                }
                if entry.showMeaning {
                    Text(w.sentenceEnglish).font(.system(size: 13)).foregroundStyle(Ink.ink2).lineLimit(2)
                        .padding(.top, 2)
                }
            }
            Spacer(minLength: 10)
            HStack(spacing: 10) {
                stat("\(entry.due)", "to review")
                stat("\(entry.newLeft)", "new left")
                Spacer(minLength: 0)
                actions
            }
        }
    }

    // MARK: Pieces

    private var levelTag: some View {
        Text(entry.level)
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(Ink.ink2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Ink.well, in: Capsule())
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(intent: KnowWordIntent(wordID: w.id)) {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 32, height: 32)
                    .background(Ink.well, in: Circle())
                    .foregroundStyle(Ink.good)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("I know this word")
            Button(intent: NextWordIntent()) {
                Label("Next", systemImage: "arrow.right")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, 12)
                    .frame(height: 32)
                    .background(Ink.seal, in: Capsule())
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next word")
        }
        .invalidatableContent()
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value).font(.system(size: 17, weight: .bold)).monospacedDigit().foregroundStyle(Ink.ink)
            Text(label).font(.system(size: 11)).foregroundStyle(Ink.ink3)
        }
    }

    private func sentenceText(size: CGFloat) -> Text {
        highlighted(w.sentence, word: w.hanzi, base: Ink.ink, accent: Ink.seal)
            .font(Ink.hanziFixed(size))
    }

    private var spoken: String {
        var parts = [w.hanzi]
        if entry.showPinyin { parts.append(Pinyin.joined(w.pinyin)) }
        if entry.showMeaning { parts.append(w.meaning) }
        return parts.joined(separator: ", ")
    }
}

/// A word written in practice-paper squares (米字格), one square per character.
/// The squares grow to fill the space they are given, up to `maxCell`.
struct GridWord: View {
    let text: String
    var pinyin: String = ""
    /// Colour each character by its tone.
    var colored: Bool = false
    var maxCell: CGFloat = 64
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        let chars = Array(text).map(String.init)
        let colors: [Color?] = colored ? toneColorList(text, pinyin: pinyin) : chars.map { _ -> Color? in nil }
        if chars.count > 4 {
            toneText(text, pinyin: pinyin, colored: colored)
                .font(Ink.hanziFixed(40))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .widgetAccentable()
        } else {
            HStack(spacing: -1) {
                ForEach(Array(chars.enumerated()), id: \.offset) { i, c in
                    ZStack {
                        PracticeGrid(color: renderingMode == .fullColor ? Ink.seal : .primary)
                        Text(c)
                            .font(Ink.hanziFixed(maxCell * 0.76))
                            .lineLimit(1)
                            .minimumScaleFactor(0.25)
                            .padding(maxCell * 0.06)
                            .foregroundStyle(colors[i] ?? Ink.ink)
                            .widgetAccentable()
                    }
                    .frame(maxWidth: maxCell, maxHeight: maxCell)
                    .aspectRatio(1, contentMode: .fit)
                }
            }
        }
    }
}

/// The sentence with each occurrence of the word picked out in the accent colour.
func highlighted(_ sentence: String, word: String, base: Color, accent: Color) -> Text {
    guard !word.isEmpty, sentence.contains(word) else { return Text(sentence).foregroundColor(base) }
    var out = Text("")
    var rest = Substring(sentence)
    while let r = rest.range(of: word) {
        out = out + Text(rest[..<r.lowerBound]).foregroundColor(base) + Text(rest[r]).foregroundColor(accent)
        rest = rest[r.upperBound...]
    }
    return out + Text(rest).foregroundColor(base)
}

extension WidgetFamily {
    var isAccessory: Bool {
        switch self {
        case .accessoryCircular, .accessoryInline, .accessoryRectangular: return true
        default: return false
        }
    }
}

// MARK: - Today widget

struct TodayWidgetView: View {
    let entry: TodayEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    private var learned: Int { max(0, entry.newPlanned - entry.newLeft) }

    var body: some View {
        Group {
            switch family {
            case .accessoryCircular: circular
            case .accessoryInline: inline
            case .accessoryRectangular: rectangular
            default: small
            }
        }
        .widgetURL(URL(string: entry.due > 0 ? "inkstone://review" : "inkstone://today"))
        .containerBackground(for: .widget) {
            if family.isAccessory { Color.clear } else { Ink.card }
        }
    }

    private var circular: some View {
        Gauge(value: Double(learned), in: 0...Double(max(entry.newPlanned, 1))) {
            Image(systemName: "rectangle.stack")
        } currentValueLabel: {
            VStack(spacing: -2) {
                Text("\(entry.due)").font(.system(size: 20, weight: .bold)).monospacedDigit()
                Text("due").font(.system(size: 9, weight: .semibold))
            }
        }
        .gaugeStyle(.accessoryCircularCapacity)
        .widgetAccentable()
        .accessibilityLabel("\(entry.due) reviews due, \(learned) of \(entry.newPlanned) new words learned")
    }

    private var inline: some View {
        Text(summaryLine)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(AppInfo.name).font(.system(size: 13, weight: .bold)).widgetAccentable()
            Text("\(entry.due) to review · \(entry.newLeft) new").font(.system(size: 15, weight: .semibold))
            Text(streakLine).font(.system(size: 13)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SealMark(size: 18)
                Text("Today").font(.caption.weight(.semibold)).foregroundStyle(Ink.ink2)
                Spacer()
            }
            Spacer(minLength: 4)
            Text("\(entry.due)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                .foregroundStyle(entry.due > 0 ? Ink.seal : Ink.good)
            Text(entry.due == 1 ? "word to review" : "words to review").font(.system(size: 13)).foregroundStyle(Ink.ink2)
            Spacer(minLength: 4)
            HStack(spacing: 4) {
                Image(systemName: "sparkles").font(.system(size: 11))
                Text("\(entry.newLeft) new left").font(.system(size: 12, weight: .medium))
            }
            .foregroundStyle(Ink.ink2)
            HStack(spacing: 4) {
                Image(systemName: "flame.fill").font(.system(size: 11)).foregroundStyle(entry.studiedToday ? Ink.seal : Ink.ink3)
                Text(streakLine).font(.system(size: 12, weight: .medium)).foregroundStyle(Ink.ink2)
            }
        }
    }

    private var streakLine: String {
        if entry.streak == 0 { return "Start a streak today" }
        let days = entry.streak == 1 ? "1 day" : "\(entry.streak) days"
        return entry.studiedToday ? "\(days) in a row" : "\(days) · study to keep it"
    }

    private var summaryLine: String {
        var parts: [String] = []
        parts.append(entry.due == 0 ? "No reviews due" : "\(entry.due) to review")
        if entry.newLeft > 0 { parts.append("\(entry.newLeft) new") }
        if entry.streak > 0 { parts.append("\(entry.streak)-day streak") }
        return parts.joined(separator: " · ")
    }
}
