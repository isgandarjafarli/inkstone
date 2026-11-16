import SwiftUI

@main
struct InkstoneApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.ensure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .task { await model.loadLexicon() }
                .onOpenURL { handle($0) }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.refresh()
                    case .background:
                        model.saveNow()
                        Task { await model.rescheduleReminders() }
                    default: break
                    }
                }
        }
    }

    /// Links used by the widgets: inkstone://word/123 opens that word, inkstone://review and
    /// inkstone://today switch tabs.
    private func handle(_ url: URL) {
        guard url.scheme == "inkstone" else { return }
        switch url.host {
        case "word":
            if let id = Int(url.lastPathComponent) { model.presentedWordID = id }
        case "review":
            model.presentedWordID = nil
            model.requestedTab = .review
        case "today":
            model.presentedWordID = nil
            model.requestedTab = .today
        default:
            break
        }
    }
}

enum Tab: Hashable { case today, review, library, progress }

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var tab: Tab = .today

    var body: some View {
        Group {
            if let err = model.loadError {
                ContentUnavailableView("Something went wrong", systemImage: "exclamationmark.triangle", description: Text(err))
            } else if !model.lexiconReady {
                LaunchView()
            } else {
                TabView(selection: $tab) {
                    TodayView(tab: $tab)
                        .tabItem { Label("Today", systemImage: "sun.horizon") }
                        .tag(Tab.today)
                    ReviewTab()
                        .tabItem { Label("Review", systemImage: "rectangle.stack") }
                        .badge(model.dueCount)
                        .tag(Tab.review)
                    LibraryView()
                        .tabItem { Label("Words", systemImage: "character.book.closed") }
                        .tag(Tab.library)
                    StatsView()
                        .tabItem { Label("Progress", systemImage: "chart.bar.xaxis") }
                        .tag(Tab.progress)
                }
                .tint(Ink.seal)
                .onAppear { applyRequestedTab() }
                .onChange(of: model.requestedTab) { _, _ in applyRequestedTab() }
                .fullScreenCover(isPresented: Binding(get: { !model.state.onboarded }, set: { _ in })) {
                    OnboardingView()
                }
                .sheet(item: Binding(get: { model.presentedWordID.map(IdentifiedInt.init) },
                                     set: { model.presentedWordID = $0?.id })) { item in
                    NavigationStack {
                        WordDetailView(wordID: item.id)
                            .inkDestinations()
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button("Done") { model.presentedWordID = nil }
                                }
                            }
                    }
                    .presentationDragIndicator(.visible)
                }
            }
        }
        .background(Ink.paper.ignoresSafeArea())
        #if DEBUG
        .fullScreenCover(item: Binding(get: { model.debugScreen.map(DebugRoute.init) }, set: { model.debugScreen = $0?.id })) {
            DebugScreenView(name: $0.id)
        }
        #endif
    }

    private func applyRequestedTab() {
        guard let t = model.requestedTab else { return }
        tab = t
        model.requestedTab = nil
    }
}

struct IdentifiedInt: Identifiable { let id: Int }

struct LaunchView: View {
    var body: some View {
        VStack(spacing: 18) {
            SealMark(size: 72)
            ProgressView().tint(Ink.ink3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Ink.paper.ignoresSafeArea())
    }
}
