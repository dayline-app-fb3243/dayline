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
                    case .day: dayView
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
    /// Preview flag: simple Health-style Day page (score + summary, then one clean list). Off until David approves.
    @AppStorage("insights.simpleDay") private var simpleDay = false

    /// Preview flag "insights.dayStyle" (David picks, Sep 24 round 2): A = big score + list, B = ring + bars, C = ring + tiles.
    @AppStorage("insights.dayStyle") private var dayStyle = "now"

    @ViewBuilder private var dayView: some View {
        switch dayStyle {
        case "A": dayA
        case "B": dayB
        case "C": dayC
        default: if simpleDay { simpleDayView } else { classicDayView }
        }
    }

    private func pts(_ f: ScoreFactor) -> String { f.points > 0 ? "+\(f.points)" : "\(f.points)" }
    private func isBad(_ f: ScoreFactor) -> Bool { f.effect == .pending || f.points <= 0 }

    private var dayA: some View {
        let r = todayResult
        return VStack(alignment: .leading, spacing: 12) {
            Card {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Day Score").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(r.score)").font(.largeTitle.bold()).monospacedDigit()
                        Text("of 100").font(.body).foregroundStyle(.secondary)
                    }
                    Text(r.tip ?? r.summary).font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Points today").font(.subheadline.weight(.semibold)).helperText().padding(.leading, 16)
            VStack(spacing: 0) {
                ForEach(Array(r.factors.enumerated()), id: \.element.id) { i, f in
                    if i > 0 { Divider().padding(.leading, 58) }
                    FactorRow(factor: f)
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        .accessibilityIdentifier("insightsDayA")
    }

    private var dayB: some View {
        let r = todayResult
        let top = max(20, r.factors.map(\.points).max() ?? 20)
        return VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack(spacing: 18) {
                    ScoreRing(score: r.score, size: 110)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.label).font(.title2.bold())
                        Text("\(r.score) of 100 points").font(.subheadline).foregroundStyle(.secondary)
                        if let tip = r.tip { Text(tip).font(.subheadline).foregroundStyle(Theme.accent) }
                    }
                    Spacer(minLength: 0)
                }
            }
            Text("Where points came from").font(.subheadline.weight(.semibold)).helperText().padding(.leading, 16)
            Card {
                VStack(spacing: 14) {
                    ForEach(r.factors) { f in
                        HStack(spacing: 12) {
                            Text(f.chip ?? f.title).font(.subheadline).lineLimit(1).frame(width: 110, alignment: .leading)
                            GeometryReader { g in
                                ZStack(alignment: .leading) {
                                    Capsule().fill(Color(.systemFill))
                                    if f.points > 0 {
                                        Capsule().fill(Theme.accent).frame(width: g.size.width * CGFloat(f.points) / CGFloat(top))
                                    }
                                }
                            }
                            .frame(height: 8)
                            Text(pts(f)).font(.subheadline.weight(.semibold)).monospacedDigit()
                                .foregroundStyle(isBad(f) ? Color.secondary : Color.primary).frame(width: 36, alignment: .trailing)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("insightsDayB")
    }

    private var dayC: some View {
        let r = todayResult
        return VStack(alignment: .leading, spacing: 12) {
            Card {
                HStack(spacing: 14) {
                    ScoreRing(score: r.score, size: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(.title3.bold())
                        Text(r.tip ?? r.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(r.factors) { f in
                    let st = FactorRow.style(f.title)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            ProfileIcon(symbol: st.0, size: 26, color: isBad(f) ? Theme.bad : Theme.accent)
                            Text(f.chip ?? f.title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(pts(f)).font(.title.bold()).monospacedDigit().foregroundStyle(isBad(f) ? Color.secondary : Color.primary)
                            Text("pts").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
                }
            }
        }
        .accessibilityIdentifier("insightsDayC")
    }

    private var simpleDayView: some View {
        let r = ScoreEngine.score(DayData.input(for: .now, context: context))
        return VStack(spacing: 12) {
            Card {
                HStack(spacing: 16) {
                    ScoreRing(score: r.score, size: 72)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(r.label).font(.title3.bold()).foregroundStyle(Theme.scoreColor(r.score))
                        Text(r.tip ?? r.summary).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("Points today").font(.subheadline.weight(.semibold)).helperText().padding(.leading, 16)
                VStack(spacing: 0) {
                    ForEach(Array(r.factors.enumerated()), id: \.element.id) { i, f in
                        if i > 0 { Divider().padding(.leading, 58) }
                        FactorRow(factor: f)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .accessibilityIdentifier("simpleDay")
        }
    }

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
            if let rough { roughDayCard(rough, all: items) }
        }
    }

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
