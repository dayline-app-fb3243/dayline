import SwiftUI

/// Twelve close variations of the two widgets David asked for. All use the same Dayline
/// blue/orange Day score and the multicolour friends-streak ring, not a second visual theme.
struct WidgetDesign: Identifiable {
    let id: Int
    let name: String
    let note: String
    let scoreSize: CGFloat
    let ringWidth: CGFloat
    let titlePlacement: Int
    let friendsLayout: Int
    let namePlacement: Int

    static let all: [WidgetDesign] = [
        .init(id: 1, name: "Original", note: "Centered rings, labels underneath", scoreSize: 104, ringWidth: 17, titlePlacement: 0, friendsLayout: 0, namePlacement: 0),
        .init(id: 2, name: "Full Circle", note: "Larger rings, compact headings", scoreSize: 122, ringWidth: 19, titlePlacement: 0, friendsLayout: 0, namePlacement: 1),
        .init(id: 3, name: "Quiet", note: "Light ring and smaller labels", scoreSize: 100, ringWidth: 13, titlePlacement: 0, friendsLayout: 1, namePlacement: 0),
        .init(id: 4, name: "Open", note: "No heading above the circle", scoreSize: 120, ringWidth: 17, titlePlacement: 1, friendsLayout: 0, namePlacement: 0),
        .init(id: 5, name: "Top Label", note: "Day score title above the ring", scoreSize: 108, ringWidth: 16, titlePlacement: 2, friendsLayout: 1, namePlacement: 1),
        .init(id: 6, name: "Streak First", note: "Streak days prominent under the ring", scoreSize: 108, ringWidth: 18, titlePlacement: 0, friendsLayout: 2, namePlacement: 0),
        .init(id: 7, name: "Compact", note: "More breathing room around both circles", scoreSize: 96, ringWidth: 15, titlePlacement: 2, friendsLayout: 0, namePlacement: 1),
        .init(id: 8, name: "Wide Ring", note: "Bolder ring, restrained type", scoreSize: 113, ringWidth: 23, titlePlacement: 0, friendsLayout: 1, namePlacement: 0),
        .init(id: 9, name: "Names In Ring", note: "Friend names and their colors inside the circle", scoreSize: 110, ringWidth: 16, titlePlacement: 1, friendsLayout: 2, namePlacement: 1),
        .init(id: 10, name: "Names Below", note: "Friend color key below a larger circle", scoreSize: 114, ringWidth: 16, titlePlacement: 2, friendsLayout: 0, namePlacement: 0),
        .init(id: 11, name: "Side By Side", note: "Horizontal cards with more room for each name", scoreSize: 110, ringWidth: 17, titlePlacement: 0, friendsLayout: 3, namePlacement: 0),
        .init(id: 12, name: "Soft", note: "Thinner arcs and compact labels", scoreSize: 108, ringWidth: 12, titlePlacement: 1, friendsLayout: 3, namePlacement: 1),
        .init(id: 13, name: "Full Circle 23", note: "Option 2 with a 23-point ring", scoreSize: 122, ringWidth: 23, titlePlacement: 0, friendsLayout: 0, namePlacement: 1),
        .init(id: 14, name: "Full Circle 27", note: "Option 2 with a 27-point ring", scoreSize: 122, ringWidth: 27, titlePlacement: 0, friendsLayout: 0, namePlacement: 1),
        .init(id: 15, name: "Full Circle 31", note: "Option 2 with a 31-point ring", scoreSize: 122, ringWidth: 31, titlePlacement: 0, friendsLayout: 0, namePlacement: 1),
    ]
}

struct DaylineWidgetScoreRing: View {
    let score: Int
    var size: CGFloat = 110
    var width: CGFloat = 17
    var body: some View {
        let progress = CGFloat(min(max(score, 0), 100)) / 100
        ZStack {
            Circle().stroke(.quaternary, lineWidth: width)
            Circle().trim(from: 0, to: progress)
                .stroke(AngularGradient(colors: [Color(red: 0.55, green: 0.76, blue: 1), .blue, .orange],
                                        center: .center, startAngle: .zero,
                                        endAngle: .degrees(360 * max(progress, 0.01))),
                        style: StrokeStyle(lineWidth: width, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if score > 0 {
                Circle().fill(Color(red: 0.55, green: 0.76, blue: 1))
                    .frame(width: width, height: width).offset(y: -size / 2)
            }
            Text("\(score)").font(.system(size: size * 0.31, weight: .bold))
                .foregroundStyle(.primary).monospacedDigit()
        }
        .frame(width: size, height: size)
        .accessibilityLabel("Day score \(score) out of 100")
    }
}

struct DaylineWidgetFriend: Identifiable {
    var id: String { name }
    let name: String
    let days: Int
    let color: Color
    static let preview: [Self] = [
        .init(name: "Sam", days: 9, color: Color(red: 0.996, green: 0.227, blue: 0.184)),
        .init(name: "Jordan", days: 7, color: Color(red: 0.2, green: 0.776, blue: 0.353)),
        .init(name: "Priya", days: 3, color: Color(red: 0.996, green: 0.588, blue: 0.004)),
    ]
}

/// Same overlaid arcs as the in-app StreakRing. A compact color key makes every arc's owner clear.
struct DaylineWidgetFriendsRing: View {
    let days: Int
    let friends: [DaylineWidgetFriend]
    var size: CGFloat = 112
    var width: CGFloat = 17
    var namesInside = false
    var body: some View {
        let all = [DaylineWidgetFriend(name: "You", days: days, color: .blue)] + friends
        let full = Double(max(14, all.map(\.days).max() ?? 0))
        let diameter = size - width
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: width)
            ForEach(all.sorted { $0.days > $1.days }) { friend in
                Circle().trim(from: 0, to: min(0.999, Double(friend.days) / full))
                    .stroke(friend.color, style: StrokeStyle(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            VStack(spacing: 0) {
                Text("\(days)").font(.system(size: size * 0.3, weight: .bold)).monospacedDigit()
                Text("days").font(.system(size: 11)).foregroundStyle(.secondary)
                if namesInside {
                    HStack(spacing: 3) {
                        ForEach(friends.prefix(3)) { f in
                            Text(f.name.prefix(1)).foregroundStyle(f.color)
                        }
                    }.font(.system(size: 10, weight: .semibold))
                }
            }
        }
        .frame(width: diameter, height: diameter)
        .frame(width: size, height: size)
        .accessibilityLabel("Your streak is \(days) days. " + friends.map { "\($0.name) \($0.days) days" }.joined(separator: ", "))
    }
}

struct WidgetScoreOption: View {
    let d: WidgetDesign
    let score: Int
    let wide: Bool
    var body: some View {
        Group {
            if wide {
                HStack(spacing: 16) {
                    DaylineWidgetScoreRing(score: score, size: d.scoreSize, width: d.ringWidth)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Day score").font(.headline)
                        Text("On track").font(.subheadline).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Label("6-day streak", systemImage: "flame.fill")
                            .font(.footnote).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 5) {
                    if d.titlePlacement != 1 { Text("Day score").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading) }
                    Spacer(minLength: 0)
                    DaylineWidgetScoreRing(score: score, size: d.scoreSize, width: d.ringWidth)
                    Spacer(minLength: 0)
                    Text(d.titlePlacement == 1 ? "Day score" : "On track")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct WidgetFriendsOption: View {
    let d: WidgetDesign
    let days: Int
    let friends: [DaylineWidgetFriend]
    let wide: Bool
    var body: some View {
        let horizontal = wide || d.friendsLayout == 3
        Group {
            if horizontal {
                HStack(spacing: 12) {
                    DaylineWidgetFriendsRing(days: days, friends: friends, size: d.scoreSize, width: d.ringWidth, namesInside: d.namePlacement == 1)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Friends' streaks").font(.subheadline.weight(.semibold))
                        ForEach(friends.prefix(3)) { friend in
                            HStack(spacing: 4) {
                                Text(friend.name).foregroundStyle(friend.color)
                                Spacer(minLength: 0)
                                Text("\(friend.days)").foregroundStyle(.secondary)
                            }.font(.caption)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                VStack(spacing: 4) {
                    if d.titlePlacement != 1 { Text("Friends' streaks").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, alignment: .leading) }
                    Spacer(minLength: 0)
                    DaylineWidgetFriendsRing(days: days, friends: friends, size: min(d.scoreSize, 112), width: d.ringWidth, namesInside: d.namePlacement == 1)
                    Spacer(minLength: 0)
                    HStack(spacing: 4) {
                        ForEach(friends.prefix(3)) { f in
                            Text(f.name.prefix(d.friendsLayout == 2 ? 1 : 3)).foregroundStyle(f.color)
                                .frame(maxWidth: .infinity)
                        }
                    }.font(.system(size: 10, weight: .semibold)).lineLimit(1)
                }
            }
        }
    }
}
