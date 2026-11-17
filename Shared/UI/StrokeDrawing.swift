import SwiftUI

// Stroke geometry and drawing, shared by the iPhone app and the watch.

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
    var outlineColor: Color = Ink.hairline
    var inkColor: Color = Ink.ink

    var body: some View {
        Canvas { ctx, size in
            let scale = min(size.width, size.height) / 1024
            ctx.translateBy(x: (size.width - 1024 * scale) / 2, y: (size.height - 1024 * scale) / 2)
            ctx.scaleBy(x: scale, y: scale)
            if showOutline {
                for p in strokes.paths { ctx.fill(p, with: .color(outlineColor)) }
            }
            for i in 0..<min(completed, strokes.count) {
                let color = colorRadical && strokes.radical.contains(i) ? Ink.seal : inkColor
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
                let color = colorRadical && strokes.radical.contains(k) ? Ink.seal : inkColor
                c.fill(strokes.paths[k], with: .color(color))
            }
        }
    }
}
