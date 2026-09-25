import SwiftUI

/// Profile > Use with Siri: a few examples so people learn to add "with Dayline".
enum SiriExamples {
    // Verbatim Siri utterances; each maps to a registered App Shortcut phrase.
    static let all = [
        "Hey Siri, take me back with Dayline",
        "Hey Siri, where was I in Dayline",
        "Hey Siri, journal in Dayline",
        "Hey Siri, what's my streak with Dayline",
        "Hey Siri, what's my Dayline score",
    ]
}

struct SiriCommandsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label { Text("Ask Siri") } icon: { SiriRowIcon() }.font(.headline)
                        Text("Say a short phrase below, starting with \u{201C}Hey Siri.\u{201D}")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                SectionHeader("Try saying")
                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(SiriExamples.all.enumerated()), id: \.offset) { i, p in
                            if i > 0 { Divider().padding(.leading, 16) }
                            Text("\u{201C}\(p)\u{201D}").font(.subheadline).foregroundStyle(.primary)
                                .lineLimit(1).minimumScaleFactor(0.78)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 16).padding(.vertical, 13)
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle("Use with Siri")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("siriCommandsScreen")
    }
}


/// Icon next to "Ask Siri".
struct SiriRowIcon: View {
    var body: some View { SiriMark().frame(width: 28, height: 28) }
}


/// Our own drawing of a ring with a wave, in the app blue. LAUNCH TODO: it copies the look of Apple's Siri mark (trademark) - App Store review risk; check or replace before release.
struct SiriMark: View {
    var color: Color = Theme.accent
    var body: some View {
        Canvas { ctx, size in
            let n = min(size.width, size.height); let w = n * 0.12
            let r = n / 2 - w / 2 - 0.5; let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.stroke(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)), with: .color(color), lineWidth: w)
            var wave = Path()
            for i in 0...60 {
                let t = Double(i) / 60
                let p = CGPoint(x: c.x - r + 2 * r * t, y: c.y - n * 0.09 * sin(.pi * (2 * t - 1)))
                if i == 0 { wave.move(to: p) } else { wave.addLine(to: p) }
            }
            ctx.stroke(wave, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        .accessibilityHidden(true)
    }
}
