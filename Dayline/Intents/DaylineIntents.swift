import AppIntents
import SwiftData

/// "Hey Siri, how's my day going in Dayline?"
struct DayScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Day Score"
    static let description = IntentDescription("Tells you today's score and what's driving it.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> & ShowsSnippetView {
        let r = ScoreEngine.score(DayData.input(for: .now, context: ModelStore.container.mainContext))
        let f = r.factors.filter { $0.points != 0 }.map { ($0.title, $0.points) }
        return .result(value: r.score, dialog: "You're at \(r.score). \(r.label). \(r.tip ?? r.summary)",
                       view: DayScoreSnippetView(score: r.score, label: r.label, tip: r.tip, factors: f))
    }
}

/// "Hey Siri, journal my last 3 photos in Dayline" - adds the latest photos plus what you say.
struct JournalByVoiceIntent: AppIntent {
    static let title: LocalizedStringResource = "Journal by Voice"
    static let description = IntentDescription("Adds your latest photos to today's journal with words you dictate.")
    @Parameter(title: "Photos", default: 1, inclusiveRange: (0, 20)) var count: Int
    @Parameter(title: "Words", requestValueDialog: "What do you want to say about it?") var note: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = ModelStore.container.mainContext
        let added = count > 0 ? try await PhotoService.shared.addLatestPhotos(count: count, context: context) : []
        let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            context.insert(JournalEntry(date: .now, kind: .text, text: text, latitude: added.first?.latitude, longitude: added.first?.longitude))
            try context.save()
        }
        await DayRefresher.refresh(context: context)
        let photos = added.count == 1 ? "1 photo" : "\(added.count) photos"
        let view = JournalSnippetView(photos: added.compactMap(\.thumbnail), note: text,
                                      detail: "Today · \(Date.now.shortTime)")
        return .result(dialog: added.isEmpty ? "Saved it to today's journal." : "Added \(photos) and what you said to today's journal.", view: view)
    }
}

/// "Hey Siri, what's my streak in Dayline?"
struct StreakIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Streak"
    static let description = IntentDescription("Tells you how many days in a row you've hit 80 or more.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> & ShowsSnippetView {
        let n = DayData.streak(context: ModelStore.container.mainContext)
        let lead = FriendStore.friends.filter { $0.current > n }.map(\.name)
        let extra = lead.isEmpty ? (FriendStore.friends.isEmpty ? "" : " You're ahead of all your friends.") : " \(lead.joined(separator: " and ")) \(lead.count == 1 ? "is" : "are") ahead of you."
        let scores = ((try? ModelStore.container.mainContext.fetch(FetchDescriptor<DayScore>(sortBy: [SortDescriptor(\.day)]))) ?? [])
        var best = 0, run = 0
        var prev: Date?
        for s in scores {
            if s.score >= 80, let p = prev, Calendar.current.dateComponents([.day], from: p, to: s.day).day == 1, run > 0 { run += 1 }
            else { run = s.score >= 80 ? 1 : 0 }
            prev = s.day; best = max(best, run)
        }
        var rows = FriendStore.friends.map { ($0.name, $0.color, $0.current) } + [("You", Theme.accent, n)]
        rows.sort { $0.2 > $1.2 }
        return .result(value: n, dialog: n == 0 ? "No streak yet. Hit 80 today to start one." : "You're on a \(n)-day streak.\(extra)",
                       view: StreakSnippetView(days: n, best: max(best, n), rows: rows))
    }
}

/// "Hey Siri, how's Sam's streak in Dayline?" (friends only share streaks)
struct FriendScoreIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Friend's Streak"
    static let description = IntentDescription("Tells you a friend's streak compared with yours.")
    @Parameter(title: "Friend") var name: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        guard let f = FriendStore.friends.first(where: {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame || $0.fullName.localizedCaseInsensitiveContains(name)
        }) else {
            throw FriendError.notFound(FriendStore.friends.isEmpty ? "Friend sharing isn't set up yet." : "I couldn't find \(name) in your Dayline friends.")
        }
        let mine = DayData.streak(context: ModelStore.container.mainContext)
        return .result(dialog: "\(f.name) is on a \(f.current)-day streak, you're at \(mine).",
                       view: FriendScoreSnippetView(name: f.name, color: f.color, streak: f.current, best: f.best, yourStreak: mine))
    }
}

/// "Hey Siri, where was I at 3 PM yesterday in Dayline?"
struct WhereWasIIntent: AppIntent {
    static let title: LocalizedStringResource = "Where Was I"
    static let description = IntentDescription("Tells you where you were at a time, from your timeline.")
    @Parameter(title: "When") var time: Date

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let visits = (try? ModelStore.container.mainContext.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrival)]))) ?? []
        if let v = visits.last(where: { $0.arrival <= time && ($0.departure ?? .now) >= time }) {
            let until = v.departure.map { " until \($0.shortTime)" } ?? ""
            let map = await RouteSnapshot.spot(.init(latitude: v.latitude, longitude: v.longitude))
            let day = v.arrival.formatted(.dateTime.weekday(.wide))
            let times = v.departure.map { "\(day) · \(v.arrival.shortTime) – \($0.shortTime)" } ?? "\(day) · since \(v.arrival.shortTime)"
            return .result(dialog: "You were at \(v.placeName), from \(v.arrival.shortTime)\(until).",
                           view: WhereWasISnippetView(name: v.placeName, timeText: times, note: nil, map: map))
        }
        if let v = visits.last(where: { $0.arrival <= time }), Calendar.current.isDate(v.arrival, inSameDayAs: time) {
            throw FriendError.notFound("You were on the move then. Your last stop before that was \(v.placeName).")
        }
        throw FriendError.notFound("I don't have your location for that time.")
    }
}

enum FriendError: Error, CustomLocalizedStringResourceConvertible {
    case notFound(String)
    var localizedStringResource: LocalizedStringResource {
        switch self { case .notFound(let m): LocalizedStringResource(stringLiteral: m) }
    }
}

extension Notification.Name { static let openVoiceCapture = Notification.Name("openVoiceCapture") }

struct DaylineShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: FindPlaceIntent(), phrases: [
            "Take me back with \(.applicationName)",
            "Take me back in \(.applicationName)",
            "\(.applicationName), take me back",
            "\(.applicationName), take me back to the \(\.$kind)",
            "Take me back to the \(\.$kind) with \(.applicationName)",
            "Take me back to the \(\.$kind) in \(.applicationName)",
            "Take me back to that \(\.$kind) with \(.applicationName)",
            "Take me to the \(\.$kind) I went to in \(.applicationName)",
            "Take me back to a place with \(.applicationName)",
            "Take me back to where I ate with \(.applicationName)",
            "Take me to where I ate in \(.applicationName)",
            "Take me to the place I ate with \(.applicationName)",
            "Where did I eat in \(.applicationName)",
            "Where did I go in \(.applicationName)",
            "Where was that \(\.$kind) in \(.applicationName)",
            "Find the \(\.$kind) I went to in \(.applicationName)",
            "Find a place I went in \(.applicationName)",
            "Find a place with \(.applicationName)",
            "Help me find the \(\.$kind) I went to in \(.applicationName)",
            "Show me the \(\.$kind) I went to in \(.applicationName)",
            "Get me back to the \(\.$kind) with \(.applicationName)",
            "Go back to the \(\.$kind) with \(.applicationName)",
            "Directions to the \(\.$kind) I went to with \(.applicationName)"
        ], shortTitle: "Take Me Back", systemImageName: "arrow.triangle.turn.up.right.diamond.fill")
        AppShortcut(intent: JournalByVoiceIntent(), phrases: [
            "Journal in \(.applicationName)",
            "Journal my latest photos in \(.applicationName)",
            "Add to my journal in \(.applicationName)"
        ], shortTitle: "Journal by Voice", systemImageName: "text.bubble.fill")
        AppShortcut(intent: FriendScoreIntent(), phrases: [
            "How's my friend's streak in \(.applicationName)",
            "Check a friend's streak in \(.applicationName)"
        ], shortTitle: "Friend's Streak", systemImageName: "person.2.fill")
        AppShortcut(intent: WhereWasIIntent(), phrases: [
            "Where was I in \(.applicationName)",
            "Where was I earlier in \(.applicationName)"
        ], shortTitle: "Where Was I", systemImageName: "mappin.and.ellipse")
        AppShortcut(intent: StreakIntent(), phrases: [
            "What's my streak in \(.applicationName)",
            "How long is my \(.applicationName) streak"
        ], shortTitle: "My Streak", systemImageName: "flame.fill")
        AppShortcut(intent: DayScoreIntent(), phrases: [
            "How's my day going in \(.applicationName)",
            "What's my \(.applicationName) score"
        ], shortTitle: "Day Score", systemImageName: "gauge.with.dots.needle.67percent")
    }
}
