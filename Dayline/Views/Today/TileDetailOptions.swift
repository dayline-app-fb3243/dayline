import SwiftUI
import Charts
import MapKit
import SwiftData

// Steps page (Health-style chart) and Gym page options (-detailVariant N previews alternatives).

enum TileDetailOption {
    static var variant: Int {
        let a = ProcessInfo.processInfo.arguments
        guard let i = a.firstIndex(of: "-detailVariant"), i + 1 < a.count else { return 1 }
        return Int(a[i + 1]) ?? 1
    }
}

private enum StepsDemo {
    static let today = 5840, goal = 8200
    /// Steps per hour, 6 AM to 11 PM (demo).
    static let hourly: [(Int, Int)] = [(6, 0), (7, 420), (8, 1310), (9, 640), (10, 180), (11, 220), (12, 960), (13, 540), (14, 160), (15, 210), (16, 380), (17, 820), (18, 0), (19, 0), (20, 0), (21, 0), (22, 0)]
    static let week: [(String, Int)] = [("Sat", 9120), ("Sun", 6450), ("Mon", 8830), ("Tue", 7210), ("Wed", 10240), ("Thu", 8600), ("Fri", 5840)]
}

private enum GymDemo {
    static let place = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
    static let visits: [(String, String, String)] = [
        ("Today", "7:00 - 7:52 AM", "52 min"), ("Wednesday", "6:45 - 7:50 AM", "65 min"),
        ("Monday", "6:55 - 7:45 AM", "50 min"), ("Saturday", "10:10 - 11:20 AM", "70 min"),
        ("Thursday, Sep 17", "7:05 - 7:55 AM", "50 min"),
    ]
}

// MARK: - Shared pieces

private struct Page<C: View>: View {
    var title: String
    @ViewBuilder var content: C
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(.horizontal, 18).padding(.bottom, 30).padding(.top, 6)
        }
        .background(AppBackgroundView())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.large)
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

private struct Row: View {
    var symbol: String; var title: String; var value: String
    var body: some View {
        HStack(spacing: 13) {
            ProfileIcon(symbol: symbol)
            Text(title).font(.body)
            Spacer()
            Text(value).font(.body).foregroundStyle(.secondary).monospacedDigit()
        }
        .padding(.horizontal, 16).padding(.vertical, 11)
    }
}

private struct Header: View {
    var text: String
    var body: some View { Text(text).font(.subheadline.weight(.semibold)).helperText().padding(.leading, 16).padding(.top, 6) }
}

// MARK: - Steps

struct StepsDetailView: View {
    /// D = today by hour, W = the last 7 days. Motion keeps about a week of steps, so longer ranges aren't offered.
    @State private var range = "D"
    @State private var hourly: [(Int, Int)] = DemoData.isDemo ? StepsDemo.hourly : []
    @State private var week: [(String, Int)] = DemoData.isDemo ? StepsDemo.week : []
    @State private var today = DemoData.isDemo ? StepsDemo.today : 0
    private var usual: Int { DemoData.isDemo ? StepsDemo.goal : UserSchedule.current.stepGoal }
    private var weekAverage: Int { week.isEmpty ? 0 : week.map(\.1).reduce(0, +) / week.count }

    var body: some View {
        Page(title: "Steps") {
            Picker("Range", selection: $range) { ForEach(["D", "W"], id: \.self) { Text($0) } }.pickerStyle(.segmented)
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    bigNumber
                    if range == "D" {
                        Chart(hourly, id: \.0) { h in
                            BarMark(x: .value("Hour", h.0), y: .value("Steps", h.1), width: 9).foregroundStyle(Theme.accent).cornerRadius(3)
                        }
                        .chartXScale(domain: 5...23)
                        .chartXAxis { AxisMarks(values: [6, 12, 18]) { v in AxisGridLine(); AxisValueLabel { Text(["6 AM", "12 PM", "6 PM"][[6, 12, 18].firstIndex(of: v.as(Int.self) ?? 6) ?? 0]) } } }
                        .frame(height: 190)
                    } else {
                        Chart(Array(week.enumerated()), id: \.offset) { i, d in
                            BarMark(x: .value("Day", "\(i)"), y: .value("Steps", d.1)).foregroundStyle(Theme.accent).cornerRadius(4)
                        }
                        .chartXAxis { AxisMarks { v in AxisValueLabel { Text(week[Int(v.as(String.self) ?? "0") ?? 0].0) } } }
                        .frame(height: 190)
                    }
                }
            }
            if let line = highlight {
                Header(text: "Highlights")
                Card { Text(line).font(.body).frame(maxWidth: .infinity, alignment: .leading) }
            }
            Card(padding: 0) {
                VStack(spacing: 0) {
                    if DemoData.isDemo {
                        Row(symbol: "point.topleft.down.to.point.bottomright.curvepath.fill", title: "Distance", value: "4.3 km"); Divider().padding(.leading, 59)
                        Row(symbol: "stairs", title: "Flights Climbed", value: "6"); Divider().padding(.leading, 59)
                    }
                    Row(symbol: "chart.bar.fill", title: "Daily Average", value: weekAverage.formatted())
                }
            }
        }
        .accessibilityIdentifier("stepsDetail")
        .task { await load() }
    }

    private var bigNumber: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(range == "D" ? "TOTAL" : "DAILY AVERAGE").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text((range == "D" ? today : weekAverage).formatted()).font(.largeTitle.weight(.semibold)).monospacedDigit()
                Text("steps").font(.body).foregroundStyle(.secondary)
            }
            Text(range == "D" ? "Today" : "Last 7 Days").font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// When you walk the most today, and how today compares with your usual day.
    private var highlight: String? {
        guard today > 0, let peak = hourly.max(by: { $0.1 < $1.1 }), peak.1 > 0 else { return nil }
        let hour = Calendar.current.date(bySettingHour: peak.0, minute: 0, second: 0, of: .now) ?? .now
        let peakText = "You walk the most around \(hour.formatted(.dateTime.hour()))."
        let diff = usual - today
        let compare = diff > 0 ? " Today you're \(diff.formatted()) steps under your usual day." : " You're past your usual day."
        return peakText + compare
    }

    private func load() async {
        guard !DemoData.isDemo else { return }
        let cal = Calendar.current
        let start = cal.startOfDay(for: .now)
        today = await StepGoal.steps(from: start, to: .now)
        var hours: [(Int, Int)] = []
        let nowHour = cal.component(.hour, from: .now)
        for h in 5...23 {
            guard h <= nowHour, let a = cal.date(byAdding: .hour, value: h, to: start), let b = cal.date(byAdding: .hour, value: 1, to: a) else { hours.append((h, 0)); continue }
            hours.append((h, await StepGoal.steps(from: a, to: min(b, .now))))
        }
        hourly = hours
        var days: [(String, Int)] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let a = cal.date(byAdding: .day, value: -offset, to: start), let b = cal.date(byAdding: .day, value: 1, to: a) else { continue }
            days.append((a.formatted(.dateTime.weekday(.abbreviated)), await StepGoal.steps(from: a, to: min(b, .now))))
        }
        week = days
    }
}

// MARK: - Gym

struct GymDetailView: View {
    @Environment(\.colorScheme) private var mapScheme
    @Query(sort: \Visit.arrival, order: .reverse) private var allVisits: [Visit]
    private var gymVisits: [Visit] { allVisits.filter { $0.category == .gym } }
    private var configuredGym: SavedPlace? { UserSchedule.current.gymPlace }
    private var gymName: String { configuredGym?.name ?? gymVisits.first?.placeName ?? "Gym" }
    private var gymCoordinate: CLLocationCoordinate2D? { configuredGym?.coordinate ?? gymVisits.first?.coordinate }
    private var recentGymVisits: [(String, String)] {
        gymVisits.prefix(5).map { v in
            let day = Calendar.current.isDateInToday(v.arrival) ? "Today" : v.arrival.formatted(.dateTime.weekday(.wide))
            let minutes = max(0, Int(v.duration / 60))
            return (day, minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
    }
    /// Default page is model-backed for real users; preview variants retain demo-only design data.
    var variant = TileDetailOption.variant
    var body: some View {
        Group {
            if variant == 2 {
                heroPage
            } else {
                Page(title: "Gym") {
                    switch variant {
                    case 3: overlaid
                    case 4: withStats
                    case 5: withWeek
                    case 6, 7, 8: combined(variant)
                    case 9, 10, 11: quietNext(variant)
                    default: DemoData.isDemo ? place : realPlace
                    }
                }
            }
        }
        .accessibilityIdentifier("gymDetail")
    }

    @ViewBuilder private var realPlace: some View {
        if let coordinate = gymCoordinate {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 900))) {
                Marker(gymName, systemImage: "dumbbell.fill", coordinate: coordinate).tint(Theme.accent)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .environment(\.colorScheme, SystemMapAppearance.scheme)
            .frame(height: 210).allowsHitTesting(false)
            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
            Card { Text(gymName).font(.headline).frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            Card { Text("No gym set yet").font(.headline).frame(maxWidth: .infinity, alignment: .leading) }
        }
        Header(text: "Recent Visits")
        if recentGymVisits.isEmpty {
            Card { Text("No gym visits recorded yet.").font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading) }
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(recentGymVisits.indices, id: \.self) { i in
                        Row(symbol: "clock.fill", title: recentGymVisits[i].0, value: recentGymVisits[i].1)
                        if i < recentGymVisits.count - 1 { Divider().padding(.leading, 59) }
                    }
                }
            }
        }
    }

    private func map(height: CGFloat) -> some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: GymDemo.place, distance: 900, heading: 20, pitch: 45))) {
            Marker("Iron Works Gym", systemImage: "dumbbell.fill", coordinate: GymDemo.place).tint(Theme.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, SystemMapAppearance.scheme)
        .frame(height: height).allowsHitTesting(false)
    }

    private var nextCard: some View {
        Card { nextContent }
    }
    @AppStorage("symbols.show") private var showSymbols = true
    private var nextContent: some View {
        HStack(spacing: 13) {
            if showSymbols { ProfileIcon(symbol: "dumbbell.fill", size: 44) }
            VStack(alignment: .leading, spacing: 2) {
                Text("NEXT").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                Text("Gym around 6:00 PM").font(.headline)
                Text("Iron Works Gym · 12 min walk").font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

    /// Recent visits; with times when `times` is on.
    private func visits(_ count: Int, times: Bool = false) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(GymDemo.visits.prefix(count).enumerated()), id: \.offset) { i, v in
                    if times {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(v.0).font(.body)
                                Text(v.1).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            }
                            Spacer()
                            Text(v.2).font(.body).foregroundStyle(.secondary).monospacedDigit()
                        }
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if i < count - 1 { Divider().padding(.leading, 16) }
                    } else {
                        Row(symbol: "clock.fill", title: v.0, value: v.2)
                        if i < count - 1 { Divider().padding(.leading, 59) }
                    }
                }
            }
        }
    }

    /// 1. Map card, next visit, last visits.
    @ViewBuilder private var place: some View {
        map(height: 210).clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        nextCard
        Header(text: "Recent Visits")
        visits(3)
    }

    /// 2. Like an Apple Maps place page: the map runs edge to edge under the bar, then the page.
    private var heroPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                map(height: 330)
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Iron Works Gym").font(.largeTitle.weight(.bold))
                        Text("Gym · 12 min walk").font(.subheadline).foregroundStyle(.secondary)
                    }
                    nextCard
                    Header(text: "Recent Visits")
                    visits(4, times: true)
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 30)
        }
        .ignoresSafeArea(edges: .top)
        .background(AppBackgroundView())
        .toolbarVisibility(.hidden, for: .tabBar)
    }

    /// 3. The next visit sits on the map in glass; stats and visits below.
    @ViewBuilder private var overlaid: some View {
        map(height: 290)
            .overlay(alignment: .bottom) {
                nextContent.padding(14)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                    .padding(8)
            }
            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        Card(padding: 0) {
            VStack(spacing: 0) {
                Row(symbol: "flame.fill", title: "Weeks in a Row", value: "5"); Divider().padding(.leading, 59)
                Row(symbol: "clock.fill", title: "Average Visit", value: "57 min")
            }
        }
        Header(text: "Recent Visits")
        visits(3)
    }

    /// 4. Map, next visit, three numbers, visits with times.
    @ViewBuilder private var withStats: some View {
        map(height: 190).clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        nextCard
        HStack(spacing: 8) {
            StreakStat(title: "This Week", value: "4 visits")
            StreakStat(title: "In a Row", value: "5 weeks")
            StreakStat(title: "Average", value: "57 min")
        }
        Header(text: "Recent Visits")
        visits(4, times: true)
    }

    /// 6-8. Requested combinations of the original page and its weekly checkmarks.
    @ViewBuilder private func combined(_ style: Int) -> some View {
        map(height: style == 8 ? 190 : 210).clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        nextCard
        if style == 6 {
            Header(text: "This Week")
            weekStrip
            Header(text: "Recent Visits")
            visits(3)
        } else if style == 7 {
            Header(text: "Recent Visits")
            visits(3)
            Header(text: "This Week")
            weekStrip
        } else {
            Card(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text("This Week").font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("3 visits").font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 7)
                    weekSymbols.padding(.horizontal, 16).padding(.bottom, 14)
                }
            }
            Header(text: "Recent Visits")
            visits(3)
        }
    }
    /// Combo 7's map, recent visits and week order; only the Next treatment changes.
    @ViewBuilder private func quietNext(_ style: Int) -> some View {
        if style == 9 {
            map(height: 210)
                .overlay(alignment: .bottomLeading) {
                    Label("Next · 6:00 PM", systemImage: "clock")
                        .font(.caption).foregroundStyle(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(.regularMaterial, in: .capsule)
                        .padding(12)
                }
                .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        } else {
            map(height: 210).clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        }
        if style == 10 {
            HStack(spacing: 6) {
                Text("Next").foregroundStyle(.secondary)
                Text("Gym around 6:00 PM")
                Spacer()
                Text("12 min walk").foregroundStyle(.secondary)
            }
            .font(.subheadline).padding(.horizontal, 6).padding(.vertical, 3)
        }
        Header(text: "Recent Visits")
        visits(3)
        if style == 11 {
            HStack(spacing: 4) {
                Text("Next · 6:00 PM").font(.footnote).foregroundStyle(.secondary)
                Spacer()
                Text("12 min walk").font(.footnote).foregroundStyle(.secondary)
            }.padding(.horizontal, 16).padding(.top, 1)
        }
        Header(text: "This Week")
        weekStrip
    }
    private var weekStrip: some View { Card { weekSymbols } }
    private var weekSymbols: some View {
        HStack(spacing: 0) {
            ForEach(Array(["S", "M", "T", "W", "T", "F", "S"].enumerated()), id: \.offset) { i, d in
                let went = [1, 3, 5].contains(i), today = i == 5
                VStack(spacing: 6) {
                    Text(d).font(.caption.weight(.semibold)).foregroundStyle(today ? Theme.accent : .secondary)
                    Image(systemName: went ? "checkmark.circle.fill" : "circle")
                        .font(.title2).foregroundStyle(went ? Theme.accent : Color(.tertiaryLabel))
                }.frame(maxWidth: .infinity)
            }
        }
    }

    /// 5. Map, next visit, this week's gym days, visits.
    @ViewBuilder private var withWeek: some View {
        map(height: 190).clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
        nextCard
        Header(text: "This Week")
        weekStrip
        Header(text: "Recent Visits")
        visits(3)
    }
}
