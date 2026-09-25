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
                    case .month: if insPage.isEmpty { monthView } else { monthPageSample }
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

    /// Day view stays as "now". Old preview flag "insights.dayStyle": A = big score + list, B = ring + bars, C = ring + tiles.
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
            if let best = items.max(by: { $0.score < $1.score }) { dayLinkCard("Best day", [best], id: "bestDayCard") }
            if let rough { roughDayCard(rough, all: items) }
        }
    }

    /// Preview "insights.page" 1-5: Month layouts ("" = the current one). Sample-only until one is picked.
    /// 1 = a calendar with each day's score. 2 = a line chart with your average. 3 = a big average ring and week bars.
    /// 4 = how often each habit got done. 5 = best day, lowest day, and streak as cards over the bars.
    @AppStorage("insights.page") private var insPage = ""
    private var monthAvg: Int { monthScores.isEmpty ? 0 : monthScores.map(\.score).reduce(0, +) / monthScores.count }
    private func dayColor(_ score: Int) -> Color { score < 45 ? Theme.bad : Theme.accent.opacity(score >= 80 ? 1 : 0.55) }

    @ViewBuilder private var monthPageSample: some View {
        let items = monthScores
        switch insPage {
        case "1":
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    Text("\(Date.now.formatted(.dateTime.month(.wide))) · average \(monthAvg)").font(.headline)
                    let cal = Calendar.current
                    let start = cal.dateInterval(of: .month, for: .now)?.start ?? .now
                    let lead = (cal.component(.weekday, from: start) - cal.firstWeekday + 7) % 7
                    let days = cal.range(of: .day, in: .month, for: .now)?.count ?? 30
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                        ForEach(0..<7, id: \.self) { i in
                            Text(cal.veryShortWeekdaySymbols[(i + cal.firstWeekday - 1) % 7]).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                        ForEach(0..<(lead + days), id: \.self) { i in
                            if i < lead { Color.clear.frame(height: 36) } else {
                                let d = cal.date(byAdding: .day, value: i - lead, to: start) ?? start
                                let sc = items.first { cal.isDate($0.day, inSameDayAs: d) }?.score
                                ZStack {
                                    Circle().fill(sc.map { dayColor($0) } ?? Color(.tertiarySystemFill))
                                    Text(sc.map { "\($0)" } ?? "\(i - lead + 1)").font(.caption.weight(.semibold))
                                        .foregroundStyle(sc == nil ? Color.secondary : Color.white)
                                }
                                .frame(height: 36)
                            }
                        }
                    }
                }
            }
        case "2":
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Average \(monthAvg)").font(.title2.bold())
                    Chart {
                        ForEach(items) { s in
                            LineMark(x: .value("Day", s.day, unit: .day), y: .value("Score", s.score)).interpolationMethod(.catmullRom)
                                .foregroundStyle(Theme.accent)
                            PointMark(x: .value("Day", s.day, unit: .day), y: .value("Score", s.score)).foregroundStyle(dayColor(s.score)).symbolSize(28)
                        }
                        RuleMark(y: .value("Average", monthAvg)).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 200)
                }
            }
            statsRow(items)
        case "3":
            Card {
                VStack(spacing: 12) {
                    ScoreRing(score: monthAvg, size: 140)
                    Text("\(Date.now.formatted(.dateTime.month(.wide))) average").font(.subheadline).foregroundStyle(.secondary)
                    let weeks = Dictionary(grouping: items) { Calendar.current.component(.weekOfMonth, from: $0.day) }.sorted { $0.key < $1.key }
                    HStack(alignment: .bottom, spacing: 14) {
                        ForEach(weeks.indices, id: \.self) { wi in
                            let w = weeks[wi]
                            let a = w.value.map(\.score).reduce(0, +) / max(1, w.value.count)
                            VStack(spacing: 4) {
                                Text("\(a)").font(.caption.weight(.semibold)).monospacedDigit()
                                Capsule().fill(dayColor(a)).frame(width: 26, height: CGFloat(a) * 1.1)
                                Text("W\(w.key)").font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(height: 150, alignment: .bottom)
                }
                .frame(maxWidth: .infinity)
            }
        case "4":
            let titles = Array(Set(items.flatMap { $0.factors.map(\.title) })).sorted()
            SectionHeader("How often")
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(titles.prefix(7).enumerated()), id: \.offset) { i, t in
                        let done = items.filter { $0.factors.contains { $0.title == t && $0.points > 0 } }.count
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(t).font(.body.weight(.semibold))
                                Spacer()
                                Text("\(done) of \(items.count) days").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                            ProgressView(value: Double(done), total: Double(max(1, items.count))).tint(Theme.accent)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        if i < min(titles.count, 7) - 1 { Divider().padding(.leading, 16) }
                    }
                }
            }
        default:
            let best = items.max { $0.score < $1.score }
            let low = items.min { $0.score < $1.score }
            HStack(spacing: 8) {
                if let best { bigCard("Best day", "\(best.score)", best.day.formatted(.dateTime.weekday(.abbreviated).day()), Theme.accent) }
                if let low { bigCard("Lowest day", "\(low.score)", low.day.formatted(.dateTime.weekday(.abbreviated).day()), Theme.bad) }
            }
            Button { showStreak = true } label: { bigCard("Streak", "\(DayData.streak(context: context)) days", "Tap to see it", Theme.accent) }.buttonStyle(.plain)
            Card {
                Chart(items) { s in
                    BarMark(x: .value("Day", s.day, unit: .day), y: .value("Score", s.score)).foregroundStyle(dayColor(s.score)).clipShape(.capsule)
                }
                .chartYScale(domain: 0...100).chartYAxis(.hidden).frame(height: 120)
            }
        }
    }
    private func statsRow(_ items: [DayScore]) -> some View {
        HStack(spacing: 8) {
            statCard("Streak", "\(DayData.streak(context: context)) days")
            statCard("80+ days", "\(items.filter { $0.score >= 80 }.count)")
            statCard("Under 45", "\(items.filter { $0.score < 45 }.count)")
        }
    }
    private func bigCard(_ title: String, _ value: String, _ sub: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            Text(value).font(.largeTitle.bold()).foregroundStyle(color).monospacedDigit()
            Text(sub).font(.caption).foregroundStyle(.secondary)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 22, style: .continuous))
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
