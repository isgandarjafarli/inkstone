import SwiftUI
import WidgetKit

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Binding var tab: Tab
    @State private var session: StudySession?
    @State private var showWidgetGuide = false
    @State private var hasLockWidget = true
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if let banner = model.banner {
                        bannerView(banner)
                    }
                    if let hero = heroWord {
                        NavigationLink(value: hero.id) { WordOfTheDayCard(word: hero) }
                            .buttonStyle(.plain)
                    }
                    sessionCard
                    if !hasLockWidget { widgetPromo }
                    if !model.todayWords.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            SectionHeader(title: "Today's words", trailing: "\(model.todayWords.count - model.newRemaining.count) of \(model.todayWords.count) learned")
                            VStack(spacing: 0) {
                                ForEach(model.todayWords) { w in
                                    NavigationLink(value: w.id) { WordRow(word: w, showLevel: false) }
                                        .buttonStyle(.plain)
                                        .padding(.horizontal, 16).padding(.vertical, 6)
                                    if w.id != model.todayWords.last?.id { Divider().padding(.leading, 74) }
                                }
                            }
                            .padding(.vertical, 6)
                            .background(Ink.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Ink.hairline, lineWidth: 0.5))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Ink.paper.ignoresSafeArea())
            .inkDestinations()
            .toolbar(.hidden, for: .navigationBar)
        }
        .fullScreenCover(item: $session) { s in
            SessionView(session: s)
        }
        .sheet(isPresented: $showWidgetGuide) { WidgetGuideView() }
        .task { await checkWidgets() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await checkWidgets() } }
        }
    }

    private var heroWord: Word? { model.newRemaining.first ?? model.todayWords.first }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(Date.now.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Ink.ink3)
                Text("Today")
                    .font(.largeTitle.bold())
                    .foregroundStyle(Ink.ink)
            }
            Spacer()
            StreakPill(days: model.streak, active: model.studiedToday)
        }
        .padding(.top, 12)
    }

    private func bannerView(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.up.forward.circle.fill").foregroundStyle(Ink.good)
            Text(text).font(.subheadline).foregroundStyle(Ink.ink)
            Spacer(minLength: 0)
            Button { model.banner = nil } label: { Image(systemName: "xmark").font(.caption.weight(.bold)) }
                .buttonStyle(.plain).foregroundStyle(Ink.ink3)
                .accessibilityLabel("Dismiss")
        }
        .card(padding: 14)
    }

    private var sessionCard: some View {
        let newLeft = model.newRemaining.count
        let due = model.dueCount
        let learnedToday = model.todayWords.count - newLeft
        return VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 0) {
                StatBlock(value: "\(newLeft)", label: newLeft == 1 ? "new word" : "new words", tint: Ink.seal)
                Divider().frame(height: 36)
                StatBlock(value: "\(due)", label: due == 1 ? "review due" : "reviews due", tint: Ink.ink)
                Divider().frame(height: 36)
                StatBlock(value: minutesEstimate(new: newLeft, due: due), label: "minutes", tint: Ink.ink2)
            }
            if newLeft + due > 0 {
                Button {
                    Haptics.tap()
                    session = StudySession(newWords: model.newRemaining, dueIDs: model.dueWordIDs, model: model)
                } label: {
                    Label(learnedToday == 0 && due == 0 ? "Start learning" : "Start session", systemImage: "play.fill")
                }
                .buttonStyle(InkButtonStyle())
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Done for today", systemImage: "checkmark.seal.fill")
                        .font(.headline)
                        .foregroundStyle(Ink.good)
                    Text("Your words will come back when they are due. You can keep going if you like.")
                        .font(.subheadline)
                        .foregroundStyle(Ink.ink2)
                    Button {
                        model.addMoreNewWords(model.state.settings.newPerDay)
                        Haptics.tap()
                    } label: {
                        Label("Learn \(model.state.settings.newPerDay) more", systemImage: "plus")
                    }
                    .buttonStyle(InkButtonStyle(prominent: false))
                }
            }
        }
        .card()
    }

    private func minutesEstimate(new: Int, due: Int) -> String {
        let secs = new * 50 + due * 12
        return secs == 0 ? "0" : "\(max(1, Int((Double(secs) / 60).rounded())))"
    }

    private var widgetPromo: some View {
        Button { showWidgetGuide = true } label: {
            HStack(spacing: 14) {
                LockScreenMini()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Put a word on your lock screen")
                        .font(.headline).foregroundStyle(Ink.ink)
                    Text("See it every time you check the time. Takes 20 seconds.")
                        .font(.subheadline).foregroundStyle(Ink.ink2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").foregroundStyle(Ink.ink3)
            }
            .card(padding: 14)
        }
        .buttonStyle(.plain)
    }

    private func checkWidgets() async {
        let configs = (try? await WidgetCenter.shared.currentConfigurations()) ?? []
        let lock = configs.contains { [.accessoryRectangular, .accessoryInline, .accessoryCircular].contains($0.family) }
        hasLockWidget = lock
    }
}

struct StatBlock: View {
    let value: String
    let label: String
    var tint: Color = Ink.ink

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
                .contentTransition(.numericText())
            Text(label)
                .font(.caption)
                .foregroundStyle(Ink.ink3)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

struct StreakPill: View {
    let days: Int
    let active: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundStyle(active ? Ink.seal : Ink.ink3)
                .symbolEffect(.bounce, value: active)
            Text("\(days)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(Ink.ink)
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Ink.card, in: Capsule())
        .overlay(Capsule().strokeBorder(Ink.hairline, lineWidth: 0.5))
        .accessibilityLabel("\(days) day streak\(active ? ", studied today" : "")")
    }
}

/// The large word card at the top of Today.
struct WordOfTheDayCard: View {
    @Environment(AppModel.self) private var model
    let word: Word

    var body: some View {
        let colored = model.state.settings.toneColors
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("WORD OF THE DAY")
                    .font(.caption.weight(.semibold))
                    .tracking(0.8)
                    .foregroundStyle(Ink.seal)
                Spacer()
                LevelBadge(level: word.displayLevel(in: model.state.settings.syllabus))
            }
            HStack(alignment: .center, spacing: 16) {
                ToneHanzi(hanzi: word.s, pinyin: word.p, size: word.s.count > 3 ? 46 : 64, colored: colored, relativeTo: .largeTitle)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Spacer(minLength: 0)
                SpeakButton(text: word.s, size: 22)
            }
            VStack(alignment: .leading, spacing: 4) {
                PinyinText(pinyin: word.p, colored: colored, font: .title3.weight(.semibold))
                Text(word.m.prefix(2).joined(separator: "; "))
                    .font(.body)
                    .foregroundStyle(Ink.ink)
                    .lineLimit(2)
            }
            if let s = model.lexicon.sentences(for: word).first {
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(s.zh).font(Ink.hanzi(19, relativeTo: .body)).foregroundStyle(Ink.ink)
                    Text(s.en).font(.subheadline).foregroundStyle(Ink.ink2).lineLimit(2)
                }
            }
        }
        .card(padding: 18)
        .contentShape(Rectangle())
    }
}

/// A tiny drawing of a lock screen with the rectangular widget.
struct LockScreenMini: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(LinearGradient(colors: [Ink.ink.opacity(0.85), Ink.ink2], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 3) {
                Text("9:41").font(.system(size: 13, weight: .semibold, design: .rounded)).foregroundStyle(Ink.paper)
                VStack(alignment: .leading, spacing: 0) {
                    Text("朋友").font(Ink.hanziFixed(10)).foregroundStyle(Ink.paper)
                    Text("péngyou").font(.system(size: 5)).foregroundStyle(Ink.paper.opacity(0.8))
                }
                .padding(3)
                .frame(width: 38, alignment: .leading)
                .background(Ink.paper.opacity(0.18), in: RoundedRectangle(cornerRadius: 4))
            }
            .padding(.top, 8)
        }
        .frame(width: 48, height: 72)
        .accessibilityHidden(true)
    }
}

/// Review tab: reviews only, plus extra practice.
struct ReviewTab: View {
    @Environment(AppModel.self) private var model
    @State private var session: StudySession?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Text("\(model.dueCount)")
                                .font(.system(size: 54, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                                .foregroundStyle(model.dueCount > 0 ? Ink.seal : Ink.ink3)
                            Text(model.dueCount == 1 ? "word to review" : "words to review")
                                .font(.title3).foregroundStyle(Ink.ink2)
                        }
                        Text(model.dueCount > 0
                             ? "Each word comes back just before you would forget it. Words you miss return later in the same session."
                             : "Nothing is due. New reviews appear as your words come due.")
                            .font(.subheadline).foregroundStyle(Ink.ink2)
                        if model.dueCount > 0 {
                            Button {
                                session = StudySession(newWords: [], dueIDs: model.dueWordIDs, model: model)
                            } label: { Label("Review now", systemImage: "play.fill") }
                                .buttonStyle(InkButtonStyle())
                        }
                        if extraPracticeIDs.count >= 4 {
                            Button {
                                session = StudySession(newWords: [], dueIDs: extraPracticeIDs, model: model)
                            } label: { Label("Extra practice (\(extraPracticeIDs.count) words)", systemImage: "dumbbell") }
                                .buttonStyle(InkButtonStyle(prominent: model.dueCount == 0))
                        }
                    }
                    .padding(.vertical, 6)
                }
                .listRowBackground(Ink.card)

                let upcoming = model.forecast(days: 7)
                Section("Coming up") {
                    ForEach(1..<7, id: \.self) { d in
                        HStack {
                            Text(d == 1 ? "Tomorrow" : StudyDay.date(for: model.today + d).formatted(.dateTime.weekday(.wide)))
                            Spacer()
                            Text("\(upcoming[d])").monospacedDigit().foregroundStyle(Ink.ink2)
                        }
                    }
                }
                .listRowBackground(Ink.card)

                if !model.dueWordIDs.isEmpty {
                    Section("Due now") {
                        ForEach(model.dueWordIDs.prefix(50), id: \.self) { id in
                            if let w = model.lexicon.word(id) {
                                NavigationLink(value: id) { WordRow(word: w) }
                            }
                        }
                    }
                    .listRowBackground(Ink.card)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle("Review")
            .inkDestinations()
        }
        .fullScreenCover(item: $session) { SessionView(session: $0) }
    }

    /// Words in learning that are not due, weakest first, for optional practice.
    private var extraPracticeIDs: [Int] {
        let due = Set(model.dueWordIDs)
        return model.state.cards.filter { !due.contains($0.key) && !$0.value.mastered && !$0.value.isKnown }
            .sorted { $0.value.stability < $1.value.stability }
            .prefix(20).map(\.key)
    }
}

extension StudySession: Identifiable {
    nonisolated var id: ObjectIdentifier { ObjectIdentifier(self) }
}
