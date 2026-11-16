import SwiftUI

struct SessionView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let session: StudySession
    @State private var confirmQuit = false

    var body: some View {
        VStack(spacing: 0) {
            topBar
            if session.finished {
                SessionSummary(session: session) { finish() }
            } else if let item = session.current, let word = model.lexicon.word(item.wordID) {
                QuizItemView(item: item, word: word, session: session)
                    .id(item.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            } else {
                Color.clear.onAppear { session.skip() }
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: session.position)
        .background(Ink.paper.ignoresSafeArea())
        .confirmationDialog("End this session?", isPresented: $confirmQuit, titleVisibility: .visible) {
            Button("End session", role: .destructive) { session.end() }
            Button("Keep going", role: .cancel) {}
        } message: {
            Text("Answers so far are saved.")
        }
    }

    private var topBar: some View {
        HStack(spacing: 14) {
            Button {
                if session.finished || session.result.answered == 0 { finish() } else { confirmQuit = true }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Ink.ink2)
                    .frame(width: 36, height: 36)
                    .background(Ink.well, in: Circle())
            }
            .accessibilityLabel("Close")
            ProgressBar(value: session.progress)
            Text("\(min(session.position + 1, session.total))/\(session.total)")
                .font(.footnote.weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(Ink.ink3)
                .frame(minWidth: 44, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func finish() {
        model.addStudyTime(seconds: Int(Date().timeIntervalSince(session.started)))
        dismiss()
    }
}

struct ProgressBar: View {
    let value: Double
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Ink.well)
                Capsule().fill(Ink.seal).frame(width: max(8, geo.size.width * value))
                    .animation(.easeOut(duration: 0.3), value: value)
            }
        }
        .frame(height: 8)
        .accessibilityElement()
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

// MARK: - One item

struct QuizItemView: View {
    @Environment(AppModel.self) private var model
    let item: SessionItem
    let word: Word
    let session: StudySession

    @State private var options: [Word] = []
    @State private var toneOptions: [String] = []
    @State private var chosen: Int?
    @State private var revealed = false
    @State private var writingIndex = 0
    @State private var writingMisses = 0
    @State private var hintToken = 0
    @State private var writingDone = false

    private var colored: Bool { model.state.settings.toneColors }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 22) {
                    Text(item.isRetry ? "Try again" : item.kind.title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(item.isRetry ? Ink.seal : Ink.ink3)
                        .padding(.top, 8)
                    content
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            footer
        }
        .onAppear(perform: setUp)
    }

    // MARK: setup

    private func setUp() {
        switch item.kind {
        case .meaningChoice, .wordChoice, .listening:
            options = (model.lexicon.distractors(for: word, syllabus: model.state.settings.syllabus) + [word]).shuffled()
        case .tones:
            toneOptions = Self.toneVariants(word.p)
        default: break
        }
        if item.kind == .learn || item.kind == .listening {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { Speech.shared.speak(word.s) }
        }
    }

    static func toneVariants(_ pinyin: String) -> [String] {
        let syl = Pinyin.syllables(pinyin)
        func withTone(_ s: String, _ t: Int) -> String {
            let base = s.folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
            let umlaut = s.contains { "üǖǘǚǜ".contains($0) }
            return ToneMarker.mark(base, tone: t, keepUmlaut: umlaut)
        }
        var set: [String] = [pinyin]
        var tries = 0
        while set.count < 4 && tries < 60 {
            tries += 1
            let variant = syl.map { s -> String in
                Bool.random() || syl.count == 1 ? withTone(s, Int.random(in: 1...4)) : s
            }.joined(separator: " ")
            if !set.contains(variant) { set.append(variant) }
        }
        return set.shuffled()
    }

    // MARK: content

    @ViewBuilder
    private var content: some View {
        switch item.kind {
        case .learn: learnContent
        case .meaningChoice: meaningChoice
        case .wordChoice: wordChoice
        case .listening: listening
        case .tones: tones
        case .recall: recall
        case .writing: writing
        }
    }

    private var bigWord: some View {
        VStack(spacing: 10) {
            ToneHanzi(hanzi: word.s, pinyin: word.p, size: word.s.count > 3 ? 54 : 76, colored: colored && revealed, relativeTo: .largeTitle)
                .lineLimit(1).minimumScaleFactor(0.4)
            if revealed || model.state.settings.showPinyinFirst {
                PinyinText(pinyin: word.p, colored: colored, font: .title2.weight(.semibold))
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var learnContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 10) {
                ToneHanzi(hanzi: word.s, pinyin: word.p, size: word.s.count > 3 ? 54 : 80, colored: colored, relativeTo: .largeTitle)
                    .lineLimit(1).minimumScaleFactor(0.4)
                PinyinText(pinyin: word.p, colored: colored, font: .title2.weight(.semibold))
                HStack(spacing: 12) {
                    SpeakButton(text: word.s, size: 20)
                    SpeakButton(text: word.s, slow: true, size: 20)
                }
            }
            .frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 6) {
                if let pos = word.pos, !pos.isEmpty {
                    Text(pos.joined(separator: " · ")).font(.caption.weight(.semibold)).foregroundStyle(Ink.ink3).textCase(.uppercase)
                }
                Text(word.m.joined(separator: "; ")).font(.title3).foregroundStyle(Ink.ink)
                if let cl = word.cl, !cl.isEmpty {
                    Text("Measure word: \(cl.joined(separator: ", "))").font(.subheadline).foregroundStyle(Ink.ink2)
                }
            }
            .card()
            if let s = model.lexicon.sentences(for: word).first {
                SentenceView(sentence: s, highlight: word.s).card()
            }
            if word.characters.count > 1 {
                HStack(spacing: 10) {
                    ForEach(word.characters, id: \.self) { c in
                        VStack(spacing: 4) {
                            Text(c).font(Ink.hanzi(30))
                            Text(model.lexicon.charInfo(c)?.m.components(separatedBy: ";").first ?? "")
                                .font(.caption).foregroundStyle(Ink.ink2).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                }
            }
        }
    }

    private var meaningChoice: some View {
        VStack(spacing: 18) {
            bigWord
            VStack(spacing: 10) {
                ForEach(Array(options.enumerated()), id: \.element.id) { i, o in
                    ChoiceButton(state: choiceState(i), action: { choose(i) }) {
                        Text(o.m.prefix(2).joined(separator: "; "))
                            .font(.body)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            if revealed { revealExtras }
        }
    }

    private var wordChoice: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(word.m.prefix(2).joined(separator: "; "))
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Ink.ink)
                if revealed { PinyinText(pinyin: word.p, colored: colored, font: .title3) }
            }
            .padding(.vertical, 24)
            optionGrid
            if revealed { revealExtras }
        }
    }

    private var listening: some View {
        VStack(spacing: 18) {
            Button { Speech.shared.speak(word.s) } label: {
                Image(systemName: "speaker.wave.3.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(Ink.seal)
                    .frame(width: 110, height: 110)
                    .background(Ink.sealSoft, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.vertical, 18)
            .accessibilityLabel("Play again")
            Button("Play slowly") { Speech.shared.speak(word.s, slow: true) }
                .font(.subheadline.weight(.semibold)).tint(Ink.seal)
            optionGrid
            if revealed { revealExtras }
        }
    }

    private var optionGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(Array(options.enumerated()), id: \.element.id) { i, o in
                ChoiceButton(state: choiceState(i), action: { choose(i) }) {
                    VStack(spacing: 4) {
                        Text(o.s).font(Ink.hanzi(o.s.count > 3 ? 24 : 32, relativeTo: .title))
                            .lineLimit(1).minimumScaleFactor(0.5)
                        if revealed {
                            Text(Pinyin.joined(o.p)).font(.caption).foregroundStyle(Ink.ink2)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
        }
    }

    private var tones: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text(word.s).font(Ink.hanzi(word.s.count > 3 ? 54 : 76, relativeTo: .largeTitle)).lineLimit(1).minimumScaleFactor(0.4)
                Text(word.m.first ?? "").font(.body).foregroundStyle(Ink.ink2)
            }
            .padding(.vertical, 14)
            VStack(spacing: 10) {
                ForEach(Array(toneOptions.enumerated()), id: \.offset) { i, p in
                    ChoiceButton(state: toneState(i), action: { chooseTone(i) }) {
                        PinyinText(pinyin: p, colored: revealed && colored, font: .title3.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            if revealed {
                SpeakButton(text: word.s)
                revealExtras
            }
        }
    }

    private var recall: some View {
        VStack(spacing: 18) {
            bigWord
            if revealed {
                VStack(alignment: .leading, spacing: 10) {
                    Text(word.m.joined(separator: "; ")).font(.title3).foregroundStyle(Ink.ink)
                    HStack { SpeakButton(text: word.s); Spacer() }
                }
                .card()
                if let s = model.lexicon.sentences(for: word).first {
                    SentenceView(sentence: s, highlight: word.s).card()
                }
            } else {
                Text("Say it out loud and think of the meaning, then check.")
                    .font(.subheadline).foregroundStyle(Ink.ink3).multilineTextAlignment(.center)
            }
        }
    }

    private var writing: some View {
        let chars = word.characters
        let current = chars.indices.contains(writingIndex) ? chars[writingIndex] : chars.last ?? word.s
        return VStack(spacing: 14) {
            VStack(spacing: 6) {
                Text(word.m.prefix(2).joined(separator: "; ")).font(.title3.weight(.semibold)).multilineTextAlignment(.center)
                PinyinText(pinyin: word.p, colored: colored, font: .title3)
                if chars.count > 1 {
                    HStack(spacing: 6) {
                        ForEach(Array(chars.enumerated()), id: \.offset) { i, c in
                            Text(i < writingIndex || writingDone ? c : "？")
                                .font(Ink.hanzi(26))
                                .foregroundStyle(i == writingIndex && !writingDone ? Ink.seal : Ink.ink)
                        }
                    }
                }
            }
            if let strokes = CharacterStrokes(character: current, data: model.lexicon.strokes(for: current)) {
                if writingDone {
                    ZStack {
                        PracticeGrid()
                        StrokeCanvas(strokes: strokes, completed: strokes.count, showOutline: false)
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 320)
                } else {
                    WritingPad(strokes: strokes, trace: (model.card(word.id)?.reps ?? 0) < 4, hintRequest: hintToken) { misses in
                        writingMisses += misses
                        if writingIndex + 1 < chars.count {
                            writingIndex += 1
                        } else {
                            writingDone = true
                            revealed = true
                            Speech.shared.speak(word.s)
                        }
                    }
                    .id(writingIndex)
                    .frame(maxWidth: 320)
                    .background(Ink.card)
                }
            } else {
                Text(current).font(Ink.hanzi(120))
                    .onAppear { writingDone = true; revealed = true }
            }
            if writingDone {
                Text(writingMisses == 0 ? "Perfect strokes." : "\(writingMisses) slip\(writingMisses == 1 ? "" : "s").")
                    .font(.headline).foregroundStyle(writingMisses == 0 ? Ink.good : Ink.warn)
            }
        }
    }

    private var revealExtras: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(word.s).font(Ink.hanzi(28))
                PinyinText(pinyin: word.p, colored: colored, font: .headline)
                Spacer()
                SpeakButton(text: word.s, size: 16)
            }
            Text(word.m.joined(separator: "; ")).font(.subheadline).foregroundStyle(Ink.ink2)
        }
        .card(padding: 14)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    // MARK: answering

    private var isCorrect: Bool {
        switch item.kind {
        case .tones: return chosen.map { toneOptions[$0] == word.p } ?? false
        case .meaningChoice, .wordChoice, .listening: return chosen.map { options[$0].id == word.id } ?? false
        default: return true
        }
    }

    private func choiceState(_ i: Int) -> ChoiceState {
        guard revealed else { return .idle }
        if options[i].id == word.id { return .correct }
        if chosen == i { return .wrong }
        return .dimmed
    }

    private func toneState(_ i: Int) -> ChoiceState {
        guard revealed else { return .idle }
        if toneOptions[i] == word.p { return .correct }
        if chosen == i { return .wrong }
        return .dimmed
    }

    private func choose(_ i: Int) {
        guard !revealed else { return }
        chosen = i
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        if options[i].id == word.id { Haptics.success() } else { Haptics.error() }
        if item.kind != .listening { Speech.shared.speak(word.s) }
    }

    private func chooseTone(_ i: Int) {
        guard !revealed else { return }
        chosen = i
        withAnimation(.easeOut(duration: 0.2)) { revealed = true }
        if toneOptions[i] == word.p { Haptics.success() } else { Haptics.error() }
        Speech.shared.speak(word.s)
    }

    // MARK: footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            switch item.kind {
            case .learn:
                Button { session.acknowledgeLearn() } label: { Text("Got it") }
                    .buttonStyle(InkButtonStyle())
            case .recall:
                if revealed {
                    GradeButtons(card: model.card(word.id), today: model.today, fsrs: model.fsrs) { g in
                        session.answer(g, model: model)
                    }
                } else {
                    Button { withAnimation { revealed = true }; Speech.shared.speak(word.s) } label: { Text("Show answer") }
                        .buttonStyle(InkButtonStyle())
                }
            case .writing:
                if writingDone {
                    Button {
                        session.answer(writingMisses == 0 ? .good : (writingMisses <= 3 ? .hard : .again), model: model)
                    } label: { Text("Continue") }
                        .buttonStyle(InkButtonStyle())
                } else {
                    HStack(spacing: 10) {
                        Button { hintToken += 1 } label: { Label("Hint", systemImage: "lightbulb") }
                            .buttonStyle(InkButtonStyle(prominent: false))
                        Button {
                            writingMisses += 5
                            writingDone = true
                            revealed = true
                        } label: { Text("Show me") }
                            .buttonStyle(InkButtonStyle(prominent: false))
                    }
                }
            default:
                if revealed {
                    HStack(spacing: 10) {
                        Image(systemName: isCorrect ? "checkmark.circle.fill" : "xmark.circle.fill")
                        Text(isCorrect ? "Correct" : "Not quite. It will come back soon.")
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundStyle(isCorrect ? Ink.good : Ink.tone(4))
                    Button { session.answer(isCorrect ? .good : .again, model: model) } label: { Text("Continue") }
                        .buttonStyle(InkButtonStyle())
                } else {
                    Button("I don't know") {
                        chosen = nil
                        withAnimation { revealed = true }
                        Speech.shared.speak(word.s)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Ink.ink3)
                    .padding(.vertical, 8)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(Ink.paper)
    }
}

enum ToneMarker {
    /// Puts tone `t` on a toneless syllable ("hao" + 3 -> "hǎo").
    static func mark(_ base: String, tone t: Int, keepUmlaut: Bool) -> String {
        var s = base.lowercased()
        if keepUmlaut { s = s.replacingOccurrences(of: "u", with: "ü", options: [], range: s.range(of: "u", options: .backwards)) }
        let table: [Character: String] = ["a": "āáǎà", "e": "ēéěè", "i": "īíǐì", "o": "ōóǒò", "u": "ūúǔù", "ü": "ǖǘǚǜ"]
        let chars = Array(s)
        var idx: Int?
        if let a = chars.firstIndex(of: "a") { idx = a }
        else if let e = chars.firstIndex(of: "e") { idx = e }
        else if let o = s.range(of: "ou").map({ s.distance(from: s.startIndex, to: $0.lowerBound) }) { idx = o }
        else { idx = chars.lastIndex(where: { "iouü".contains($0) }) }
        guard let i = idx, let marks = table[chars[i]], (1...4).contains(t) else { return s }
        var out = chars
        out[i] = Array(marks)[t - 1]
        let result = String(out)
        return base.first?.isUppercase == true ? result.prefix(1).uppercased() + result.dropFirst() : result
    }
}

enum ChoiceState { case idle, correct, wrong, dimmed }

struct ChoiceButton<Label: View>: View {
    let state: ChoiceState
    let action: () -> Void
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button(action: action) {
            label()
                .padding(.horizontal, 16).padding(.vertical, 14)
                .foregroundStyle(state == .dimmed ? Ink.ink3 : Ink.ink)
                .background(background, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(border, lineWidth: state == .idle ? 0.5 : 2))
        }
        .buttonStyle(.plain)
        .disabled(state != .idle)
        .animation(.easeOut(duration: 0.15), value: state)
    }

    private var background: Color {
        switch state {
        case .correct: return Ink.good.opacity(0.12)
        case .wrong: return Ink.tone(4).opacity(0.12)
        default: return Ink.card
        }
    }

    private var border: Color {
        switch state {
        case .correct: return Ink.good
        case .wrong: return Ink.tone(4)
        default: return Ink.hairline
        }
    }
}

struct GradeButtons: View {
    let card: CardState?
    let today: Int
    let fsrs: FSRS
    let onGrade: (Grade) -> Void

    var body: some View {
        let preview = fsrs.preview(card, today: today)
        HStack(spacing: 8) {
            ForEach(Grade.allCases, id: \.self) { g in
                Button {
                    if g == .again { Haptics.error() } else { Haptics.tap() }
                    onGrade(g)
                } label: {
                    VStack(spacing: 3) {
                        Text(g.label).font(.subheadline.weight(.semibold))
                        Text(FSRS.describe(days: preview[g] ?? 0))
                            .font(.caption2).monospacedDigit().opacity(0.75)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .foregroundStyle(color(g))
                    .background(color(g).opacity(0.12), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func color(_ g: Grade) -> Color {
        switch g {
        case .again: return Ink.tone(4)
        case .hard: return Ink.warn
        case .good: return Ink.good
        case .easy: return Ink.tone(1)
        }
    }
}

struct SessionSummary: View {
    @Environment(AppModel.self) private var model
    let session: StudySession
    let onDone: () -> Void

    var body: some View {
        let r = session.result
        ScrollView {
            VStack(spacing: 22) {
                SealMark(text: r.missed.isEmpty ? "好" : "成", size: 84)
                    .padding(.top, 30)
                Text(r.answered == 0 ? "See you next time" : "Session complete")
                    .font(.title.bold())
                HStack(spacing: 0) {
                    StatBlock(value: "\(r.learned.count)", label: "learned", tint: Ink.seal)
                    StatBlock(value: "\(r.reviewed.count)", label: "reviewed")
                    StatBlock(value: r.answered > 0 ? "\(Int((Double(r.firstTryCorrect) / Double(max(1, r.learned.count + r.reviewed.count)) * 100).rounded()))%" : "–",
                              label: "first try")
                }
                .card()
                if !r.learned.isEmpty {
                    wordList(title: "New words", ids: r.learned)
                }
                if !r.missed.isEmpty {
                    wordList(title: "Worth another look", ids: r.missed)
                }
                Button("Done", action: onDone).buttonStyle(InkButtonStyle())
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 30)
        }
        .onAppear { Haptics.success() }
    }

    private func wordList(title: String, ids: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: title)
            VStack(spacing: 0) {
                ForEach(ids, id: \.self) { id in
                    if let w = model.lexicon.word(id) {
                        WordRow(word: w, showLevel: false).padding(.horizontal, 14).padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, 6)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}
