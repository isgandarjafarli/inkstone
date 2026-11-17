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
                ForEach(Array(groups.enumerated()), id: \.offset) { _, group in
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.offset) { _, tok in
                            tokenView(tok)
                        }
                    }
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

    /// Tokens grouped so that closing punctuation stays on the line of the word before it.
    private var groups: [[SentenceToken]] {
        let opening: Set<Character> = ["“", "‘", "（", "(", "《", "「", "『", "【", "〈"]
        var out: [[SentenceToken]] = []
        for tok in sentence.tokens {
            let isClosingPunct = !tok.isHan && !tok.text.isEmpty
                && tok.text.allSatisfy { $0.isPunctuation || $0.isWhitespace }
                && !tok.text.contains(where: { opening.contains($0) })
            if isClosingPunct, !out.isEmpty {
                out[out.count - 1].append(tok)
            } else {
                out.append([tok])
            }
        }
        return out
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

    private struct Line { var items: [(index: Int, size: CGSize, x: CGFloat)] = []; var height: CGFloat = 0 }

    /// Measuring and placing both use this, so they always break lines in the same places.
    private func lines(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = [Line()]
        var x: CGFloat = 0
        for (i, v) in subviews.enumerated() {
            let s = v.sizeThatFits(.unspecified)
            if x > 0 && x + s.width > maxWidth + 0.5 {
                lines.append(Line())
                x = 0
            }
            lines[lines.count - 1].items.append((i, s, x))
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, s.height)
            x += s.width + spacing
        }
        return lines
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        let ls = lines(maxWidth: maxW, subviews: subviews)
        let widest = ls.map { l in l.items.last.map { $0.x + $0.size.width } ?? 0 }.max() ?? 0
        let height = ls.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(ls.count - 1, 0))
        return CGSize(width: min(widest, maxW), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        // Break with the width we were measured at, not the (possibly narrower) bounds.
        let maxW = max(proposal.width ?? bounds.width, bounds.width)
        var y = bounds.minY
        for line in lines(maxWidth: maxW, subviews: subviews) {
            // bottom-align items on a line so characters share a baseline
            for item in line.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: y + line.height - item.size.height),
                    proposal: ProposedViewSize(item.size))
            }
            y += line.height + lineSpacing
        }
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
