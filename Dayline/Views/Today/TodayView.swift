import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \PlanItem.start) private var allPlan: [PlanItem]
    @Query(sort: \JournalEntry.date, order: .reverse) private var journal: [JournalEntry]
    @Query private var visits: [Visit]
    @State private var capture: CaptureMode?
    @State private var showGym = false

    private var isFreshStart: Bool { !DemoData.isDemo && allPlan.isEmpty && journal.isEmpty && visits.isEmpty && DayCache.steps(for: DayBoundary.shared.today) == 0 }

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
                    if isFreshStart {
                        ContentUnavailableView {
                            Label("Your day starts here", systemImage: "calendar.badge.clock")
                        } description: {
                            Text("As you use Dayline, your places, schedule and journal will appear here. Add a journal entry to begin.")
                        } actions: {
                            Button { capture = .text } label: {
                                Text("Add Journal Entry").font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Color.white)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.accent)
                            .accessibilityIdentifier("addJournalEmpty")
                        }
                        .accessibilityIdentifier("todayEmptyState")
                    }
                    if TodayStepsNextTiles.ringStyle != 5 { scoreLink }
                    TodayStepsNextTiles(result: result, showEmpty: isFreshStart)
                    if FriendsEntry.style == 0 { TodayFriendsCircleCard() }
                    if FriendsEntry.style == 3 { TodayStreakCard() }
                    if FriendsEntry.style == 2 { TodayFriendsRow() }
                    scheduleSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            // A light base behind the floating glass keeps scrolling content from
            // ghosting through the tab bar without clipping the visible list above it.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AppBackgroundView().frame(height: 60)
            }
            .background(AppBackgroundView())
            .tabRoot()
            .sheet(item: $capture) { mode in CaptureSheet(mode: mode) }
            .navigationDestination(isPresented: $showGym) { GymDetailView() }
        }
    }

    private var scoreLink: some View {
        NavigationLink { ScoreDetailView(result: result) } label: {
            if isFreshStart { EmptyScoreCard() } else { ScoreCard(result: result) }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("scoreCard")
    }

    /// Friends button (option 4) or your picture that opens Profile (option 1, when Friends is a tab).
    @ViewBuilder private var headerButton: some View {
        switch FriendsEntry.style {
        case 4:
            NavigationLink { StreakView() } label: {
                Image(systemName: "person.2.fill").font(.body).foregroundStyle(Theme.accent).frame(width: 44, height: 44)
            }
            .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle)
            .accessibilityLabel("Friends").accessibilityIdentifier("friendsEntry")
        case 1:
            NavigationLink { ProfileView() } label: { PersonAvatar(name: AuthService.shared.displayName, size: 40) }
                .buttonStyle(.plain).accessibilityLabel("Profile")
        default: EmptyView()
        }
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
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottomTrailing) { headerButton }
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
            Text("Schedule").font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
                .padding(.leading, 4).padding(.top, 6)
            DayActivityList(day: .now, onGymTap: { showGym = true }, plainStyle: true)
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

/// An unfilled outline, not a computed score or a zero that looks like a bad day.
struct EmptyCardRing: View {
    var size: CGFloat = 84
    var body: some View {
        Circle().stroke(Color.secondary.opacity(0.35), style: StrokeStyle(lineWidth: 12, dash: [4, 6]))
            .overlay { Image(systemName: "ellipsis").font(.title3).foregroundStyle(.secondary) }
            .frame(width: size, height: size)
            .accessibilityLabel("No data yet")
    }
}

struct EmptyScoreCard: View {
    var body: some View {
        Card {
            HStack(spacing: 16) {
                EmptyCardRing()
                VStack(alignment: .leading, spacing: 2) {
                    Text("DAY SCORE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text("No score yet").font(.title2.weight(.semibold)).foregroundStyle(.primary)
                    Text("Your score appears as Dayline learns your day.").font(.subheadline).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
        }
    }
}

struct ScoreCard: View {
    var result: ScoreEngine.Result
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
            }
            .padding(.vertical, 4)
        }
    }
    /// Status color follows the theme: blue while keeping pace with your own habits (ScoreEngine.Pace), orange when not.
    private var behind: Bool { result.pace?.behind ?? false }
    private var labelColor: Color { behind ? .orange : Theme.accent }
    private var statusLabel: String { StatusPhrase.text(behind: behind, score: result.score) }
}


/// Shows only when Location was turned off for Dayline, instead of a permanent row in Profile.
struct LocationOffCard: View {
    @AppStorage("symbols.show") private var showSymbols = true
    @ObservedObject private var location = LocationService.shared
    @Environment(\.openURL) private var openURL
    var body: some View {
        if !DemoData.isDemo, location.authorization == .denied || location.authorization == .restricted {
            Card(padding: 14) {
                HStack(alignment: .top, spacing: 12) {
                    if showSymbols {
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
    var showEmpty = false
    @State private var steps: Int? = nil
    private var s: UserSchedule { UserSchedule.current }
    private var goal: Int { DemoData.isDemo ? 8200 : s.stepGoal }

    private func done(_ title: String) -> Bool {
        result.factors.contains { $0.title.hasPrefix(title) && $0.effect == .up }
    }
    /// The next thing on the day, named as itself: gym (if on and not done yet), then the walk, then the journal,
    /// then bedtime; after bedtime, waking up.
    private var next: (title: String, symbol: String) {
        let now = Calendar.current.component(.hour, from: .now) * 60 + Calendar.current.component(.minute, from: .now)
        if DemoData.isDemo && ProcessInfo.processInfo.arguments.contains("-detailVariant") { return ("Gym", "dumbbell.fill") }
        let late = now < s.wake || now >= s.bed
        if late { return ("Wake Up", "sunrise.fill") }
        if s.gym && !done("Gym") && now < s.gymDeadline { return ("Gym", "dumbbell.fill") }
        if s.walk, let st = steps, st < goal { return ("Walk", "figure.walk") }
        if s.journal && !done("Journal") { return ("Journal", "book.closed.fill") }
        return ("Bedtime", "moon.fill")
    }
    private func tile(_ title: String, _ value: String, _ symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).monospacedDigit().lineLimit(1)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
    }
    /// Steps ring style preview (-stepsRing N): 0 = plain tile, 1 = orange ring card, 2 = blue ring card,
    /// 3 = ring tile, 4 = small ring in the tile, 5 = score and steps rings in one card.
    static var ringStyle: Int {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-stepsRing"), i + 1 < a.count { return Int(a[i + 1]) ?? 0 }
        return 1
    }
    private var stepCount: Int { steps ?? 0 }
    private var stepsStatus: String { stepCount >= goal ? "Goal Reached" : (stepCount * 2 >= goal ? "Keep Going" : "Get Moving") }
    /// Full-width card in the Day score card's layout, with the steps ring.
    private func ringCard(_ tint: String) -> some View {
        NavigationLink { StepsDetailView() } label: {
            Card {
                HStack(alignment: .center, spacing: 16) {
                    if showEmpty {
                        EmptyCardRing(size: 84)
                    } else {
                        StepsRing(steps: stepCount, goal: goal, size: 84, tint: tint)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STEPS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(showEmpty ? "No steps yet" : stepsStatus).font(.title2.weight(.semibold))
                            .foregroundStyle(showEmpty ? Color.primary : (tint == "blue" ? Theme.accent : .orange))
                            .lineLimit(1).minimumScaleFactor(0.8)
                        if showEmpty { Text("Steps appear after Motion or Health access.").font(.subheadline).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 4)
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier("stepsTile")
    }
    @AppStorage("symbols.show") private var showSymbols = true
    private func nextLink(_ n: (title: String, symbol: String)) -> some View {
        NavigationLink {
            if n.title == "Walk" { StepsDetailView() } else { GymDetailView() }
        } label: {
            Card {
                HStack(spacing: 12) {
                    if showSymbols {
                        Image(systemName: n.symbol).font(.title3).foregroundStyle(Theme.accent)
                            .frame(width: 42, height: 42)
                            .background(Theme.accent.opacity(0.12), in: .circle)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text("NEXT").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(n.title).font(.title2.weight(.bold)).foregroundStyle(.primary)
                    }
                    Spacer(minLength: 0)
                }.padding(.vertical, 4)
            }
        }
            .buttonStyle(.plain).accessibilityIdentifier("nextTile")
            .disabled(n.title != "Gym" && n.title != "Walk")
    }
    /// Only legacy screenshot tours can expose Next; the real Today page never shows it.
    private var showNextPreview: Bool { ProcessInfo.processInfo.arguments.contains("-detailVariant") }
    var body: some View {
        let n = next
        let style = Self.ringStyle
        Group {
            switch style {
            case 1, 2:
                VStack(spacing: 12) {
                    ringCard(style == 2 ? "blue" : "orange")
                    if showNextPreview { GlassEffectContainer { nextLink(n) } }
                }
            case 3:
                GlassEffectContainer(spacing: 12) {
                    HStack(alignment: .top, spacing: 12) {
                        NavigationLink { StepsDetailView() } label: {
                            VStack(alignment: .leading, spacing: 10) {
                                Label("Steps", systemImage: "figure.walk").font(.caption.weight(.semibold)).foregroundStyle(.orange)
                                StepsRing(steps: stepCount, goal: goal, size: 96).frame(maxWidth: .infinity)
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("stepsTile")
                        if showNextPreview { nextLink(n) }
                    }
                }
            case 4:
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        NavigationLink { StepsDetailView() } label: {
                            HStack(spacing: 10) {
                                StepsRing(steps: stepCount, goal: goal, size: 56)
                                Text("Steps").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
                                Spacer(minLength: 0)
                            }
                            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("stepsTile")
                        if showNextPreview { nextLink(n).frame(maxHeight: .infinity) }
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
            case 5:
                VStack(spacing: 12) {
                    Card {
                        HStack(spacing: 0) {
                            NavigationLink { ScoreDetailView(result: result) } label: {
                                VStack(spacing: 8) {
                                    ScoreRing(score: result.score, size: 96, lost: result.pace?.net, good: result.pace?.good)
                                    Text("Day Score").font(.subheadline).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).contentShape(.rect)
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("scoreCard")
                            NavigationLink { StepsDetailView() } label: {
                                VStack(spacing: 8) {
                                    StepsRing(steps: stepCount, goal: goal, size: 96)
                                    Text("Steps").font(.subheadline).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity).contentShape(.rect)
                            }
                            .buttonStyle(.plain).accessibilityIdentifier("stepsTile")
                        }
                        .padding(.vertical, 6)
                    }
                    if showNextPreview { GlassEffectContainer { nextLink(n) } }
                }
            default:
                GlassEffectContainer(spacing: 12) {
                    HStack(spacing: 12) {
                        NavigationLink { StepsDetailView() } label: {
                            tile("Steps", steps.map { $0.formatted() } ?? "–", "figure.walk")
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("stepsTile")
                        if showNextPreview { nextLink(n) }
                    }
                }
            }
        }
        .task {
            if DemoData.isDemo { steps = 5840; return }
            steps = await StepGoal.steps(from: Calendar.current.startOfDay(for: .now), to: .now)
        }
    }
}
