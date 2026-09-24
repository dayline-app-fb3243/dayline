import Foundation
import SwiftData

/// Turns a day into a 0-100 score, a one-word label and an encouraging summary.
/// Style is inspired by readiness-type scores: one number, one label, and the factors that drove it.
enum ScoreEngine {
    struct Result: Equatable {
        var score: Int
        var label: String
        var summary: String
        var tip: String?
        var factors: [ScoreFactor]
    }

    struct DayInput {
        var firstActivity: Date?
        var plan: [PlanItem]
        var visits: [Visit]
        var journal: [JournalEntry]
        var isFinished: Bool
    }

    static func score(_ input: DayInput, calendar: Calendar = .current) -> Result {
        var factors: [ScoreFactor] = []
        var summaryBits: [String] = []

        // 1. Woke up early (20)
        if let first = input.firstActivity {
            let hour = calendar.component(.hour, from: first), minute = calendar.component(.minute, from: first)
            let time = first.formatted(date: .omitted, time: .shortened)
            if hour < 8 {
                factors.append(.init(title: "Up at \(time)", effect: .up, points: 20)); summaryBits.append("woke up early")
            } else if hour < 9 || (hour == 9 && minute == 0) {
                factors.append(.init(title: "Up at \(time)", effect: .up, points: 12))
            } else {
                factors.append(.init(title: "Late start", effect: .neutral, points: 4))
            }
        }

        // 2. Plan done (30)
        let plan = input.plan
        if !plan.isEmpty {
            let done = plan.filter(\.isDone).count
            let pts = Int((Double(done) / Double(plan.count) * 30).rounded())
            factors.append(.init(title: "\(done)/\(plan.count) planned", effect: done > 0 ? .up : .pending, points: pts))
        }

        // 3. Got out and about (20)
        let outside = input.visits.filter { $0.category != .home }
        let places = Set(outside.map(\.placeKey)).count
        if places > 0 { factors.append(.init(title: "\(places) place\(places == 1 ? "" : "s")", effect: .up, points: min(places, 4) * 5)) }
        if outside.contains(where: { $0.category == .work }) { summaryBits.append("worked") }

        // 4. Moved your body (15)
        let gym = outside.contains { $0.category == .gym && $0.duration > 20 * 60 }
        let outdoors = outside.filter { $0.category == .outdoors }.reduce(0) { $0 + $1.duration } > 30 * 60
        if gym { factors.append(.init(title: "Gym done", effect: .up, points: 15)); summaryBits.append("hit the gym") }
        else if outdoors { factors.append(.init(title: "Time outside", effect: .up, points: 12)); summaryBits.append("got outside") }
        else if !input.isFinished { factors.append(.init(title: "Move later", effect: .pending, points: 0)) }

        // 5. Journal (10) + went out to eat (5)
        if !input.journal.isEmpty { factors.append(.init(title: "Journaled", effect: .up, points: 10)) }
        if outside.contains(where: { $0.category == .food || $0.category == .coffee }) {
            factors.append(.init(title: "Went out", effect: .up, points: 5)); summaryBits.append("went out to eat")
        }

        let score = min(100, factors.reduce(0) { $0 + $1.points })
        let label = label(for: score, finished: input.isFinished)
        return Result(score: score, label: label, summary: summary(score: score, bits: summaryBits, finished: input.isFinished),
                      tip: tip(factors: factors, plan: plan, finished: input.isFinished, score: score), factors: factors)
    }

    static func label(for score: Int, finished: Bool) -> String {
        switch score {
        case 90...: finished ? "Great day" : "Crushing it"
        case 75..<90: finished ? "Strong day" : "On track"
        case 55..<75: finished ? "Solid day" : "Building"
        case 35..<55: "Slow day"
        default: "Rest day"
        }
    }

    static func summary(score: Int, bits: [String], finished: Bool) -> String {
        let list = ListFormatter.localizedString(byJoining: bits)
        if score >= 55, !bits.isEmpty {
            let lead = "You \(list)."
            return score >= 85 ? "\(lead) Keep it going!" : "\(lead) Nice work."
        }
        if finished {
            return bits.isEmpty
                ? "Some days are slow, and that's okay. Rest counts too. Tomorrow's a fresh start."
                : "You \(list). Not every day has to be big. Tomorrow's a fresh start."
        }
        return "The day's still young. One small win gets you moving."
    }

    static func tip(factors: [ScoreFactor], plan: [PlanItem], finished: Bool, score: Int) -> String? {
        guard !finished else { return nil }
        if let next = plan.filter({ !$0.isDone && $0.start > .now }).sorted(by: { $0.start < $1.start }).first {
            let gain = max(5, Int(30.0 / Double(max(plan.count, 1))))
            return "Keep going. \(next.title) gets you to \(min(100, score + gain))+."
        }
        if factors.contains(where: { $0.effect == .pending && $0.title == "Move later" }) {
            return "A short walk later adds up to 12 points."
        }
        return "Keep going. You're doing great."
    }
}

/// Builds score inputs from the database.
@MainActor
enum DayData {
    static func input(for day: Date, context: ModelContext, calendar: Calendar = .current) -> ScoreEngine.DayInput {
        // The day runs from waking up to falling asleep (see DayBoundary); 4 AM when sleep can't be read.
        let window = DayBoundary.shared.window(for: day, calendar: calendar)
        let start = window.start, end = window.end
        let plan = (try? context.fetch(FetchDescriptor<PlanItem>(predicate: #Predicate { $0.start >= start && $0.start < end }))) ?? []
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= start && $0.arrival < end }))) ?? []
        let journal = (try? context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date >= start && $0.date < end }))) ?? []
        // First activity: leaving home, or the first journal entry / check-in after 4 AM.
        let fourAM = start
        let leftHome = visits.filter { $0.category == .home }.compactMap(\.departure).filter { $0 > fourAM }.min()
        let firstOut = visits.filter { $0.category != .home }.map(\.arrival).filter { $0 > fourAM }.min()
        let firstJournal = journal.map(\.date).filter { $0 > fourAM }.min()
        // Wake-up = first motion after the overnight still stretch; otherwise the first sign of activity.
        let first = DayBoundary.shared.wakeUp(on: day, calendar: calendar)
            ?? [leftHome, firstOut.map { $0.addingTimeInterval(-15 * 60) }, firstJournal].compactMap { $0 }.min()
        return .init(firstActivity: first, plan: plan, visits: visits, journal: journal, isFinished: end <= .now)
    }

    /// Stores final scores for finished days that don't have one yet (last 60 days).
    static func finalizePastDays(context: ModelContext, calendar: Calendar = .current) {
        let existing = Set(((try? context.fetch(FetchDescriptor<DayScore>())) ?? []).map(\.day))
        let today = DayBoundary.shared.today
        for offset in 1...60 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            guard !existing.contains(day) else { continue }
            let input = input(for: day, context: context)
            guard input.firstActivity != nil || !input.visits.isEmpty else { continue }
            let r = ScoreEngine.score(input)
            context.insert(DayScore(day: day, score: r.score, label: r.label, summary: r.summary, factors: r.factors))
        }
        try? context.save()
    }

    static func streak(context: ModelContext, calendar: Calendar = .current) -> Int {
        let scores = ((try? context.fetch(FetchDescriptor<DayScore>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? [])
        var count = 0
        let today = DayBoundary.shared.today
        // Today counts once it reaches 80; otherwise the streak runs through yesterday.
        var expected = scores.first.map { $0.day == today && $0.score >= 80 } == true ? today : calendar.date(byAdding: .day, value: -1, to: today)!
        for s in scores where s.day <= expected {
            guard s.day == expected, s.score >= 80 else { break }
            count += 1
            expected = calendar.date(byAdding: .day, value: -1, to: expected)!
        }
        return count
    }
}
