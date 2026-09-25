import SwiftUI

/// One shared layout for the real widget and its size-accurate preview.
struct WeekWidgetContent: View {
    let scores: [Int]
    var previewSmall = false
    @Environment(\.widgetFamily) private var family
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("This week").font(.system(.headline, design: .default)).lineLimit(1).minimumScaleFactor(0.85)
                Spacer(minLength: 4)
                if family != .systemSmall && !previewSmall {
                    Text("Day score").font(.system(.caption, design: .default)).foregroundStyle(.secondary)
                }
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    let score = i < scores.count ? min(100, max(0, scores[i])) : 0
                    VStack(spacing: 3) {
                        Capsule()
                            .fill(score < 45 ? Color.orange : blue(for: score))
                            .frame(height: max(23, CGFloat(score) * 0.55))
                            .overlay {
                                Text("\(score)")
                                    .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                                    .minimumScaleFactor(0.7).lineLimit(1)
                                    .foregroundStyle(score < 45 || score < 72 ? Color.black.opacity(0.85) : .white)
                                    .padding(.horizontal, 1)
                            }
                        Text(["S", "M", "T", "W", "T", "F", "S"][i])
                            .font(.system(.caption2, design: .default)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .padding(16)
    }

    /// A higher score is a deeper blue; a lower non-orange score is a lighter blue.
    private func blue(for score: Int) -> Color {
        let t = min(1.0, max(0.0, Double(score - 45) / 55.0))
        return Color(red: 0.43 - 0.39 * t, green: 0.72 - 0.37 * t, blue: 0.96 - 0.18 * t)
    }
}

/// Simulator capture places the same widget view in Apple's small/medium physical dimensions.
struct WeekWidgetSizePreview: View {
    @Environment(\.colorScheme) private var scheme
    private let scores = [82, 64, 90, 31, 88, 93, 74]
    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 18) {
                Text("Week widget").font(.title2)
                Text("Medium · 360 × 170 pt").font(.caption).foregroundStyle(.secondary)
                WeekWidgetContent(scores: scores)
                    .frame(width: 360, height: 170)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 23))
                Text("Small · 170 × 170 pt").font(.caption).foregroundStyle(.secondary)
                WeekWidgetContent(scores: scores, previewSmall: true)
                    .frame(width: 170, height: 170)
                    .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 23))
                Spacer()
            }
            .padding(.horizontal, 16).padding(.top, 75)
        }
    }
}
