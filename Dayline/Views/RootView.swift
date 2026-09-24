import SwiftUI

enum AppTab: Hashable { case today, timeline, insights, journal, profile }

struct RootView: View {
    @State private var tab: AppTab = .today
    @State private var showVoice = false
    @State private var showStreak = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "calendar", value: AppTab.today) { TodayView() }
            Tab("Timeline", systemImage: "mappin", value: AppTab.timeline) { TimelineScreen() }
            Tab("Insights", systemImage: "chart.bar", value: AppTab.insights) { InsightsView(showStreak: $showStreak) }
            Tab("Journal", systemImage: "doc.text", value: AppTab.journal) { JournalView() }
            Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationStack { ProfileView() } }
        }
        // The tab bar stays put on every tab page; only detail screens hide it.
        .tabBarMinimizeBehavior(.never)
        // Outline tab icons, like the design (iOS fills them by default).
        .environment(\.symbolVariants, .none)
        .tint(Theme.accent)
        .sheet(isPresented: $showVoice) { CaptureSheet(mode: .voice) }
        .onReceive(NotificationCenter.default.publisher(for: .openVoiceCapture)) { _ in showVoice = true }
        .onOpenURL { url in if url.host() == "voice" { showVoice = true } else if url.host() == "timeline" { tab = .timeline } else if url.host() == "streak" { tab = .insights; showStreak = true } else if url.host() == "today" { tab = .today } }
    }
}
