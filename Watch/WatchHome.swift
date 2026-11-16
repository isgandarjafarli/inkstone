import SwiftUI

struct WatchHome: View {
    @Environment(WatchModel.self) private var model
    @State private var carouselStart: Int?
    @State private var showCarousel = false
    @State private var showWriting = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                currentWord
                NavigationLink {
                    ReviewView()
                } label: {
                    HStack {
                        Label("Review", systemImage: "rectangle.stack")
                        Spacer()
                        if model.dueCount > 0 {
                            Text("\(model.dueCount)").monospacedDigit().foregroundStyle(Ink.seal)
                        }
                    }
                }
                Button {
                    showWriting = true
                } label: {
                    Label("Write", systemImage: "pencil.line")
                }
                .disabled(model.writingItems.isEmpty)
                NavigationLink {
                    WatchSettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                if model.loaded && !model.hasPhoneData {
                    Text("Open Inkstone on your iPhone once to send your words here. Until then the watch shows HSK 1 words.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .listRowBackground(Color.clear)
                }
            }
            .navigationTitle("Inkstone")
            .navigationDestination(isPresented: $showCarousel) {
                CarouselView(startID: carouselStart)
            }
            .navigationDestination(isPresented: $model.openReview) {
                ReviewView()
            }
            .fullScreenCover(isPresented: $showWriting) {
                WriteView()
            }
            .onChange(of: model.openWordID) { _, id in
                guard let id else { return }
                carouselStart = id
                showCarousel = true
                model.openWordID = nil
            }
        }
    }

    @ViewBuilder private var currentWord: some View {
        if model.pool.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
        } else {
            let w = model.pool[min(model.currentIndex, model.pool.count - 1)]
            Button {
                carouselStart = w.id
                showCarousel = true
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    toneText(w.hanzi, pinyin: w.pinyin, colored: model.feed?.toneHanzi ?? true, base: .white)
                        .font(Ink.hanzi(w.hanzi.count <= 2 ? 40 : 28, relativeTo: .title))
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    PinyinText(pinyin: w.pinyin, colored: model.feed?.toneColors ?? true, font: .headline)
                        .lineLimit(1)
                    Text(w.meaning)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .listRowBackground(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(hex: 0x3A1E19)))
            .accessibilityLabel("\(w.hanzi), \(Pinyin.joined(w.pinyin)), \(w.meaning). Open words.")
        }
    }
}

/// Today's words, one per page. Turn the Digital Crown or swipe up to move on.
struct CarouselView: View {
    @Environment(WatchModel.self) private var model
    var startID: Int?
    @State private var selection = 0
    @State private var autoPlay = false

    var body: some View {
        TabView(selection: $selection) {
            ForEach(model.pool) { w in
                WordPage(word: w)
                    .tag(w.id)
            }
        }
        .tabViewStyle(.verticalPage)
        .containerBackground(Color(hex: 0x3A1E19).gradient, for: .tabView)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    autoPlay.toggle()
                } label: {
                    Image(systemName: autoPlay ? "pause.fill" : "play.fill")
                }
                .accessibilityLabel(autoPlay ? "Stop moving on by itself" : "Move on by itself")
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button {
                    if let w = current { model.speak(w.hanzi) }
                } label: {
                    Image(systemName: "speaker.wave.2.fill")
                }
                .accessibilityLabel("Say it")
                Spacer()
                Button {
                    guard let w = current else { return }
                    model.markKnown(w)
                    advance()
                } label: {
                    Image(systemName: "checkmark")
                }
                .tint(Ink.good)
                .accessibilityLabel("I know this word")
            }
        }
        .onAppear {
            if let startID, model.pool.contains(where: { $0.id == startID }) {
                selection = startID
            } else if !model.pool.isEmpty {
                selection = model.pool[min(model.currentIndex, model.pool.count - 1)].id
            }
        }
        .task(id: autoPlay) {
            guard autoPlay else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                if Task.isCancelled { break }
                advance()
            }
        }
    }

    private var current: WidgetWord? { model.pool.first { $0.id == selection } }

    private func advance() {
        guard let i = model.pool.firstIndex(where: { $0.id == selection }), !model.pool.isEmpty else { return }
        withAnimation { selection = model.pool[(i + 1) % model.pool.count].id }
    }
}

struct WordPage: View {
    @Environment(WatchModel.self) private var model
    let word: WidgetWord

    var body: some View {
        VStack(spacing: 4) {
            Spacer(minLength: 0)
            toneText(word.hanzi, pinyin: word.pinyin, colored: model.feed?.toneHanzi ?? true, base: .white)
                .font(Ink.hanzi(size, relativeTo: .largeTitle))
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .onTapGesture { model.speak(word.hanzi) }
            PinyinText(pinyin: word.pinyin, colored: model.feed?.toneColors ?? true, font: .system(size: 18, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(word.meaning)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
            if model.done.contains(word.id) {
                Label("Known", systemImage: "checkmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Ink.good)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }

    private var size: CGFloat {
        switch word.hanzi.count {
        case 1: return 68
        case 2: return 56
        case 3: return 42
        case 4: return 34
        default: return 26
        }
    }
}
