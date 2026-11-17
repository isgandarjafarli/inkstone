import Foundation
import WatchConnectivity

/// Keeps the Apple Watch app up to date and applies what the learner does on the watch.
/// The phone sends a small `WatchFeed` as application context (only the latest one matters);
/// the watch sends back "I know it" taps and reviews as queued user-info transfers.
@MainActor
final class WatchLink: NSObject {
    static let shared = WatchLink()

    private weak var model: AppModel?
    private var lastSent: Data?
    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    func start(model: AppModel) {
        self.model = model
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    /// Sends the current state if the watch app is installed and something changed.
    func update() {
        guard let model, model.lexiconReady, let session, session.activationState == .activated,
              session.isPaired, session.isWatchAppInstalled else { return }
        let feed = WatchFeed(state: model.state, today: model.today,
                             upcomingIDs: model.upcomingNewWords(limit: 40).map(\.id))
        guard let data = try? JSONEncoder().encode(feed), data != lastSent else { return }
        do {
            try session.updateApplicationContext([WatchMessage.feed: data])
            lastSent = data
        } catch {
            #if DEBUG
            print("\(AppInfo.name): could not update the watch: \(error)")
            #endif
        }
    }

    private func apply(known: [Int], reviews: [[Int]]) {
        guard let model else { return }
        model.applyFromWatch(known: known, reviews: reviews)
        update()
    }
}

extension WatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        Task { @MainActor in self.lastSent = nil; self.update() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // The user switched to another watch: start talking to the new one.
        session.activate()
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.lastSent = nil; self.update() }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        let known = userInfo[WatchMessage.known] as? [Int] ?? []
        let reviews = userInfo[WatchMessage.reviews] as? [[Int]] ?? []
        Task { @MainActor in self.apply(known: known, reviews: reviews) }
    }
}
