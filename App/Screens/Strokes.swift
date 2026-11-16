import SwiftUI

/// Plays the stroke-order animation. Tap "Play" to restart.
struct StrokePlayer: View {
    let strokes: CharacterStrokes
    @Binding var playToken: Int
    var speed: Double = 1
    @State private var start: Date?

    private func timings() -> [(Double, Double)] {
        var t = 0.0
        var out: [(Double, Double)] = []
        for i in 0..<strokes.count {
            let d = 0.18 + Double(strokes.medianLength(i)) / 1024 * 0.75 / speed
            out.append((t, d))
            t += d + 0.12 / speed
        }
        return out
    }

    var body: some View {
        TimelineView(.animation(paused: start == nil)) { tl in
            let state = frame(at: tl.date)
            StrokeCanvas(strokes: strokes, completed: state.0, animating: state.1, progress: state.2)
        }
        .onChange(of: playToken) { _, _ in start = Date() }
        .onAppear { if playToken > 0 { start = Date() } }
    }

    private func frame(at date: Date) -> (Int, Int?, CGFloat) {
        guard let start else { return (strokes.count, nil, 0) }
        let t = date.timeIntervalSince(start)
        let tm = timings()
        for (i, (s, d)) in tm.enumerated() {
            if t < s { return (i, nil, 0) }
            if t < s + d { return (i, i, CGFloat((t - s) / d)) }
        }
        DispatchQueue.main.async { self.start = nil }
        return (strokes.count, nil, 0)
    }
}

/// Step-by-step strip: one small box per stroke.
struct StrokeSteps: View {
    let strokes: CharacterStrokes

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(0..<strokes.count, id: \.self) { i in
                    VStack(spacing: 3) {
                        ZStack {
                            PracticeGrid(color: Ink.ink3)
                            StrokeCanvas(strokes: strokes, completed: i, showOutline: true, highlight: i, colorRadical: false)
                        }
                        .frame(width: 46, height: 46)
                        .background(Ink.card)
                        Text("\(i + 1)").font(.caption2).monospacedDigit().foregroundStyle(Ink.ink3)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("\(strokes.count) strokes, in order")
    }
}

/// Handwriting practice for one character: draw each stroke in order.
struct WritingPad: View {
    let strokes: CharacterStrokes
    /// Show the faint outline to trace over.
    var trace: Bool
    /// Increment to ask for a hint (animates the next stroke, counts as a miss).
    var hintRequest: Int = 0
    var onComplete: (Int) -> Void

    @State private var done = 0
    @State private var points: [CGPoint] = []
    @State private var missesOnStroke = 0
    @State private var totalMisses = 0
    @State private var flashWrong = false
    @State private var hintToken = 0
    @State private var hintStart: Date?
    @State private var finished = false

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let scale = side / 1024
            ZStack {
                PracticeGrid()
                TimelineView(.animation(paused: hintStart == nil)) { tl in
                    let hint = hintFrame(tl.date)
                    StrokeCanvas(strokes: strokes, completed: done, animating: hint.0, progress: hint.1,
                                 showOutline: trace || missesOnStroke >= 2, highlight: nil)
                }
                Canvas { ctx, _ in
                    guard points.count > 1 else { return }
                    var p = Path()
                    p.addLines(points)
                    ctx.stroke(p, with: .color(flashWrong ? Ink.tone(4).opacity(0.7) : Ink.seal.opacity(0.85)),
                               style: StrokeStyle(lineWidth: max(10, side / 22), lineCap: .round, lineJoin: .round))
                }
            }
            .frame(width: side, height: side)
            .contentShape(Rectangle())
            .gesture(
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
        .onChange(of: hintRequest) { _, _ in showHint() }
        .accessibilityLabel("Writing area. Draw stroke \(min(done + 1, strokes.count)) of \(strokes.count).")
    }

    func showHint() {
        guard done < strokes.count else { return }
        totalMisses += 1
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
        let leniency: CGFloat = missesOnStroke >= 2 ? 1.35 : (trace ? 1.15 : 1.0)
        if Geometry.strokeMatches(drawn: drawn, median: strokes.medians[done], leniency: leniency) {
            Haptics.soft()
            done += 1
            missesOnStroke = 0
            if done == strokes.count {
                finished = true
                Haptics.success()
                let misses = totalMisses
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onComplete(misses) }
            }
        } else if Geometry.length(drawn) >= 18 {
            Haptics.error()
            missesOnStroke += 1
            totalMisses += 1
            flashWrong = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                if flashWrong { flashWrong = false; points = [] }
            }
            if missesOnStroke >= 3 { hintStart = Date() }
        }
    }
}
