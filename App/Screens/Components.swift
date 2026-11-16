import SwiftUI

struct SpeakButton: View {
    let text: String
    var slow: Bool = false
    var size: CGFloat = 20
    @ObservedObject private var speech = Speech.shared

    var body: some View {
        Button {
            Haptics.tap()
            speech.speak(text, slow: slow)
        } label: {
            Image(systemName: slow ? "tortoise.fill" : (speech.speakingText == text ? "speaker.wave.3.fill" : "speaker.wave.2.fill"))
                .font(.system(size: size * 0.8, weight: .semibold))
                .foregroundStyle(Ink.seal)
                .frame(width: size * 2, height: size * 2)
                .background(Ink.sealSoft, in: Circle())
                .symbolEffect(.variableColor.iterative, isActive: speech.speakingText == text && !slow)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(slow ? "Play slowly" : "Play pronunciation")
    }
}

struct StatusDot: View {
    let status: AppModel.WordStatus
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(Ink.hairline, lineWidth: status == .new ? 1 : 0))
            .accessibilityLabel(label)
    }
    var color: Color {
        switch status {
        case .new: return .clear
        case .learning: return Ink.warn
        case .known: return Ink.good
        }
    }
    var label: String {
        switch status {
        case .new: return "Not learned yet"
        case .learning: return "Learning"
        case .known: return "Known"
        }
    }
}

struct WordRow: View {
    @Environment(AppModel.self) private var model
    let word: Word
    var showLevel = true

    var body: some View {
        HStack(spacing: 14) {
            ToneHanzi(hanzi: word.s, pinyin: word.p, size: 26, colored: model.state.settings.toneHanzi, relativeTo: .title2)
                .lineLimit(1)
                .frame(minWidth: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                PinyinText(pinyin: word.p, colored: model.state.settings.toneColors, font: .subheadline.weight(.medium))
                Text(word.m.joined(separator: "; "))
                    .font(.subheadline)
                    .foregroundStyle(Ink.ink2)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if showLevel { LevelBadge(level: word.displayLevel(in: model.state.settings.syllabus)) }
            StatusDot(status: model.status(word.id))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// An example sentence. Each word is tappable and opens a small card for it.
struct SentenceView: View {
    @Environment(AppModel.self) private var model
    let sentence: Sentence
    var highlight: String? = nil
    var showPinyin = true
    var showEnglish = true
    @State private var tapped: Word?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 2, lineSpacing: 6) {
                ForEach(Array(sentence.tokens.enumerated()), id: \.offset) { _, tok in
                    tokenView(tok)
                }
            }
            if showEnglish {
                Text(sentence.en)
                    .font(.subheadline)
                    .foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                SpeakButton(text: sentence.zh, size: 14)
                SpeakButton(text: sentence.zh, slow: true, size: 14)
                Spacer()
            }
        }
        .sheet(item: $tapped) { w in
            WordPeekSheet(word: w)
        }
    }

    @ViewBuilder
    private func tokenView(_ tok: SentenceToken) -> some View {
        let isTarget = highlight != nil && tok.text == highlight
        let word = tok.wordID > 0 ? model.lexicon.word(tok.wordID) : model.lexicon.word(hanzi: tok.text)
        VStack(spacing: 0) {
            if showPinyin && tok.isHan {
                PinyinText(pinyin: tok.pinyin, colored: model.state.settings.toneColors, font: .caption2)
                    .lineLimit(1)
                    .fixedSize()
            }
            Text(tok.text)
                .font(Ink.hanzi(22, relativeTo: .title3))
                .foregroundStyle(isTarget ? Ink.seal : Ink.ink)
                .underline(word != nil && !isTarget, color: Ink.hairline)
        }
        .padding(.horizontal, tok.isHan ? 1 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            if let word, tok.isHan { Haptics.tap(); tapped = word }
        }
        .accessibilityLabel(tok.text)
        .accessibilityHint(word != nil ? "Shows this word" : "")
    }
}

/// Sheet shown when a word inside a sentence is tapped: a short card that can open the full word
/// in place (so it also works inside a study session).
struct WordPeekSheet: View {
    let word: Word
    @State private var path = NavigationPath()
    @State private var detent: PresentationDetent = .height(280)

    var body: some View {
        NavigationStack(path: $path) {
            MiniWordCard(word: word) { path.append(word.id) }
                .toolbar(.hidden, for: .navigationBar)
                .inkDestinations()
        }
        .presentationDetents([.height(280), .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .onChange(of: path.count) { _, n in
            withAnimation { detent = n > 0 ? .large : .height(280) }
        }
    }
}

/// The short card inside `WordPeekSheet`.
struct MiniWordCard: View {
    @Environment(AppModel.self) private var model
    let word: Word
    var onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                ToneHanzi(hanzi: word.s, pinyin: word.p, size: 44, colored: model.state.settings.toneHanzi, relativeTo: .largeTitle)
                VStack(alignment: .leading, spacing: 2) {
                    PinyinText(pinyin: word.p, colored: model.state.settings.toneColors, font: .title3.weight(.semibold))
                    LevelBadge(level: word.displayLevel(in: model.state.settings.syllabus))
                }
                Spacer()
                SpeakButton(text: word.s)
            }
            Text(word.m.joined(separator: "; "))
                .font(.body)
                .foregroundStyle(Ink.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button {
                    model.toggleSaved(word.id)
                    Haptics.tap()
                } label: {
                    Label(model.isSaved(word.id) ? "Saved" : "Save", systemImage: model.isSaved(word.id) ? "bookmark.fill" : "bookmark")
                }
                .buttonStyle(.bordered)
                Spacer()
                Button("Open word", action: onOpen)
                .buttonStyle(.borderedProminent)
            }
            .tint(Ink.seal)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Ink.paper)
    }
}

/// Wraps children onto multiple lines, like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, widest: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxW {
                y += lineH + lineSpacing
                x = 0
                lineH = 0
            }
            x += s.width + spacing
            lineH = max(lineH, s.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: min(widest, maxW), height: y + lineH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineH: CGFloat = 0
        // bottom-align items on a line so characters share a baseline
        var line: [(LayoutSubview, CGSize, CGFloat)] = []
        func flush() {
            for (v, s, lx) in line {
                v.place(at: CGPoint(x: lx, y: y + lineH - s.height), proposal: ProposedViewSize(s))
            }
            line.removeAll()
        }
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX && x + s.width > bounds.maxX {
                flush()
                y += lineH + lineSpacing
                x = bounds.minX
                lineH = 0
            }
            line.append((v, s, x))
            x += s.width + spacing
            lineH = max(lineH, s.height)
        }
        flush()
    }
}

/// Primary call-to-action button style.
struct InkButtonStyle: ButtonStyle {
    var prominent = true
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .foregroundStyle(prominent ? Color.white : Ink.ink)
            .background(prominent ? Ink.seal : Ink.well, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var trailing: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .textCase(.uppercase)
                .tracking(0.6)
                .foregroundStyle(Ink.ink3)
            Spacer()
            if let trailing { Text(trailing).font(.footnote).foregroundStyle(Ink.ink3) }
        }
        .padding(.horizontal, 4)
    }
}
