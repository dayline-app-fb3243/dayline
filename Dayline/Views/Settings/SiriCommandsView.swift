import SwiftUI
import AppIntents

/// What you can say to Siri. Keep in step with DaylineShortcuts.
struct SiriCommand: Identifiable {
    var id: String { title }
    var title: String
    var symbol: String
    var what: String
    var phrases: [String]
}

enum SiriCommands {
    static let all: [SiriCommand] = [
        SiriCommand(title: "Take Me Back", symbol: "arrow.triangle.turn.up.right.diamond.fill",
                    what: "Finds a place you went, shows your photos from there and opens directions in Apple Maps.",
                    phrases: ["Take me back with Dayline", "Dayline, take me back", "Take me back to the restaurant with Dayline",
                              "Take me to where I ate in Dayline", "Where did I eat in Dayline", "Where did I go in Dayline",
                              "Find the coffee shop I went to in Dayline", "Get me back to the park with Dayline",
                              "Directions to the gym I went to with Dayline"]),
        SiriCommand(title: "Journal by Voice", symbol: "text.bubble.fill",
                    what: "Adds your latest photos to today with a note you say out loud.",
                    phrases: ["Journal in Dayline", "Journal my latest photos in Dayline", "Add to my journal in Dayline"]),
        SiriCommand(title: "Where Was I", symbol: "mappin.and.ellipse",
                    what: "Tells you where you were at a time, from your timeline.",
                    phrases: ["Where was I in Dayline", "Where was I earlier in Dayline"]),
        SiriCommand(title: "My Streak", symbol: "flame.fill",
                    what: "How many days in a row you hit 80 or more.",
                    phrases: ["What's my streak in Dayline", "How long is my Dayline streak"]),
        SiriCommand(title: "Friend's Streak", symbol: "person.2.fill",
                    what: "A friend's streak next to yours.",
                    phrases: ["How's my friend's streak in Dayline", "Check a friend's streak in Dayline"]),
        SiriCommand(title: "Day Score", symbol: "gauge.with.dots.needle.67percent",
                    what: "Today's score and what's pushing it up or down.",
                    phrases: ["How's my day going in Dayline", "What's my Dayline score"]),
    ]
}

/// Profile > Use with Siri: every command and how it works.
struct SiriCommandsView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("How it works", systemImage: "waveform").font(.headline)
                        Text("Say \u{201C}Hey Siri\u{201D}, then a command below. Always say \u{201C}Dayline\u{201D} so Siri knows to use this app. Nothing to set up.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Text("For places, you can say restaurant, coffee shop, gym, park, store or place.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                ForEach(SiriCommands.all) { c in
                    SectionHeader(c.title)
                    Card(padding: 0) {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(alignment: .top, spacing: 13) {
                                ProfileIcon(symbol: c.symbol)
                                Text(c.what).font(.subheadline).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.horizontal, 14).padding(.vertical, 11)
                            ForEach(c.phrases, id: \.self) { p in
                                Divider().padding(.leading, 14)
                                Text("\u{201C}\(p)\u{201D}").font(.body).foregroundStyle(.primary)
                                    .padding(.horizontal, 14).padding(.vertical, 11)
                            }
                        }
                    }
                }
                ShortcutsLink().shortcutsLinkStyle(.automaticOutline)
                    .frame(maxWidth: .infinity).padding(.top, 14)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle("Use with Siri")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("siriCommandsScreen")
    }
}
