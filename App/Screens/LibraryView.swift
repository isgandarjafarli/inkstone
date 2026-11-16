import SwiftUI

struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var section: Section = .levels

    enum Section: String, CaseIterable { case levels = "Levels", topics = "Topics", saved = "Saved" }

    var body: some View {
        NavigationStack {
            Group {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    browse
                } else {
                    results
                }
            }
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle("Words")
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "汉字, pinyin or English")
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .inkDestinations()
            .navigationDestination(for: LevelRoute.self) { WordListView(title: Syllabus.levelName($0.level), words: model.lexicon.words(level: $0.level, syllabus: model.state.settings.syllabus)) }
            .navigationDestination(for: TopicRoute.self) { r in
                WordListView(title: r.title, words: model.lexicon.words(topic: r.id, syllabus: model.state.settings.syllabus, maxLevel: 7))
            }
        }
    }

    private var browse: some View {
        List {
            Picker("Show", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))

            switch section {
            case .levels: levels
            case .topics: topics
            case .saved: saved
            }
        }
        .scrollContentBackground(.hidden)
    }

    @ViewBuilder
    private var levels: some View {
        let syllabus = model.state.settings.syllabus
        SwiftUI.Section {
            ForEach(syllabus.levels, id: \.self) { lv in
                let p = model.levelProgress(lv)
                NavigationLink(value: LevelRoute(level: lv)) {
                    HStack(spacing: 14) {
                        Text(lv >= 7 ? "7–9" : "\(lv)")
                            .font(.system(.title3, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(lv == model.state.settings.level ? Color.white : Ink.ink)
                            .frame(width: 44, height: 44)
                            .background(lv == model.state.settings.level ? Ink.seal : Ink.well, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(Syllabus.levelName(lv)).font(.headline)
                                if lv == model.state.settings.level {
                                    Text("Your level").font(.caption2.weight(.semibold)).foregroundStyle(Ink.seal)
                                }
                                Spacer()
                                Text("\(p.known + p.learning) / \(p.total)").font(.subheadline).monospacedDigit().foregroundStyle(Ink.ink2)
                            }
                            SegmentBar(known: p.known, learning: p.learning, total: p.total)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            Text(syllabus.title)
        } footer: {
            Text("Change the word list in Progress → Settings.")
        }
        .listRowBackground(Ink.card)
    }

    @ViewBuilder
    private var topics: some View {
        SwiftUI.Section {
            ForEach(model.lexicon.topics) { t in
                NavigationLink(value: TopicRoute(id: t.id, title: t.title)) {
                    Label {
                        Text(t.title)
                    } icon: {
                        Image(systemName: t.symbol).foregroundStyle(Ink.seal)
                    }
                }
            }
        } footer: {
            Text("Topics are grouped automatically from each word's meaning, so a few words land in surprising places.")
        }
        .listRowBackground(Ink.card)
    }

    @ViewBuilder
    private var saved: some View {
        let ids = model.state.lists.first?.wordIDs ?? []
        if ids.isEmpty {
            SwiftUI.Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Nothing saved yet", systemImage: "bookmark").font(.headline)
                    Text("Tap the bookmark on any word to keep it here. Saved words can also rotate on your widget.")
                        .font(.subheadline).foregroundStyle(Ink.ink2)
                }
                .padding(.vertical, 6)
            }
            .listRowBackground(Ink.card)
        } else {
            SwiftUI.Section("\(ids.count) saved") {
                ForEach(ids, id: \.self) { id in
                    if let w = model.lexicon.word(id) {
                        NavigationLink(value: id) { WordRow(word: w) }
                            .swipeActions {
                                Button(role: .destructive) { model.toggleSaved(id) } label: { Label("Remove", systemImage: "bookmark.slash") }
                            }
                    }
                }
            }
            .listRowBackground(Ink.card)
        }
    }

    private var results: some View {
        let hits = model.lexicon.search(query, syllabus: model.state.settings.syllabus)
        return List {
            if hits.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                ForEach(hits) { w in
                    NavigationLink(value: w.id) { WordRow(word: w) }
                }
                .listRowBackground(Ink.card)
            }
        }
        .scrollContentBackground(.hidden)
    }
}

struct LevelRoute: Hashable { let level: Int }
struct TopicRoute: Hashable { let id: String; let title: String }

struct SegmentBar: View {
    let known: Int
    let learning: Int
    let total: Int

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let t = CGFloat(max(total, 1))
            HStack(spacing: 0) {
                Rectangle().fill(Ink.good).frame(width: w * CGFloat(known) / t)
                Rectangle().fill(Ink.warn).frame(width: w * CGFloat(learning) / t)
                Rectangle().fill(Ink.well)
            }
            .clipShape(Capsule())
        }
        .frame(height: 6)
        .accessibilityElement()
        .accessibilityLabel("\(known) known, \(learning) learning, of \(total)")
    }
}

struct WordListView: View {
    @Environment(AppModel.self) private var model
    let title: String
    let words: [Word]
    @State private var filter: Filter = .all

    enum Filter: String, CaseIterable { case all = "All", new = "New", learning = "Learning", known = "Known" }

    var body: some View {
        let shown = words.filter { w in
            switch filter {
            case .all: return true
            case .new: return model.status(w.id) == .new
            case .learning: return model.status(w.id) == .learning
            case .known: return model.status(w.id) == .known
            }
        }
        List {
            Picker("Filter", selection: $filter) {
                ForEach(Filter.allCases, id: \.self) { Text($0.rawValue) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            SwiftUI.Section("\(shown.count) words") {
                ForEach(shown) { w in
                    NavigationLink(value: w.id) { WordRow(word: w, showLevel: false) }
                        .swipeActions(edge: .trailing) {
                            if model.status(w.id) == .new {
                                Button { model.startLearning(w.id) } label: { Label("Learn", systemImage: "plus") }.tint(Ink.seal)
                                Button { model.markKnown(w.id) } label: { Label("Know it", systemImage: "checkmark") }.tint(Ink.good)
                            }
                        }
                }
            }
            .listRowBackground(Ink.card)
        }
        .scrollContentBackground(.hidden)
        .background(Ink.paper.ignoresSafeArea())
        .navigationTitle(title)
    }
}
