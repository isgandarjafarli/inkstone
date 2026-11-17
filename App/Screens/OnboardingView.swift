import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var syllabus: Syllabus = .hsk2026
    @State private var level = 1
    @State private var perDay = 5
    @State private var reminderTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    @State private var showGuide = false
    @State private var checking = false

    private let steps = 5

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                ForEach(0..<steps, id: \.self) { i in
                    Capsule().fill(i <= step ? Ink.seal : Ink.well).frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .opacity(step == 0 ? 0 : 1)

            Group {
                switch step {
                case 0: welcome
                case 1: levelStep
                case 2: goalStep
                case 3: widgetStep
                default: reminderStep
                }
            }
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity), removal: .move(edge: .leading).combined(with: .opacity)))
            .id(step)
        }
        .animation(.spring(response: 0.42, dampingFraction: 0.9), value: step)
        .background(Ink.paper.ignoresSafeArea())
        .sheet(isPresented: $showGuide) { WidgetGuideView() }
        #if DEBUG
        .onAppear { if let s = ScreenshotMode.onboardingStep { step = s } }
        #endif
        .sheet(isPresented: $checking) {
            LevelCheckView(syllabus: syllabus) { suggested in
                if let suggested { level = suggested }
                checking = false
            }
        }
    }

    // MARK: steps

    private var welcome: some View {
        VStack(spacing: 14) {
            // Centred when it fits; scrolls on small phones or with large text, never cut off.
            ViewThatFits(in: .vertical) {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    welcomeContent
                    Spacer(minLength: 0)
                }
                ScrollView {
                    welcomeContent.padding(.vertical, 12)
                }
            }
            Button("Get started") { next() }.buttonStyle(InkButtonStyle())
            Text("Free, offline, no account.").font(.footnote).foregroundStyle(Ink.ink3)
        }
        .padding(24)
    }

    private var welcomeContent: some View {
        VStack(spacing: 26) {
            SealMark(size: 96)
            VStack(spacing: 10) {
                Text(AppInfo.name).font(.largeTitle.bold())
                Text("Learn Chinese one word a day, with the word waiting on your lock screen.")
                    .font(.title3).foregroundStyle(Ink.ink2).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 16) {
                feature("lock.iphone", "Words on your lock screen", "A new HSK word whenever you check the time.")
                feature("rectangle.stack", "Reviews that adapt to you", "Words return just before you would forget them.")
                feature("pencil.tip", "Stroke order and handwriting", "Watch each character drawn, then write it yourself.")
                feature("text.quote", "Real sentences, tap any word", "Thousands of example sentences with pinyin.")
            }
            .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity)
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol).font(.title3).foregroundStyle(Ink.seal).frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.subheadline).foregroundStyle(Ink.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var levelStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Where are you starting?").font(.title.bold()).padding(.top, 24)
            Picker("Word list", selection: $syllabus) {
                Text("HSK 2026").tag(Syllabus.hsk2026)
                Text("HSK 3.0").tag(Syllabus.hsk30)
                Text("HSK 2.0").tag(Syllabus.hsk20)
            }
            .pickerStyle(.segmented)
            .onChange(of: syllabus) { _, s in if !s.levels.contains(level) { level = s.levels.last ?? 1 } }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(syllabus.levels, id: \.self) { lv in
                        Button { level = lv; Haptics.tap() } label: { levelCard(lv) }
                            .buttonStyle(.plain)
                    }
                }
            }
            Button { checking = true } label: {
                Label("Not sure? Take a one-minute check", systemImage: "questionmark.circle")
                    .font(.subheadline.weight(.semibold))
            }
            .tint(Ink.seal)
            Button("Continue") { next() }.buttonStyle(InkButtonStyle())
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func levelCard(_ lv: Int) -> some View {
        let words = model.lexicon.words(level: lv, syllabus: syllabus)
        let sample = words.prefix(5).map(\.s).joined(separator: " ")
        let selected = lv == level
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Syllabus.levelName(lv)).font(.headline)
                    Text(Self.levelBlurb(lv)).font(.subheadline).foregroundStyle(Ink.ink2)
                }
                Text(sample).font(Ink.hanzi(18)).foregroundStyle(Ink.ink2).lineLimit(1)
            }
            Spacer()
            Text("\(words.count)").font(.subheadline).monospacedDigit().foregroundStyle(Ink.ink3)
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.title3).foregroundStyle(selected ? Ink.seal : Ink.hairline)
        }
        .padding(14)
        .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Ink.seal : Ink.hairline, lineWidth: selected ? 2 : 0.5))
    }

    static func levelBlurb(_ lv: Int) -> String {
        switch lv {
        case 1: return "Complete beginner"
        case 2: return "Basics"
        case 3: return "Everyday topics"
        case 4: return "Comfortable"
        case 5: return "Upper intermediate"
        case 6: return "Advanced"
        default: return "Near fluent"
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How many new words a day?").font(.title.bold()).padding(.top, 24)
            Text("Reviews of earlier words come on top. You can change this any time.")
                .font(.subheadline).foregroundStyle(Ink.ink2)
            VStack(spacing: 10) {
                goal(3, "Easy", "about 3 minutes a day")
                goal(5, "Steady", "about 5 minutes a day")
                goal(10, "Serious", "about 10 minutes a day")
                goal(15, "Intense", "about 15 minutes a day")
            }
            Spacer()
            Button("Continue") { next() }.buttonStyle(InkButtonStyle())
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func goal(_ n: Int, _ title: String, _ detail: String) -> some View {
        let selected = perDay == n
        return Button { perDay = n; Haptics.tap() } label: {
            HStack {
                Text("\(n)").font(.system(.title2, design: .rounded).weight(.semibold)).monospacedDigit().frame(width: 40)
                VStack(alignment: .leading) {
                    Text(title).font(.headline)
                    Text(detail).font(.subheadline).foregroundStyle(Ink.ink2)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle").font(.title3)
                    .foregroundStyle(selected ? Ink.seal : Ink.hairline)
            }
            .padding(14)
            .background(Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(selected ? Ink.seal : Ink.hairline, lineWidth: selected ? 2 : 0.5))
        }
        .buttonStyle(.plain)
    }

    private var widgetStep: some View {
        VStack(spacing: 22) {
            Text("Your word, on your lock screen").font(.title.bold()).multilineTextAlignment(.center).padding(.top, 24)
            LockScreenPreview()
                .frame(maxWidth: 260)
            Text("You will glance at it dozens of times a day without trying. That is where most of the learning happens.")
                .font(.body).foregroundStyle(Ink.ink2).multilineTextAlignment(.center)
            Spacer()
            Button("Show me how") { showGuide = true }.buttonStyle(InkButtonStyle(prominent: false))
            Button("Continue") { next() }.buttonStyle(InkButtonStyle())
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private var reminderStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("A daily nudge?").font(.title.bold()).padding(.top, 24)
            Text("One notification a day with that day's word. Nothing else.")
                .font(.subheadline).foregroundStyle(Ink.ink2)
            DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .frame(maxWidth: .infinity)
            Spacer()
            Button("Remind me") {
                Task {
                    let ok = await Reminders.requestPermission()
                    finish(reminder: ok)
                }
            }
            .buttonStyle(InkButtonStyle())
            Button("Not now") { finish(reminder: false) }
                .buttonStyle(InkButtonStyle(prominent: false))
        }
        .padding(.horizontal, 24).padding(.bottom, 16)
    }

    private func next() {
        Haptics.tap()
        step += 1
    }

    private func finish(reminder: Bool) {
        var s = model.settings
        s.syllabus = syllabus
        s.level = level
        s.newPerDay = perDay
        let c = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        s.reminderHour = c.hour ?? 9
        s.reminderMinute = c.minute ?? 0
        s.reminderOn = reminder
        model.settings = s
        model.state.onboarded = true
        model.rebuildTodayPlan()
        model.saveNow()
        Task { await model.rescheduleReminders() }
        Haptics.success()
    }
}

/// Drawing of a lock screen with the Inkstone widgets, used in onboarding.
struct LockScreenPreview: View {
    var body: some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(LinearGradient(colors: [Color(light: 0x2B3A36, dark: 0x2B3A36), Color(light: 0x0F1513, dark: 0x0F1513)], startPoint: .top, endPoint: .bottom))
            VStack(spacing: 6) {
                Text("péngyou · friend").font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                Text("9:41").font(.system(size: 64, weight: .semibold, design: .rounded)).foregroundStyle(.white)
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text("朋友").font(Ink.hanziFixed(22))
                            Text("péngyou").font(.system(size: 11, weight: .semibold))
                        }
                        Text("friend").font(.system(size: 11)).opacity(0.85)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .frame(width: 128, alignment: .leading)
                    .background(.white.opacity(0.16), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    Text("友").font(Ink.hanziFixed(24))
                        .frame(width: 46, height: 46)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .foregroundStyle(.white)
            }
            .padding(.top, 34)
        }
        .aspectRatio(0.62, contentMode: .fit)
        .shadow(color: .black.opacity(0.15), radius: 18, y: 8)
        .accessibilityLabel("A lock screen showing 朋友, péngyou, friend")
    }
}

/// Quick level check: tap the words you know, level by level.
struct LevelCheckView: View {
    @Environment(AppModel.self) private var model
    let syllabus: Syllabus
    /// The suggested level, or nil if the check was cancelled.
    let onDone: (Int?) -> Void
    @State private var round = 0
    @State private var known: Set<Int> = []
    @State private var samples: [[Word]] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if samples.indices.contains(round) {
                    Text("Tap every word you know").font(.title2.bold())
                    Text("\(Syllabus.levelName(syllabus.levels[round])) · round \(round + 1) of \(samples.count)")
                        .font(.subheadline).foregroundStyle(Ink.ink2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                        ForEach(samples[round]) { w in
                            let on = known.contains(w.id)
                            Button {
                                if on { known.remove(w.id) } else { known.insert(w.id) }
                                Haptics.tap()
                            } label: {
                                VStack(spacing: 2) {
                                    Text(w.s).font(Ink.hanzi(30)).lineLimit(1).minimumScaleFactor(0.5)
                                    Text(on ? w.meaning : " ").font(.caption).foregroundStyle(Ink.ink2).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 78)
                                .background(on ? Ink.sealSoft : Ink.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(on ? Ink.seal : Ink.hairline, lineWidth: on ? 2 : 0.5))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    Spacer()
                    Button("Next") { advance() }.buttonStyle(InkButtonStyle())
                } else {
                    ProgressView()
                }
            }
            .padding(24)
            .background(Ink.paper.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { onDone(nil) } } }
        }
        .tint(Ink.seal)
        .onAppear {
            samples = syllabus.levels.map { lv in
                let words = model.lexicon.words(level: lv, syllabus: syllabus).filter { $0.s.count <= 3 }
                // spread the sample across the level, not just its most common words
                let stride = max(1, words.count / 6)
                return Array(Swift.stride(from: stride / 2, to: words.count, by: stride).prefix(6).map { words[$0] })
            }
        }
    }

    private func advance() {
        let ids = Set(samples[round].map(\.id))
        let hits = known.intersection(ids).count
        let level = syllabus.levels[round]
        // Knowing 5 of 6 means the level is mostly done: check the next one.
        // Otherwise this is the level to study.
        if hits >= 5 && round + 1 < samples.count {
            round += 1
        } else {
            onDone(level)
        }
    }
}
