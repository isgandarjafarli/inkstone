import SwiftUI

/// Stroke geometry for one character in a 1024-unit screen-oriented box (y down).
struct CharacterStrokes {
    let character: String
    let paths: [Path]
    let medians: [[CGPoint]]
    let radical: Set<Int>

    init?(character: String, data: StrokeData?) {
        guard let data, !data.strokes.isEmpty else { return nil }
        self.character = character
        paths = data.strokes.map { SVGPath.parse($0) }
        medians = data.medians.map { pts in pts.compactMap { $0.count >= 2 ? CGPoint(x: $0[0], y: 900 - $0[1]) : nil } }
        radical = data.radicalStrokes
    }

    var count: Int { paths.count }

    func medianPath(_ i: Int) -> Path {
        var p = Path()
        guard i < medians.count, let first = medians[i].first else { return p }
        p.move(to: first)
        for pt in medians[i].dropFirst() { p.addLine(to: pt) }
        return p
    }

    func medianLength(_ i: Int) -> CGFloat {
        guard i < medians.count else { return 0 }
        return Geometry.length(medians[i])
    }
}

enum SVGPath {
    /// Parses the absolute M/L/Q/C/Z subset used by Make Me a Hanzi, flipping y (y' = 900 - y).
    static func parse(_ d: String) -> Path {
        var path = Path()
        var nums: [CGFloat] = []
        var cmd: Character = " "
        func pt(_ i: Int) -> CGPoint { CGPoint(x: nums[i], y: 900 - nums[i + 1]) }
        func flush() {
            switch cmd {
            case "M": if nums.count >= 2 { path.move(to: pt(0)) }
            case "L": if nums.count >= 2 { path.addLine(to: pt(0)) }
            case "Q": if nums.count >= 4 { path.addQuadCurve(to: pt(2), control: pt(0)) }
            case "C": if nums.count >= 6 { path.addCurve(to: pt(4), control1: pt(0), control2: pt(2)) }
            case "Z": path.closeSubpath()
            default: break
            }
            nums.removeAll(keepingCapacity: true)
        }
        var token = ""
        for ch in d {
            if ch.isLetter {
                if !token.isEmpty, let v = Double(token) { nums.append(CGFloat(v)) }
                token = ""
                flush()
                cmd = ch
            } else if ch == " " || ch == "," {
                if !token.isEmpty, let v = Double(token) { nums.append(CGFloat(v)) }
                token = ""
            } else {
                token.append(ch)
            }
        }
        if !token.isEmpty, let v = Double(token) { nums.append(CGFloat(v)) }
        flush()
        return path
    }
}

enum Geometry {
    static func length(_ pts: [CGPoint]) -> CGFloat {
        zip(pts, pts.dropFirst()).reduce(0) { $0 + hypot($1.1.x - $1.0.x, $1.1.y - $1.0.y) }
    }

    static func resample(_ pts: [CGPoint], count n: Int) -> [CGPoint] {
        guard pts.count > 1, n > 1 else { return pts.isEmpty ? [] : Array(repeating: pts[0], count: max(n, 1)) }
        let total = length(pts)
        guard total > 0 else { return Array(repeating: pts[0], count: n) }
        let step = total / CGFloat(n - 1)
        var out = [pts[0]]
        var acc: CGFloat = 0
        var prev = pts[0]
        var i = 1
        while i < pts.count && out.count < n {
            let cur = pts[i]
            let seg = hypot(cur.x - prev.x, cur.y - prev.y)
            if acc + seg >= step && seg > 0 {
                let t = (step - acc) / seg
                let q = CGPoint(x: prev.x + (cur.x - prev.x) * t, y: prev.y + (cur.y - prev.y) * t)
                out.append(q)
                prev = q
                acc = 0
            } else {
                acc += seg
                prev = cur
                i += 1
            }
        }
        while out.count < n { out.append(pts[pts.count - 1]) }
        return out
    }

    static func dist(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }

    /// Does a drawn stroke match the expected median? Both in the 1024 box.
    static func strokeMatches(drawn: [CGPoint], median: [CGPoint], leniency: CGFloat) -> Bool {
        guard drawn.count >= 2, median.count >= 2 else { return false }
        let mLen = length(median)
        let dLen = length(drawn)
        if dLen < 18 { return false }
        let a = resample(drawn, count: 20)
        let b = resample(median, count: 20)
        let avg = zip(a, b).reduce(0) { $0 + dist($1.0, $1.1) } / 20
        let start = dist(a[0], b[0])
        let end = dist(a[19], b[19])
        let ratio = dLen / max(mLen, 1)
        let short = mLen < 130
        let avgLimit: CGFloat = (short ? 170 : 140) * leniency
        let endLimit: CGFloat = (short ? 230 : 200) * leniency
        var directionOK = true
        if mLen > 60 {
            let dv = CGPoint(x: a[19].x - a[0].x, y: a[19].y - a[0].y)
            let mv = CGPoint(x: b[19].x - b[0].x, y: b[19].y - b[0].y)
            let dot = dv.x * mv.x + dv.y * mv.y
            let mag = max(hypot(dv.x, dv.y) * hypot(mv.x, mv.y), 0.001)
            directionOK = dot / mag > 0.3
        }
        let ratioOK = short ? ratio < 4 : (ratio > 0.35 && ratio < 2.6)
        return avg < avgLimit && start < endLimit && end < endLimit && directionOK && ratioOK
    }
}

/// Draws a character's strokes, optionally animating them in order.
struct StrokeCanvas: View {
    let strokes: CharacterStrokes
    var completed: Int
    var animating: Int? = nil
    var progress: CGFloat = 0
    var showOutline: Bool = true
    var highlight: Int? = nil
    var colorRadical: Bool = true

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width, size.height) / 1024
            ctx.translateBy(x: (size.width - 1024 * scale) / 2, y: (size.height - 1024 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            if showOutline {
                for p in strokes.paths { ctx.fill(p, with: .color(Ink.hairline)) }
            }
            for i in 0..<min(completed, strokes.count) {
                let color = colorRadical && strokes.radical.contains(i) ? Ink.seal : Ink.ink
                ctx.fill(strokes.paths[i], with: .color(color))
            }
            if let h = highlight, h < strokes.count {
                ctx.fill(strokes.paths[h], with: .color(Ink.seal))
            }
            if let k = animating, k < strokes.count {
                var c = ctx
                let reveal = strokes.medianPath(k).trimmedPath(from: 0, to: max(0.001, progress))
                    .strokedPath(StrokeStyle(lineWidth: 190, lineCap: .round, lineJoin: .round))
                c.clip(to: reveal)
                let color = colorRadical && strokes.radical.contains(k) ? Ink.seal : Ink.ink
                c.fill(strokes.paths[k], with: .color(color))
            }
        }
    }
}

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
