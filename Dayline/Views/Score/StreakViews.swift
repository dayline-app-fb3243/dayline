import SwiftUI
import MessageUI
import SwiftData

// MARK: - Friends (local for now; sharing needs the sync backend)

struct StreakFriend: Identifiable, Hashable {
    var id: String { name }
    var name: String
    var fullName: String
    var color: Color
    var current: Int
    var best: Int
    var monthCount: Int
    var since: String
    /// Days ago (0 = today) that scored 80+.
    var goodDaysAgo: Set<Int>

    /// Streak length as of a past day (consecutive 80+ days ending that day).
    func streak(asOf date: Date, calendar: Calendar = .current) -> Int {
        var back = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        var n = 0
        while goodDaysAgo.contains(back) { n += 1; back += 1 }
        return n
    }

    func isGood(_ date: Date, calendar: Calendar = .current) -> Bool {
        let back = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? -1
        return goodDaysAgo.contains(back)
    }
}

@MainActor
enum FriendStore {
    /// Friends whose streaks show on your ring. Empty until sharing is connected; the demo has sample friends.
    static var friends: [StreakFriend] { DemoData.isDemo ? demo : [] }

    static let demo: [StreakFriend] = [
        StreakFriend(name: "Sam", fullName: "Sam Rivera", color: Color(red: 0.996, green: 0.227, blue: 0.184), current: 9, best: 14, monthCount: 17,
                     since: "August", goodDaysAgo: Set(0...8).union([12, 13, 14, 15, 18, 19, 20, 21, 22])),
        StreakFriend(name: "Jordan", fullName: "Jordan Lee", color: Color(red: 0.2, green: 0.776, blue: 0.353), current: 7, best: 11, monthCount: 15,
                     since: "July", goodDaysAgo: Set(0...6).union([9, 10, 11, 14, 15, 16, 17])),
        StreakFriend(name: "Priya", fullName: "Priya Shah", color: Color(red: 0.996, green: 0.588, blue: 0.004), current: 3, best: 5, monthCount: 9,
                     since: "September", goodDaysAgo: Set(0...2).union([5, 6, 7, 10, 11])),
    ]
}

// MARK: - Ring

/// One thick ring. Each person's streak is an arc from the top; the longest sits at the back.
/// Friends' arcs end in a small white dot with their number.
struct StreakRing: View {
    struct Arc: Identifiable { var id: String; var value: Int; var color: Color; var showsBadge: Bool }
    var arcs: [Arc]
    var center: Int
    var size: CGFloat = 250
    var lineWidthBase: CGFloat = 34
    @AppStorage("rings.thick") private var thick = false
    private var lineWidth: CGFloat { thick ? lineWidthBase * 1.3 : lineWidthBase }

    var body: some View {
        let full = Double(max(14, arcs.map(\.value).max() ?? 0))
        let diameter = size - 48
        let r = diameter / 2
        let sorted = arcs.sorted { $0.value > $1.value }
        ZStack {
            Circle().stroke(Color.primary.opacity(0.08), lineWidth: lineWidth).frame(width: diameter, height: diameter)
            ForEach(sorted) { a in
                Circle()
                    .trim(from: 0, to: min(0.999, Double(a.value) / full))
                    .stroke(a.color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: diameter, height: diameter)
            }
            ForEach(sorted.filter { $0.showsBadge && $0.value > 0 }) { a in
                let angle = -Double.pi / 2 + 2 * Double.pi * min(0.999, Double(a.value) / full)
                Text("\(a.value)")
                    .font(.caption.bold()).foregroundStyle(a.color)
                    .frame(width: 24, height: 24)
                    .background(.white, in: .circle)
                    .offset(x: r * cos(angle), y: r * sin(angle))
            }
            VStack(spacing: 0) {
                Text("\(center)").font(.largeTitle.bold()).contentTransition(.numericText())
                Text(center == 1 ? "day in a row" : "days in a row").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(center) days in a row")
    }
}

// MARK: - Streak

/// Days in a row on schedule with 80+, with friends' streaks on the same ring.
/// Opened from the Streak card on Insights or the Streak widget.
struct StreakView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \DayScore.day) private var scores: [DayScore]
    @AppStorage("hiddenFriends") private var hiddenRaw = ""
    @State private var pickedDay: Date?

    var body: some View {
        let streak = DayData.streak(context: context)
        let friends = FriendStore.friends
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        let arcs = [StreakRing.Arc(id: "you", value: streak, color: Theme.accent, showsBadge: false)]
            + friends.filter { !hidden.contains($0.name) }.map { StreakRing.Arc(id: $0.id, value: $0.current, color: $0.color, showsBadge: true) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 14) {
                    VStack(spacing: 4) {
                        StreakRing(arcs: arcs, center: streak)
                        Text("On schedule with a score of 80 or more.").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                HStack(spacing: 8) {
                    StreakStat(title: "Best", value: "\(max(StreakMath.best(scores), streak)) days")
                    StreakStat(title: "Next goal", value: "\(StreakMath.nextGoal(streak)) days")
                    StreakStat(title: "80+ this month", value: "\(StreakMath.monthCount(scores))")
                }
                SectionHeader("History")
                Card(padding: 12) {
                    MonthHistory(color: Theme.accent, isGood: { day in
                        scores.first { Calendar.current.isDate($0.day, inSameDayAs: day) }.map { $0.score >= 80 } ?? false
                    }, onPick: { pickedDay = $0 })
                }
                .accessibilityIdentifier("streakHistory")
                if !friends.isEmpty {
                    SectionHeader("Friends this week")
                    Card(padding: 0) {
                        let people: [StreakFriend?] = (friends.map { Optional($0) } + [nil]).sorted { ($0?.current ?? streak) > ($1?.current ?? streak) }
                        VStack(spacing: 0) {
                            ForEach(Array(people.enumerated()), id: \.offset) { i, f in
                                if let f {
                                    NavigationLink { FriendStreakView(friend: f, yourStreak: streak) } label: {
                                        FriendRow(initials: String(f.name.prefix(1)), color: f.color, name: f.name, best: f.best, current: f.current)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("friend-\(f.name)")
                                } else {
                                    FriendRow(initials: "Me", color: Theme.accent, name: "You", best: max(StreakMath.best(scores), streak), current: streak)
                                }
                                if i < people.count - 1 { Divider().padding(.leading, 58) }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle("Streak")
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $pickedDay) { StreakDayView(day: $0) }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink { PeopleView() } label: { Image(systemName: "person.2").foregroundStyle(.primary) }
                    .tint(.primary)
                    .accessibilityLabel("People")
                    .accessibilityIdentifier("peopleButton")
            }
        }
        .accessibilityIdentifier("streakScreen")
    }
}

private struct FriendRow: View {
    var initials: String
    var color: Color
    var name: String
    var best: Int
    var current: Int
    var body: some View {
        HStack(spacing: 12) {
            Text(initials).font(.caption.bold()).foregroundStyle(.white)
                .markerBackground(color, size: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.subheadline.weight(.semibold))
                Text("Best \(best) days").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(current)").font(.headline).foregroundStyle(color)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
        .contentShape(.rect)
    }
}

struct StreakStat: View {
    var title: String
    var value: String
    var body: some View {
        Card(padding: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Text(value).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
    }
}

enum StreakMath {
    static func best(_ scores: [DayScore]) -> Int {
        var best = 0, run = 0
        var last: Date?
        for s in scores {
            if s.score >= 80, let l = last, Calendar.current.dateComponents([.day], from: l, to: s.day).day == 1 { run += 1 }
            else { run = s.score >= 80 ? 1 : 0 }
            last = s.day
            best = max(best, run)
        }
        return best
    }
    static func monthCount(_ scores: [DayScore]) -> Int {
        scores.filter { $0.score >= 80 && Calendar.current.isDate($0.day, equalTo: .now, toGranularity: .month) }.count
    }
    static func nextGoal(_ n: Int) -> Int { [3, 7, 14, 21, 30, 50, 100, 365].first { $0 > n } ?? n + 30 }
}

// MARK: - Friend

/// Tap a friend on Streak: their ring in their color and only the past week (friends share streaks only).
struct FriendStreakView: View {
    var friend: StreakFriend
    var yourStreak: Int

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 12) {
                    VStack(spacing: 2) {
                        StreakRing(arcs: [.init(id: friend.id, value: friend.current, color: friend.color, showsBadge: true)],
                                   center: friend.current, size: 210)
                        Text("Friends since \(friend.since) · you follow each other").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                HStack(spacing: 8) {
                    StreakStat(title: "Best", value: "\(friend.best) days")
                    StreakStat(title: "Now", value: "\(friend.current) days")
                    StreakStat(title: "You", value: "\(yourStreak) days")
                }
                SectionHeader("Past week")
                Card(padding: 12) { FriendWeekStrip(color: friend.color) { friend.isGood($0) } }
                Text("Friends see streaks only. Places, photos and notes stay private.")
                    .font(.footnote).helperText().padding(.horizontal, 4)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle(friend.fullName)
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("friendScreen")
    }
}

/// The past 7 days, oldest first, ending today.
struct FriendWeekStrip: View {
    var color: Color
    var isGood: (Date) -> Bool
    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        HStack {
            ForEach(0..<7, id: \.self) { i in
                let day = cal.date(byAdding: .day, value: i - 6, to: today)!
                let good = isGood(day)
                VStack(spacing: 6) {
                    Text(day.formatted(.dateTime.weekday(.narrow))).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Text(day.formatted(.dateTime.day())).font(.caption.weight(.semibold))
                        .foregroundStyle(good ? Color.white : Color.secondary)
                        .frame(width: 34, height: 34)
                        .background(good ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary.opacity(0.07)), in: .circle)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Your own streak history: one month at a time, back up to a year.
struct MonthHistory: View {
    var color: Color
    var isGood: (Date) -> Bool
    var onPick: ((Date) -> Void)? = nil
    @State private var back = 0

    var body: some View {
        var cal = Calendar.current
        cal.firstWeekday = 2
        let today = cal.startOfDay(for: .now)
        let monthStart = cal.date(byAdding: .month, value: -back, to: cal.dateInterval(of: .month, for: today)!.start)!
        let days = cal.range(of: .day, in: .month, for: monthStart)!.count
        let lead = (cal.component(.weekday, from: monthStart) - cal.firstWeekday + 7) % 7
        let cells: [Date?] = Array(repeating: nil, count: lead) + (0..<days).map { cal.date(byAdding: .day, value: $0, to: monthStart) }
        let count = cells.compactMap { $0 }.filter { $0 <= today && isGood($0) }.count
        return VStack(spacing: 8) {
            HStack {
                Button { back = min(back + 1, 11) } label: { Image(systemName: "chevron.left").frame(width: 32, height: 32) }
                    .disabled(back >= 11).accessibilityIdentifier("historyBack")
                Spacer()
                VStack(spacing: 0) {
                    Text(monthStart.formatted(.dateTime.month(.wide).year())).font(.headline)
                    Text("\(count) days at 80+").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { back = max(back - 1, 0) } label: { Image(systemName: "chevron.right").frame(width: 32, height: 32) }
                    .disabled(back == 0)
            }
            .tint(.primary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 6) {
                ForEach(0..<7, id: \.self) { i in
                    Text(cal.date(byAdding: .day, value: i, to: cal.dateInterval(of: .weekOfYear, for: today)!.start)!.formatted(.dateTime.weekday(.narrow)))
                        .font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                }
                ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                    if let day {
                        let future = day > today
                        let good = !future && isGood(day)
                        Text(day.formatted(.dateTime.day())).font(.caption.weight(.semibold))
                            .foregroundStyle(good ? Color.white : Color.secondary)
                            .frame(width: 34, height: 34)
                            .background(future ? AnyShapeStyle(.clear) : good ? AnyShapeStyle(color) : AnyShapeStyle(Color.primary.opacity(0.07)), in: .circle)
                            .contentShape(.circle)
                            .onTapGesture { if !future { onPick?(day) } }
                            .accessibilityAddTraits(future ? [] : .isButton)
                            .accessibilityIdentifier("historyDay-\(cal.component(.day, from: day))")
                    } else {
                        Color.clear.frame(height: 34)
                    }
                }
            }
        }
        .gesture(DragGesture(minimumDistance: 30).onEnded { v in
            if v.translation.width > 0 { back = min(back + 1, 11) } else { back = max(back - 1, 0) }
        })
    }
}

/// Streak as of one past day, opened from the History calendar.
/// Friends show too when the day is within the last 7 days (that's how far shared streaks go back).
struct StreakDayView: View {
    let day: Date
    @Query(sort: \DayScore.day) private var scores: [DayScore]
    @AppStorage("hiddenFriends") private var hiddenRaw = ""

    private func myStreak(asOf d: Date) -> Int {
        let cal = Calendar.current
        var cur = cal.startOfDay(for: d); var n = 0
        while let s = scores.first(where: { cal.isDate($0.day, inSameDayAs: cur) }), s.score >= 80 {
            n += 1; cur = cal.date(byAdding: .day, value: -1, to: cur)!
        }
        return n
    }

    var body: some View {
        let cal = Calendar.current
        let mine = myStreak(asOf: day)
        let score = scores.first { cal.isDate($0.day, inSameDayAs: day) }?.score
        let daysAgo = cal.dateComponents([.day], from: cal.startOfDay(for: day), to: cal.startOfDay(for: .now)).day ?? 99
        let hidden = Set(hiddenRaw.split(separator: ",").map(String.init))
        let friends = daysAgo <= 6 ? FriendStore.friends.filter { !hidden.contains($0.name) } : []
        let arcs = [StreakRing.Arc(id: "you", value: mine, color: Theme.accent, showsBadge: false)]
            + friends.map { StreakRing.Arc(id: $0.id, value: $0.streak(asOf: day), color: $0.color, showsBadge: true) }
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Card(padding: 14) {
                    VStack(spacing: 4) {
                        StreakRing(arcs: arcs, center: mine)
                        Text(score.map { "Day score \($0)" } ?? "No score this day").font(.footnote).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
                if !friends.isEmpty {
                    SectionHeader("Friends on this day")
                    Card(padding: 0) {
                        let people: [StreakFriend?] = (friends.map { Optional($0) } + [nil]).sorted { ($0?.streak(asOf: day) ?? mine) > ($1?.streak(asOf: day) ?? mine) }
                        VStack(spacing: 0) {
                            ForEach(Array(people.enumerated()), id: \.offset) { i, f in
                                if let f {
                                    FriendRow(initials: String(f.name.prefix(1)), color: f.color, name: f.name, best: f.best, current: f.streak(asOf: day))
                                } else {
                                    FriendRow(initials: "Me", color: Theme.accent, name: "You", best: max(StreakMath.best(scores), mine), current: mine)
                                }
                                if i < people.count - 1 { Divider().padding(.leading, 58) }
                            }
                        }
                    }
                } else if !FriendStore.friends.isEmpty {
                    Text("Friends' streaks show for the last 7 days.").font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 4)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle(day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
        .navigationBarTitleDisplayMode(.inline)
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("streakDay")
    }
}

// MARK: - People

/// People page: switch friends on/off on your streak ring, find people to follow, invite a friend.
// MARK: - People (Health-style sharing pages)

/// Person avatar: colored circle with initials (gray for people not sharing yet).
struct PersonAvatar: View {
    var name: String
    var color: Color? = nil
    var size: CGFloat = 40
    var body: some View {
        let initials = name.split(separator: " ").prefix(2).compactMap(\.first).map { String($0) }.joined()
        Text(initials).font(.system(size: size * 0.42, weight: .semibold)).foregroundStyle(.white)
            .markerBackground(color.map { AnyShapeStyle($0) } ?? AnyShapeStyle(LinearGradient(colors: [Color(white: 0.66), Color(white: 0.53)], startPoint: .top, endPoint: .bottom)), size: size)
    }
}

private struct PeopleGroup<C: View>: View {
    @ViewBuilder var content: C
    var body: some View {
        VStack(spacing: 0) { content }
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
    }
}

private struct PeopleHeader: View {
    var title: String
    init(_ t: String) { title = t }
    var body: some View {
        Text(title).font(.title2.bold()).padding(.leading, 14).padding(.top, 18).padding(.bottom, 8)
    }
}

private struct PersonRow<Trailing: View>: View {
    var name: String
    var subtitle: String
    var color: Color? = nil
    var last = false
    @ViewBuilder var trailing: Trailing
    var body: some View {
        HStack(spacing: 14) {
            PersonAvatar(name: name, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                Text(subtitle).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 16).frame(minHeight: 58)
        .overlay(alignment: .bottom) { if !last { Divider().padding(.leading, 70) } }
        .contentShape(.rect)
    }
}

private struct LinkRow: View {
    var title: String
    var top = true
    var body: some View {
        Text(title).font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).padding(.horizontal, 16)
            .overlay(alignment: .top) { if top { Divider().padding(.leading, 16) } }
            .contentShape(.rect)
    }
}

private struct Chevron: View {
    var body: some View { Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary) }
}

private struct PillButton: View {
    var title: String
    var done: String
    @State private var on = false
    var body: some View {
        Button { on.toggle() } label: {
            Text(on ? done : title).font(.subheadline.weight(.semibold))
                .foregroundStyle(on ? Color.secondary : Theme.accent)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(on ? Color(.tertiarySystemFill) : Theme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
    }
}

/// Invite pill: opens Messages with the link filled in, or the share sheet when Messages isn't available.
private struct InviteButton: View {
    var recipient: String
    @State private var showMessages = false
    @State private var showShare = false
    var body: some View {
        Button {
            if MFMessageComposeViewController.canSendText() { showMessages = true } else { showShare = true }
        } label: {
            Text("Invite").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Theme.accent.opacity(0.12), in: .capsule)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showMessages) { MessageCompose(recipient: recipient, text: PeopleStore.inviteText).ignoresSafeArea() }
        .sheet(isPresented: $showShare) { ActivitySheet(items: [PeopleStore.inviteText]).presentationDetents([.medium, .large]) }
    }
}

private struct MessageCompose: UIViewControllerRepresentable {
    var recipient: String
    var text: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = [recipient]; vc.body = text; vc.messageComposeDelegate = context.coordinator
        return vc
    }
    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}
    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        func messageComposeViewController(_ controller: MFMessageComposeViewController, didFinishWith result: MessageComposeResult) {
            controller.dismiss(animated: true)
        }
    }
}

private struct ActivitySheet: UIViewControllerRepresentable {
    var items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController { UIActivityViewController(activityItems: items, applicationActivities: nil) }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// Demo people for the sharing pages.
@MainActor
enum PeopleStore {
    /// People who can see your streak.
    static var sharingWith: [StreakFriend] { FriendStore.friends.filter { $0.name != "Priya" } }
    static let contacts: [(String, String)] = [("Alex Kim", "alex@icloud.com"), ("Nina Patel", "(416) 555-0142")]
    static let notOnDayline: [(String, String)] = [("Maya Cohen", "(647) 555-0199"), ("Ben Levi", "ben.levi@gmail.com")]
    static let inviteText = "Join me on Dayline. It builds your day for you and we can keep streaks together. https://dayline.app/invite"
}

struct PeopleView: View {
    @AppStorage("hiddenFriends") private var hiddenRaw = ""
    @State private var search = ""

    private var hidden: Set<String> { Set(hiddenRaw.split(separator: ",").map(String.init)) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PeopleHeader("Sharing With You")
                PeopleGroup {
                    if FriendStore.friends.isEmpty {
                        Text("Friends who share with you show up here.").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(16)
                    }
                    ForEach(Array(FriendStore.friends.enumerated()), id: \.element.id) { i, f in
                        PersonRow(name: f.name, subtitle: "Show on my streak", color: f.color, last: i == FriendStore.friends.count - 1) {
                            Toggle("", isOn: FriendVisibility.binding(f.name, raw: $hiddenRaw)).labelsHidden()
                        }
                        .accessibilityIdentifier("friendSwitch\(f.name)")
                    }
                }
                Text("Turn someone off to hide them from your streak ring.")
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 7)
                PeopleGroup {
                    NavigationLink { AskToShareView() } label: { LinkRow(title: "Ask Someone to Share", top: false) }
                        .accessibilityIdentifier("askToShare")
                }
                .padding(.top, 10)

                PeopleHeader("You\u{2019}re Sharing With")
                PeopleGroup {
                    ForEach(PeopleStore.sharingWith) { f in
                        NavigationLink { PersonView(friend: f) } label: {
                            PersonRow(name: f.name, subtitle: "Sees your streak", color: f.color) { Chevron() }
                        }
                        .accessibilityIdentifier("person-\(f.name)")
                    }
                    NavigationLink { ShareWithView() } label: { LinkRow(title: "Add Another Person", top: false) }
                        .accessibilityIdentifier("addPerson")
                }

                if DemoData.isDemo {
                    PeopleHeader("People to Follow")
                    PeopleGroup {
                        ForEach(PeopleStore.contacts, id: \.0) { c in
                            PersonRow(name: c.0, subtitle: "On Dayline") {
                                PillButton(title: "Follow", done: "Requested")
                            }
                            .accessibilityIdentifier("follow-\(c.0)")
                        }
                        ForEach(Array(PeopleStore.notOnDayline.enumerated()), id: \.offset) { i, c in
                            PersonRow(name: c.0, subtitle: "Not on Dayline yet", last: i == PeopleStore.notOnDayline.count - 1) {
                                InviteButton(recipient: c.1).accessibilityIdentifier("invite-\(c.0)")
                            }
                        }
                    }
                    Text("From your contacts. Follow sends a request. Invite sends a link in Messages.")
                        .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 7)
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .navigationTitle("People")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Phone, Email or Contact")
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("peopleScreen")
    }
}

enum FriendVisibility {
    static func binding(_ name: String, raw: Binding<String>) -> Binding<Bool> {
        Binding(get: { !raw.wrappedValue.split(separator: ",").map(String.init).contains(name) }, set: { on in
            var h = Set(raw.wrappedValue.split(separator: ",").map(String.init))
            if on { h.remove(name) } else { h.insert(name) }
            raw.wrappedValue = h.sorted().joined(separator: ",")
        })
    }
}

/// One person you share with: what they see, what they share, stop sharing.
struct PersonView: View {
    let friend: StreakFriend
    var yourStreak: Int = 6
    @AppStorage("hiddenFriends") private var hiddenRaw = ""
    @State private var confirmStop = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 4) {
                    PersonAvatar(name: friend.name, color: friend.color, size: 96)
                    Text(friend.fullName).font(.title.bold()).padding(.top, 6)
                    Text("Sharing since \(friend.since)").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.top, 8).padding(.bottom, 6)

                PeopleHeader("\(friend.name) Can See")
                PeopleGroup {
                    HStack { Text("Your streak").font(.body.weight(.medium)); Spacer(); Text("\(yourStreak) days").foregroundStyle(.secondary) }
                        .padding(.horizontal, 16).frame(minHeight: 52)
                }
                Text("Friends only see your streak. Nothing else leaves your phone.")
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 8)

                PeopleHeader("\(friend.name) Shares With You")
                PeopleGroup {
                    HStack {
                        Text("Show on my streak").font(.body.weight(.medium)); Spacer()
                        Toggle("", isOn: FriendVisibility.binding(friend.name, raw: $hiddenRaw)).labelsHidden()
                    }
                    .padding(.horizontal, 16).frame(minHeight: 52)
                    .overlay(alignment: .bottom) { Divider().padding(.leading, 16) }
                    NavigationLink { FriendStreakView(friend: friend, yourStreak: yourStreak) } label: {
                        HStack { Text("View \(friend.name)\u{2019}s Streak").font(.body.weight(.medium)).foregroundStyle(.primary); Spacer(); Chevron() }
                            .padding(.horizontal, 16).frame(minHeight: 52).contentShape(.rect)
                    }
                }

                PeopleGroup {
                    Button { confirmStop = true } label: {
                        Text("Stop Sharing with \(friend.name)").font(.body.weight(.semibold)).foregroundStyle(.red)
                            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading).padding(.horizontal, 16).contentShape(.rect)
                    }
                }
                .padding(.top, 24)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .navigationTitle("")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .confirmationDialog("\(friend.name) will no longer see your streak.", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop Sharing", role: .destructive) { dismiss() }
        }
        .accessibilityIdentifier("personScreen")
    }
}

/// Gray search field that matches the People screen and the approved Share With design.
private struct FlatSearchField: View {
    @Binding var text: String
    var id: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Phone, Email or Contact", text: $text)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier(id)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear text")
            }
        }
        .font(.body)
        .padding(.horizontal, 12).frame(height: 40)
        .background(Color(.tertiarySystemFill), in: .capsule)
        .padding(.top, 4)
    }
}

/// Ask someone to share their streak with you.
struct AskToShareView: View {
    @State private var search = ""
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FlatSearchField(text: $search, id: "askSearch")
                Text("They\u{2019}ll get a request to share their streak with you.")
                    .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.top, 10)
                PeopleHeader("Contacts on Dayline")
                PeopleGroup {
                    ForEach(Array(PeopleStore.contacts.enumerated()), id: \.offset) { i, c in
                        PersonRow(name: c.0, subtitle: c.1, last: i == PeopleStore.contacts.count - 1) { PillButton(title: "Ask", done: "Asked") }
                    }
                }
                PeopleHeader("Not on Dayline Yet")
                PeopleGroup {
                    ForEach(Array(PeopleStore.notOnDayline.enumerated()), id: \.offset) { i, c in
                        PersonRow(name: c.0, subtitle: c.1, last: i == PeopleStore.notOnDayline.count - 1) {
                            ShareLink(item: PeopleStore.inviteText) {
                                Text("Invite").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accent)
                                    .padding(.horizontal, 14).padding(.vertical, 6).background(Theme.accent.opacity(0.12), in: .capsule)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Ask to Share")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("askScreen")
    }
}

/// Share your streak: contacts on Dayline get Share, anyone else found by search gets Invite.
struct ShareWithView: View {
    @State private var search = ""
    private var q: String { search.trimmingCharacters(in: .whitespaces).lowercased() }
    private func match(_ c: (String, String)) -> Bool { q.isEmpty || c.0.lowercased().contains(q) || c.1.lowercased().contains(q) }
    private var onDayline: [(String, String)] { PeopleStore.contacts.filter(match) }
    private var notOn: [(String, String)] { q.isEmpty ? [] : PeopleStore.notOnDayline.filter(match) }
    /// Friends who share with you but don't see your streak yet (Priya in the demo).
    private var followers: [StreakFriend] {
        let sharing = Set(PeopleStore.sharingWith.map(\.name))
        return FriendStore.friends.filter { !sharing.contains($0.name) && (q.isEmpty || $0.fullName.lowercased().contains(q)) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                FlatSearchField(text: $search, id: "shareSearch")
                if !onDayline.isEmpty || !followers.isEmpty {
                    PeopleHeader("Contacts on Dayline")
                    PeopleGroup {
                        ForEach(Array(onDayline.enumerated()), id: \.offset) { i, c in
                            PersonRow(name: c.0, subtitle: c.1, last: followers.isEmpty && i == onDayline.count - 1) {
                                PillButton(title: "Share", done: "Sharing")
                            }
                            .accessibilityIdentifier("share-\(c.0)")
                        }
                        ForEach(Array(followers.enumerated()), id: \.offset) { i, f in
                            PersonRow(name: f.fullName, subtitle: "Shares with you", color: f.color, last: i == followers.count - 1) {
                                PillButton(title: "Share", done: "Sharing")
                            }
                            .accessibilityIdentifier("share-\(f.name)")
                        }
                    }
                }
                if !notOn.isEmpty {
                    PeopleHeader("Not on Dayline Yet")
                    PeopleGroup {
                        ForEach(Array(notOn.enumerated()), id: \.offset) { i, c in
                            PersonRow(name: c.0, subtitle: c.1, last: i == notOn.count - 1) {
                                InviteButton(recipient: c.1)
                            }
                            .accessibilityIdentifier("shareInvite-\(c.0)")
                        }
                    }
                }
                Text(q.isEmpty ? "Share lets them see your streak only. Search to invite someone who isn\u{2019}t on Dayline." : "Share lets them see your streak only. Invite sends a link in Messages.")
                    .font(.footnote).helperText().padding(.horizontal, 16).padding(.top, 7)
            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .buttonStyle(.plain)
        .background(AppBackgroundView())
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Share With")
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("shareWithScreen")
    }
}
