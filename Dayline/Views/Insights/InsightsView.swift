import SwiftUI
import SwiftData
import Charts

enum InsightRange: String, CaseIterable, Identifiable { case day = "Day", month = "Month", year = "Year"; var id: String { rawValue } }

struct InsightsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DayScore.day) private var scores: [DayScore]
    @Query private var visits: [Visit]
    @State private var range: InsightRange = .month
    @Binding var showStreak: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TabTitle("Insights")
                    CapsuleSegmented(selection: $range, options: InsightRange.allCases.map { ($0, $0.rawValue) }, plain: true).glassEffect(.regular, in: .capsule)
                    switch range {
                    case .day: classicDayView
                    case .month: monthView
                    case .year: yearView
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .navigationTitle("Insights")
            .tabRoot()
            .navigationDestination(isPresented: $showStreak) { StreakView() }
            .navigationBarTitleDisplayMode(.large)
        }
    }

    // MARK: Day

    private var classicDayView: some View {
        let r = ScoreEngine.score(DayData.input(for: .now, context: context))
        return VStack(spacing: 12) {
            ScoreCard(result: r)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("What's driving today").font(.headline)
                    ForEach(r.factors) { f in
                        HStack {
                            FactorChip(factor: f)
                            Spacer()
                            Text(f.points > 0 ? "+\(f.points)" : "–").font(.subheadline.weight(.bold)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    // MARK: Month
    private var monthScores: [DayScore] {
        guard let month = Calendar.current.dateInterval(of: .month, for: .now) else { return [] }
        return scores.filter { month.contains($0.day) }
    }
    private var previousMonthAverage: Int? {
        let cal = Calendar.current
        guard let prev = cal.date(byAdding: .month, value: -1, to: .now), let m = cal.dateInterval(of: .month, for: prev) else { return nil }
        let s = scores.filter { m.contains($0.day) }
        return s.isEmpty ? nil : s.map(\.score).reduce(0, +) / s.count
    }

    private var monthView: some View {
        let items = monthScores
        let avg = items.isEmpty ? 0 : items.map(\.score).reduce(0, +) / items.count
        let rough = items.filter { $0.score < 45 }.last
        return VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading) {
                            Text("\(Date.now.formatted(.dateTime.month(.wide))) average").font(.subheadline).foregroundStyle(.secondary)
                            HStack(alignment: .firstTextBaseline, spacing: 2) {
                                Text("\(avg)").font(.largeTitle.bold())
                                Text("/100").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let prev = previousMonthAverage {
                            let diff = avg - prev
                            Badge(text: "\(diff >= 0 ? "▲" : "▼") \(abs(diff)) vs \((Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now).formatted(.dateTime.month(.abbreviated)))", color: diff >= 0 ? Theme.accent : Theme.bad)
                                .padding(.bottom, 12)
                        }
                    }
                    Chart(items) { s in
                        BarMark(x: .value("Day", s.day, unit: .day), y: .value("Score", s.score))
                            .foregroundStyle(s.score < 45 ? Theme.bad : Theme.accent.opacity(s.score >= 80 ? 1 : 0.55))
                            .clipShape(.capsule)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: 130)
                    HStack(spacing: 12) {
                        legend(Theme.accent, "80+")
                        legend(Theme.accent.opacity(0.55), "45-79")
                        legend(Theme.bad, "under 45")
                    }
                }
            }
            HStack(spacing: 8) {
                Button { showStreak = true } label: { statCard("Streak", "\(DayData.streak(context: context)) days ›") }
                    .buttonStyle(.plain).accessibilityIdentifier("streakCard")
                statCard("80+ days", "\(items.filter { $0.score >= 80 }.count)")
                statCard("Places", "\(Set(visits.filter { Calendar.current.isDate($0.arrival, equalTo: .now, toGranularity: .month) }.map(\.placeKey)).count)")
            }
            if let best = items.max(by: { $0.score < $1.score }) { dayLinkCard("Best day", [best], id: "bestDayCard") }
            if let rough { roughDayCard(rough, all: items) }
        }
    }

    /// Preview "insights.page" 1-5: Month layouts ("" = the current one). Sample-only until one is picked.
    /// 1 = a calendar with each day's score. 2 = a line chart with your average. 3 = a big average ring and week bars.
    /// 4 = how often each habit got done. 5 = best day, lowest day, and streak as cards over the bars.
    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color == Theme.bad ? Theme.bad : .secondary)
        }
    }

    /// Lowest day of the month and the day after, as a plain list.
    private func roughDayCard(_ rough: DayScore, all: [DayScore]) -> some View {
        let cal = Calendar.current
        let next = all.first { $0.day > rough.day }
        let why = rough.factors.filter { $0.points < 0 }.prefix(2).map(\.title)
        let reason = why.isEmpty ? rough.label : why.joined(separator: ", ")
        func back(_ d: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: .now)).day ?? 0 }
        func longDate(_ d: Date) -> String { d.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader("Lowest day").padding(.bottom, 6).padding(.top, 8)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    NavigationLink { ScoreDetailView(result: todayResult, startBack: back(rough.day)) } label: {
                        dayRow(title: longDate(rough.day), subtitle: reason, score: rough.score, up: false)
                    }
                    if let next {
                        Divider().padding(.leading, 16)
                        NavigationLink { ScoreDetailView(result: todayResult, startBack: back(next.day)) } label: {
                            dayRow(title: "Next Day", subtitle: longDate(next.day), score: next.score, up: next.score > rough.score)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("lowestDayCard")
        }
    }

    /// A titled card of days; tapping a row opens that day's score page.
    private func dayLinkCard(_ header: String, _ days: [DayScore], id: String) -> some View {
        let cal = Calendar.current
        func back(_ d: Date) -> Int { cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: .now)).day ?? 0 }
        return VStack(alignment: .leading, spacing: 0) {
            SectionHeader(header).padding(.bottom, 6).padding(.top, 8)
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                        if i > 0 { Divider().padding(.leading, 16) }
                        let why = d.factors.filter { $0.points > 0 }.prefix(2).map(\.title)
                        NavigationLink { ScoreDetailView(result: todayResult, startBack: back(d.day)) } label: {
                            dayRow(title: d.day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()),
                                   subtitle: d.score < 45 ? d.label : (why.isEmpty ? d.label : why.joined(separator: ", ")),
                                   score: d.score, up: false)
                        }
                    }
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(id)
        }
    }

    private var todayResult: ScoreEngine.Result { ScoreEngine.score(DayData.input(for: .now, context: context)) }

    private func dayRow(title: String, subtitle: String, score: Int, up: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            HStack(spacing: 4) {
                if up { Image(systemName: "arrowtriangle.up.fill").font(.caption) }
                Text("\(score)").font(.title.bold())
            }
            .foregroundStyle(score < 45 ? Theme.bad : Theme.accent)
            Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
        .contentShape(.rect)
    }

    // MARK: Year
    private var yearView: some View {
        let cal = Calendar.current
        let year = cal.component(.year, from: .now)
        let byMonth = Dictionary(grouping: scores.filter { cal.component(.year, from: $0.day) == year }) { cal.component(.month, from: $0.day) }
        let points = (1...12).map { m -> (Int, Int?) in
            guard let s = byMonth[m], !s.isEmpty else { return (m, nil) }
            return (m, s.map(\.score).reduce(0, +) / s.count)
        }
        let all = scores.filter { cal.component(.year, from: $0.day) == year }
        return VStack(spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(String(year)) so far").font(.headline)
                    Chart(points.compactMap { p in p.1.map { (p.0, $0) } }, id: \.0) { p in
                        BarMark(x: .value("Month", cal.shortMonthSymbols[p.0 - 1]), y: .value("Average", p.1))
                            .foregroundStyle(LinearGradient(colors: [Theme.accent.opacity(0.5), Theme.accent], startPoint: .bottom, endPoint: .top))
                            .clipShape(.rect(cornerRadius: 8))
                    }
                    .chartXScale(domain: cal.shortMonthSymbols)
                    .chartYScale(domain: 0...100)
                    .frame(height: 180)
                }
            }
            HStack(spacing: 8) {
                statCard("Year average", all.isEmpty ? "–" : "\(all.map(\.score).reduce(0, +) / all.count)")
                statCard("Great days", "\(all.filter { $0.score >= 90 }.count)")
                statCard("Days logged", "\(all.count)")
            }
            if let best = all.max(by: { $0.score < $1.score }), let low = all.min(by: { $0.score < $1.score }) {
                dayLinkCard("Best and lowest days", best.day == low.day ? [best] : [best, low], id: "yearDaysCard")
            }
        }
    }

    private func statCard(_ title: String, _ value: String) -> some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }

}
