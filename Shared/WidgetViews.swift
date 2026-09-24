import SwiftUI

// Approved style: option 2 - bold blue cards with Apple's layout (ring, Up Next, week dots).

let widgetBlueCard = LinearGradient(colors: [Color(red: 0.18, green: 0.48, blue: 1), Color(red: 0.04, green: 0.31, blue: 0.88)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing)

struct WidgetRing: View {
    var score: Int
    var lineWidth: CGFloat
    var color: Color = .white
    var showsNumber = false
    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: lineWidth)
            Circle().trim(from: 0, to: CGFloat(min(max(score, 0), 100)) / 100)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsNumber { Text("\(score)").font(.system(size: 34, weight: .heavy)).foregroundStyle(color) }
        }
        .padding(lineWidth / 2)
    }
}

/// Soft light circle in the corner of the blue cards.
struct WidgetBubble: View {
    var size: CGFloat
    var body: some View { Circle().fill(.white.opacity(0.12)).frame(width: size, height: size) }
}

struct WidgetFriendFace: View {
    var tag: WidgetSnapshot.FriendTag
    var body: some View {
        Text(tag.initial).font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Color(red: tag.red, green: tag.green, blue: tag.blue), in: .circle)
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}


/// Small blue Today widget.
struct TodaySmallWidgetContent: View {
    let s: WidgetSnapshot
    var body: some View {
        ZStack(alignment: .topLeading) {
            Text("Today").font(.footnote.weight(.bold))
            WidgetRing(score: s.score, lineWidth: 11).frame(width: 76, height: 76)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            VStack(alignment: .leading, spacing: 0) {
                Text("\(s.score)").font(.system(size: 36, weight: .heavy))
                Text(s.label).font(.caption.weight(.bold)).lineLimit(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .foregroundStyle(.white)
    }
}

/// Wide blue Today widget: ring, Up Next, streak line.
struct TodayWideWidgetContent: View {
    let s: WidgetSnapshot
    var body: some View {
        HStack(spacing: 16) {
            WidgetRing(score: s.score, lineWidth: 14, showsNumber: true).frame(width: 108, height: 108)
            VStack(alignment: .leading, spacing: 0) {
                Text("UP NEXT").font(.footnote.weight(.bold)).opacity(0.9)
                Spacer(minLength: 0)
                if let next = s.nextTitle {
                    Text(next).font(.title3.weight(.heavy)).lineLimit(1)
                    if let start = s.nextStart {
                        Text(start, style: .time).font(.footnote.weight(.semibold)).opacity(0.85)
                    }
                } else {
                    Text(s.summary).font(.subheadline.weight(.semibold)).lineLimit(2)
                }
                Spacer(minLength: 0)
                Rectangle().fill(.white.opacity(0.35)).frame(height: 0.5)
                Label("\(s.streakDays)-day streak · \(s.label)", systemImage: "flame.fill")
                    .font(.footnote.weight(.bold)).lineLimit(1).padding(.top, 8)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(.white)
    }
}

/// White Streak widget: days, friend faces, last 7 days as dots.
struct StreakWidgetContent: View {
    let s: WidgetSnapshot
    var body: some View {
        let cal = Calendar.current
        let scores = Array(s.recentScores.suffix(7))
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Streak", systemImage: "flame.fill").font(.footnote.weight(.bold)).foregroundStyle(.blue)
                Spacer()
                HStack(spacing: -6) { ForEach(Array((s.friendTags ?? []).enumerated()), id: \.offset) { WidgetFriendFace(tag: $0.element) } }
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.streakDays)").font(.system(size: 40, weight: .heavy))
                Text("days").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
            }
            .padding(.top, 4)
            Spacer(minLength: 0)
            HStack {
                ForEach(Array(scores.enumerated()), id: \.offset) { i, v in
                    let day = cal.date(byAdding: .day, value: i - (scores.count - 1), to: .now) ?? .now
                    VStack(spacing: 4) {
                        Circle().fill(v >= 80 ? Color.blue : Color.blue.opacity(0.18)).frame(width: 14, height: 14)
                        Text(day.formatted(.dateTime.weekday(.narrow))).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}
