import SwiftUI

/// New widget ideas for David to consider. They are previews, not installed widgets.
struct WidgetConceptsGallery: View {
    let concept: Int
    private let snap = WidgetSnapshot.placeholder
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 15) {
                Text("Widget ideas").font(.largeTitle.bold())
                Text("\(concept). \(title)").font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
                card(width: 352, height: 170) { conceptView }
                Text("Preview only · sample data").font(.footnote).foregroundStyle(.secondary)
                Spacer()
            }.padding(.horizontal, 20).padding(.top, 70)
        }
    }
    private var title: String {
        switch concept { case 2: "Week at a glance"; case 3: "Next up"; default: "Places today" }
    }
    private var subtitle: String {
        switch concept { case 2: "Your last seven Day scores"; case 3: "Your next plan, right on Home Screen"; default: "The places in your day, on a small map" }
    }
    @ViewBuilder private var conceptView: some View {
        switch concept {
        case 2:
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("This week").font(.headline); Spacer(); Text("Day score").font(.footnote).foregroundStyle(.secondary) }
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(Array(snap.recentScores.enumerated()), id: \.offset) { i, score in
                        VStack(spacing: 5) {
                            Capsule().fill(score < 45 ? Color.orange : Color.blue.opacity(score >= 80 ? 1 : 0.55))
                                .frame(height: CGFloat(score) * 0.72)
                            Text(["S", "M", "T", "W", "T", "F", "S"][i]).font(.caption2).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }.frame(height: 105, alignment: .bottom)
            }
        case 3:
            HStack(spacing: 16) {
                Image(systemName: "calendar").font(.largeTitle).foregroundStyle(.blue)
                    .frame(width: 64, height: 64).background(.blue.opacity(0.12), in: .rect(cornerRadius: 15))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Up next").font(.footnote).foregroundStyle(.secondary)
                    Text(snap.nextTitle ?? "No plans").font(.title2.weight(.semibold))
                    if let next = snap.nextStart { Text(next, style: .time).font(.subheadline).foregroundStyle(.secondary) }
                }
                Spacer()
            }
        default:
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Places today").font(.headline); Spacer(); Image(systemName: "map").foregroundStyle(.blue) }
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.08))
                    Path { path in
                        path.move(to: CGPoint(x: 20, y: 85)); path.addCurve(to: CGPoint(x: 290, y: 20),
                            control1: CGPoint(x: 120, y: 95), control2: CGPoint(x: 200, y: 10))
                    }.stroke(.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    HStack { Label("Gym", systemImage: "dumbbell.fill"); Spacer(); Label("Coffee", systemImage: "cup.and.saucer.fill") }
                        .font(.caption).padding(12).background(.regularMaterial, in: .capsule)
                        .padding(.horizontal, 12)
                }.frame(height: 98)
            }
        }
    }
    private func card<C: View>(width: CGFloat, height: CGFloat, @ViewBuilder content: () -> C) -> some View {
        content().padding(16).frame(width: width, height: height)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
}
