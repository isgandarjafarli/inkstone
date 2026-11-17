import SwiftUI
import WidgetKit

/// One word on the watch face at one moment.
struct WatchWordEntry: TimelineEntry {
    let date: Date
    let word: WidgetWord
    var showPinyin = true
    var showMeaning = true
    var toneColors = true
    var toneHanzi = true

    var url: URL { URL(string: "inkstone://word/\(word.id)")! }

    static let preview = WatchWordEntry(date: Date(), word: .placeholder)
}

/// Today's numbers on the watch face.
struct WatchTodayEntry: TimelineEntry {
    let date: Date
    let due: Int
    let newLeft: Int
    let streak: Int

    static let preview = WatchTodayEntry(date: Date(), due: 12, newLeft: 3, streak: 4)
}

/// The rotating word, in every watch face shape.
struct WatchWordView: View {
    let entry: WatchWordEntry
    /// Lets the watch app draw a complication at a chosen shape (for screenshots).
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    @Environment(\.widgetRenderingMode) private var renderingMode
    private var family: WidgetFamily { familyOverride ?? envFamily }
    private var w: WidgetWord { entry.word }
    private var colorPinyin: Bool { entry.toneColors && renderingMode == .fullColor }
    private var colorHanzi: Bool { entry.toneHanzi && renderingMode == .fullColor }

    var body: some View {
        content
            .widgetURL(entry.url)
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        default: rectangular
        }
    }

    private var hanzi: Text { toneText(w.hanzi, pinyin: w.pinyin, colored: colorHanzi, base: .primary) }

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
        case 1: withPinyin ? 26 : 32
        case 2: withPinyin ? 19 : 22
        case 3: 15
        default: 12
        }
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                hanzi
                    .font(Ink.hanziFixed(size))
                    .lineLimit(n > 3 ? 2 : 1)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.5)
                    .widgetAccentable()
                if withPinyin {
                    Text(Pinyin.joined(w.pinyin))
                        .font(.system(size: 9, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            .padding(4)
        }
        .accessibilityLabel(spoken)
    }

    private var corner: some View {
        hanzi
            .font(Ink.hanziFixed(w.hanzi.count == 1 ? 26 : 16))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .widgetAccentable()
            .widgetCurvesContent()
            .widgetLabel {
                Text(entry.showMeaning ? "\(Pinyin.joined(w.pinyin)) · \(w.meaning)" : Pinyin.joined(w.pinyin))
            }
            .accessibilityLabel(spoken)
    }

    private var rectangular: some View {
        HStack(spacing: 8) {
            hanzi
                .font(Ink.hanziFixed(w.hanzi.count <= 2 ? 34 : (w.hanzi.count <= 4 ? 22 : 17)))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .widgetAccentable()
                .layoutPriority(1)
            VStack(alignment: .leading, spacing: 0) {
                if entry.showPinyin {
                    PinyinText(pinyin: w.pinyin, colored: colorPinyin, font: .system(size: 15, weight: .semibold))
                        .lineLimit(1).minimumScaleFactor(0.6)
                }
                if entry.showMeaning {
                    Text(w.meaning)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(entry.showPinyin ? 2 : 3)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private var spoken: String {
        var parts = [w.hanzi]
        if entry.showPinyin { parts.append(Pinyin.joined(w.pinyin)) }
        if entry.showMeaning { parts.append(w.meaning) }
        return parts.joined(separator: ", ")
    }
}

/// Reviews due today, in every watch face shape.
struct WatchTodayView: View {
    let entry: WatchTodayEntry
    var familyOverride: WidgetFamily? = nil
    @Environment(\.widgetFamily) private var envFamily
    private var family: WidgetFamily { familyOverride ?? envFamily }

    var body: some View {
        content
            .widgetURL(URL(string: "inkstone://review"))
            .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder private var content: some View {
        switch family {
        case .accessoryInline:
            Text(entry.due > 0 ? "\(entry.due) to review" : "Reviews done")
        case .accessoryCircular:
            Gauge(value: Double(min(entry.due, 50)), in: 0...50) {
                Text("due")
            } currentValueLabel: {
                Text("\(entry.due)").font(.system(size: 17, weight: .bold)).monospacedDigit()
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
        case .accessoryCorner:
            Text("\(entry.due)")
                .font(.system(size: 20, weight: .bold))
                .monospacedDigit()
                .widgetCurvesContent()
                .widgetLabel { Text(entry.due == 1 ? "review due" : "reviews due") }
        default:
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 5) {
                    Text("砚").font(Ink.hanziFixed(13)).widgetAccentable()
                    Text(AppInfo.name).font(.system(size: 13, weight: .semibold))
                }
                Text(entry.due > 0 ? "\(entry.due) to review" : "Reviews done")
                    .font(.system(size: 17, weight: .bold))
                    .widgetAccentable()
                Text("\(entry.newLeft) new left · \(entry.streak)-day streak")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
