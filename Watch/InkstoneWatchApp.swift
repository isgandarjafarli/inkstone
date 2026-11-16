import SwiftUI
import WatchKit

@main
struct InkstoneWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate
    @State private var model = WatchModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        FontRegistry.ensure()
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(model)
                .tint(Ink.seal)
                .task {
                    #if DEBUG
                    if WatchScreenshots.isActive { WatchScreenshots.apply(to: model); return }
                    #endif
                    WatchSync.shared.start(model: model)
                    model.reload()
                }
                .onOpenURL { handle($0) }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { model.reload() }
                }
        }
    }

    @ViewBuilder private var root: some View {
        #if DEBUG
        if let screen = model.debugScreen {
            WatchDebugScreen(name: screen)
        } else {
            WatchHome()
        }
        #else
        WatchHome()
        #endif
    }

    /// Complication taps: inkstone://word/123 opens that word, inkstone://review the reviews.
    private func handle(_ url: URL) {
        guard url.scheme == "inkstone" else { return }
        switch url.host {
        case "word": model.openWordID = Int(url.lastPathComponent)
        case "review": model.openReview = true
        default: break
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let t = task as? WKWatchConnectivityRefreshBackgroundTask {
                Task { @MainActor in WatchSync.shared.handle(t) }
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
