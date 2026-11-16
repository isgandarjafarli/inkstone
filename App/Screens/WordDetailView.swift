import SwiftUI

struct WordDetailView: View {
    @Environment(AppModel.self) private var model
    let wordID: Int
    @State private var confirmForget = false

    var body: some View {
        if let word = model.lexicon.word(wordID) {
            content(word)
        } else {
            ContentUnavailableView("Word not found", systemImage: "questionmark.square.dashed")
        }
    }

    private func content(_ word: Word) -> some View {
        let colored = model.state.settings.toneColors
        let syllabus = model.state.settings.syllabus
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Head
                VStack(spacing: 12) {
                    ToneHanzi(hanzi: word.s, pinyin: word.p, size: word.s.count > 3 ? 56 : 84, colored: model.state.settings.toneHanzi, relativeTo: .largeTitle)
                        .lineLimit(1).minimumScaleFactor(0.4)
                        .textSelection(.enabled)
                    PinyinText(pinyin: word.p, colored: colored, font: .title2.weight(.semibold))
                    HStack(spacing: 12) {
                        SpeakButton(text: word.s, size: 20)
                        SpeakButton(text: word.s, slow: true, size: 20)
                    }
                    HStack(spacing: 6) {
                        LevelBadge(level: word.displayLevel(in: syllabus))
                        if let t = word.t {
                            Text("Traditional \(t)")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Ink.well, in: Capsule())
                                .foregroundStyle(Ink.ink2)
                        }
                        ForEach(word.topics.prefix(2), id: \.self) { tid in
                            if let topic = model.lexicon.topics.first(where: { $0.id == tid }) {
                                Label(topic.title, systemImage: topic.symbol)
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(Ink.well, in: Capsule())
                                    .foregroundStyle(Ink.ink2)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Meaning
                VStack(alignment: .leading, spacing: 10) {
                    if let pos = word.pos, !pos.isEmpty {
                        Text(pos.joined(separator: " · ")).font(.caption.weight(.semibold)).textCase(.uppercase).tracking(0.5).foregroundStyle(Ink.ink3)
                    }
                    ForEach(Array(word.m.enumerated()), id: \.offset) { i, m in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("\(i + 1)").font(.footnote.weight(.semibold)).monospacedDigit().foregroundStyle(Ink.ink3)
                            Text(m).font(.body).foregroundStyle(Ink.ink).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let cl = word.cl, !cl.isEmpty {
                        Divider()
                        HStack(spacing: 8) {
                            Text("Measure word").font(.subheadline).foregroundStyle(Ink.ink2)
                            ForEach(cl, id: \.self) { c in
                                Text(c).font(Ink.hanzi(20))
                            }
                        }
                    }
                    if let alt = word.alt, !alt.isEmpty {
                        Divider()
                        ForEach(alt, id: \.p) { a in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("Also").font(.subheadline).foregroundStyle(Ink.ink3)
                                PinyinText(pinyin: a.p, colored: colored, font: .subheadline.weight(.semibold))
                                Text(a.m.joined(separator: "; ")).font(.subheadline).foregroundStyle(Ink.ink2)
                            }
                        }
                    }
                }
                .card()

                statusCard(word)

                // Sentences
                let sentences = model.lexicon.sentences(for: word)
                if !sentences.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "In a sentence", trailing: "Tap a word to look it up")
                        VStack(alignment: .leading, spacing: 18) {
                            ForEach(sentences) { s in
                                SentenceView(sentence: s, highlight: word.s)
                                if s.id != sentences.last?.id { Divider() }
                            }
                        }
                        .card()
                    }
                }

                // Characters
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeader(title: word.characters.count > 1 ? "Characters" : "Character")
                    VStack(spacing: 10) {
                        ForEach(Array(word.characters.enumerated()), id: \.offset) { _, c in
                            NavigationLink(value: CharRoute(char: c)) {
                                CharacterRow(char: c)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                Text("Sentences from Tatoeba (CC BY 2.0 FR). Definitions from CC-CEDICT.")
                    .font(.caption2).foregroundStyle(Ink.ink3)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle(word.s)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    model.toggleSaved(word.id)
                    Haptics.tap()
                } label: {
                    Image(systemName: model.isSaved(word.id) ? "bookmark.fill" : "bookmark")
                }
                .tint(Ink.seal)
                .accessibilityLabel(model.isSaved(word.id) ? "Remove from saved" : "Save word")
            }
        }
        .confirmationDialog("Reset this word?", isPresented: $confirmForget, titleVisibility: .visible) {
            Button("Reset progress for \(word.s)", role: .destructive) { model.forget(word.id) }
        } message: {
            Text("It will be treated as a new word again.")
        }
    }

    @ViewBuilder
    private func statusCard(_ word: Word) -> some View {
        let card = model.card(word.id)
        HStack(alignment: .center, spacing: 12) {
            StatusDot(status: model.status(word.id))
            VStack(alignment: .leading, spacing: 2) {
                if let c = card {
                    Text(c.mastered ? "Marked as known" : (c.isKnown ? "Known" : "Learning"))
                        .font(.subheadline.weight(.semibold))
                    Text(c.mastered ? "It will come back in about four months." : "Next review \(nextText(c.due)) · seen \(c.reps) time\(c.reps == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Ink.ink2)
                } else {
                    Text("Not learned yet").font(.subheadline.weight(.semibold))
                    Text("Add it to today's words, or skip it if you know it.").font(.caption).foregroundStyle(Ink.ink2)
                }
            }
            Spacer()
            Menu {
                if card == nil {
                    Button { model.startLearning(word.id) } label: { Label("Learn today", systemImage: "plus") }
                }
                if card?.mastered != true {
                    Button { model.markKnown(word.id) } label: { Label("I already know this", systemImage: "checkmark.seal") }
                }
                if card != nil {
                    Button(role: .destructive) { confirmForget = true } label: { Label("Reset this word", systemImage: "arrow.counterclockwise") }
                }
            } label: {
                Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Ink.ink2)
            }
            .accessibilityLabel("Word options")
        }
        .card(padding: 14)
    }

    private func nextText(_ due: Int) -> String {
        let d = due - model.today
        switch d {
        case ..<1: return "today"
        case 1: return "tomorrow"
        default: return "in \(FSRS.describe(days: d))"
        }
    }
}

struct CharRoute: Hashable { let char: String }

extension View {
    /// Registers the word and character destinations. Apply once at the root of each NavigationStack.
    func inkDestinations() -> some View {
        self
            .navigationDestination(for: Int.self) { WordDetailView(wordID: $0) }
            .navigationDestination(for: CharRoute.self) { CharacterDetailView(char: $0.char) }
    }
}

struct CharacterRow: View {
    @Environment(AppModel.self) private var model
    let char: String

    var body: some View {
        let info = model.lexicon.charInfo(char)
        HStack(spacing: 14) {
            ZStack {
                PracticeGrid()
                Text(char).font(Ink.hanziFixed(38)).foregroundStyle(Ink.ink)
            }
            .frame(width: 58, height: 58)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    PinyinText(pinyin: info?.p ?? "", colored: model.state.settings.toneColors, font: .headline)
                    if let n = info?.n { Text("\(n) strokes").font(.caption).foregroundStyle(Ink.ink3) }
                }
                Text(info?.m ?? "").font(.subheadline).foregroundStyle(Ink.ink2).lineLimit(2)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(Ink.ink3)
        }
        .card(padding: 12)
        .contentShape(Rectangle())
    }
}

struct CharacterDetailView: View {
    @Environment(AppModel.self) private var model
    let char: String
    @State private var playToken = 0
    @State private var practicing = false
    @State private var traceMode = true
    @State private var practiceID = 0
    @State private var practiceResult: Int?

    var body: some View {
        let info = model.lexicon.charInfo(char)
        let strokes = CharacterStrokes(character: char, data: model.lexicon.strokes(for: char))
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 14) {
                    Group {
                        if let strokes {
                            if practicing {
                                WritingPad(strokes: strokes, trace: traceMode) { misses in
                                    practiceResult = misses
                                    practicing = false
                                }
                                .id(practiceID)
                            } else {
                                ZStack {
                                    PracticeGrid()
                                    StrokePlayer(strokes: strokes, playToken: $playToken)
                                        .padding(6)
                                }
                            }
                        } else {
                            ZStack { PracticeGrid(); Text(char).font(Ink.hanziFixed(180)) }
                        }
                    }
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: 300)
                    .background(Ink.card)

                    if let r = practiceResult, !practicing {
                        Text(r == 0 ? "Every stroke right." : "Done, with \(r) slip\(r == 1 ? "" : "s").")
                            .font(.headline).foregroundStyle(r == 0 ? Ink.good : Ink.warn)
                    }
                    HStack(spacing: 10) {
                        Button {
                            practicing = false
                            playToken += 1
                        } label: { Label("Play strokes", systemImage: "play.fill") }
                        .buttonStyle(.bordered)
                        Button {
                            startPractice(trace: true)
                        } label: { Label("Trace it", systemImage: "pencil.tip") }
                        .buttonStyle(.borderedProminent)
                        Button {
                            startPractice(trace: false)
                        } label: { Label("From memory", systemImage: "eye.slash") }
                        .buttonStyle(.bordered)
                    }
                    .tint(Ink.seal)
                    .font(.subheadline.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                if let info {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            PinyinText(pinyin: info.p, colored: model.state.settings.toneColors, font: .title2.weight(.semibold))
                            SpeakButton(text: char, size: 16)
                            Spacer()
                            Text("\(info.n) strokes").font(.subheadline).foregroundStyle(Ink.ink2)
                        }
                        Text(info.m).font(.body)
                        if info.r != nil || info.c != nil { Divider() }
                        if let r = info.r {
                            HStack { Text("Radical").foregroundStyle(Ink.ink2); Spacer(); Text(r).font(Ink.hanzi(22)) }
                                .font(.subheadline)
                        }
                        if let c = info.c, c.count > 1 {
                            HStack { Text("Parts").foregroundStyle(Ink.ink2); Spacer(); Text(c.map(String.init).joined(separator: " + ")).font(Ink.hanzi(22)) }
                                .font(.subheadline)
                        }
                        if let e = info.etymologyText {
                            Text(e).font(.subheadline).foregroundStyle(Ink.ink2).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .card()
                }

                if let strokes {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Stroke order")
                        StrokeSteps(strokes: strokes).card(padding: 12)
                    }
                }

                let words = model.lexicon.wordsContaining(char, syllabus: model.state.settings.syllabus)
                if !words.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Words with \(char)")
                        VStack(spacing: 0) {
                            ForEach(words) { w in
                                NavigationLink(value: w.id) { WordRow(word: w) }
                                    .buttonStyle(.plain)
                                    .padding(.horizontal, 14).padding(.vertical, 4)
                            }
                        }
                        .padding(.vertical, 6)
                        .background(Ink.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                }
                Text("Stroke data from Make Me a Hanzi (Arphic Public License).")
                    .font(.caption2).foregroundStyle(Ink.ink3)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle(char)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { playToken += 1 }
    }

    private func startPractice(trace: Bool) {
        practiceResult = nil
        traceMode = trace
        practiceID += 1
        practicing = true
        Haptics.tap()
    }
}
