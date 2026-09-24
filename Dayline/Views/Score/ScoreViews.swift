import SwiftUI
import SwiftData

/// Tap the Today score card: the full breakdown of a day's score.
/// Swipe sideways (or use the arrows) to see earlier days, like Screen Time. Tap the date for a calendar.
struct ScoreDetailView: View {
    var result: ScoreEngine.Result
    /// Days back to open on (0 = today).
    var startBack = 0
    @Environment(\.modelContext) private var context
    @Query(sort: \DayScore.day, order: .reverse) private var scores: [DayScore]
    @State private var back = 0
    @State private var didSetStart = false
    @State private var showPicker = false

    private var cal: Calendar { .current }
    private func day(_ back: Int) -> Date { cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: .now))! }
    private var maxBack: Int {
        guard let oldest = scores.last?.day else { return 0 }
        return min(60, max(0, cal.dateComponents([.day], from: cal.startOfDay(for: oldest), to: cal.startOfDay(for: .now)).day ?? 0))
    }

    var body: some View {
        VStack(spacing: 0) {
            dateBar.padding(.horizontal, 18).padding(.bottom, 8)
            TabView(selection: $back) {
                ForEach(Array((0...maxBack).reversed()), id: \.self) { b in
                    page(b).tag(b)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .onAppear { if !didSetStart { didSetStart = true; back = min(startBack, maxBack) } }
        .background(AppBackgroundView())
        .navigationTitle("Day score")
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if back > 0 {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") { withAnimation(.snappy) { back = 0 } }
                        .font(.subheadline.weight(.semibold))
                        .accessibilityIdentifier("backToToday")
                }
            }
        }
        .sheet(isPresented: $showPicker) {
            DayPickerSheet(selected: day(back), earliest: day(maxBack), scores: scores) { picked in
                let b = cal.dateComponents([.day], from: cal.startOfDay(for: picked), to: cal.startOfDay(for: .now)).day ?? 0
                withAnimation(.snappy) { back = min(max(0, b), maxBack) }
                showPicker = false
            }
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
            .presentationBackground(Color(.systemBackground))
            .presentationCornerRadius(34)
        }
    }

    private var dateBar: some View {
        HStack {
            roundButton("chevron.left", id: "previousDay") { withAnimation(.snappy) { back = min(back + 1, maxBack) } }
                .opacity(back >= maxBack ? 0.35 : 1)
            Spacer()
            Button { showPicker = true } label: {
                VStack(spacing: 1) {
                    HStack(spacing: 5) {
                        Text(title(back)).font(.headline)
                        Image(systemName: "arrowtriangle.down.fill").font(.system(size: 8)).foregroundStyle(Theme.accent)
                    }
                    Text(subtitle(back)).font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dayTitle")
            Spacer()
            roundButton("chevron.right", id: "nextDay") { withAnimation(.snappy) { back = max(back - 1, 0) } }
                .opacity(back == 0 ? 0.35 : 1)
        }
    }

    private func roundButton(_ symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(.primary)
                .frame(width: 36, height: 36)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(id)
    }

    private func title(_ b: Int) -> String {
        switch b {
        case 0: "Today"
        case 1: "Yesterday"
        case 2...6: day(b).formatted(.dateTime.weekday(.wide))
        default: day(b).formatted(.dateTime.month(.abbreviated).day())
        }
    }

    private func subtitle(_ b: Int) -> String {
        if b == 0 { return day(0).formatted(.dateTime.weekday(.wide).month(.abbreviated).day()) + " · swipe for other days" }
        let date = day(b).formatted(.dateTime.month(.abbreviated).day())
        return b == 1 ? date : "\(date) · \(b) days ago"
    }

    private func result(_ b: Int) -> ScoreEngine.Result? {
        if b == 0 { return result }
        let d = day(b)
        if let s = scores.first(where: { cal.isDate($0.day, inSameDayAs: d) }) {
            return .init(score: s.score, label: s.label, summary: s.summary, tip: nil, factors: s.factors)
        }
        return nil
    }

    @ViewBuilder
    private func page(_ b: Int) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if let r = result(b) {
                    Card {
                        VStack(spacing: 8) {
                            ScoreRing(score: r.score, lineWidth: 14, size: 132)
                            Text(r.label).font(.title.bold()).foregroundStyle(Theme.scoreColor(r.score))
                            Text(r.summary.isEmpty ? (r.tip ?? "") : r.summary).font(.subheadline).foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    if !r.factors.isEmpty {
                        SectionHeader(b == 0 ? "What shaped today" : "What shaped \(title(b).lowercased() == "yesterday" ? "yesterday" : title(b))")
                        Card(padding: 0) {
                            VStack(spacing: 0) {
                                ForEach(Array(r.factors.enumerated()), id: \.element.id) { i, f in
                                    FactorRow(factor: f)
                                    if i < r.factors.count - 1 { Divider().padding(.leading, 62) }
                                }
                            }
                        }
                    }
                } else {
                    Card {
                        Text("No score for this day. Dayline wasn't tracking yet.")
                            .font(.subheadline).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                    }
                }
                if b == 0 {
                    SectionHeader("This week")
                    Card { WeekStrip(scores: Array(scores.prefix(7)), today: result.score) }
                } else {
                    SectionHeader("Schedule")
                    DayActivityList(day: day(b))
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .accessibilityIdentifier("dayPage-\(b)")
    }
}

/// Tap the date on Day score: a month calendar. Dots mark scored days (orange under 45).
struct DayPickerSheet: View {
    var selected: Date
    var earliest: Date
    var scores: [DayScore]
    var onPick: (Date) -> Void
    @State private var month: Date = .now

    private var cal: Calendar { var c = Calendar.current; c.firstWeekday = 2; return c }

    var body: some View {
        let today = cal.startOfDay(for: .now)
        let monthStart = cal.dateInterval(of: .month, for: month)!.start
        let gridStart = cal.dateInterval(of: .weekOfYear, for: monthStart)!.start
        let earliestMonth = cal.dateInterval(of: .month, for: earliest)!.start
        let thisMonth = cal.dateInterval(of: .month, for: today)!.start
        VStack(spacing: 14) {
            HStack {
                Button { month = cal.date(byAdding: .month, value: -1, to: monthStart)! } label: { Image(systemName: "chevron.left") }
                    .disabled(monthStart <= earliestMonth)
                Spacer()
                Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                Spacer()
                Button { month = cal.date(byAdding: .month, value: 1, to: monthStart)! } label: { Image(systemName: "chevron.right") }
                    .disabled(monthStart >= thisMonth)
            }
            .font(.body.weight(.semibold)).foregroundStyle(.secondary)
            HStack {
                ForEach(0..<7, id: \.self) { i in
                    Text(cal.date(byAdding: .day, value: i, to: gridStart)!.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            VStack(spacing: 6) {
                ForEach(0..<6, id: \.self) { w in
                    HStack {
                        ForEach(0..<7, id: \.self) { d in
                            let date = cal.date(byAdding: .day, value: w * 7 + d, to: gridStart)!
                            cell(date, today: today, inMonth: cal.isDate(date, equalTo: monthStart, toGranularity: .month))
                        }
                    }
                }
            }
            HStack(spacing: 14) {
                Label { Text("scored day") } icon: { Circle().fill(Theme.accent).frame(width: 6, height: 6) }
                Label { Text("under 45") } icon: { Circle().fill(Theme.bad).frame(width: 6, height: 6) }
            }
            .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20).padding(.top, 24)
        .onAppear { month = selected }
        .accessibilityIdentifier("dayPicker")
    }

    private func cell(_ date: Date, today: Date, inMonth: Bool) -> some View {
        let score = scores.first { cal.isDate($0.day, inSameDayAs: date) }?.score
        let selectable = inMonth && date <= today && date >= cal.startOfDay(for: earliest)
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        return Button { onPick(date) } label: {
            VStack(spacing: 3) {
                Text(date.formatted(.dateTime.day())).font(.body.weight(selectable ? .semibold : .regular))
                    .foregroundStyle(isSelected ? Color.white : selectable ? Color.primary : Color.secondary.opacity(0.5))
                Circle().fill(score.map { $0 < 45 ? Theme.bad : Theme.accent } ?? .clear).frame(width: 5, height: 5)
                    .opacity(isSelected ? 0 : 1)
            }
            .frame(width: 40, height: 44)
            .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .frame(maxWidth: .infinity)
    }
}

/// What you actually did on a day, built from visits (no manual entries).
struct DayActivityList: View {
    var day: Date
    @Environment(\.modelContext) private var context
    @Query(sort: \Visit.arrival) private var visits: [Visit]
    @Query(sort: \JournalEntry.date) private var journal: [JournalEntry]

    struct Row: Identifiable { var id: String; var time: Date; var title: String; var detail: String; var isNow: Bool }

    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()

    private var rows: [Row] {
        let cal = Calendar.current, now = Date.now
        var out: [Row] = []
        let isToday = cal.isDate(day, inSameDayAs: DayBoundary.shared.today)
        let window = DayBoundary.shared.window(for: day)
        let sensedWake = DayBoundary.shared.wakeUp(on: day)
        let wake: Date? = (DemoData.isDemo && isToday)
            ? cal.date(bySettingHour: 6, minute: 50, second: 0, of: day)
            : DayData.input(for: day, context: context).firstActivity
        let wakeDetail = DemoData.isDemo ? "Phone first used" : (sensedWake != nil ? "First move after sleep" : "First activity")
        if let wake { out.append(Row(id: "wake", time: wake, title: "Woke up", detail: wakeDetail, isNow: false)) }
        for v in visits where window.contains(v.arrival) && v.category != .home && v.arrival <= now {
            let here = v.departure.map { $0 > now } ?? true
            let end = here ? now : v.departure!
            var detail = here && isToday ? "Here since \(Self.clock.string(from: v.arrival))" : Self.duration(end.timeIntervalSince(v.arrival))
            let photos = journal.filter { $0.kind == .photo && $0.date >= v.arrival && $0.date <= end }.count
            if photos > 0 { detail += " · \(photos) photo\(photos == 1 ? "" : "s")" }
            out.append(Row(id: "\(v.arrival.timeIntervalSince1970)-\(v.placeKey)", time: v.arrival, title: v.placeName, detail: detail, isNow: here && isToday))
        }
        return out.sorted { $0.time < $1.time }
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    var body: some View {
        let rows = rows
        Card(padding: 0) {
            if rows.isEmpty {
                Text("Nothing yet. Dayline fills this in from where you go.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        HStack(spacing: 12) {
                            Text(Self.clock.string(from: r.time))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                                .frame(width: 46, alignment: .leading)
                            Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.body.weight(.semibold))
                                Text(r.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if r.isNow { Text("now").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        if i < rows.count - 1 { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }
}

struct FactorRow: View {
    var factor: ScoreFactor
    var body: some View {
        let symbol = Self.style(factor.title).0
        let bad = factor.effect == .pending || factor.points <= 0
        let color = bad ? Theme.bad : Theme.accent
        HStack(spacing: 12) {
            ProfileIcon(symbol: symbol, size: 30, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(factor.title).font(.body.weight(.semibold))
                Text(factor.detail ?? (bad ? "No points yet" : factor.effect == .up ? "Counted" : "Small boost"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(factor.points >= 0 ? "+\(factor.points)" : "\(factor.points)")
                .font(.footnote.weight(.bold)).monospacedDigit()
                .foregroundStyle(color)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(color.opacity(0.14), in: .capsule)
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }

    static func style(_ title: String) -> (String, Color) {
        let t = title.lowercased()
        if t.hasPrefix("up at") || t.contains("start") || t.contains("woke") { return ("sun.max.fill", .orange) }
        if t.contains("late night") { return ("moon.fill", Theme.bad) }
        if t == "plans" { return ("checkmark", Theme.accent) }
        if t.contains("moving") { return ("figure.walk", Theme.accent) }
        if t.contains("gym") { return ("dumbbell.fill", Theme.good) }
        if t.contains("planned") { return ("checkmark", Theme.accent) }
        if t.contains("place") { return ("mappin", .teal) }
        if t.contains("outside") || t.contains("move") { return ("figure.walk", .teal) }
        if t.contains("journal") { return ("pencil", Theme.journal) }
        if t.contains("went out") { return ("fork.knife", .orange) }
        return ("star.fill", Theme.accent)
    }
}

struct WeekStrip: View {
    var scores: [DayScore]
    var today: Int
    var body: some View {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
        HStack(alignment: .bottom) {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i, to: start)!
                let isToday = cal.isDateInToday(day)
                let value = isToday ? today : scores.first { cal.isDate($0.day, inSameDayAs: day) }?.score
                VStack(spacing: 6) {
                    Text(value.map(String.init) ?? " ").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                    Capsule()
                        .fill(value == nil ? AnyShapeStyle(.quaternary) :
                              isToday ? AnyShapeStyle(Theme.accent) :
                              (value ?? 0) < 45 ? AnyShapeStyle(Theme.bad) : AnyShapeStyle(Theme.accent.opacity(0.5)))
                        .frame(width: 22, height: max(6, CGFloat(value ?? 6) * 0.8))
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(isToday ? .bold : .medium))
                        .foregroundStyle(isToday ? .primary : .secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 112, alignment: .bottom)
    }
}

