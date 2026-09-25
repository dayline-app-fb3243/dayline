import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanItem.start) private var allPlan: [PlanItem]
    @Query(sort: \JournalEntry.date, order: .reverse) private var journal: [JournalEntry]
    @Query private var visits: [Visit]
    @State private var capture: CaptureMode?

    private var result: ScoreEngine.Result {
        // Recomputed whenever the queried data changes.
        _ = (allPlan.count, journal.count, visits.count)
        if DemoData.isDemo { return DemoData.todayScore }
        return ScoreEngine.score(DayData.input(for: .now, context: context))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    LocationOffCard()
                    scoreLink
                    TodayStepsNextTiles(result: result)
                    scheduleSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .tabRoot()
            .sheet(item: $capture) { mode in CaptureSheet(mode: mode) }
        }
    }

    private var scoreLink: some View {
        NavigationLink { ScoreDetailView(result: result) } label: { ScoreCard(result: result, showsChevron: true) }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scoreCard")
    }

    private var header: some View {
        // Re-checks every minute so the greeting flips on its own while the app is open.
        TimelineView(.everyMinute) { ctx in
            VStack(alignment: .leading, spacing: 2) {
                Text(ctx.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.subheadline.weight(.medium)).helperText()
                Text(Self.greeting(at: ctx.date)).font(.largeTitle.bold()).backgroundTitle()
                    .contentTransition(.opacity)
                    .accessibilityIdentifier("todayGreeting")
            }
            .padding(.top, 2)
        }
    }

    /// Morning 5-12, afternoon 12-17, evening 17-21, night 21-5.
    static func greeting(at date: Date) -> String {
        switch Calendar.current.component(.hour, from: date) {
        case 5..<12: "Good morning"
        case 12..<17: "Good afternoon"
        case 17..<21: "Good evening"
        default: "Good night"
        }
    }

    /// Built from what you actually did today: where you went and when. No manual entries.
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("Schedule").font(.subheadline.weight(.semibold))
                Text(" · built from your day").font(.subheadline)
            }
            .foregroundStyle(.secondary)
                .padding(.leading, 4).padding(.top, 6)
            DayActivityList(day: .now)
        }
        .accessibilityIdentifier("todaySchedule")
    }

    private var captureButtons: some View {
        HStack(spacing: 10) {
            Button { capture = .photo } label: { Label("Photo", systemImage: "camera").frame(maxWidth: .infinity) }
            Button { capture = .voice } label: { Label("Voice memo", systemImage: "mic").frame(maxWidth: .infinity) }
        }
        .buttonStyle(.glass)
        .controlSize(.large)
        .font(.headline)
    }
}

struct ScoreCard: View {
    var result: ScoreEngine.Result
    var showsChevron = false
    /// The tip follows the time of day and what's still open.
    private var tipText: String {
        if DemoData.isDemo, !(UserDefaults.standard.string(forKey: "demo.pace") ?? "").isEmpty { return result.tip ?? result.summary }
        return result.tip == nil ? result.summary : ScoreEngine.dynamicTip(score: result.score, factors: result.factors)
    }
    var body: some View {
        Card {
            HStack(alignment: .center, spacing: 16) {
                ScoreRing(score: result.score, size: 84, lost: result.pace?.net, good: result.pace?.good)
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAY SCORE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(statusLabel).font(.title2.weight(.bold))
                        .foregroundStyle(labelColor).lineLimit(1).minimumScaleFactor(0.8)
                    Text(tipText).font(.subheadline).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                if showsChevron {
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            .padding(.vertical, 4)
        }
    }
    /// Status color follows the theme: blue while keeping pace with your own habits (ScoreEngine.Pace), orange when not.
    private var behind: Bool { result.pace?.behind ?? false }
    private var labelColor: Color { behind ? .orange : Theme.accent }
    private var statusLabel: String {
        guard !paceStyle.isEmpty else { return result.label }
        return StatusPhrase.text(behind: behind, score: result.score)
    }
}


/// Shows only when Location was turned off for Dayline, instead of a permanent row in Profile.
struct LocationOffCard: View {
    @ObservedObject private var location = LocationService.shared
    @Environment(\.openURL) private var openURL
    var body: some View {
        if !DemoData.isDemo, location.authorization == .denied || location.authorization == .restricted {
            Card(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    if UserDefaults.standard.object(forKey: "symbols.show") as? Bool ?? true {
                        Image(systemName: "location.slash.fill").font(.title3).foregroundStyle(Theme.accent).frame(width: 28)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Location Is Off").font(.headline)
                        Text("Dayline needs Location to build your timeline and score.").font(.subheadline).foregroundStyle(.secondary)
                        Button("Open Settings") {
                            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                        }
                        .font(.subheadline.weight(.semibold)).padding(.top, 2)
                    }
                }
            }
            .accessibilityIdentifier("locationOffCard")
        }
    }
}

/// Today: Steps and what's next, as two Liquid Glass tiles under the day score card. Real numbers, demo numbers in demo mode.
struct TodayStepsNextTiles: View {
    var result: ScoreEngine.Result
    @State private var steps: Int? = nil
    private var s: UserSchedule { UserSchedule.current }
    private var goal: Int { DemoData.isDemo ? 8200 : s.stepGoal }

    private func clock(_ minutes: Int) -> String {
        UserSchedule.date(minutes, on: .now).formatted(date: .omitted, time: .shortened)
    }
    private func done(_ title: String) -> Bool {
        result.factors.contains { $0.title.hasPrefix(title) && $0.effect == .up }
    }
    /// The next thing on the day: gym (if on and not done yet), then the walk, then the journal, then bedtime.
    private var next: (title: String, symbol: String, when: String) {
        let now = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        if DemoData.isDemo { return ("Gym", "dumbbell.fill", "Around 6:00 PM") }
        if s.gym && !done("Gym") && now < s.gymDeadline { return ("Gym", "dumbbell.fill", "Before \(clock(s.gymDeadline))") }
        if s.walk, let st = steps, st < goal { return ("Walk", "figure.walk", "\((goal - st).formatted()) steps to go") }
        if s.journal && !done("Journal") { return ("Journal", "book.closed.fill", "Before bed") }
        return ("Bedtime", "moon.fill", clock(s.bed))
    }
    private func tile(_ title: String, _ value: String, _ symbol: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
    }
    var body: some View {
        let n = next
        GlassEffectContainer(spacing: 12) {
            HStack(spacing: 12) {
                tile("Steps", steps.map { $0.formatted() } ?? "–", "figure.walk", "of \(goal.formatted()) on a usual day")
                tile("Next", n.title, n.symbol, n.when)
            }
        }
        .task {
            if DemoData.isDemo { steps = 5840; return }
            steps = await StepGoal.steps(from: Calendar.current.startOfDay(for: .now), to: .now)
        }
    }
}
