import SwiftUI

/// "today.page" 1-5: sample layouts for the whole Today page.
/// 1 = big ring on top, centered. 2 = small ring in the header next to the greeting, schedule right away.
/// 3 = ring card plus small tiles (steps, next up). 4 = an "Up next" card between the ring and the schedule.
/// 5 = quick-add buttons (photo, voice memo, write) under the ring.
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
}
