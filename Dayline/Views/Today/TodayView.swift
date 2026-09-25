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
                    if page.isEmpty {
                        header
                        LocationOffCard()
                        scoreLink
                        scheduleSection
                    } else {
                        TodayPageSample(page: page, result: result, header: AnyView(header),
                                        score: AnyView(scoreLink), schedule: AnyView(scheduleSection))
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .tabRoot()
            .sheet(item: $capture) { mode in CaptureSheet(mode: mode) }
        }
    }

    /// "today.page": 3a (default) = the day score card with Steps + Next glass tiles under it.
    /// "" = the page before that; 1-5 and 3b-3d are the other samples.
    @AppStorage("today.page") private var page = "3a"
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
    /// At most three chips, like the design: the factors that name a chip, or the first three.
    private var chips: [ScoreFactor] {
        let named = result.factors.filter { $0.chip != nil }
        return Array((named.isEmpty ? result.factors : named).prefix(3))
    }
    /// "today.card": A (default) = ring on the left, status in color, no chips, tip that follows the time of day.
    /// B = label in black, bigger ring. C = ring on top, text centered below. "" = the old card with chips.
    @AppStorage("today.card") private var style = "A"
    private var tipText: String {
        if DemoData.isDemo, !(UserDefaults.standard.string(forKey: "demo.pace") ?? "").isEmpty { return result.tip ?? result.summary }
        return style.isEmpty ? (result.tip ?? result.summary) : (result.tip == nil ? result.summary : ScoreEngine.dynamicTip(score: result.score, factors: result.factors))
    }
    var body: some View {
        Card {
            if style == "C" {
                VStack(spacing: 10) {
                    ScoreRing(score: result.score, size: 104)
                    VStack(spacing: 3) {
                        Text("DAY SCORE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(statusLabel).font(.title2.weight(.bold)).foregroundStyle(labelColor).lineLimit(1).minimumScaleFactor(0.8)
                        Text(tipText).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if showsChevron { Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary) }
                }
                .padding(.vertical, 4)
            } else if !style.isEmpty {
                HStack(alignment: .center, spacing: 16) {
                    ScoreRing(score: result.score, size: style == "B" ? 96 : 84, lost: result.pace?.net, good: result.pace?.good)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAY SCORE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(statusLabel).font(style == "B" ? .title2.weight(.semibold) : .title2.weight(.bold))
                            .foregroundStyle(style == "B" ? Color.primary : labelColor).lineLimit(1).minimumScaleFactor(0.8)
                        Text(tipText).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if showsChevron {
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 4)
            } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ScoreRing(score: result.score, size: 84)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAY SCORE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(statusLabel).font(.title2.bold()).foregroundStyle(labelColor).lineLimit(1).minimumScaleFactor(0.8)
                        Text(result.tip ?? result.summary).font(.subheadline).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if showsChevron {
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                FlowLayout { ForEach(chips) { FactorChip(factor: $0) } }
            }
            }
        }
    }
    /// Status color follows the theme: blue while on track, orange when not. With "ring.pace" set, on track means
    /// keeping pace with your own habits (ScoreEngine.Pace); otherwise below 55 ("Slow day" / "Rest day") is orange.
    @AppStorage("ring.pace") private var paceStyle = "B"
    private var behind: Bool { paceStyle.isEmpty ? result.score < 55 : (result.pace?.behind ?? false) }
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
