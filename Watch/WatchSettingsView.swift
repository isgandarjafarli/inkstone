import SwiftUI

struct WatchSettingsView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        List {
            Section {
                Picker("Words", selection: binding(\.source)) {
                    ForEach(WidgetSource.allCases, id: \.self) { s in
                        Text(s.title).tag(s)
                    }
                }
                Picker("New word every", selection: binding(\.interval)) {
                    ForEach(WatchPrefs.intervals, id: \.self) { m in
                        Text(m >= 60 ? "hour" : "\(m) minutes").tag(m)
                    }
                }
                Toggle("Pinyin", isOn: binding(\.showPinyin))
                Toggle("Meaning", isOn: binding(\.showMeaning))
                Button("Show the next word now") { model.nextOnWatchFace() }
            } header: {
                Text("Watch face")
            } footer: {
                Text("Add \(AppInfo.name) to a watch face: touch and hold the face, tap Edit, swipe to the complications and choose \(AppInfo.name).")
            }
            Section {
                Text(model.hasPhoneData
                     ? "Your words come from \(AppInfo.name) on your iPhone. Reviews and \"I know it\" taps go back to it."
                     : "Open \(AppInfo.name) on your iPhone to send your words here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }

    private func binding<T>(_ key: WritableKeyPath<WatchPrefs, T>) -> Binding<T> {
        Binding(get: { model.prefs[keyPath: key] }, set: { v in model.update { $0[keyPath: key] = v } })
    }
}
