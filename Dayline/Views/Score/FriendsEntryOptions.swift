import SwiftUI
import SwiftData

/// Preview (-friendsEntry N): ways to reach your streak and friends faster.
/// 1 = Friends tab (Profile opens from your picture on Today), 2 = friends row on Today,
/// 3 = streak card on Today, 4 = friends button at the top of Today, 5 = streak and friends first in Insights.
enum FriendsEntry {
    static var style: Int {
        let a = ProcessInfo.processInfo.arguments
        if let i = a.firstIndex(of: "-friendsEntry"), i + 1 < a.count { return Int(a[i + 1]) ?? 0 }
        return 0
    }
}

/// Friends as a row of gray circles with each streak under the name; opens the Streak page.
struct TodayFriendsRow: View {
    @Environment(\.modelContext) private var context
    var body: some View {
        let streak = DayData.streak(context: context)
        NavigationLink { StreakView() } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Friends").font(.headline).foregroundStyle(.primary)
                    Spacer()
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                Card(padding: 14) {
                    HStack(alignment: .top, spacing: 0) {
                        person("Me", "You", streak)
                        ForEach(FriendStore.friends.prefix(4)) { f in person(f.fullName, f.name, f.current) }
                    }
                }
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier("friendsEntry")
    }
    private func person(_ full: String, _ name: String, _ days: Int) -> some View {
        VStack(spacing: 4) {
            PersonAvatar(name: full, size: 48)
            Text(name).font(.caption.weight(.semibold)).lineLimit(1)
            Label("\(days)", systemImage: "flame.fill").font(.caption).foregroundStyle(.orange).monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

/// Your streak with friends' circles stacked beside it; opens the Streak page.
struct TodayStreakCard: View {
    @Environment(\.modelContext) private var context
    var body: some View {
        let streak = DayData.streak(context: context)
        NavigationLink { StreakView() } label: {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "flame.fill").font(.title).foregroundStyle(.orange).frame(width: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STREAK").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("\(streak) days").font(.title2.weight(.bold)).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 0)
                    HStack(spacing: -10) {
                        ForEach(FriendStore.friends.prefix(3)) { f in
                            PersonAvatar(name: f.fullName, size: 34).overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
                        }
                    }
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 2)
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier("friendsEntry")
    }
}

/// The Friends tab: the Streak page as its own tab.
struct FriendsTab: View {
    var body: some View {
        NavigationStack {
            StreakView()
                .navigationTitle("Friends")
                .navigationBarTitleDisplayMode(.large)
        }
    }
}

/// Picked direction: Today card uses the exact multicolor ring from the Streak page.
/// A single tap opens that page with the full ring, stats and history calendar.
struct TodayFriendsCircleCard: View {
    @Environment(\.modelContext) private var context
    @AppStorage("hiddenFriends") private var hiddenRaw = ""
    var body: some View {
        let streak = DayData.streak(context: context)
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        let friends = FriendStore.friends.filter { !hidden.contains($0.name) }
        let arcs = [StreakRing.Arc(id: "you", value: streak, color: Theme.accent, showsBadge: false)]
            + friends.map { StreakRing.Arc(id: $0.id, value: $0.current, color: $0.color, showsBadge: true) }
        NavigationLink { StreakView() } label: {
            Card {
                HStack(spacing: 16) {
                    DaylineWidgetFriendsRing(days: streak,
                        friends: friends.map { DaylineWidgetFriend(name: $0.name, days: $0.current, color: $0.color) },
                        size: 94, width: 17, namesInside: false)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("FRIENDS").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Your streak").font(.title3.weight(.semibold)).foregroundStyle(.primary)
                        Text(friends.isEmpty ? "See your streak" : friends.map(\.name).joined(separator: ", "))
                            .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                }
                .padding(.vertical, 3)
            }
        }
        .buttonStyle(.plain).accessibilityIdentifier("friendsCircleCard")
    }
}
