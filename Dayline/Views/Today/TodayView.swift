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
                    NavigationLink { ScoreDetailView(result: result) } label: { ScoreCard(result: result, showsChevron: true) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scoreCard")
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
            Button { capture = .voice } label: { Label("Voice note", systemImage: "mic").frame(maxWidth: .infinity) }
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
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    ScoreRing(score: result.score, size: 84)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAY SCORE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text(result.label).font(.title2.bold()).foregroundStyle(labelColor)
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
    private var labelColor: Color { Theme.scoreColor(result.score) }
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
