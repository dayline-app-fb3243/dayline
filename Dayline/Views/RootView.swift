import SwiftUI

enum AppTab: Hashable { case today, timeline, insights, journal, profile }

struct RootView: View {
    @State private var tab: AppTab = .today
    @State private var showVoice = false
    @State private var showStreak = false
    @State private var banner: DemoBanner? = nil
    @State private var didStartDemoBanners = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "calendar", value: AppTab.today) { TodayView().tint(ChromeStyle.tint) }
            Tab("Timeline", systemImage: "mappin", value: AppTab.timeline) { TimelineScreen().tint(ChromeStyle.tint) }
            Tab("Insights", systemImage: "chart.bar", value: AppTab.insights) { InsightsView(showStreak: $showStreak).tint(ChromeStyle.tint) }
            Tab("Journal", systemImage: "doc.text", value: AppTab.journal) { JournalView().tint(ChromeStyle.tint) }
            if FriendsEntry.style == 1 {
                Tab("Friends", systemImage: "person.2", value: AppTab.profile) { FriendsTab().tint(ChromeStyle.tint) }
            } else {
                Tab("Profile", systemImage: "person", value: AppTab.profile) { NavigationStack { ProfileView() }.tint(ChromeStyle.tint) }
            }
        }
        // The tab bar stays put on every tab page; only detail screens hide it.
        .tabBarMinimizeBehavior(.never)
        // Outline tab icons, like the design (iOS fills them by default).
        .environment(\.symbolVariants, .none)
        // Selected tab: blue icon and label on the normal glass (David, like Photos). Screens keep the black chrome.
        .tint((UserDefaults.standard.string(forKey: "pill.style") ?? "flat") == "old" ? ChromeStyle.tint : Theme.accent) // blue selected tab on gray
        .overlay(alignment: .top) {
            if let banner {
                DemoNotificationBanner(banner: banner)
                    .padding(.horizontal, 12).padding(.top, 5)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
                    .accessibilityIdentifier("demoNotificationBanner")
            }
        }
        .task {
            guard SampleMode.on, !didStartDemoBanners else { return }
            didStartDemoBanners = true
            // Seeded Xcode build only: preview in-app banner choreography. This is NOT an iOS
            // delivered notification and is never enabled in the Empty/production build.
            let quick = ProcessInfo.processInfo.arguments.contains("-demoBannerNow")
            if quick { try? await Task.sleep(for: .seconds(2)) }
            else { try? await Task.sleep(for: .seconds(12)) }
            let examples = [
                DemoBanner(title: "Maya wants to follow you", detail: "They'd see your streak only.", symbol: "person.badge.plus"),
                DemoBanner(title: "You hit 80 today", detail: "Today counts toward your streak.", symbol: "star.fill"),
                DemoBanner(title: "A moment for your journal", detail: "Add a note, photo or voice memo.", symbol: "book")
            ]
            for example in examples {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.84)) { banner = example }
                try? await Task.sleep(for: .seconds(5))
                withAnimation(.easeOut(duration: 0.25)) { banner = nil }
                try? await Task.sleep(for: .seconds(quick ? 3 : 34))
            }
        }
        .sheet(isPresented: $showVoice) { CaptureSheet(mode: .voice) }
        .onReceive(NotificationCenter.default.publisher(for: .openVoiceCapture)) { _ in showVoice = true }
        .onReceive(NotificationCenter.default.publisher(for: .showOnMap)) { _ in tab = .timeline }
        .onOpenURL { url in if url.host() == "voice" { showVoice = true } else if url.host() == "timeline" { tab = .timeline } else if url.host() == "streak" { tab = .insights; showStreak = true } else if url.host() == "today" { tab = .today } }
    }
}

/// Only for the seeded demo Xcode project; native local notifications are scheduled separately.
private struct DemoBanner: Identifiable {
    var id: String { title }
    let title: String
    let detail: String
    let symbol: String
}

private struct DemoNotificationBanner: View {
    let banner: DemoBanner
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: banner.symbol)
                .font(.body.weight(.semibold)).foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .background(Theme.accent, in: .rect(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text("DAYLINE").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Text("now").font(.caption2).foregroundStyle(.secondary)
                }
                Text(banner.title).font(.subheadline.weight(.semibold))
                Text(banner.detail).font(.subheadline).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(13)
        .background(.regularMaterial, in: .rect(cornerRadius: 21, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 21).strokeBorder(.white.opacity(0.28), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.18), radius: 15, y: 6)
    }
}
