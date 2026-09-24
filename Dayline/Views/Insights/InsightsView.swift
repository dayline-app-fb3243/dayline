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
                    CapsuleSegmented(selection: $range, options: InsightRange.allCases.map { ($0, $0.rawValue) })
                    switch range {
                    case .day: dayView
                    case .month: monthView
                    case .year: yearView
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .navigationTitle("Insights")
            .navigationDestination(isPresented: $showStreak) { StreakView() }
            .toolbarRole(.editor)
        }
    }

    // MARK: Day
    private var dayView: some View {
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
                                Text("\(avg)").font(.system(size: 44, weight: .heavy))
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
            if let rough { roughDayCard(rough, all: items) }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 8, height: 8)
            Text(text).font(.caption2.weight(.semibold)).foregroundStyle(color == Theme.bad ? Theme.bad : .secondary)
        }
    }

    private func roughDayCard(_ rough: DayScore, all: [DayScore]) -> some View {
        let next = all.first { $0.day > rough.day }
        return Card(padding: 13) {
            HStack(spacing: 12) {
                Text("\(rough.score)").font(.headline.weight(.heavy)).foregroundStyle(Theme.bad)
                    .frame(width: 44, height: 44).background(Theme.bad.opacity(0.15), in: .circle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(rough.day.formatted(.dateTime.month(.abbreviated).day())) was a rough one.").font(.subheadline.weight(.semibold))
                    Text(next.map { "That's okay. You bounced back to \($0.score) the next day." } ?? "That's okay. Tomorrow's a fresh start.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
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
                            .foregroundStyle(LinearGradient(colors: [Color.blue.opacity(0.5), .blue], startPoint: .bottom, endPoint: .top))
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
