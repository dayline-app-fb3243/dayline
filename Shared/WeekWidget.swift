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
                        Text("\(score)")
                            .font(.system(.caption2, design: .default).monospacedDigit())
                            .foregroundStyle(score < 45 ? .orange : .secondary)
                        Capsule()
                            .fill(score < 45 ? Color.orange : Color.blue.opacity(score >= 80 ? 0.9 : 0.65))
                            .frame(height: max(8, CGFloat(score) * 0.55))
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
