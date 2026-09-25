import SwiftUI
import SwiftData
import MapKit

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
                        Image(systemName: "arrowtriangle.down.fill").font(.scaled(size: 8)).foregroundStyle(Theme.accent)
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
            Image(systemName: symbol).font(.scaled(size: 14, weight: .semibold)).foregroundStyle(.primary)
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

    /// The same tip the Today card shows, so the two never disagree.
    private func todayTip(_ r: ScoreEngine.Result) -> String {
        if DemoData.isDemo, !(UserDefaults.standard.string(forKey: "demo.pace") ?? "").isEmpty { return r.tip ?? r.summary }
        let card = UserDefaults.standard.string(forKey: "today.card") ?? "A"
        return card.isEmpty || r.tip == nil ? (r.tip ?? r.summary) : ScoreEngine.dynamicTip(score: r.score, factors: r.factors)
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
                    // Same look as Today sample 1 (big centered ring), per David 7:56: the Today card stays, tapping it opens this.
                    Card {
                        VStack(spacing: 10) {
                            if b == 0 {
                                let behind = r.pace?.behind ?? false
                                ScoreRing(score: r.score, size: 150, lost: r.pace?.net, good: r.pace?.good)
                                Text(StatusPhrase.text(behind: behind, score: r.score)).font(.title2.bold())
                                    .foregroundStyle(behind ? Theme.bad : Theme.accent)
                                Text(todayTip(r)).font(.subheadline).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            } else {
                                ScoreRing(score: r.score, size: 150)
                                Text(r.label).font(.title2.bold()).foregroundStyle(Theme.scoreColor(r.score))
                                Text(r.summary.isEmpty ? (r.tip ?? "") : r.summary).font(.subheadline).foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 6)
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
                    if UserDefaults.standard.string(forKey: "score.friends") == "2" { FriendsTodayCard() }
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

    @Query(sort: \PlanItem.start) private var plans: [PlanItem]
    /// Preview flag "today.schedule": C (default, with layout 4d) = only what happened. A = plain list, no taps. B = timeline with a line through
    /// category symbols, plus plans still to come today in gray. C = only what actually happened, built fresh
    /// each day: places (home stays too), journal entries away from a place, plans you finished, and a "?" row
    /// for time Dayline knows nothing about, with a guess. Tap any row to open it.
    @AppStorage("today.schedule") private var style = "C"
    @State private var open: String?

    struct Row: Identifiable {
        var id: String; var time: Date; var title: String; var detail: String; var isNow: Bool
        var symbol = "sun.max.fill"; var upcoming = false
        var place: CLLocationCoordinate2D? = nil; var end: Date? = nil
        var kind = Kind.visit; var note: String? = nil
        enum Kind { case wake, visit, journal, plan, gap }
    }

    static let clock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()

    private var rows: [Row] {
        let cal = Calendar.current, now = Date.now
        var out: [Row] = []
        let isToday = cal.isDate(day, inSameDayAs: DayBoundary.shared.today)
        let window = DayBoundary.shared.window(for: day)
        let sensedWake = DayBoundary.shared.wakeUp(on: day)
        let wake: Date? = (DemoData.isDemo && isToday)
            ? cal.date(bySettingHour: DemoData.lateDay ? 9 : 6, minute: DemoData.lateDay ? 0 : 50, second: 0, of: day)
            : DayData.input(for: day, context: context).firstActivity
        let wakeDetail = DemoData.isDemo ? "Phone first used" : (sensedWake != nil ? "First move after sleep" : "First activity")
        if let wake {
            out.append(Row(id: "wake", time: wake, title: "Woke up", detail: wakeDetail, isNow: false, kind: .wake,
                           note: DemoData.isDemo || sensedWake != nil
                               ? "Up at \(Self.clock.string(from: wake)). That\u{2019}s the first time your phone moved or was used after sleep."
                               : "Your first activity today was at \(Self.clock.string(from: wake))."))
        }
        if style == "B" && isToday {
            for p in plans where cal.isDate(p.start, inSameDayAs: day) && p.start > now && !p.isDone {
                out.append(Row(id: "plan-\(p.start.timeIntervalSince1970)-\(p.title)", time: p.start, title: p.title,
                               detail: "Planned · \(Self.duration(p.end.timeIntervalSince(p.start)))", isNow: false,
                               symbol: p.category.symbol, upcoming: true))
            }
        }
        for v in visits where window.contains(v.arrival) && v.category != .home && v.arrival <= now {
            let here = v.departure.map { $0 > now } ?? true
            let end = here ? now : v.departure!
            var detail = here && isToday ? "Here since \(Self.clock.string(from: v.arrival))" : Self.duration(end.timeIntervalSince(v.arrival))
            let photos = journal.filter { $0.kind == .photo && $0.date >= v.arrival && $0.date <= end }.count
            if photos > 0 { detail += " · \(photos) photo\(photos == 1 ? "" : "s")" }
            out.append(Row(id: "\(v.arrival.timeIntervalSince1970)-\(v.placeKey)", time: v.arrival, title: v.placeName, detail: detail, isNow: here && isToday,
                           symbol: v.category.symbol, place: CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude), end: end))
        }
        if style == "C" { out = builtFromDay(out, day: day, window: window, wake: wake, now: now, isToday: isToday) }
        return out.sorted { $0.time < $1.time }
    }

    /// C: adds home stays, journal entries away from any place, finished plans, and "?" rows for unknown time.
    private func builtFromDay(_ base: [Row], day: Date, window: DateInterval, wake: Date?, now: Date, isToday: Bool) -> [Row] {
        var out = base
        let start = wake ?? window.start
        // Home stays after waking up, 45 min or longer.
        for v in visits where v.category == .home && v.arrival <= now {
            let a = max(v.arrival, start), e = min(v.departure ?? now, now, window.end)
            guard window.contains(a), e.timeIntervalSince(a) >= 45 * 60 else { continue }
            let here = (v.departure ?? .distantFuture) > now && isToday
            out.append(Row(id: "home-\(a.timeIntervalSince1970)", time: a, title: "Home",
                           detail: here ? "Here since \(Self.clock.string(from: a))" : Self.duration(e.timeIntervalSince(a)), isNow: here,
                           symbol: "house.fill", place: CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude), end: e))
        }
        func covered(_ t: Date) -> Bool { out.contains { r in r.kind == .visit && r.end.map { t >= r.time && t <= $0 } == true } }
        // Journal entries that don't belong to a place row.
        for j in journal where window.contains(j.date) && j.date <= now && !covered(j.date) {
            if j.placeName == "Apple Health" {
                // A workout from Apple Health: "Run · 5.2 km · 31 min".
                let parts = j.text.components(separatedBy: " · ")
                let kind = parts.first ?? "Workout"
                let sym = ["Run": "figure.run", "Walk": "figure.walk", "Ride": "figure.outdoor.cycle", "Swim": "figure.pool.swim",
                           "Yoga": "figure.yoga"][kind] ?? "figure.strengthtraining.traditional"
                let mins = Int(parts.last?.components(separatedBy: " ").first ?? "") ?? 30
                out.append(Row(id: "w-\(j.date.timeIntervalSince1970)", time: j.date, title: kind,
                               detail: parts.dropFirst().joined(separator: " · ") + " · Apple Health", isNow: false, symbol: sym,
                               end: j.date.addingTimeInterval(Double(mins) * 60), kind: .plan,
                               note: "From Apple Health. It counts as something good today, so it won back points on your ring."))
                continue
            }
            let (title, sym): (String, String) = switch j.kind {
            case .photo: ("Photo", "camera.fill"); case .voice: ("Voice memo", "mic.fill"); case .text: ("Journal entry", "pencil")
            }
            out.append(Row(id: "j-\(j.date.timeIntervalSince1970)", time: j.date, title: title,
                           detail: j.text.isEmpty ? "From your journal" : String(j.text.prefix(40)), isNow: false,
                           symbol: sym, place: j.latitude.flatMap { la in j.longitude.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } },
                           end: j.date, kind: .journal, note: j.text.isEmpty ? nil : j.text))
        }
        // Plans you finished that no place row already shows.
        for p in plans where window.contains(p.start) && p.isDone && !covered(p.start) && !covered(p.end) {
            out.append(Row(id: "p-\(p.start.timeIntervalSince1970)", time: p.start, title: p.title, detail: "Done · from your plans",
                           isNow: false, symbol: p.category.symbol, end: p.end, kind: .plan))
        }
        // "?" rows: 45 min or more between two things with nothing known.
        var gaps: [Row] = []
        var cursor = start
        for r in out.sorted(by: { $0.time < $1.time }) where r.time >= start {
            if r.time.timeIntervalSince(cursor) >= 45 * 60 {
                let guess = Self.guess(from: cursor, to: r.time)
                gaps.append(Row(id: "gap-\(cursor.timeIntervalSince1970)", time: cursor, title: guess,
                                detail: "\(Self.clock.string(from: cursor)) - \(Self.clock.string(from: r.time)) · not sure", isNow: false,
                                symbol: "questionmark", end: r.time, kind: .gap,
                                note: "Dayline has nothing from \(Self.clock.string(from: cursor)) to \(Self.clock.string(from: r.time)): no place, photo, or journal entry. A photo or voice memo next time fills this in."))
            }
            cursor = max(cursor, r.end ?? r.time)
        }
        return out + gaps
    }

    /// A guess for unknown time from the hour it starts: breakfast, lunch, or dinner, otherwise just "?".
    static func guess(from a: Date, to b: Date) -> String {
        let cal = Calendar.current
        let mid = a.addingTimeInterval(min(b.timeIntervalSince(a) / 2, 45 * 60))
        let m = cal.component(.hour, from: mid) * 60 + cal.component(.minute, from: mid)
        switch m {
        case 6 * 60..<(10 * 60 + 30): return "Breakfast?"
        case (11 * 60 + 30)..<(14 * 60 + 30): return "Lunch?"
        case (17 * 60 + 30)..<(21 * 60): return "Dinner?"
        default: return "Not sure"
        }
    }

    /// C: the opened row (wake and journal rows show no photos). From arrival to leaving (or now), the photos taken there, and a small map.
    @ViewBuilder private func detail(_ r: Row) -> some View {
        let end = r.end ?? .now
        let pics = (r.kind == .wake || r.kind == .journal) ? [] : journal.filter { $0.kind == .photo && $0.date >= r.time && $0.date <= end }.compactMap { $0.thumbnail.flatMap(UIImage.init(data:)) }
        let texts = r.kind == .visit ? journal.filter { $0.kind != .photo && !$0.text.isEmpty && $0.date >= r.time && $0.date <= end }.map(\.text) : []
        VStack(alignment: .leading, spacing: 10) {
            if r.kind == .visit || r.kind == .plan {
                Text("\(Self.clock.string(from: r.time)) - \(r.isNow ? "now" : Self.clock.string(from: end))")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            if let note = r.note { Text(note).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            ForEach(texts, id: \.self) { t in
                Text("\u{201C}\(t)\u{201D}").font(.subheadline).fixedSize(horizontal: false, vertical: true)
            }
            if !pics.isEmpty {
                HStack(spacing: 6) {
                    ForEach(pics.indices.prefix(4), id: \.self) { k in
                        Image(uiImage: pics[k]).resizable().scaledToFill().frame(width: 64, height: 64).clipShape(.rect(cornerRadius: 10))
                    }
                }
            }
            if let place = r.place, r.kind == .visit {
                Map(initialPosition: .camera(MapCamera(centerCoordinate: place, distance: 700))) {
                    Marker(r.title, systemImage: r.symbol, coordinate: place).tint(Theme.accent)
                }
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .allowsHitTesting(false)
                .frame(height: 120).clipShape(.rect(cornerRadius: 12))
            }
        }
        .padding(.leading, 70).padding(.trailing, 14).padding(.bottom, 12)
        .transition(.opacity)
    }

    static func duration(_ t: TimeInterval) -> String {
        let m = Int(t / 60)
        return m >= 60 ? "\(m / 60) h \(m % 60) min" : "\(m) min"
    }

    /// Preview flag "schedule.layout" (only with today.schedule C; "" = the current list). Every row shows from when
    /// till when, and no time shows twice. 1 = start over end in the time column, wake-up as a header line.
    /// 2 = no time column, the range under the title. 3 = a line with pins at each start and end.
    /// 4 = a line of blocks sized by how long each thing took. 5 = times as small dividers between rows.
    /// 6 = the range in a pill on the right.
    /// 4a-4f = takes on 4, each shows a time only once (a shared start/end shows as the next start):
    /// a = 4 with that fix. b = one line runs through all blocks. c = the icon sits inside a wider block.
    /// d = no time column, the range under the title. e = each stay is a tinted card sized by how long it took.
    /// f = every row the same height.
    @AppStorage("schedule.layout") var layout = "4d"

    var body: some View {
        switch style {
        case "B": timelineBody
        default:
            if style == "C" && !layout.isEmpty { layoutBody } else { listBody }
        }
    }

    /// B: a line through the day, a symbol per stop, the next plans in gray under a "Later today" dot.
    private var timelineBody: some View {
        let rows = rows
        return Card(padding: 0) {
            if rows.isEmpty {
                Text("Nothing yet. Dayline fills this in from where you go.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, r in
                        HStack(alignment: .center, spacing: 12) {
                            Text(Self.clock.string(from: r.time))
                                .font(.subheadline.weight(.semibold)).foregroundStyle(r.upcoming ? .tertiary : .secondary).monospacedDigit()
                                .frame(width: 46, alignment: .leading)
                            ZStack {
                                // The line: solid for what happened, dotted for what is still planned.
                                VStack(spacing: 0) {
                                    Rectangle().fill(i == 0 ? .clear : (r.upcoming ? Color.secondary.opacity(0.3) : Theme.accent.opacity(0.35))).frame(width: 2)
                                    Rectangle().fill(i == rows.count - 1 ? .clear : (rows[i + 1].upcoming ? Color.secondary.opacity(0.3) : Theme.accent.opacity(0.35))).frame(width: 2)
                                }
                                Image(systemName: r.symbol).font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(r.upcoming ? Color.secondary : (r.isNow ? .white : Theme.accent))
                                    .frame(width: 30, height: 30)
                                    .background(r.upcoming ? AnyShapeStyle(Color(.secondarySystemFill)) : (r.isNow ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14))), in: .circle)
                            }
                            .frame(width: 30)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.body.weight(.semibold)).foregroundStyle(r.upcoming ? .secondary : .primary)
                                Text(r.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if r.isNow { Text("now").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                        }
                        .padding(.horizontal, 14).frame(minHeight: 58)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private var listBody: some View {
        let rows = rows
        return Card(padding: 0) {
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
                            if r.kind == .gap {
                                Circle().stroke(Color.secondary.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2, 2])).frame(width: 8, height: 8)
                            } else {
                                Circle().fill(Theme.accent).frame(width: 8, height: 8)
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(r.title).font(.body.weight(.semibold)).foregroundStyle(r.kind == .gap ? .secondary : .primary)
                                Text(r.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if r.isNow { Text("now").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent) }
                            if style == "C" {
                                Image(systemName: "chevron.down").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                                    .rotationEffect(.degrees(open == r.id ? 180 : 0))
                            }
                        }
                        .padding(.horizontal, 14).padding(.vertical, 11)
                        .contentShape(.rect)
                        .onTapGesture {
                            guard style == "C" else { return }
                            withAnimation(.snappy) { open = open == r.id ? nil : r.id }
                        }
                        .accessibilityIdentifier("scheduleRow-\(i)")
                        if style == "C", open == r.id { detail(r) }
                        if i < rows.count - 1 { Divider().padding(.leading, 70) }
                    }
                }
            }
        }
    }
}

struct FactorRow: View {
    var factor: ScoreFactor
    /// no tile. Old previews: icons.tile A/A2/A3/C/C2.
    @AppStorage("icons.tile") private var tile = "blue"
    @AppStorage("symbols.show") private var showSymbols = true
    var body: some View {
        let st = Self.style(factor.title)
        let symbol = st.0
        let bad = factor.effect == .pending || factor.points <= 0
        let color = ["A2", "A3", "C2"].contains(tile) ? st.1 : (bad ? Theme.bad : Theme.accent)
        HStack(spacing: 12) {
            if tile == "blue" {
                // Sep 24: David wants C (blue symbol in a light round circle) when Show Symbols is on, nothing when off.
                if showSymbols {
                    Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                        .frame(width: 34, height: 34).background(Theme.accent.opacity(0.14), in: .circle)
                }
            } else {
                ProfileIcon(symbol: symbol, size: 30, color: color)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(factor.title).font(.body.weight(.semibold))
                Text(factor.detail ?? (bad ? "No points yet" : factor.effect == .up ? "Counted" : "Small boost"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            Text(factor.points > 0 ? "+\(factor.points)" : factor.points == 0 ? "0" : "\(factor.points)")
                .font(.body.weight(.semibold)).monospacedDigit()
                .foregroundStyle(factor.points > 0 ? Color.primary : Color.secondary)
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

// MARK: - Schedule layout previews ("schedule.layout" 1-6)

extension DayActivityList {
    /// "9:00", or "12:00 – 12:50", or "3:10 – now".
    fileprivate func range(_ r: Row) -> String {
        let a = Self.clock.string(from: r.time)
        guard r.kind != .wake, let e = r.end, e.timeIntervalSince(r.time) >= 60 else { return a }
        return "\(a) – \(r.isNow ? "now" : Self.clock.string(from: e))"
    }
    /// The small line under the title, without any "50 min".
    fileprivate func sub(_ r: Row) -> String {
        switch r.kind {
        case .gap: return "Not sure what this was"
        case .wake: return r.detail
        case .journal: return r.detail
        case .plan:
            let parts = r.detail.components(separatedBy: " · ").filter { !$0.hasSuffix(" min") && !$0.hasPrefix("Done") }
            return parts.isEmpty ? "Done" : parts.joined(separator: " · ")
        case .visit:
            let photos = r.detail.components(separatedBy: " · ").first { $0.contains("photo") }
            return r.isNow ? "You\u{2019}re here" : (photos ?? "")
        }
    }
    fileprivate func toggle(_ r: Row) { withAnimation(.snappy) { open = open == r.id ? nil : r.id } }

    fileprivate func icon(_ r: Row, size: CGFloat = 28) -> some View {
        Image(systemName: r.kind == .wake ? "sun.max.fill" : r.symbol).font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(r.kind == .gap ? Color.secondary : (r.isNow ? Color.white : Theme.accent))
            .frame(width: size, height: size)
            .background(r.kind == .gap ? AnyShapeStyle(Color(.secondarySystemFill)) : (r.isNow ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14))), in: .circle)
    }
    fileprivate func titles(_ r: Row) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(r.title).font(.body.weight(.semibold)).foregroundStyle(r.kind == .gap ? .secondary : .primary)
            let s = sub(r)
            if !s.isEmpty { Text(s).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
        }
    }
    fileprivate func chevron(_ r: Row) -> some View {
        Image(systemName: "chevron.down").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(open == r.id ? 180 : 0))
    }

    @ViewBuilder var layoutBody: some View {
        let all = rows
        Card(padding: 0) {
            if all.isEmpty {
                Text("Nothing yet. Dayline fills this in from where you go.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
            } else {
                switch layout {
                case "3": pinLayout(all, line: true)
                case "4": blockLayout(all)
                case "4a", "4b", "4c", "4d", "4e", "4f": block4(all)
                case "5": pinLayout(all, line: false)
                default: plainLayout(all)
                }
            }
        }
        .accessibilityIdentifier("scheduleLayout")
    }

    /// 1, 2 and 6: wake-up becomes a header line; each row carries its own range.
    fileprivate func plainLayout(_ all: [Row]) -> some View {
        let wake = all.first { $0.kind == .wake }
        let list = all.filter { $0.kind != .wake }
        return VStack(spacing: 0) {
            if let wake {
                HStack(spacing: 8) {
                    Image(systemName: "sun.max.fill").foregroundStyle(Theme.accent)
                    Text("Woke up at \(Self.clock.string(from: wake.time))").font(.subheadline.weight(.semibold))
                    Spacer()
                    chevron(wake)
                }
                .padding(.horizontal, 14).padding(.vertical, 10)
                .contentShape(.rect).onTapGesture { toggle(wake) }
                if open == wake.id { detail(wake) }
                Divider()
            }
            ForEach(Array(list.enumerated()), id: \.element.id) { i, r in
                plainRow(r).contentShape(.rect).onTapGesture { toggle(r) }
                    .accessibilityIdentifier("scheduleRow-\(i)")
                if open == r.id { detail(r) }
                if i < list.count - 1 { Divider().padding(.leading, layout == "1" ? 76 : 56) }
            }
        }
    }
    @ViewBuilder fileprivate func plainRow(_ r: Row) -> some View {
        HStack(spacing: 12) {
            switch layout {
            case "1":
                VStack(alignment: .leading, spacing: 0) {
                    Text(Self.clock.string(from: r.time)).font(.subheadline.weight(.semibold)).monospacedDigit()
                    if let e = r.end, e.timeIntervalSince(r.time) >= 60 {
                        Text(r.isNow ? "now" : Self.clock.string(from: e)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                    }
                }
                .frame(width: 50, alignment: .leading)
                icon(r)
                titles(r)
                Spacer()
            case "6":
                icon(r)
                titles(r)
                Spacer()
                Text(range(r)).font(.caption.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(r.isNow ? Color.white : (r.kind == .gap ? Color.secondary : Theme.accent))
                    .padding(.horizontal, 9).padding(.vertical, 5)
                    .background(r.isNow ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Color(.secondarySystemFill)), in: .capsule)
            default:
                icon(r)
                VStack(alignment: .leading, spacing: 1) {
                    Text(r.title).font(.body.weight(.semibold)).foregroundStyle(r.kind == .gap ? .secondary : .primary)
                    Text(sub(r).isEmpty ? range(r) : "\(range(r)) · \(sub(r))").font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                }
                Spacer()
            }
            chevron(r)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
    }

    /// 3 and 5: a time at every start and end, shown once. 3 joins them with a line (dashed through unknown time).
    fileprivate func pinLayout(_ all: [Row], line: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                let prevEnd: Date? = i > 0 ? (all[i - 1].end ?? all[i - 1].time) : nil
                let sharesStart = prevEnd.map { abs($0.timeIntervalSince(r.time)) < 90 } ?? false
                if !sharesStart { pin(Self.clock.string(from: r.time), filled: r.kind != .gap, first: i == 0, line: line, dashedBelow: false) }
                pinBody(r, line: line)
                    .contentShape(.rect).onTapGesture { toggle(r) }
                    .accessibilityIdentifier("scheduleRow-\(i)")
                if open == r.id { detail(r) }
                if let e = r.end, e.timeIntervalSince(r.time) >= 60 {
                    let nextStart = i + 1 < all.count ? all[i + 1].time : nil
                    let shared = nextStart.map { abs($0.timeIntervalSince(e)) < 90 } ?? false
                    pin(r.isNow ? "now" : Self.clock.string(from: e), filled: true, first: false, line: line,
                        dashedBelow: shared && all[i + 1].kind == .gap, last: i == all.count - 1)
                }
            }
        }
        .padding(.vertical, 6)
    }
    fileprivate func pin(_ time: String, filled: Bool, first: Bool, line: Bool, dashedBelow: Bool, last: Bool = false) -> some View {
        HStack(spacing: 10) {
            Text(time).font(.caption.weight(.semibold)).foregroundStyle(.secondary).monospacedDigit()
                .frame(width: 44, alignment: .trailing)
            if line {
                Circle().fill(Theme.accent).frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                    .frame(width: 20)
            } else {
                Rectangle().fill(Color.secondary.opacity(0.25)).frame(height: 1)
            }
            if line { Spacer() }
        }
        .padding(.horizontal, 14).frame(height: 22)
        .background(alignment: .leading) {
            if line && !first {
                Rectangle().fill(Theme.accent.opacity(0.35)).frame(width: 2).frame(maxHeight: last ? 11 : .infinity, alignment: .top)
                    .padding(.leading, 14 + 44 + 10 + 9).frame(maxHeight: .infinity, alignment: .top)
            }
        }
    }
    fileprivate func pinBody(_ r: Row, line: Bool) -> some View {
        HStack(spacing: 10) {
            Color.clear.frame(width: 44)
            if line {
                Group {
                    if r.kind == .gap {
                        VLine().stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 2, dash: [3, 3])).frame(width: 2)
                    } else {
                        Rectangle().fill(Theme.accent.opacity(0.35)).frame(width: 2)
                    }
                }
                .frame(width: 20).frame(maxHeight: .infinity)
            }
            icon(r, size: 26)
            titles(r)
            Spacer()
            chevron(r)
        }
        .padding(.horizontal, 14).frame(minHeight: 50)
    }

    /// 4: blocks on a line, taller the longer it took (capped), start and end beside each block.
    fileprivate func blockLayout(_ all: [Row]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                let mins = (r.end ?? r.time).timeIntervalSince(r.time) / 60
                let h = max(44, min(120, 44 + mins / 3))
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .trailing) {
                        Text(Self.clock.string(from: r.time)).font(.caption.weight(.semibold)).monospacedDigit()
                        Spacer(minLength: 0)
                        if r.kind != .wake, mins >= 1 {
                            Text(r.isNow ? "now" : Self.clock.string(from: r.end ?? r.time)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    .frame(width: 44, height: h, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(r.kind == .gap ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.accent.opacity(r.isNow ? 0.9 : 0.35)))
                        .overlay {
                            if r.kind == .gap {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            }
                        }
                        .frame(width: 8, height: r.kind == .wake || mins < 1 ? 8 : h)
                        .frame(width: 20, height: h, alignment: .top)
                    HStack(spacing: 10) {
                        icon(r, size: 26)
                        titles(r)
                        Spacer()
                        chevron(r)
                    }
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 14)
                .contentShape(.rect).onTapGesture { toggle(r) }
                .accessibilityIdentifier("scheduleRow-\(i)")
                if open == r.id { detail(r) }
            }
        }
        .padding(.vertical, 10)
    }
    /// 4a-4f (see the "schedule.layout" note).
    fileprivate func block4(_ all: [Row]) -> some View {
        let v = layout
        func mins(_ r: Row) -> Double { (r.end ?? r.time).timeIntervalSince(r.time) / 60 }
        func showStart(_ i: Int) -> Bool {
            guard i > 0 else { return true }
            let p = all[i - 1]
            return !(p.kind == .wake && abs(p.time.timeIntervalSince(all[i].time)) < 90)
        }
        func showEnd(_ i: Int) -> Bool {
            let r = all[i]
            guard r.kind != .wake, mins(r) >= 1 else { return false }
            if r.isNow { return true }
            guard i + 1 < all.count, let e = r.end else { return true }
            return abs(all[i + 1].time.timeIntervalSince(e)) >= 90
        }
        func height(_ r: Row) -> CGFloat {
            if v == "4f" { return 52 }
            let m = mins(r)
            return v == "4e" ? max(52, min(150, 52 + m / 2.5)) : max(44, min(120, 44 + m / 3))
        }
        func fill(_ r: Row) -> AnyShapeStyle {
            r.kind == .gap ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.accent.opacity(r.isNow ? 0.9 : 0.35))
        }
        return ZStack(alignment: .topLeading) {
            if v == "4b" {
                Rectangle().fill(Theme.accent.opacity(0.2)).frame(width: 2)
                    .padding(.leading, 14 + 44 + 10 + 9).padding(.vertical, 18)
            }
            VStack(alignment: .leading, spacing: v == "4b" || v == "4f" ? 0 : 6) {
                ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                    let h = height(r)
                    let bar = r.kind == .wake || mins(r) < 1 ? CGFloat(8) : h
                    HStack(alignment: .top, spacing: 10) {
                        if v != "4d" {
                            VStack(alignment: .trailing) {
                                if showStart(i) { Text(Self.clock.string(from: r.time)).font(.caption.weight(.semibold)).monospacedDigit() }
                                Spacer(minLength: 0)
                                if showEnd(i) {
                                    Text(r.isNow ? "now" : Self.clock.string(from: r.end ?? r.time)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                }
                            }
                            .frame(width: 44, height: h, alignment: .trailing)
                        }
                        if v == "4e" {
                            HStack(alignment: .top, spacing: 10) {
                                icon(r, size: 26)
                                titles(r)
                                Spacer()
                                chevron(r)
                            }
                            .padding(10)
                            .frame(height: h, alignment: .top)
                            .background(r.kind == .gap ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.accent.opacity(r.isNow ? 0.22 : 0.1)),
                                        in: .rect(cornerRadius: 12, style: .continuous))
                            .overlay {
                                if r.kind == .gap {
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .stroke(Color.secondary.opacity(0.45), style: StrokeStyle(lineWidth: 1.2, dash: [4, 3]))
                                }
                            }
                            .overlay(alignment: .leading) {
                                if r.kind != .gap { RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(r.isNow ? 1 : 0.6)).frame(width: 4).padding(.vertical, 8) }
                            }
                        } else {
                            let w: CGFloat = v == "4c" ? 30 : (v == "4a" || v == "4d" ? 8 : 10)
                            RoundedRectangle(cornerRadius: v == "4c" ? 9 : 5, style: .continuous)
                                .fill(fill(r))
                                .overlay {
                                    if r.kind == .gap {
                                        RoundedRectangle(cornerRadius: v == "4c" ? 9 : 5, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                                    }
                                }
                                .overlay(alignment: .top) {
                                    if v == "4c" {
                                        Image(systemName: r.kind == .wake ? "sun.max.fill" : r.symbol).font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(r.kind == .gap ? Color.secondary : (r.isNow ? Color.white : Theme.accent))
                                            .padding(.top, 8)
                                    }
                                }
                                .frame(width: w, height: v == "4c" ? max(bar, 30) : bar)
                                .frame(width: v == "4c" ? 30 : 20, height: h, alignment: .top)
                            HStack(spacing: 10) {
                                if v != "4c" { icon(r, size: 26) }
                                if v == "4d" {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(r.title).font(.body.weight(.semibold)).foregroundStyle(r.kind == .gap ? .secondary : .primary)
                                        Text(sub(r).isEmpty ? range(r) : "\(range(r)) · \(sub(r))").font(.caption).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                                    }
                                } else {
                                    titles(r)
                                }
                                Spacer()
                                chevron(r)
                            }
                            .frame(minHeight: 44)
                        }
                    }
                    .padding(.horizontal, 14)
                    .contentShape(.rect).onTapGesture { toggle(r) }
                    .accessibilityIdentifier("scheduleRow-\(i)")
                    if open == r.id { detail(r) }
                }
            }
        }
        .padding(.vertical, 10)
    }
}

/// A vertical line down the middle of its frame (dashed "unknown time" segments).
private struct VLine: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); p.move(to: CGPoint(x: rect.midX, y: rect.minY)); p.addLine(to: CGPoint(x: rect.midX, y: rect.maxY)); return p
    }
}
