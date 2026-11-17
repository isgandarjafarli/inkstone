import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

/// Receives the word lists from the iPhone and sends back what was done on the watch.
@MainActor
final class WatchSync: NSObject {
    static let shared = WatchSync()

    private weak var model: WatchModel?
    /// Background refresh tasks waiting for the phone's data to arrive.
    private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    func start(model: WatchModel?) {
        if let model { self.model = model }
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate == nil {
            session.delegate = self
            session.activate()
        } else if session.activationState == .activated {
            receive(session.receivedApplicationContext)
        }
    }

    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        pendingTasks.append(task)
        start(model: nil)
        completeTasksIfIdle()
    }

    func send(known: [Int]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([WatchMessage.known: known])
    }

    func send(reviews: [[Int]]) {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo([WatchMessage.reviews: reviews])
    }

    private func receive(_ context: [String: Any]) {
        guard let data = context[WatchMessage.feed] as? Data else { return }
        receive(data: data)
    }

    private func receive(data: Data) {
        guard let feed = try? JSONDecoder().decode(WatchFeed.self, from: data) else { return }
        if let model {
            if model.feed != feed { model.received(feed) }
        } else {
            // App not on screen (background refresh): store it for the complications.
            WatchStore.saveFeed(feed)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    private func completeTasksIfIdle() {
        guard WCSession.isSupported(), WCSession.default.activationState == .activated,
              !WCSession.default.hasContentPending else { return }
        for t in pendingTasks { t.setTaskCompletedWithSnapshot(false) }
        pendingTasks.removeAll()
    }
}

extension WatchSync: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
        let data = session.receivedApplicationContext[WatchMessage.feed] as? Data
        Task { @MainActor in
            if let data { self.receive(data: data) }
            self.completeTasksIfIdle()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        let data = applicationContext[WatchMessage.feed] as? Data
        Task { @MainActor in
            if let data { self.receive(data: data) }
            self.completeTasksIfIdle()
        }
    }
}
