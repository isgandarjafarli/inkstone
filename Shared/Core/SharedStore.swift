import Foundation

/// Reads and writes the learner's progress in the App Group container, so the app and the
/// widgets see the same data.
enum SharedStore {
    static var groupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "InkstoneAppGroup") as? String) ?? "group.app.inkstone.hanzi7q4k"
    }

    static var containerURL: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) {
            return url
        }
        // Fallback (for example when signing has no App Group yet): the app's own folder.
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var stateURL: URL { containerURL.appendingPathComponent("progress.json") }
    static var backupURL: URL { containerURL.appendingPathComponent("progress.backup.json") }

    static var isSharedContainerAvailable: Bool {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) != nil
    }

    static func load() -> UserState {
        for url in [stateURL, backupURL] {
            if let data = try? Data(contentsOf: url),
               let state = try? JSONDecoder.inkstone.decode(UserState.self, from: data) {
                return state
            }
        }
        return UserState()
    }

    static func save(_ state: UserState) {
        do {
            let data = try JSONEncoder.inkstone.encode(state)
            if FileManager.default.fileExists(atPath: stateURL.path) {
                try? FileManager.default.removeItem(at: backupURL)
                try? FileManager.default.copyItem(at: stateURL, to: backupURL)
            }
            try data.write(to: stateURL, options: [.atomic])
        } catch {
            #if DEBUG
            print("Inkstone: could not save progress: \(error)")
            #endif
        }
    }
}

extension JSONEncoder {
    static var inkstone: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}

extension JSONDecoder {
    static var inkstone: JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
