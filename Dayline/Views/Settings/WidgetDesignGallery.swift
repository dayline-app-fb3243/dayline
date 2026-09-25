import SwiftUI

/// Screenshot page for choosing a widget design: one design's widgets on a Home Screen (page 1)
/// and its large widget plus Lock Screen widgets (page 2). Opened with -widgetDesign N -widgetPage P.
struct WidgetDesignGalleryView: View {
    var design: WidgetDesign
    var page: Int
    private let snap = WidgetSnapshot(date: .now, score: 86, label: "Great day", summary: "Up early, gym done.",
                                      nextTitle: "Lunch out", nextStart: Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now),
                                      streakDays: 6, recentScores: [72, 85, 90, 64, 88, 91, 86])
    private let small: CGFloat = 170, wide: CGFloat = 364, gap: CGFloat = 20

    var body: some View {
        ZStack(alignment: .top) {
            wallpaper
            VStack(spacing: 0) {
                Text("\(design.id). \(design.name)").font(.headline).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 6).background(.black.opacity(0.35), in: .capsule)
                    .padding(.top, 62).padding(.bottom, 14)
                if page == 1 { home } else { large }
                Spacer(minLength: 0)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(false)
    }

    private var wallpaper: some View {
        LinearGradient(colors: [Color(red: 0.33, green: 0.45, blue: 0.72), Color(red: 0.62, green: 0.55, blue: 0.78), Color(red: 0.93, green: 0.7, blue: 0.62)],
                       startPoint: .top, endPoint: .bottom)
    }

    private var home: some View {
        VStack(spacing: gap) {
            HStack(spacing: 0) {
                w(small, small) { DesignTodaySmall(d: design, s: snap) }; Spacer(); w(small, small) { DesignStreakSmall(d: design, s: snap) }
            }
            w(wide, small) { DesignTodayMedium(d: design, s: snap) }
            HStack(spacing: 0) {
                w(small, small) { DesignFriendsSmall(d: design) }; Spacer(); w(small, small) { DesignUpNextSmall(d: design) }
            }
            w(wide, small) { DesignFriendsMedium(d: design) }
        }
        .frame(width: wide)
    }

    private var large: some View {
        VStack(spacing: 22) {
            w(wide, 382) { DesignDayLarge(d: design, s: snap) }
            lockScreen
        }
        .frame(width: wide)
    }

    /// Lock Screen widgets are drawn by iOS in one tint; the design shows through the shape of the score.
    private var lockScreen: some View {
        VStack(spacing: 10) {
            Text("Lock Screen").font(.footnote.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(.white.opacity(0.2))
                    WidgetScoreView(d: lockDesign, score: 86, size: 52, showsNumber: design.mark != .number && design.mark != .bar)
                    if design.mark == .number || design.mark == .bar { Text("86").font(.title3.weight(.semibold)).foregroundStyle(.white) }
                }
                .frame(width: 70, height: 70)
                ZStack {
                    Circle().fill(.white.opacity(0.2))
                    VStack(spacing: 0) {
                        HStack(spacing: -8) { ForEach(WidgetDemo.friends.prefix(3)) { f in lockFace(f.fullName) } }
                        Text("Sam 91").font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    }
                }
                .frame(width: 70, height: 70)
                VStack(alignment: .leading, spacing: 2) {
                    Label("Day score 86", systemImage: "circle.circle.fill").font(.subheadline.weight(.semibold))
                    Text("Next: Lunch out 12:30").font(.footnote)
                    Text("Sam 91 · Leo 88 · Jordan 78").font(.footnote).opacity(0.85)
                }
                .foregroundStyle(.white).padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
                .background(.white.opacity(0.2), in: .rect(cornerRadius: 16, style: .continuous))
            }
        }
    }

    private var lockDesign: WidgetDesign {
        var d = design
        d.foreground = .white; d.secondary = .white.opacity(0.7); d.accent = .white; d.track = .white.opacity(0.3)
        return d
    }

    private func lockFace(_ name: String) -> some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0) }.joined().uppercased()
        return Text(initials).font(.system(size: 9, weight: .semibold)).foregroundStyle(.black.opacity(0.7))
            .frame(width: 24, height: 24).background(.white.opacity(0.85), in: .circle)
            .overlay(Circle().stroke(.black.opacity(0.15), lineWidth: 1))
    }

    private func w<C: View>(_ width: CGFloat, _ height: CGFloat, @ViewBuilder _ c: () -> C) -> some View {
        c().padding(16)
            .frame(width: width, height: height)
            .background(design.background)
            .clipShape(.rect(cornerRadius: 24, style: .continuous))
            .environment(\.colorScheme, design.material ? .dark : .light)
    }
}
