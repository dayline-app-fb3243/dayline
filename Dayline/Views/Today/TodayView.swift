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
                    NavigationLink { ScoreDetailView(result: result) } label: { ScoreCard(result: result, showsChevron: true) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("scoreCard")
                    scheduleSection
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { EmptyView() }
            }
            // iOS 26+ back button: round Liquid Glass circle with a chevron, no text.
            .toolbarRole(.editor)
            .sheet(item: $capture) { mode in CaptureSheet(mode: mode) }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(Date.now.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                .font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            Text(greeting).font(.largeTitle.bold())
        }
        .padding(.top, 4)
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: .now) {
        case 4..<12: "Good morning"
        case 12..<17: "Good afternoon"
        default: "Good evening"
        }
    }

    /// Built from what you actually did today: where you went and when. No manual entries.
    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text("SCHEDULE").font(.footnote.weight(.semibold))
                Text(" · built from your day").font(.footnote)
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

/// Entry point for the headline feature (also available from Siri).
struct TakeMeBackRow: View {
    var body: some View {
        Card {
            HStack(spacing: 12) {
                Image(systemName: "car.fill").font(.title3).foregroundStyle(.white)
                    .frame(width: 40, height: 40).background(Color.blue.gradient, in: .rect(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Take me back").font(.headline)
                    Text("\"Hey Siri, take me to where I ate 4 days ago\"").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.footnote.weight(.bold)).foregroundStyle(.tertiary)
            }
        }
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
                        Text(result.label).font(.title2.weight(.heavy)).foregroundStyle(labelColor)
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
