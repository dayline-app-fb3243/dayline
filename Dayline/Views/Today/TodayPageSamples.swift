import SwiftUI

/// "today.page" 1-5: sample layouts for the whole Today page.
/// 1 = big ring on top, centered. 2 = small ring in the header next to the greeting, schedule right away.
/// 3 = ring card plus small tiles (steps, next up). 4 = an "Up next" card between the ring and the schedule.
/// 5 = quick-add buttons (photo, voice memo, write) under the ring.
/// 3a-3d: sample 3's content (steps, next up) in sample 5's Liquid Glass tile style. 3a is the Today page.
struct TodayPageSample: View {
    var page: String
    var result: ScoreEngine.Result
    var header: AnyView
    var score: AnyView
    var schedule: AnyView

    private var behind: Bool { result.pace?.behind ?? false }
    private var statusText: String { StatusPhrase.text(behind: behind, score: result.score) }

    var body: some View {
        switch page {
        case "1": big
        case "3a", "3b", "3c", "3d": glassTiles
        case "2": compact
        case "3": tiles
        case "4": upNext
        default: quickAdd
        }
    }

    private var big: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Card {
                VStack(spacing: 10) {
                    ScoreRing(score: result.score, size: 150, lost: result.pace?.net, good: result.pace?.good)
                    Text(statusText).font(.title2.bold()).foregroundStyle(behind ? Theme.bad : Theme.accent)
                    Text(result.tip ?? result.summary).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 6)
            }
            schedule
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                header
                Spacer()
                VStack(spacing: 4) {
                    ScoreRing(score: result.score, size: 64, lost: result.pace?.net, good: result.pace?.good)
                    Text(statusText).font(.caption.weight(.semibold)).foregroundStyle(behind ? Theme.bad : Theme.accent)
                }
            }
            if let tip = result.tip {
                Label(tip, systemImage: "lightbulb").font(.subheadline).foregroundStyle(.secondary)
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background, in: .rect(cornerRadius: 18, style: .continuous))
            }
            schedule
        }
    }

    private func tile(_ title: String, _ value: String, _ symbol: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: .rect(cornerRadius: 20, style: .continuous))
    }

    private var tiles: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            score
            HStack(spacing: 12) {
                tile("Steps", "5,840", "figure.walk", "of 8,200 on a usual day")
                tile("Next", "Gym", "dumbbell.fill", "Around 6:00 PM")
            }
            schedule
        }
    }

    private func nextRow(_ symbol: String, _ title: String, _ when: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Theme.accent.opacity(0.14), in: .circle)
            Text(title).font(.body.weight(.semibold))
            Spacer()
            Text(when).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    private var upNext: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            score
            Text("Up next").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            Card {
                VStack(spacing: 12) {
                    nextRow("dumbbell.fill", "Gym", "Around 6:00 PM")
                    Divider()
                    nextRow("figure.walk", "20 min walk", "Any time")
                    Divider()
                    nextRow("book.closed.fill", "Journal", "Before bed")
                }
            }
            schedule
        }
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            score
            HStack(spacing: 10) {
                let items = [("camera.fill", "Photo"), ("mic.fill", "Voice Memo"), ("square.and.pencil", "Write")]
                ForEach(items.indices, id: \.self) { i in
                    let item = items[i]
                    Button {} label: {
                        VStack(spacing: 6) {
                            Image(systemName: item.0).font(.system(size: 18, weight: .semibold))
                            Text(item.1).font(.caption.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity).frame(height: 62)
                    }
                    .buttonStyle(.glass)
                }
            }
            schedule
        }
    }

    // MARK: 3a-3d: steps / next up as Liquid Glass tiles

    private func glassTile(_ title: String, _ value: String, _ symbol: String, _ sub: String, progress: Double? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: symbol).font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.title3.bold()).monospacedDigit()
            if let progress {
                ProgressView(value: progress).tint(Theme.accent).padding(.vertical, 2)
            }
            Text(sub).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func smallGlassTile(_ symbol: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(Theme.accent)
            Text(value).font(.headline).monospacedDigit().lineLimit(1)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity).frame(height: 78)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 22, style: .continuous))
    }

    private func barItem(_ symbol: String, _ value: String, _ sub: String) -> some View {
        VStack(spacing: 2) {
            Label(value, systemImage: symbol).font(.subheadline.weight(.semibold)).labelStyle(.titleAndIcon)
            Text(sub).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder private var glassRow: some View {
        switch page {
        case "3a":
            TodayStepsNextTiles(result: result)
        case "3b":
            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    smallGlassTile("figure.walk", "5,840", "steps")
                    smallGlassTile("dumbbell.fill", "Gym", "around 6 PM")
                    smallGlassTile("book.closed.fill", "Journal", "before bed")
                }
            }
        case "3c":
            GlassEffectContainer(spacing: 12) {
                HStack(spacing: 12) {
                    glassTile("Steps", "5,840", "figure.walk", "71% of a usual day", progress: 5840.0 / 8200)
                    glassTile("Next", "Gym", "dumbbell.fill", "Around 6:00 PM · 3 h")
                }
            }
        default:
            HStack(spacing: 0) {
                barItem("figure.walk", "5,840", "steps")
                Divider().frame(height: 28)
                barItem("dumbbell.fill", "Gym", "around 6 PM")
                Divider().frame(height: 28)
                barItem("figure.walk.motion", "20 min", "walk left")
            }
            .padding(.vertical, 12)
            .glassEffect(.regular.interactive(), in: .capsule)
        }
    }

    private var glassTiles: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            score
            glassRow
            schedule
        }
    }
}

/// Today (3a): Steps and what's next, as two Liquid Glass tiles under the day score card. Real numbers, demo numbers in demo mode.
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
