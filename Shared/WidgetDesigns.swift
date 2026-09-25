import SwiftUI

// Widget design directions for David to pick from. Every design draws the same set of widgets
// (Today small/medium, Streak, Friends small/medium, Up Next, Day large, Lock Screen) from the
// same data; only the look changes. Once he picks one, the others come out.

enum WidgetScoreMark { case ring, thinRing, gauge, bar, number, rings }

struct WidgetDesign: Identifiable {
    let id: Int
    let name: String
    let note: String
    var background: AnyShapeStyle
    var foreground: Color
    var secondary: Color
    var accent: Color
    var track: Color
    var mark: WidgetScoreMark
    var roundedNumbers = false
    var material = false

    static let all: [WidgetDesign] = [
        WidgetDesign(id: 1, name: "Fitness", note: "Black with a bright ring, like Apple's Activity widgets.",
                     background: AnyShapeStyle(Color.black), foreground: .white, secondary: Color(white: 0.62),
                     accent: Color(red: 0.2, green: 0.84, blue: 0.29), track: Color(red: 0.2, green: 0.84, blue: 0.29).opacity(0.25), mark: .ring),
        WidgetDesign(id: 2, name: "Blue", note: "The current blue card, cleaned up.",
                     background: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.18, green: 0.48, blue: 1), Color(red: 0.04, green: 0.31, blue: 0.88)], startPoint: .topLeading, endPoint: .bottomTrailing)),
                     foreground: .white, secondary: .white.opacity(0.78), accent: .white, track: .white.opacity(0.25), mark: .ring),
        WidgetDesign(id: 3, name: "Plain", note: "White with blue, like Calendar and Reminders.",
                     background: AnyShapeStyle(Color.white), foreground: .black, secondary: Color(white: 0.45),
                     accent: Color(red: 0, green: 0.48, blue: 1), track: Color(white: 0.9), mark: .thinRing),
        WidgetDesign(id: 4, name: "Gray Circles", note: "Soft gray with the Contacts-style circles you picked for People.",
                     background: AnyShapeStyle(Color(red: 0.95, green: 0.95, blue: 0.97)), foreground: .black, secondary: Color(white: 0.45),
                     accent: Color(red: 0.46, green: 0.51, blue: 0.74), track: Color(white: 0.86), mark: .ring),
        WidgetDesign(id: 5, name: "Big Number", note: "Just the number, large, like the Clock and Stocks widgets.",
                     background: AnyShapeStyle(Color.white), foreground: .black, secondary: Color(white: 0.45),
                     accent: Color(red: 0, green: 0.48, blue: 1), track: Color(white: 0.9), mark: .number, roundedNumbers: true),
        WidgetDesign(id: 6, name: "Glass", note: "See-through glass over your wallpaper.",
                     background: AnyShapeStyle(.ultraThinMaterial), foreground: .white, secondary: .white.opacity(0.8),
                     accent: .white, track: .white.opacity(0.3), mark: .ring, material: true),
        WidgetDesign(id: 7, name: "Bars", note: "Dark gray with a bar for each day, like Screen Time.",
                     background: AnyShapeStyle(Color(red: 0.11, green: 0.11, blue: 0.12)), foreground: .white, secondary: Color(white: 0.6),
                     accent: Color(red: 0.04, green: 0.52, blue: 1), track: Color(white: 0.25), mark: .bar),
        WidgetDesign(id: 8, name: "Night", note: "Deep navy with a half-circle gauge.",
                     background: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.07, green: 0.1, blue: 0.24), Color(red: 0.12, green: 0.2, blue: 0.42)], startPoint: .top, endPoint: .bottom)),
                     foreground: .white, secondary: .white.opacity(0.7), accent: Color(red: 0.39, green: 0.82, blue: 1), track: .white.opacity(0.18), mark: .gauge),
        WidgetDesign(id: 9, name: "Rings", note: "Three rings: score, on time, and places, like Activity.",
                     background: AnyShapeStyle(Color.white), foreground: .black, secondary: Color(white: 0.45),
                     accent: Color(red: 0, green: 0.48, blue: 1), track: Color(white: 0.9), mark: .rings),
        WidgetDesign(id: 10, name: "Sky", note: "Changes with the time of day, like Weather (evening shown).",
                     background: AnyShapeStyle(LinearGradient(colors: [Color(red: 0.98, green: 0.55, blue: 0.35), Color(red: 0.55, green: 0.33, blue: 0.72)], startPoint: .top, endPoint: .bottom)),
                     foreground: .white, secondary: .white.opacity(0.82), accent: .white, track: .white.opacity(0.28), mark: .gauge, roundedNumbers: true),
    ]
}

/// Demo data for the design gallery (and the shape the real widgets will read).
struct WidgetFriendScore: Identifiable {
    var id: String { name }
    var name: String
    var fullName: String
    var score: Int
    var streak: Int
}

struct WidgetDayStop: Identifiable {
    var id: String { title }
    var time: String
    var title: String
    var symbol: String
    var done: Bool
}

enum WidgetDemo {
    static let friends: [WidgetFriendScore] = [
        .init(name: "You", fullName: "Me", score: 86, streak: 6),
        .init(name: "Sam", fullName: "Sam Lee", score: 91, streak: 12),
        .init(name: "Jordan", fullName: "Jordan Park", score: 78, streak: 3),
        .init(name: "Maya", fullName: "Maya Cohen", score: 64, streak: 0),
        .init(name: "Leo", fullName: "Leo Hart", score: 88, streak: 9),
    ]
    static let stops: [WidgetDayStop] = [
        .init(time: "7:02 AM", title: "Up", symbol: "sunrise.fill", done: true),
        .init(time: "8:10 AM", title: "Gym", symbol: "dumbbell.fill", done: true),
        .init(time: "9:30 AM", title: "Office", symbol: "briefcase.fill", done: true),
        .init(time: "12:30 PM", title: "Lunch out", symbol: "fork.knife", done: false),
        .init(time: "6:00 PM", title: "Run", symbol: "figure.run", done: false),
        .init(time: "11:00 PM", title: "Bed", symbol: "bed.double.fill", done: false),
    ]
}

/// Contacts-style monogram, same gray-blue as the People screen.
struct WidgetMonogram: View {
    var name: String
    var size: CGFloat
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
        Text(initials).font(.system(size: size * 0.4, weight: .semibold)).foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(LinearGradient(colors: [Color(red: 0.63, green: 0.71, blue: 0.86), Color(red: 0.46, green: 0.51, blue: 0.74)], startPoint: .top, endPoint: .bottom), in: .circle)
    }
}

// MARK: - Score mark

struct WidgetScoreView: View {
    var d: WidgetDesign
    var score: Int
    var size: CGFloat
    var showsNumber = true
    private var f: CGFloat { CGFloat(min(max(score, 0), 100)) / 100 }
    var body: some View {
        switch d.mark {
        case .ring, .thinRing:
            let w = size * (d.mark == .ring ? 0.13 : 0.07)
            ZStack {
                Circle().stroke(d.track, lineWidth: w)
                Circle().trim(from: 0, to: f).stroke(d.accent, style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(-90))
                if showsNumber { number(size * 0.34) }
            }
            .padding(w / 2).frame(width: size, height: size)
        case .rings:
            let w = size * 0.1
            ZStack {
                ringLayer(f, Color(red: 1, green: 0.18, blue: 0.33), inset: 0, w: w)
                ringLayer(0.72, Color(red: 0.6, green: 0.95, blue: 0), inset: w * 1.15, w: w)
                ringLayer(0.5, Color(red: 0, green: 0.8, blue: 1), inset: w * 2.3, w: w)
            }
            .frame(width: size, height: size)
        case .gauge:
            let w = size * 0.1
            ZStack {
                Circle().trim(from: 0.125, to: 0.875).stroke(d.track, style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(90))
                Circle().trim(from: 0.125, to: 0.125 + 0.75 * f).stroke(d.accent, style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(90))
                if showsNumber { number(size * 0.32) }
            }
            .padding(w / 2).frame(width: size, height: size)
        case .bar:
            VStack(alignment: .leading, spacing: size * 0.08) {
                if showsNumber { number(size * 0.42) }
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(d.track)
                        Capsule().fill(d.accent).frame(width: g.size.width * f)
                    }
                }
                .frame(height: size * 0.09)
            }
            .frame(width: size)
        case .number:
            number(size * 0.62).frame(width: size, height: size, alignment: .bottomLeading)
        }
    }
    private func number(_ pt: CGFloat) -> some View {
        Text("\(score)").font(.system(size: pt, weight: .semibold, design: d.roundedNumbers ? .rounded : .default))
            .foregroundStyle(d.foreground).monospacedDigit()
    }
    private func ringLayer(_ v: CGFloat, _ c: Color, inset: CGFloat, w: CGFloat) -> some View {
        ZStack {
            Circle().stroke(c.opacity(0.2), lineWidth: w)
            Circle().trim(from: 0, to: v).stroke(c, style: StrokeStyle(lineWidth: w, lineCap: .round)).rotationEffect(.degrees(-90))
        }
        .padding(inset + w / 2)
    }
}

// MARK: - Widgets

struct DesignTodaySmall: View {
    var d: WidgetDesign; let s: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(d.foreground)
                Spacer()
                if d.mark == .number || d.mark == .bar { Image(systemName: "circle.circle.fill").foregroundStyle(d.accent) }
            }
            Spacer(minLength: 0)
            if d.mark == .number {
                WidgetScoreView(d: d, score: s.score, size: 90).frame(height: 70, alignment: .bottomLeading)
            } else if d.mark == .bar {
                WidgetScoreView(d: d, score: s.score, size: 138)
            } else {
                HStack(alignment: .bottom) {
                    if d.mark == .rings {
                        Text("\(s.score)").font(.largeTitle.weight(.semibold)).foregroundStyle(d.foreground)
                        Spacer(minLength: 0)
                        WidgetScoreView(d: d, score: s.score, size: 70)
                    } else {
                        Spacer(minLength: 0)
                        WidgetScoreView(d: d, score: s.score, size: 92)
                        Spacer(minLength: 0)
                    }
                }
            }
            Spacer(minLength: 0)
            Text(s.label).font(.footnote).foregroundStyle(d.secondary).lineLimit(1)
        }
    }
}

struct DesignTodayMedium: View {
    var d: WidgetDesign; let s: WidgetSnapshot
    var body: some View {
        HStack(spacing: 16) {
            if d.mark == .number || d.mark == .bar {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.subheadline.weight(.semibold)).foregroundStyle(d.foreground)
                    Spacer(minLength: 0)
                    WidgetScoreView(d: d, score: s.score, size: 120)
                    Text(s.label).font(.footnote).foregroundStyle(d.secondary)
                }
                .frame(width: 130, alignment: .leading)
            } else {
                WidgetScoreView(d: d, score: s.score, size: 118)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Up Next").font(.footnote.weight(.semibold)).foregroundStyle(d.secondary)
                Text(s.nextTitle ?? "Nothing planned").font(.headline).foregroundStyle(d.foreground).lineLimit(1)
                if let start = s.nextStart {
                    Text(start, style: .time).font(.subheadline).foregroundStyle(d.secondary)
                }
                Spacer(minLength: 0)
                Divider().overlay(d.track)
                Label("\(s.streakDays)-day streak", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold)).foregroundStyle(d.foreground).padding(.top, 6)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct DesignStreakSmall: View {
    var d: WidgetDesign; let s: WidgetSnapshot
    var body: some View {
        let scores = Array(s.recentScores.suffix(7))
        let days = ["S", "M", "T", "W", "T", "F", "S"]
        VStack(alignment: .leading, spacing: 0) {
            Label("Streak", systemImage: "flame.fill").font(.subheadline.weight(.semibold)).foregroundStyle(.orange)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("\(s.streakDays)").font(.system(size: 44, weight: .semibold, design: d.roundedNumbers ? .rounded : .default)).foregroundStyle(d.foreground)
                Text("days").font(.subheadline).foregroundStyle(d.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(scores.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 4) {
                        if d.mark == .bar {
                            Capsule().fill(v >= 80 ? d.accent : d.track).frame(width: 10, height: CGFloat(v) * 0.36)
                        } else {
                            Circle().fill(v >= 80 ? d.accent : d.track).frame(width: 13, height: 13)
                        }
                        Text(days[i]).font(.caption2).foregroundStyle(d.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// New: friends' scores in the gray Contacts-style circles.
struct DesignFriendsSmall: View {
    var d: WidgetDesign
    var body: some View {
        let f = Array(WidgetDemo.friends.prefix(4))
        VStack(alignment: .leading, spacing: 8) {
            Text("Friends").font(.subheadline.weight(.semibold)).foregroundStyle(d.foreground)
            Spacer(minLength: 0)
            Grid(horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow { cell(f[0]); cell(f[1]) }
                GridRow { cell(f[2]); cell(f[3]) }
            }
            .frame(maxWidth: .infinity)
        }
    }
    private func cell(_ p: WidgetFriendScore) -> some View {
        VStack(spacing: 2) {
            ZStack {
                if d.mark == .ring || d.mark == .thinRing || d.mark == .rings || d.mark == .gauge {
                    Circle().stroke(d.track, lineWidth: 3)
                    Circle().trim(from: 0, to: CGFloat(p.score) / 100).stroke(d.accent == .white ? Color.white : d.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90))
                }
                WidgetMonogram(name: p.fullName, size: 38)
            }
            .frame(width: 46, height: 46)
            Text("\(p.name) \(p.score)").font(.caption2.weight(.semibold)).foregroundStyle(d.foreground).lineLimit(1)
        }
    }
}

struct DesignFriendsMedium: View {
    var d: WidgetDesign
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Friends Today").font(.subheadline.weight(.semibold)).foregroundStyle(d.foreground)
                Spacer()
                Text("Day score").font(.footnote).foregroundStyle(d.secondary)
            }
            Spacer(minLength: 0)
            HStack(alignment: .top, spacing: 0) {
                ForEach(WidgetDemo.friends) { p in
                    VStack(spacing: 5) {
                        WidgetMonogram(name: p.fullName, size: 48)
                        Text(p.name).font(.caption.weight(.semibold)).foregroundStyle(d.foreground).lineLimit(1)
                        Text("\(p.score)").font(.system(.title3, design: d.roundedNumbers ? .rounded : .default).weight(.semibold))
                            .foregroundStyle(d.foreground).monospacedDigit()
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// New: the next few things on today's plan.
struct DesignUpNextSmall: View {
    var d: WidgetDesign
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Up Next").font(.subheadline.weight(.semibold)).foregroundStyle(d.foreground)
            Spacer(minLength: 0)
            ForEach(WidgetDemo.stops.filter { !$0.done }.prefix(3)) { st in
                HStack(spacing: 8) {
                    Image(systemName: st.symbol).font(.footnote).foregroundStyle(d.accent).frame(width: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(st.title).font(.footnote.weight(.semibold)).foregroundStyle(d.foreground).lineLimit(1)
                        Text(st.time).font(.caption2).foregroundStyle(d.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// New: today's timeline so far, with the score on top.
struct DesignDayLarge: View {
    var d: WidgetDesign; let s: WidgetSnapshot
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 14) {
                if d.mark == .number || d.mark == .bar {
                    Text("\(s.score)").font(.system(size: 54, weight: .semibold, design: d.roundedNumbers ? .rounded : .default)).foregroundStyle(d.foreground)
                } else {
                    WidgetScoreView(d: d, score: s.score, size: 76)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Today").font(.headline).foregroundStyle(d.foreground)
                    Text(s.label).font(.subheadline).foregroundStyle(d.secondary)
                    Label("\(s.streakDays)-day streak", systemImage: "flame.fill").font(.footnote.weight(.semibold)).foregroundStyle(.orange)
                }
                Spacer()
            }
            if d.mark == .bar { WidgetScoreView(d: d, score: s.score, size: 318, showsNumber: false).padding(.top, 10) }
            Divider().overlay(d.track).padding(.vertical, 12)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(WidgetDemo.stops) { st in
                    HStack(spacing: 12) {
                        Image(systemName: st.symbol).font(.subheadline)
                            .foregroundStyle(st.done ? d.accent : d.secondary).frame(width: 22)
                        Text(st.title).font(.subheadline.weight(st.done ? .semibold : .regular))
                            .foregroundStyle(st.done ? d.foreground : d.secondary)
                        Spacer()
                        Text(st.time).font(.subheadline).foregroundStyle(d.secondary).monospacedDigit()
                        Image(systemName: st.done ? "checkmark.circle.fill" : "circle").font(.subheadline)
                            .foregroundStyle(st.done ? d.accent : d.track)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}
