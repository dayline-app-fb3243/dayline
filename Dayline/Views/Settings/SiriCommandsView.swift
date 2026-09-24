import SwiftUI

/// Profile > Use with Siri: a few examples so people learn to add "with Dayline".
enum SiriExamples {
    static let all = [
        "Take me back to where I had pancakes last month with Dayline",
        "Where did I eat on Friday with Dayline",
        "Add my last 3 photos to my journal with Dayline",
        "What\u{2019}s my streak with Dayline",
        "How\u{2019}s my day going with Dayline",
    ]
}

struct SiriCommandsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label { Text("Ask Siri") } icon: { SiriRowIcon() }.font(.headline)
                        Text("Say \u{201C}Hey Siri\u{201D} and ask in your own words. Add \u{201C}with Dayline\u{201D} so Siri looks in your Dayline.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                SectionHeader("Try saying")
                Card(padding: 0) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(SiriExamples.all.enumerated()), id: \.offset) { i, p in
                            if i > 0 { Divider().padding(.leading, 16) }
                            Text("\u{201C}\(p)\u{201D}").font(.body).foregroundStyle(.primary)
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


/// Icon next to "Ask Siri". Preview options until David picks one (-siri.iconStyle orb|circle).
struct SiriRowIcon: View {
    @AppStorage("siri.iconStyle") private var style = "waveform"
    var body: some View {
        switch style {
        case "orb":
            // Apple's official Siri artwork; only bundled in preview builds, never committed.
            if let img = UIImage(named: "SiriOrb") {
                Image(uiImage: img).resizable().scaledToFit().frame(width: 24, height: 24)
            } else {
                Image(systemName: "waveform")
            }
        case "circle":
            Image(systemName: "waveform.circle").foregroundStyle(Theme.accent)
        default:
            Image(systemName: "waveform")
        }
    }
}
