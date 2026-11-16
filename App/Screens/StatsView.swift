import SwiftUI
import Charts

struct StatsView: View {
    @Environment(AppModel.self) private var model
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    summary
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Practice calendar", trailing: "Best streak \(model.bestStreak)")
                        Heatmap().card(padding: 14)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: "Reviews coming up")
                        ForecastChart(values: model.forecast(days: 14)).card(padding: 14)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        SectionHeader(title: model.state.settings.syllabus.title)
                        VStack(spacing: 12) {
                            ForEach(model.state.settings.syllabus.levels, id: \.self) { lv in
                                let p = model.levelProgress(lv)
                                HStack(spacing: 12) {
                                    Text(lv >= 7 ? "7–9" : "\(lv)")
                                        .font(.subheadline.weight(.semibold)).monospacedDigit()
                                        .frame(width: 30, alignment: .leading)
                                    SegmentBar(known: p.known, learning: p.learning, total: p.total)
                                    Text("\(p.known + p.learning)/\(p.total)")
                                        .font(.caption).monospacedDigit().foregroundStyle(Ink.ink2)
                                        .frame(width: 74, alignment: .trailing)
                                }
                            }
                            HStack(spacing: 14) {
                                LegendDot(color: Ink.good, text: "Known (3+ weeks)")
                                LegendDot(color: Ink.warn, text: "Learning")
                                Spacer()
                            }
                            .padding(.top, 2)
                        }
                        .card()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 32)
            }
            .background(Ink.paper.ignoresSafeArea())
            .navigationTitle("Progress")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .tint(Ink.ink)
                        .accessibilityLabel("Settings")
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
        }
    }

    private var summary: some View {
        let cards = model.state.cards.values
        let known = cards.filter(\.isKnown).count
        let totalMinutes = model.state.log.values.reduce(0) { $0 + $1.seconds } / 60
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            BigStat(value: "\(model.streak)", label: "day streak", symbol: "flame.fill", tint: Ink.seal)
            BigStat(value: "\(cards.count)", label: "words met", symbol: "character.book.closed", tint: Ink.ink)
            BigStat(value: "\(known)", label: "known well", symbol: "checkmark.seal.fill", tint: Ink.good)
            BigStat(value: model.retention30.map { "\(Int(($0 * 100).rounded()))%" } ?? "–", label: "recall, 30 days", symbol: "brain.head.profile", tint: Ink.tone(1))
            BigStat(value: "\(totalMinutes)", label: "minutes studied", symbol: "clock", tint: Ink.ink2)
            BigStat(value: "\(model.dueCount)", label: "due now", symbol: "rectangle.stack", tint: Ink.warn)
        }
        .padding(.top, 4)
    }
}

struct BigStat: View {
    let value: String
    let label: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).font(.subheadline.weight(.semibold)).foregroundStyle(tint)
            Text(value).font(.system(.title, design: .rounded).weight(.semibold)).monospacedDigit().foregroundStyle(Ink.ink)
            Text(label).font(.caption).foregroundStyle(Ink.ink2)
        }
        .card(padding: 14)
        .accessibilityElement(children: .combine)
    }
}

struct LegendDot: View {
    let color: Color
    let text: String
    var body: some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text).font(.caption).foregroundStyle(Ink.ink2)
        }
    }
}

/// Last 20 weeks, one square per day, Monday at the top.
struct Heatmap: View {
    @Environment(AppModel.self) private var model
    let weeks = 20

    var body: some View {
        let today = model.today
        let weekday = (Calendar(identifier: .iso8601).component(.weekday, from: StudyDay.date(for: today)) + 5) % 7  // Mon = 0
        let start = today - weekday - (weeks - 1) * 7
        // read the log here (not inside the Canvas) so the view updates when it changes
        let counts = (0..<weeks * 7).map { model.state.log[start + $0]?.reviews ?? 0 }
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { geo in
                let gap: CGFloat = 3
                let cell = min(14, (geo.size.width - gap * CGFloat(weeks - 1)) / CGFloat(weeks))
                Canvas { ctx, _ in
                    for w in 0..<weeks {
                        for d in 0..<7 {
                            let day = start + w * 7 + d
                            guard day <= today else { continue }
                            let n = counts[w * 7 + d]
                            let rect = CGRect(x: CGFloat(w) * (cell + gap), y: CGFloat(d) * (cell + gap), width: cell, height: cell)
                            let color: Color = n == 0 ? Ink.well : (n < 10 ? Ink.seal.opacity(0.35) : (n < 30 ? Ink.seal.opacity(0.65) : Ink.seal))
                            ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(color))
                            if day == today {
                                ctx.stroke(Path(roundedRect: rect.insetBy(dx: -1, dy: -1), cornerRadius: 3.5), with: .color(Ink.ink), lineWidth: 1.2)
                            }
                        }
                    }
                }
            }
            .frame(height: 7 * 14 + 6 * 3)
            HStack(spacing: 4) {
                Text("Less").font(.caption2).foregroundStyle(Ink.ink3)
                ForEach([0.0, 0.35, 0.65, 1.0], id: \.self) { o in
                    RoundedRectangle(cornerRadius: 2).fill(o == 0 ? Ink.well : Ink.seal.opacity(o)).frame(width: 10, height: 10)
                }
                Text("More").font(.caption2).foregroundStyle(Ink.ink3)
                Spacer()
                Text("Each square is a day").font(.caption2).foregroundStyle(Ink.ink3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Practice calendar for the last \(weeks) weeks")
    }
}

struct ForecastChart: View {
    let values: [Int]

    var body: some View {
        Chart {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                BarMark(x: .value("Day", i), y: .value("Reviews", v))
                    .foregroundStyle(i == 0 ? Ink.seal : Ink.ink2.opacity(0.55))
                    .cornerRadius(3)
            }
        }
        .chartXAxis {
            AxisMarks(values: [0, 1, 7, 13]) { v in
                AxisValueLabel {
                    if let i = v.as(Int.self) {
                        Text(i == 0 ? "Today" : (i == 1 ? "Tmrw" : "+\(i)d"))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { _ in
                AxisGridLine().foregroundStyle(Ink.hairline)
                AxisValueLabel()
            }
        }
        .frame(height: 150)
        .accessibilityLabel("Reviews due over the next two weeks")
    }
}
