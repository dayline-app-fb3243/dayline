import SwiftUI
import Charts
import MapKit

// Steps page (Health-style chart) and the Gym page options (-detailVariant N picks one; default 1).

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
    static let legs: [(String, String, String, Int)] = [
        ("house.fill", "Home to Gym", "7:40 - 7:58 AM", 1480),
        ("dumbbell.fill", "At Iron Works Gym", "8:00 - 8:52 AM", 1310),
        ("briefcase.fill", "Gym to Office", "9:05 - 9:22 AM", 1350),
        ("fork.knife", "Lunch at Joe's", "12:20 - 1:10 PM", 1500),
        ("figure.walk", "Around the office", "All day", 200),
    ]
}

private enum GymDemo {
    static let place = CLLocationCoordinate2D(latitude: 40.7527, longitude: -73.9772)
    static let visits: [(String, String, String)] = [
        ("Today", "7:00 - 7:52 AM", "52 min"), ("Wednesday", "6:45 - 7:50 AM", "65 min"),
        ("Monday", "6:55 - 7:45 AM", "50 min"), ("Saturday", "10:10 - 11:20 AM", "70 min"),
        ("Thursday, Sep 17", "7:05 - 7:55 AM", "50 min"),
    ]
    static let weeks: [(String, Int)] = [("Aug 24", 2), ("Aug 31", 3), ("Sep 7", 4), ("Sep 14", 3), ("Sep 21", 4)]
    /// Days of September with a gym visit.
    static let days: Set<Int> = [1, 3, 5, 8, 10, 12, 15, 17, 19, 21, 22, 24, 25]
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

private struct GoalRing: View {
    var value: Double; var lineWidth: CGFloat
    var body: some View {
        ZStack {
            Circle().stroke(Theme.accent.opacity(0.18), lineWidth: lineWidth)
            Circle().trim(from: 0, to: min(value, 1)).stroke(Theme.accent, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .padding(lineWidth / 2)
    }
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
    var variant = TileDetailOption.variant
    var body: some View {
        Page(title: "Gym") {
            switch variant {
            case 2: month
            case 3: plan
            case 4: history
            case 5: weekGoal
            default: place
            }
        }
        .accessibilityIdentifier("gymDetail")
    }

    private var nextCard: some View {
        Card {
            HStack(spacing: 13) {
                ProfileIcon(symbol: "dumbbell.fill", size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text("NEXT").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    Text("Gym around 6:00 PM").font(.headline)
                    Text("Iron Works Gym · 12 min walk").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
    }

    /// 1. The place: map, next visit, last visits.
    @ViewBuilder private var place: some View {
        Map(initialPosition: .camera(MapCamera(centerCoordinate: GymDemo.place, distance: 900, heading: 20, pitch: 45))) {
            Marker("Iron Works Gym", systemImage: "dumbbell.fill", coordinate: GymDemo.place).tint(Theme.accent)
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 210).clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous)).allowsHitTesting(false)
        nextCard
        Header(text: "Recent Visits")
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(GymDemo.visits.prefix(3).enumerated()), id: \.offset) { i, v in
                    Row(symbol: "clock.fill", title: v.0, value: v.2)
                    if i < 2 { Divider().padding(.leading, 59) }
                }
            }
        }
    }

    /// 2. The month with gym days marked, like Fitness history.
    @ViewBuilder private var month: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("September").font(.title3.weight(.semibold))
                    Spacer()
                    Text("13 visits").font(.subheadline).foregroundStyle(.secondary)
                }
                let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
                LazyVGrid(columns: cols, spacing: 8) {
                    ForEach(["S", "M", "T", "W", "T", "F", "S"].indices, id: \.self) { i in
                        Text(["S", "M", "T", "W", "T", "F", "S"][i]).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(0..<2, id: \.self) { _ in Color.clear.frame(height: 34) }
                    ForEach(1...30, id: \.self) { d in
                        let on = GymDemo.days.contains(d)
                        Text("\(d)").font(.subheadline.weight(on ? .semibold : .regular)).monospacedDigit()
                            .foregroundStyle(on ? .white : (d > 25 ? Color.secondary : Color.primary))
                            .frame(width: 34, height: 34)
                            .background(on ? Theme.accent : .clear, in: .circle)
                    }
                }
            }
        }
        Card(padding: 0) {
            VStack(spacing: 0) {
                Row(symbol: "flame.fill", title: "Weeks in a Row", value: "5"); Divider().padding(.leading, 59)
                Row(symbol: "clock.fill", title: "Average Visit", value: "57 min")
            }
        }
    }

    /// 3. Today's plan: when, what it does to the score, mark it done.
    @ViewBuilder private var plan: some View {
        nextCard
        Card {
            VStack(alignment: .leading, spacing: 6) {
                Text("Adds up to 8 points").font(.headline)
                Text("Going before 8 PM keeps today at Great. Dayline marks it done on its own when you get to the gym.").font(.body).foregroundStyle(.secondary)
            }
        }
        Button {} label: { Text("Mark as Done").font(.headline).frame(maxWidth: .infinity) }
            .buttonStyle(.glassProminent).tint(Theme.accent).controlSize(.large)
        Header(text: "Plan")
        Card(padding: 0) {
            VStack(spacing: 0) {
                Row(symbol: "calendar", title: "Days", value: "Mon, Wed, Fri, Sat"); Divider().padding(.leading, 59)
                Row(symbol: "clock.fill", title: "Go Before", value: "8:00 PM"); Divider().padding(.leading, 59)
                Row(symbol: "bell.fill", title: "Reminder", value: "5:30 PM")
            }
        }
    }

    /// 4. History: visits per week and the list.
    @ViewBuilder private var history: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("THIS WEEK").font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("4").font(.largeTitle.weight(.semibold))
                        Text("visits").font(.body).foregroundStyle(.secondary)
                    }
                }
                Chart(GymDemo.weeks, id: \.0) { w in
                    BarMark(x: .value("Week", w.0), y: .value("Visits", w.1), width: 26)
                        .foregroundStyle(w.0 == "Sep 21" ? Theme.accent : Theme.accent.opacity(0.45)).cornerRadius(5)
                }
                .chartYAxis { AxisMarks(values: [0, 2, 4]) }
                .frame(height: 160)
            }
        }
        Header(text: "Visits")
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(GymDemo.visits.enumerated()), id: \.offset) { i, v in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(v.0).font(.body)
                            Text(v.1).font(.subheadline).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(v.2).font(.body).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    if i < GymDemo.visits.count - 1 { Divider().padding(.leading, 16) }
                }
            }
        }
    }

    /// 5. Weekly goal ring plus when you usually go.
    @ViewBuilder private var weekGoal: some View {
        Card {
            HStack(spacing: 20) {
                ZStack {
                    GoalRing(value: 0.75, lineWidth: 16).frame(width: 120, height: 120)
                    VStack(spacing: 0) {
                        Text("3 of 4").font(.title2.weight(.semibold))
                        Text("this week").font(.caption).foregroundStyle(.secondary)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("One more to go").font(.headline)
                    Text("Today around 6:00 PM would finish the week.").font(.subheadline).foregroundStyle(.secondary)
                }
            }
        }
        Header(text: "When You Usually Go")
        Card {
            Chart([("6 AM", 9), ("8 AM", 3), ("12 PM", 1), ("6 PM", 4), ("8 PM", 1)], id: \.0) { t in
                BarMark(x: .value("Visits", t.1), y: .value("Time", t.0), height: 16).foregroundStyle(Theme.accent).cornerRadius(4)
            }
            .frame(height: 170)
        }
        Card(padding: 0) {
            VStack(spacing: 0) {
                Row(symbol: "clock.fill", title: "Average Visit", value: "57 min"); Divider().padding(.leading, 59)
                Row(symbol: "flame.fill", title: "Weeks in a Row", value: "5")
            }
        }
    }
}
