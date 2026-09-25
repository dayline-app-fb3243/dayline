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
            // Let the list run under the home indicator to the screen edge, like Apple's lists (the paging view
            // otherwise stops its pages at the safe area and the last card looks cut off above the bottom).
            .ignoresSafeArea(.container, edges: .bottom)
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

    /// Day title in the middle; swipe left/right to change days (no arrow buttons, per David).
    private var dateBar: some View {
        Button { showPicker = true } label: {
            VStack(spacing: 1) {
                HStack(spacing: 5) {
                    Text(title(back)).font(.headline)
                    Image(systemName: "arrowtriangle.down.fill").font(.caption2).imageScale(.small).foregroundStyle(Theme.accent)
                }
                Text(subtitle(back)).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dayTitle")
        // VoiceOver: swipe up/down on the title to change days.
        .accessibilityAdjustableAction { dir in
            withAnimation(.snappy) {
                switch dir {
                case .decrement: back = min(back + 1, maxBack)
                case .increment: back = max(back - 1, 0)
                @unknown default: break
                }
            }
        }
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
        return r.tip == nil ? r.summary : ScoreEngine.dynamicTip(score: r.score, factors: r.factors)
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
                        FactorGlassList(factors: r.factors)
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
        // The page runs under the home indicator; keep the last card clear of it when scrolled to the end.
        .contentMargins(.bottom, 34, for: .scrollContent)
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
        // Like Apple Calendar: the picked day is a filled circle; today is blue text when it isn't picked.
        let isToday = cal.isDate(date, inSameDayAs: today)
        return Button { onPick(date) } label: {
            VStack(spacing: 2) {
                Text(date.formatted(.dateTime.day())).font(.body.weight(selectable ? .semibold : .regular)).monospacedDigit()
                    .foregroundStyle(isSelected ? Color.white : isToday ? Theme.accent : selectable ? Color.primary : Color.secondary.opacity(0.5))
                    .frame(width: 38, height: 38)
                    .background(isSelected ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(.clear), in: .circle)
                Circle().fill(score.map { $0 < 45 ? Theme.bad : Theme.accent } ?? .clear).frame(width: 5, height: 5)
            }
            .frame(width: 40, height: 46)
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .frame(maxWidth: .infinity)
    }
}

/// What you actually did on a day, built from visits (no manual entries).
struct DayActivityList: View {
    @Environment(\.colorScheme) private var mapScheme
    @AppStorage("symbols.show") private var showSymbols = true
    var day: Date
    var onGymTap: (() -> Void)? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \Visit.arrival) private var visits: [Visit]
    @Query(sort: \JournalEntry.date) private var journal: [JournalEntry]

    @Query(sort: \PlanItem.start) private var plans: [PlanItem]
    /// Only what actually happened, built fresh each day: places (home stays too), journal entries away from a place,
    /// plans you finished, and a "?" row for time Dayline knows nothing about. Tap any row to open it.
    @State private var open: String?

    struct Row: Identifiable {
        var id: String; var time: Date; var title: String; var detail: String; var isNow: Bool
        var symbol = "sun.max.fill"
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
        for v in visits where window.contains(v.arrival) && v.category != .home && v.arrival <= now {
            let here = v.departure.map { $0 > now } ?? true
            let end = here ? now : v.departure!
            var detail = here && isToday ? "Here since \(Self.clock.string(from: v.arrival))" : Self.duration(end.timeIntervalSince(v.arrival))
            let photos = journal.filter { $0.kind == .photo && $0.date >= v.arrival && $0.date <= end }.count
            if photos > 0 { detail += " · \(photos) photo\(photos == 1 ? "" : "s")" }
            out.append(Row(id: "\(v.arrival.timeIntervalSince1970)-\(v.placeKey)", time: v.arrival, title: v.placeName, detail: detail, isNow: here && isToday,
                           symbol: v.category.symbol, place: CLLocationCoordinate2D(latitude: v.latitude, longitude: v.longitude), end: end))
        }
        out = builtFromDay(out, day: day, window: window, wake: wake, now: now, isToday: isToday)
        return out.sorted { $0.time < $1.time }
    }

    /// Adds home stays, journal entries away from any place, finished plans, and "?" rows for unknown time.
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
        // JournalGroup uses the composer groupID, so photos, voice and text saved together
        // appear as one event rather than separate schedule rows.
        let eligibleJournal = journal.filter { window.contains($0.date) && $0.date <= now }
        let visibleJournal = eligibleJournal.filter { entry in
            entry.placeName == "Apple Health" || !covered(entry.date)
        }
        for j in visibleJournal where j.placeName == "Apple Health" {
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
        }
        let groups = JournalGroup.make(eligibleJournal.filter { $0.placeName != "Apple Health" }
            .sorted { $0.date > $1.date }, visits: visits)
        for group in groups where group.entries.contains(where: { !covered($0.date) }) {
            let first = group.entries.min(by: { $0.date < $1.date })!
            let text = group.text ?? group.voice?.text ?? ""
            let title = group.title ?? "Journal entry"
            let media = group.photos.count
            let detail = text.isEmpty ? (media > 0 ? "\(media) photo\(media == 1 ? "" : "s")" : "From your journal") : String(text.prefix(60))
            out.append(Row(id: "j-\(group.id)", time: group.date, title: title,
                           detail: detail, isNow: false, symbol: "pencil",
                           place: first.latitude.flatMap { la in first.longitude.map { CLLocationCoordinate2D(latitude: la, longitude: $0) } },
                           end: group.date, kind: .journal, note: text.isEmpty ? nil : text))
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
                .environment(\.colorScheme, SystemMapAppearance.scheme)
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

    var body: some View {
        let all = rows
        Card(padding: 0) {
            if all.isEmpty {
                Text("Nothing yet. Dayline fills this in from where you go.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(16)
            } else {
                blocks(all)
            }
        }
        .accessibilityIdentifier("scheduleLayout")
    }
}

/// Dayline's grouped-card factor list. Preview variants change only icon treatment.
struct FactorGlassList: View {
    @AppStorage("symbols.show") private var showSymbols = true
    let factors: [ScoreFactor]
    var body: some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(factors.enumerated()), id: \.element.id) { i, f in
                    FactorRow(factor: f)
                    if i < factors.count - 1 {
                        Divider().padding(.leading, showSymbols ? 70 : 16)
                            .padding(.trailing, 16)
                    }
                }
            }
        }
    }
}

struct FactorRow: View {
    var factor: ScoreFactor
    @AppStorage("symbols.show") private var showSymbols = true
    @AppStorage("factorIcons") private var iconStyle = "gray"
    private var styleVariant: Int {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-factorIconStyle"), i + 1 < a.count else { return 2 }
        return Int(a[i + 1]) ?? 2
    }
    var body: some View {
        let symbol = Self.style(factor).0
        let bad = factor.effect == .pending || factor.points <= 0
        HStack(spacing: 12) {
            if showSymbols {
                let tint = factor.points < 0 ? Theme.bad : Theme.accent
                let glyph = Image(systemName: symbol).font(.body.weight(.medium))
                switch styleVariant {
                case 1: // Square, Apple's Settings-like rounded square.
                    glyph.foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(tint.opacity(0.13), in: .rect(cornerRadius: 9))
                case 2: // Neutral gray circle; only the glyph carries the meaning color.
                    glyph.foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(Color(.tertiarySystemFill), in: .circle)
                case 3: // Subtle native glass icon, lighter than the card's surface.
                    glyph.foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .glassEffect(.regular, in: .circle)
                case 4: // Darker solid fill and white glyph.
                    glyph.foregroundStyle(.white)
                        .frame(width: 38, height: 38)
                        .background(factor.points < 0 ? Color(red: 0.72, green: 0.34, blue: 0.03) : Color(red: 0.06, green: 0.31, blue: 0.68), in: .circle)
                default:
                    glyph.foregroundStyle(tint)
                        .frame(width: 38, height: 38)
                        .background(iconStyle == "bare" ? Color.clear : tint.opacity(0.14), in: .circle)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayTitle).font(.body)
                Text(factor.detail ?? (bad ? "No points yet" : "Adds to your score"))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(factor.points > 0 ? "+" : "")\(factor.points) pts")
                .font(.subheadline).monospacedDigit()
                .foregroundStyle(factor.points > 0 ? Color.primary : Color.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var displayTitle: String {
        let title = factor.title
        if title.range(of: #"^\d+/\d+ done$"#, options: .regularExpression) != nil {
            let count = title.replacingOccurrences(of: " done", with: "").split(separator: "/")
            if count.count == 2 { return "Plans: \(count[0]) of \(count[1]) done" }
        }
        return title
    }

    static func style(_ factor: ScoreFactor) -> (String, Color) {
        switch factor.part {
        case "wake": return ("sun.max.fill", .orange)
        case "bed": return ("moon.fill", Theme.accent)
        case "work": return ("briefcase.fill", Theme.accent)
        case "plans": return ("checklist", Theme.accent)
        case "moving": return ("figure.walk", .teal)
        case "gotOut": return ("sun.horizon.fill", .orange)
        case "journal": return ("pencil", Theme.journal)
        default: break
        }
        let t = factor.title.lowercased()
        if t.hasPrefix("up at") || t.contains("start") || t.contains("woke") || t == "wake-up" { return ("sun.max.fill", .orange) }
        if t.contains("bed") || t.contains("late night") { return ("moon.fill", Theme.bad) }
        if t.contains("work") && !t.contains("workout") { return ("briefcase.fill", Theme.accent) }
        if t.contains("plan") || t.contains("reminder") || t.contains("done") { return ("checklist", Theme.accent) }
        if t.contains("gym") || t.contains("strength") { return ("dumbbell.fill", Theme.good) }
        if t.contains("run") || t.contains("step") || t.contains("walk") || t.contains("move") { return ("figure.walk", .teal) }
        if t.contains("ride") || t.contains("cycling") { return ("bicycle", .teal) }
        if t.contains("swim") { return ("figure.pool.swim", .teal) }
        if t.contains("yoga") { return ("figure.yoga", .teal) }
        if t.contains("place") { return ("mappin", .teal) }
        if t.contains("outside") || t.contains("went out") { return ("sun.horizon.fill", .orange) }
        if t.contains("journal") { return ("pencil", Theme.journal) }
        return ("circle.grid.2x2.fill", Theme.accent)
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

// MARK: - Schedule rows

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
        Image(systemName: r.kind == .wake ? "sun.max.fill" : r.symbol).font(.scaled(size: size * 0.45, weight: .semibold, relativeTo: .body))
            .foregroundStyle(r.kind == .gap ? Color.secondary : (r.isNow ? Color.white : Theme.accent))
            .frame(width: size, height: size)
            .background(r.kind == .gap ? AnyShapeStyle(Color(.secondarySystemFill)) : (r.isNow ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.accent.opacity(0.14))), in: .circle)
    }
    fileprivate func chevron(_ r: Row) -> some View {
        let opensGym = onGymTap != nil && r.kind == .visit && r.title.localizedCaseInsensitiveContains("gym")
        return Image(systemName: opensGym ? "chevron.right" : "chevron.down")
            .font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
            .rotationEffect(.degrees(opensGym ? 0 : (open == r.id ? 180 : 0)))
    }

    /// Each row: a blue bar sized by how long it took, the symbol, the title, and from-till under it.
    fileprivate func blocks(_ all: [Row]) -> some View {
        func mins(_ r: Row) -> Double { (r.end ?? r.time).timeIntervalSince(r.time) / 60 }
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(all.enumerated()), id: \.element.id) { i, r in
                let h = max(44, min(120, 44 + mins(r) / 3))
                let bar = r.kind == .wake || mins(r) < 1 ? CGFloat(8) : h
                HStack(alignment: .top, spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(r.kind == .gap ? AnyShapeStyle(Color.clear) : AnyShapeStyle(Theme.accent.opacity(r.isNow ? 0.9 : 0.35)))
                        .overlay {
                            if r.kind == .gap {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .stroke(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                            }
                        }
                        .frame(width: 8, height: bar)
                        .frame(width: 20, height: h, alignment: .top)
                    HStack(spacing: 10) {
                        if showSymbols { icon(r, size: 26) }
                        VStack(alignment: .leading, spacing: 1) {
                            Text(r.title).foregroundStyle(r.kind == .gap ? .secondary : .primary)
                            Text(sub(r).isEmpty ? range(r) : "\(range(r)) · \(sub(r))").font(.subheadline).foregroundStyle(.secondary).monospacedDigit().lineLimit(1)
                        }
                        Spacer()
                        chevron(r)
                    }
                    .frame(minHeight: 44)
                }
                .padding(.horizontal, 14)
                .contentShape(.rect).onTapGesture {
                    if r.kind == .visit && r.title.localizedCaseInsensitiveContains("gym"), let onGymTap {
                        onGymTap()
                    } else { toggle(r) }
                }
                .accessibilityIdentifier("scheduleRow-\(i)")
                if open == r.id { detail(r) }
            }
        }
        .padding(.vertical, 10)
    }
}
