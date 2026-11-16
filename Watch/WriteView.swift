import SwiftUI
import WatchKit

/// Writing practice on the whole watch screen: trace each character stroke by stroke.
struct WriteView: View {
    @Environment(WatchModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var items: [WritingItem] = []
    @State private var index = 0
    @State private var trace = true
    @State private var hintToken = 0
    /// Debug builds only: strokes already drawn when the screen opens.
    var initialDone = 0

    var body: some View {
        NavigationStack {
            Group {
                if let item = current, let data = model.strokes?.strokes(for: item.char),
                   let strokes = CharacterStrokes(character: item.char, data: data) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            PinyinText(pinyin: syllable(of: item), colored: model.feed?.toneColors ?? true,
                                       font: .system(size: 14, weight: .semibold))
                            Text("· \(item.word.meaning)")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        WatchWritingPad(strokes: strokes, trace: trace, hintRequest: hintToken, initialDone: initialDone) {
                            next()
                        }
                        .id(item.id)
                    }
                } else {
                    Text("No characters to write yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("Close")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { hintToken += 1 } label: { Image(systemName: "lightbulb") }
                        .accessibilityLabel("Show the next stroke")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { trace.toggle() } label: { Image(systemName: trace ? "eye" : "eye.slash") }
                        .accessibilityLabel(trace ? "Hide the outline" : "Show the outline")
                    Spacer()
                    Text(items.isEmpty ? "" : "\(index + 1)/\(items.count)")
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button { next() } label: { Image(systemName: "forward.fill") }
                        .accessibilityLabel("Next character")
                }
            }
        }
        .onAppear { if items.isEmpty { items = model.writingItems } }
    }

    private var current: WritingItem? { items.isEmpty ? nil : items[index % items.count] }

    private func next() {
        guard !items.isEmpty else { return }
        index = (index + 1) % items.count
    }

    /// The pinyin syllable of this character within its word.
    private func syllable(of item: WritingItem) -> String {
        let chars = Array(item.word.hanzi).map(String.init)
        let syl = Pinyin.syllables(item.word.pinyin)
        if chars.count == syl.count, let i = chars.firstIndex(of: item.char) { return syl[i] }
        return item.word.pinyin
    }
}

/// Draw each stroke in order over a practice grid. Wrong strokes buzz; after two misses the
/// outline appears, after three the stroke is shown.
struct WatchWritingPad: View {
    let strokes: CharacterStrokes
    var trace: Bool
    var hintRequest: Int = 0
    var initialDone = 0
    var onComplete: () -> Void

    @State private var done = 0
    @State private var points: [CGPoint] = []
    @State private var missesOnStroke = 0
    @State private var flashWrong = false
    @State private var hintStart: Date?
    @State private var finished = false

    private let outline = Color(hex: 0x3B423E)
    private let ink = Color(hex: 0xF2F3EF)

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 1024
            ZStack {
                PracticeGrid(color: Color(hex: 0xE8624F))
                TimelineView(.animation(paused: hintStart == nil)) { tl in
                    let hint = hintFrame(tl.date)
                    StrokeCanvas(strokes: strokes, completed: done, animating: hint.0, progress: hint.1,
                                 showOutline: trace || missesOnStroke >= 2, highlight: nil, colorRadical: false,
                                 outlineColor: outline, inkColor: finished ? Color(hex: 0x5CC48E) : ink)
                }
                Canvas { ctx, _ in
                    guard points.count > 1 else { return }
                    var p = Path()
                    p.addLines(points)
                    ctx.stroke(p, with: .color(flashWrong ? Color.red.opacity(0.8) : Color(hex: 0xE8624F)),
                               style: StrokeStyle(lineWidth: max(7, side / 20), lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .highPriorityGesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { v in
                        guard !finished else { return }
                        if flashWrong { flashWrong = false; points = [] }
                        points.append(v.location)
                    }
                    .onEnded { _ in evaluate(scale: scale) }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onAppear { done = min(initialDone, strokes.count) }
        .onChange(of: hintRequest) { _, _ in showHint() }
        .accessibilityLabel("Writing area. Draw stroke \(min(done + 1, strokes.count)) of \(strokes.count).")
    }

    private func showHint() {
        guard done < strokes.count else { return }
        missesOnStroke = max(missesOnStroke, 2)
        hintStart = Date()
    }

    private func hintFrame(_ date: Date) -> (Int?, CGFloat) {
        guard let s = hintStart else { return (nil, 0) }
        let t = date.timeIntervalSince(s)
        if t > 1.1 {
            DispatchQueue.main.async { hintStart = nil }
            return (nil, 0)
        }
        return (done, CGFloat(min(1, t / 0.8)))
    }

    private func evaluate(scale: CGFloat) {
        defer { if !flashWrong { points = [] } }
        guard done < strokes.count, points.count > 1 else { points = []; return }
        let drawn = points.map { CGPoint(x: $0.x / scale, y: $0.y / scale) }
        // A fingertip is large next to a watch-sized character, so be more forgiving than on the phone.
        let leniency: CGFloat = missesOnStroke >= 2 ? 1.5 : (trace ? 1.3 : 1.15)
        if Geometry.strokeMatches(drawn: drawn, median: strokes.medians[done], leniency: leniency) {
            WKInterfaceDevice.current().play(.click)
            done += 1
            missesOnStroke = 0
            if done == strokes.count {
                finished = true
                WKInterfaceDevice.current().play(.success)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { onComplete() }
            }
        } else if Geometry.length(drawn) >= 18 {
            WKInterfaceDevice.current().play(.failure)
            missesOnStroke += 1
            flashWrong = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if flashWrong { flashWrong = false; points = [] }
            }
            if missesOnStroke >= 3 { hintStart = Date() }
        }
    }
}
