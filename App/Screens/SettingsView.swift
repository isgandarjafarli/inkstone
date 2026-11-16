import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showWidgetGuide = false
    @State private var importing = false
    @State private var importMessage: String?
    @State private var notificationsDenied = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    Picker("Word list", selection: $model.settings.syllabus) {
                        ForEach(Syllabus.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("My level", selection: $model.settings.level) {
                        ForEach(model.settings.syllabus.levels, id: \.self) { Text(Syllabus.levelName($0)).tag($0) }
                    }
                    Stepper(value: $model.settings.newPerDay, in: 1...30) {
                        LabeledContent("New words a day", value: "\(model.settings.newPerDay)")
                    }
                    Picker("Reviews a day", selection: $model.settings.reviewCap) {
                        Text("50").tag(50); Text("100").tag(100); Text("200").tag(200); Text("No limit").tag(0)
                    }
                    NavigationLink {
                        TopicPicker()
                    } label: {
                        LabeledContent("Topics", value: model.settings.topics.isEmpty ? "All" : "\(model.settings.topics.count) chosen")
                    }
                } header: {
                    Text("Learning")
                } footer: {
                    Text("HSK 2026 is the list used by the current exam. Changing level or topics refreshes the words you have not learned yet today.")
                }

                Section("Practice") {
                    Toggle("Colour pinyin by tone", isOn: $model.settings.toneColors)
                    Toggle("Colour characters by tone", isOn: $model.settings.toneHanzi)
                    Toggle("Show pinyin before answering", isOn: $model.settings.showPinyinFirst)
                    Toggle("Handwriting questions", isOn: $model.settings.writingPractice)
                    Toggle("Listening questions", isOn: $model.settings.listeningQuiz)
                    VStack(alignment: .leading) {
                        Text("Speaking speed")
                        Slider(value: $model.settings.speechRate, in: 0.3...0.55) {
                            Text("Speaking speed")
                        } minimumValueLabel: { Image(systemName: "tortoise") } maximumValueLabel: { Image(systemName: "hare") }
                    }
                    Button("Test voice") { Speech.shared.speak("你好，我们一起学习中文吧。") }
                    Toggle("Haptics", isOn: $model.settings.haptics)
                    Picker("Memory target", selection: $model.settings.retention) {
                        Text("85% (fewer reviews)").tag(0.85)
                        Text("90% (recommended)").tag(0.9)
                        Text("95% (more reviews)").tag(0.95)
                    }
                }

                Section {
                    Toggle("Daily reminder", isOn: Binding(
                        get: { model.settings.reminderOn },
                        set: { on in
                            if on {
                                Task {
                                    let ok = await Reminders.requestPermission()
                                    notificationsDenied = !ok
                                    model.settings.reminderOn = ok
                                }
                            } else {
                                model.settings.reminderOn = false
                            }
                        }))
                    if model.settings.reminderOn {
                        DatePicker("Time", selection: reminderTime, displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminder")
                } footer: {
                    if notificationsDenied {
                        Text("Notifications are turned off for Inkstone. Turn them on in the iPhone Settings app.")
                    } else {
                        Text("Each reminder names a word from your plan for that day.")
                    }
                }

                Section("Widgets") {
                    Button { showWidgetGuide = true } label: {
                        Label("Add to lock screen or home screen", systemImage: "lock.iphone")
                    }
                    if !SharedStore.isSharedContainerAvailable {
                        Text("Widgets cannot see your progress yet: the App Group is not set up in Xcode's Signing & Capabilities. See the install guide.")
                            .font(.footnote).foregroundStyle(Ink.warn)
                    }
                }

                Section("Your data") {
                    ShareLink(item: ProgressExport(data: model.exportData()), preview: SharePreview("Inkstone progress")) {
                        Label("Export progress", systemImage: "square.and.arrow.up")
                    }
                    Button { importing = true } label: { Label("Import progress", systemImage: "square.and.arrow.down") }
                    if let importMessage { Text(importMessage).font(.footnote).foregroundStyle(Ink.ink2) }
                    Button(role: .destructive) { confirmReset = true } label: { Label("Reset all progress", systemImage: "trash") }
                }

                Section {
                    NavigationLink("About and data sources") { AboutView() }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.bold() } }
            .confirmationDialog("Reset all progress?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Reset everything", role: .destructive) { model.resetProgress() }
            } message: {
                Text("Every word goes back to new and your streak is cleared. Settings are kept. This cannot be undone.")
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let access = url.startAccessingSecurityScopedResource()
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url), model.importData(data) {
                    importMessage = "Progress imported."
                } else {
                    importMessage = "That file is not an Inkstone export."
                }
            }
            .sheet(isPresented: $showWidgetGuide) { WidgetGuideView() }
        }
        .tint(Ink.seal)
    }

    private var reminderTime: Binding<Date> {
        Binding(
            get: {
                Calendar.current.date(bySettingHour: model.settings.reminderHour, minute: model.settings.reminderMinute, second: 0, of: Date()) ?? Date()
            },
            set: { d in
                let c = Calendar.current.dateComponents([.hour, .minute], from: d)
                var s = model.settings
                s.reminderHour = c.hour ?? 9
                s.reminderMinute = c.minute ?? 0
                model.settings = s
            })
    }
}

struct ProgressExport: Transferable {
    let data: Data
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { $0.data }
            .suggestedFileName("Inkstone-progress.json")
    }
}

struct TopicPicker: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            Section {
                Button {
                    var s = model.settings; s.topics = []; model.settings = s
                } label: {
                    HStack { Text("All topics"); Spacer(); if model.settings.topics.isEmpty { Image(systemName: "checkmark") } }
                }
            } footer: {
                Text("New words come from the chosen topics first, then from the rest of your level.")
            }
            Section {
                ForEach(model.lexicon.topics) { t in
                    Button {
                        var s = model.settings
                        if let i = s.topics.firstIndex(of: t.id) { s.topics.remove(at: i) } else { s.topics.append(t.id) }
                        model.settings = s
                    } label: {
                        HStack {
                            Label(t.title, systemImage: t.symbol)
                            Spacer()
                            if model.settings.topics.contains(t.id) { Image(systemName: "checkmark") }
                        }
                    }
                }
            }
        }
        .foregroundStyle(Ink.ink)
        .tint(Ink.seal)
        .navigationTitle("Topics")
    }
}

struct WidgetGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("A new word every time you look at your phone.")
                        .font(.title2.bold())
                    GuideStep(n: 1, title: "Lock screen", lines: [
                        "Lock your iPhone, then press and hold an empty part of the lock screen.",
                        "Tap Customize, then Lock Screen.",
                        "Tap the box under the clock, find Inkstone, and pick the wide widget (word, pinyin and meaning).",
                        "Want it above the clock too? Tap the date line and choose Inkstone.",
                    ])
                    GuideStep(n: 2, title: "Home screen", lines: [
                        "Press and hold an empty area of the home screen until icons jiggle.",
                        "Tap Edit, then Add Widget, and search for Inkstone.",
                        "The medium size shows an example sentence and has Next and \"I know it\" buttons.",
                    ])
                    GuideStep(n: 3, title: "Choose what it shows", lines: [
                        "Press and hold the widget, then tap Edit Widget.",
                        "Pick the words (smart mix, today's words, words you are learning, your level, or saved words), how often it changes, and whether to show pinyin and meaning.",
                    ])
                    GuideStep(n: 4, title: "StandBy", lines: [
                        "Charging on its side at night? The small widget works in StandBy too.",
                    ])
                    Text("Tapping a widget opens exactly the word it shows.")
                        .font(.subheadline).foregroundStyle(Ink.ink2)
                }
                .padding(20)
            }
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle("Add a widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() }.bold() } }
        }
        .tint(Ink.seal)
    }
}

struct GuideStep: View {
    let n: Int
    let title: String
    let lines: [String]

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)")
                .font(.headline).foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(Ink.seal, in: Circle())
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.headline)
                ForEach(lines, id: \.self) { l in
                    Text(l).font(.body).foregroundStyle(Ink.ink2).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .card()
    }
}

struct AboutView: View {
    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    SealMark(size: 48)
                    VStack(alignment: .leading) {
                        Text("Inkstone").font(.title3.bold())
                        Text("Free and offline. No account, no ads, no tracking.").font(.subheadline).foregroundStyle(Ink.ink2)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Data sources") {
                source("HSK word lists", "complete-hsk-vocabulary by drkameleon, MIT licence", "https://github.com/drkameleon/complete-hsk-vocabulary")
                source("Definitions", "CC-CEDICT, CC BY-SA 4.0", "https://cc-cedict.org/wiki/")
                source("Example sentences", "Tatoeba, CC BY 2.0 FR", "https://tatoeba.org")
                source("Stroke order and character data", "Make Me a Hanzi: graphics under the Arphic Public License, dictionary under LGPL", "https://github.com/skishore/makemeahanzi")
                source("Chinese font", "LXGW WenKai, SIL Open Font License 1.1", "https://github.com/lxgw/LxgwWenKai")
                source("Scheduling", "FSRS, the open spaced-repetition algorithm", "https://github.com/open-spaced-repetition")
            }
            Section {
                Text("Pronunciation uses the Mandarin voice built into iOS. For a more natural voice, download an enhanced Chinese voice in Settings → Accessibility → Spoken Content → Voices → Chinese.")
                    .font(.footnote).foregroundStyle(Ink.ink2)
            }
        }
        .navigationTitle("About")
    }

    private func source(_ title: String, _ detail: String, _ url: String) -> some View {
        Link(destination: URL(string: url)!) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).foregroundStyle(Ink.ink)
                Text(detail).font(.caption).foregroundStyle(Ink.ink2)
            }
        }
    }
}
