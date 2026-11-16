import SwiftUI
#if canImport(CoreText)
import CoreText
#endif

/// Paper-and-ink palette. One cinnabar accent (the seal), tone colours, everything else neutral.
enum Ink {
    static let paper = Color(light: 0xF3F4F0, dark: 0x0E100F)       // page
    static let card = Color(light: 0xFFFFFF, dark: 0x191C1A)        // raised surface
    static let well = Color(light: 0xE9EBE6, dark: 0x232724)        // inset surface, chips
    static let ink = Color(light: 0x161A18, dark: 0xECEEEA)         // primary text
    static let ink2 = Color(light: 0x56605B, dark: 0xA3ACA7)        // secondary text
    static let ink3 = Color(light: 0x8C948F, dark: 0x6F7873)        // tertiary
    static let hairline = Color(light: 0xDCE0DA, dark: 0x2C312E)
    static let seal = Color(light: 0xC23A2B, dark: 0xE8624F)        // cinnabar accent
    static let sealSoft = Color(light: 0xF6E2DE, dark: 0x3A1E19)
    static let good = Color(light: 0x2F8A5B, dark: 0x5CC48E)
    static let warn = Color(light: 0xB7791F, dark: 0xE2AE55)

    static func tone(_ t: Int) -> Color {
        switch t {
        case 1: return Color(light: 0x2F6FD0, dark: 0x6EA3F0)
        case 2: return Color(light: 0x2A9163, dark: 0x5CC992)
        case 3: return Color(light: 0xB57A0C, dark: 0xE5B04B)
        case 4: return Color(light: 0x8A4FD0, dark: 0xB58CF0)
        default: return Color(light: 0x7E8782, dark: 0x8D9691)
        }
    }

    static let fontName = "LXGWWenKai-Regular"

    /// Brush-style Chinese font, scaling with Dynamic Type.
    static func hanzi(_ size: CGFloat, relativeTo style: Font.TextStyle = .body) -> Font {
        FontRegistry.ensure()
        return .custom(fontName, size: size, relativeTo: style)
    }

    /// Fixed-size brush font (for widgets and large display characters that must not reflow).
    static func hanziFixed(_ size: CGFloat) -> Font {
        FontRegistry.ensure()
        return .custom(fontName, fixedSize: size)
    }
}

enum FontRegistry {
    private static let once: Void = {
        #if canImport(CoreText)
        let bundles = [Bundle.main] + Bundle.allBundles
        for b in bundles {
            if let url = b.url(forResource: "LXGWWenKai-Inkstone", withExtension: "ttf") {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
                break
            }
        }
        #endif
    }()

    static func ensure() { _ = once }
}

extension Color {
    init(hex v: UInt32) {
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    init(light: UInt32, dark: UInt32) {
        #if os(watchOS)
        // The watch is always dark.
        self.init(hex: dark)
        #else
        self.init(uiColor: UIColor { trait in
            let v = trait.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((v >> 16) & 0xFF) / 255,
                           green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: 1)
        })
        #endif
    }
}

/// Characters as one Text, each in its syllable's tone colour (or `base` when colouring is off
/// or the pinyin does not line up with the characters).
func toneText(_ hanzi: String, pinyin: String, colored: Bool, base: Color = Ink.ink) -> Text {
    let chars = Array(hanzi)
    let syl = Pinyin.syllables(pinyin)
    let canColor = colored && chars.count == syl.count
    return chars.enumerated().reduce(Text("")) { acc, item in
        let color = canColor ? Ink.tone(Pinyin.tone(of: syl[item.offset])) : base
        return acc + Text(String(item.element)).foregroundColor(color)
    }
}

/// The tone colour of each character of a word, or nil where it cannot be told.
func toneColorList(_ hanzi: String, pinyin: String) -> [Color?] {
    let chars = Array(hanzi)
    let syl = Pinyin.syllables(pinyin)
    guard chars.count == syl.count else { return chars.map { _ in nil } }
    return syl.map { Ink.tone(Pinyin.tone(of: $0)) }
}

/// Pinyin with each syllable coloured by tone. A word's syllables are written together
/// ("péngyou", "Xī'ān"), the way dictionaries print them.
struct PinyinText: View {
    let pinyin: String
    var colored: Bool = true
    var font: Font = .body
    var joined: Bool = true

    var body: some View {
        let syllables = Pinyin.syllables(pinyin)
        syllables.enumerated().reduce(Text("")) { acc, item in
            let (i, syl) = item
            let piece = Text(syl).foregroundColor(colored ? Ink.tone(Pinyin.tone(of: syl)) : Ink.ink2)
            if i == 0 { return acc + piece }
            let gap = joined ? (Pinyin.needsApostrophe(syl) ? "'" : "") : " "
            return acc + Text(gap).foregroundColor(Ink.ink3) + piece
        }
        .font(font)
        .accessibilityLabel(Pinyin.joined(pinyin))
    }
}

/// Chinese text where each character takes the colour of its syllable's tone.
struct ToneHanzi: View {
    let hanzi: String
    let pinyin: String
    var size: CGFloat
    var colored: Bool = true
    var relativeTo: Font.TextStyle = .title

    var body: some View {
        toneText(hanzi, pinyin: pinyin, colored: colored)
            .font(Ink.hanzi(size, relativeTo: relativeTo))
    }
}

/// The square red seal used as the app's mark.
struct SealMark: View {
    var text: String = "砚"
    var size: CGFloat = 34

    var body: some View {
        Text(text)
            .font(Ink.hanziFixed(size * 0.62))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Ink.seal, in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
            .rotationEffect(.degrees(-3))
            .accessibilityHidden(true)
    }
}

/// Dashed 米字格 practice grid.
struct PracticeGrid: View {
    var color: Color = Ink.seal

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            var p = Path()
            p.move(to: CGPoint(x: r.midX, y: 0)); p.addLine(to: CGPoint(x: r.midX, y: r.maxY))
            p.move(to: CGPoint(x: 0, y: r.midY)); p.addLine(to: CGPoint(x: r.maxX, y: r.midY))
            p.move(to: .zero); p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
            p.move(to: CGPoint(x: r.maxX, y: 0)); p.addLine(to: CGPoint(x: 0, y: r.maxY))
            ctx.stroke(p, with: .color(color.opacity(0.22)), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
            ctx.stroke(Path(r.insetBy(dx: 0.75, dy: 0.75)), with: .color(color.opacity(0.55)), lineWidth: 1.5)
        }
        .accessibilityHidden(true)
    }
}

extension View {
    /// Standard raised card.
    func card(padding: CGFloat = 16) -> some View {
        self.padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 0.5))
    }
}

struct LevelBadge: View {
    let level: Int
    var body: some View {
        Text(level >= 7 ? "HSK 7–9" : "HSK \(level)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(Ink.well, in: Capsule())
            .foregroundStyle(Ink.ink2)
    }
}
