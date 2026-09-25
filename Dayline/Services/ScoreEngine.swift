import Foundation
import SwiftData

/// Turns a day into a 0-100 score, a one-word label and an encouraging summary.
/// Style is inspired by readiness-type scores: one number, one label, and the factors that drove it.
extension ScoreFactor {
    init(part: ScoreEngine.Part, title: String, effect: Effect, points: Int, detail: String? = nil, chip: String? = nil) {
        self.init(title: title, effect: effect, points: points, detail: detail, chip: chip, part: part.rawValue)
    }
}

enum ScoreEngine {
    struct Result: Equatable {
        var score: Int
        var label: String
        var summary: String
        var tip: String?
        var factors: [ScoreFactor]
        var pace: Pace? = nil
    }

    /// Pace from your own habits: a habit only counts against you once its time is up
    /// (wake-up goal, work start, a plan's end, the gym's "Go By" time, bedtime for the journal).
    /// Extra activity, such as a workout, can win points back.
    struct Pace: Equatable {
        /// Points you can no longer get today from your habits.
        var lost: Int
        /// Points won back with make-up actions.
        var madeUp: Int = 0
        /// How well it's going so far, 0...1: points you have vs. points that were due by now.
        var good: Double = 1
        /// The habits whose time ran out.
        var missed: [String] = []
        /// What still counts against you after make-up points.
        var net: Int { max(0, lost - madeUp) }
        /// Small misses (under 5 points) don't count as behind.
        var behind: Bool { net >= 5 }
    }

    static let bonusPart = "bonus"

    static func pace(factors: [ScoreFactor], schedule s: UserSchedule, day: Date = .now, plan: [PlanItem] = [],
                     remindersTotal: Int = 0, now: Date = .now, calendar: Calendar = .current) -> Pace {
        let input = DayInput(firstActivity: nil, plan: [], visits: [], journal: [], isFinished: false, day: day, schedule: s)
        let w = weights(input, calendar: calendar)
        // Minutes since the start of this day; past midnight keeps counting (25:30 = 1:30 AM) while the day is still going.
        let mins = Int(now.timeIntervalSince(calendar.startOfDay(for: day)) / 60)
        let bed = s.bed < 12 * 60 ? s.bed + 24 * 60 : s.bed
        func earned(_ p: Part) -> Double { Double(max(0, factors.filter { $0.part == p.rawValue }.reduce(0) { $0 + $1.points })) }
        var lost = 0.0, due = 0.0, missed: [String] = []
        func miss(_ p: Part, _ name: String, deadline: Int, share: Double = 1) {
            guard let full = w[p], mins >= deadline else { return }
            due += full * share
            let gone = max(0, full * share - earned(p))
            if gone >= 1 { lost += gone; missed.append(name) }
        }
        miss(.wake, "Wake-up", deadline: s.wake + 10)
        if let block = s.work(on: day, calendar: calendar), w[.work] != nil {
            // Not at work half an hour after it starts; after it ends, whatever wasn't done.
            if mins >= block.end { miss(.work, "Work", deadline: block.end) }
            else if earned(.work) == 0 { miss(.work, "Work", deadline: block.start + 30) }
        }
        let total = plan.count + remindersTotal
        if total > 0, let full = w[.plans] {
            let over = plan.filter { $0.end <= now }
            let overdue = over.filter { !$0.isDone }.count
            due += full * Double(over.count) / Double(total)
            if overdue > 0 { lost += full * Double(overdue) / Double(total); missed.append("Plans") }
        }
        var moveBy = 0
        // Gym deadline: when your gym closes (real hours from Google). Hours unknown: the gym only counts as
        // missed at the end of the day (bedtime), never mid-day. With "gym.hours" off: the old Go By setting.
        if s.gym {
            let deadline = GymHours.enabled ? (GymHours.closing(on: day, calendar: calendar) ?? bed) : s.gymDeadline
            moveBy = max(moveBy, deadline)
        }
        if s.walk { moveBy = max(moveBy, bed - 60) }
        if moveBy > 0 { miss(.moving, s.gym && !s.walk ? "Gym" : "Moving", deadline: moveBy) }
        miss(.journal, "Journal", deadline: bed)
        miss(.bed, "Bedtime", deadline: bed + 10)
        let madeUp = Double(max(0, factors.filter { $0.part == bonusPart }.reduce(0) { $0 + $1.points }))
        let have = Double(max(0, factors.reduce(0) { $0 + $1.points }))
        // Points you have vs. points that were due by now (habits done early count on both sides).
        let early = have - (due - lost) - madeUp
        let good = min(1, have / max(10, due + max(0, early)))
        return Pace(lost: Int(lost.rounded()), madeUp: Int(madeUp), good: good, missed: missed)
    }

    struct DayInput {
        var firstActivity: Date?
        var plan: [PlanItem]
        var visits: [Visit]
        var journal: [JournalEntry]
        var isFinished: Bool
        var day: Date = .now
        var bedtime: Date? = nil
        var steps: Int = 0
        var remindersDone: Int = 0
        var remindersTotal: Int = 0
        var schedule: UserSchedule = .current
    }

    /// Base sizes. Anything switched off drops out and the rest grow evenly, so they still add up to 100.
    enum Part: String, CaseIterable { case wake, bed, work, plans, moving, gotOut, journal
        var base: Double {
            switch self {
            case .wake: return 20
            case .bed: return 10
            case .work: return 15
            case .plans: return 20
            case .moving: return 20
            case .gotOut: return 10
            case .journal: return 5
            }
        }
    }

    static func activeParts(_ input: DayInput, calendar: Calendar = .current) -> [Part] {
        let s = input.schedule
        var parts: [Part] = [.wake, .bed, .plans]
        if s.work(on: input.day, calendar: calendar) != nil { parts.append(.work) }
        if s.gym || s.walk { parts.append(.moving) }
        if s.journal { parts.append(.journal) }
        return parts
    }

    /// Points each part is worth today (they add up to 100).
    static func weights(_ input: DayInput, calendar: Calendar = .current) -> [Part: Double] {
        let parts = activeParts(input, calendar: calendar)
        let total = parts.reduce(0) { $0 + $1.base }
        return Dictionary(uniqueKeysWithValues: parts.map { ($0, $0.base * 100 / total) })
    }

    static func score(_ input: DayInput, calendar: Calendar = .current) -> Result {
        let s = input.schedule
        let w = weights(input, calendar: calendar)
        func pts(_ p: Part, _ fraction: Double) -> Int { Int(((w[p] ?? 0) * max(0, min(1, fraction))).rounded()) }
        var factors: [ScoreFactor] = []
        var summaryBits: [String] = []
        let outside = input.visits.filter { $0.category != .home }

        // 1. Wake-up vs goal
        if let first = input.firstActivity {
            let late = UserSchedule.minutes(of: first, calendar: calendar) - s.wake
            let time = first.formatted(date: .omitted, time: .shortened)
            if late <= 10 {
                factors.append(.init(part: .wake, title: "Up at \(time)", effect: .up, points: pts(.wake, 1))); summaryBits.append("woke up on time")
            } else if late <= 60 {
                factors.append(.init(part: .wake, title: "Up at \(time)", effect: .up, points: pts(.wake, 0.6)))
            } else {
                let minus = -min(8, 2 + ((late - 61) / 30))
                factors.append(.init(part: .wake, title: "Late start", effect: .neutral, points: minus))
            }
        } else if !input.isFinished {
            factors.append(.init(part: .wake, title: "Wake-up", effect: .pending, points: 0))
        }

        // 2. Bedtime vs goal
        if let bed = input.bedtime {
            var m = UserSchedule.minutes(of: bed, calendar: calendar), goal = s.bed
            if m < 12 * 60 { m += 24 * 60 }; if goal < 12 * 60 { goal += 24 * 60 }
            let late = m - goal
            let time = bed.formatted(date: .omitted, time: .shortened)
            if late <= 10 { factors.append(.init(part: .bed, title: "Bed at \(time)", effect: .up, points: pts(.bed, 1))) }
            else if late <= 30 { factors.append(.init(part: .bed, title: "Bed at \(time)", effect: .up, points: pts(.bed, 0.5))) }
            else {
                let minus = late <= 60 ? 0 : -min(10, 2 * ((late - 31) / 30))
                factors.append(.init(part: .bed, title: "Late night", effect: .neutral, points: minus))
            }
        } else {
            factors.append(.init(part: .bed, title: "Bedtime", effect: .pending, points: 0))
        }

        // 3. Work (only on work days)
        if w[.work] != nil, let block = s.work(on: input.day, calendar: calendar) {
            let ws = UserSchedule.date(block.start, on: input.day, calendar: calendar)
            let we = UserSchedule.date(block.end, on: input.day, calendar: calendar)
            let planned = max(1, we.timeIntervalSince(ws))
            let atWork = input.visits.filter { $0.category == .work }.reduce(0.0) { sum, v in
                let a = max(v.arrival, ws), b = min(v.departure ?? .now, we)
                return sum + max(0, b.timeIntervalSince(a))
            }
            if atWork > 0 {
                factors.append(.init(part: .work, title: "Work", effect: .up, points: pts(.work, min(1, atWork / planned / 0.8)))); summaryBits.append("worked")
            } else {
                factors.append(.init(part: .work, title: "Work", effect: .pending, points: 0))
            }
        }

        // 4. Plans & reminders: no tasks means nothing was completed, not an automatic reward.
        let plan = input.plan
        let total = plan.count + input.remindersTotal
        let done = plan.filter(\.isDone).count + input.remindersDone
        if total == 0 {
            factors.append(.init(part: .plans, title: "No plans or reminders yet", effect: .pending, points: 0))
        } else {
            factors.append(.init(part: .plans, title: "Plans: \(done) of \(total) done", effect: done > 0 ? .up : .pending, points: pts(.plans, Double(done) / Double(total))))
        }

        // 5. Moving: any one of gym, the personal step goal, or time outside. Half-way counts half.
        if w[.moving] != nil {
            var best = 0.0, title = "Move", bit: String? = nil
            if s.gym, outside.contains(where: { $0.category == .gym && $0.duration > 20 * 60 }) { best = 1; title = "Gym done"; bit = "hit the gym" }
            if s.walk, best < 1 {
                let f = Double(input.steps) / Double(max(1, s.stepGoal))
                if f > best { best = f; title = "\(input.steps.formatted()) steps"; if f >= 1 { bit = "hit your steps" } }
            }
            if let bit { summaryBits.append(bit) }
            factors.append(.init(part: .moving, title: best > 0 ? title : "Move later", effect: best > 0 ? .up : .pending, points: pts(.moving, best)))
        }

        // Apple Health workouts arrive as journal lines ("Run · 5.2 km · 31 min"); they count as activity, not journaling.
        let workouts = input.journal.filter { $0.placeName == "Apple Health" }
        let entries = input.journal.filter { $0.placeName != "Apple Health" }
        // One composer save may contain text, photos and voice stored as separate records.
        // Count it once for the person's journal habit.
        let distinctEntries = Set(entries.map { $0.groupID ?? String(describing: $0.persistentModelID) }).count

        // 7. Journal
        if w[.journal] != nil, !entries.isEmpty {
            factors.append(.init(part: .journal, title: "Journaled", effect: .up, points: pts(.journal, Double(distinctEntries) * 0.4),
                                 detail: "\(distinctEntries) journal entr\(distinctEntries == 1 ? "y" : "ies")")))
        }

        // 8. Make-up actions: anything good wins back points for missed habits (and moves the ring back toward blue).
        // Workouts from Apple Health (a run, a ride, a swim), a lot more steps than usual,
        // or a gym visit when the gym isn't one of your habits.
        for wk in workouts.prefix(2) {
            let kind = wk.text.components(separatedBy: " · ").first ?? "Workout"
            let rest = wk.text.components(separatedBy: " · ").dropFirst().joined(separator: " · ")
            factors.append(ScoreFactor(title: "\(kind) (make-up)", effect: .up, points: 12,
                                       detail: rest.isEmpty ? "From Apple Health" : "\(rest) · from Apple Health", part: bonusPart))
        }
        let usual = max(1, s.stepGoal)
        if input.steps >= usual * 3 / 2 || (!s.walk && input.steps >= usual) {
            factors.append(ScoreFactor(title: "Lots of steps", effect: .up, points: 8,
                                       detail: "\(input.steps.formatted()) steps · probably a walk", part: bonusPart))
        }
        if !s.gym, outside.contains(where: { $0.category == .gym && $0.duration > 20 * 60 }) {
            factors.append(ScoreFactor(title: "Gym (make-up)", effect: .up, points: 15, detail: "Not one of your habits, so it makes up for a miss", part: bonusPart))
        }

        let score = max(0, min(100, factors.reduce(0) { $0 + $1.points }))
        let label = label(for: score, finished: input.isFinished)
        return Result(score: score, label: label, summary: summary(score: score, bits: summaryBits, finished: input.isFinished),
                      tip: tip(factors: factors, plan: plan, finished: input.isFinished, score: score), factors: factors,
                      pace: input.isFinished ? nil : pace(factors: factors, schedule: s, day: input.day, plan: plan,
                                                          remindersTotal: input.remindersTotal, calendar: calendar))
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

    /// The tip follows the time of day and what's still open.
    /// No walk ideas before the evening; a missing journal is the first suggestion.
    static func dynamicTip(score: Int, factors: [ScoreFactor], at date: Date = .now) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        func to(_ gain: Int) -> Int { min(100, score + gain) }
        let journalOpen = factors.contains { $0.title == "Journal" && $0.effect == .pending }
        if journalOpen && hour >= 7 { return "A journal now gets you to \(to(6))." }
        switch hour {
        case 5..<12: return "Getting to your plans on time keeps you at \(score)+."
        case 12..<17: return "Finish your afternoon plans to reach \(to(8))."
        case 17..<21: return "A 20-min walk tonight gets you to \(to(10))."
        default: return "Bed by 11:30 keeps tomorrow on track."
        }
    }

    static func tip(factors: [ScoreFactor], plan: [PlanItem], finished: Bool, score: Int) -> String? {
        guard !finished else { return nil }
        if let good = factors.last(where: { $0.part == bonusPart && $0.points > 0 }) {
            let name = good.title.replacingOccurrences(of: " (make-up)", with: "")
            return "You did good. \(name) won back \(good.points) points."
        }
        if let next = plan.filter({ !$0.isDone && $0.start > .now }).sorted(by: { $0.start < $1.start }).first {
            let gain = max(5, Int(20.0 / Double(max(plan.count, 1))))
            return "Keep going. \(next.title) gets you to \(min(100, score + gain))+."
        }
        if factors.contains(where: { $0.effect == .pending && $0.title == "Move later" }) {
            return "A short walk later adds points."
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
        // Writing a journal entry does not establish when the person woke up.
        let first = DayBoundary.shared.wakeUp(on: day, calendar: calendar)
            ?? [leftHome, firstOut.map { $0.addingTimeInterval(-15 * 60) }].compactMap { $0 }.min()
        return .init(firstActivity: first, plan: plan, visits: visits, journal: journal, isFinished: end <= .now,
                     day: day, bedtime: DayBoundary.shared.night(after: day, calendar: calendar)?.sleep,
                     steps: DayCache.steps(for: day), remindersDone: DayCache.reminders(for: day).done,
                     remindersTotal: DayCache.reminders(for: day).total)
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

/// Values read asynchronously (steps, reminders) and kept per day so scoring stays synchronous.
@MainActor
enum DayCache {
    private static func k(_ p: String, _ day: Date) -> String { "daycache.\(p).\(DayBoundary.key(day))" }
    static func steps(for day: Date) -> Int { UserDefaults.standard.integer(forKey: k("steps", day)) }
    static func setSteps(_ n: Int, for day: Date) { UserDefaults.standard.set(n, forKey: k("steps", day)) }
    static func reminders(for day: Date) -> (done: Int, total: Int) {
        (UserDefaults.standard.integer(forKey: k("remDone", day)), UserDefaults.standard.integer(forKey: k("remTotal", day)))
    }
    static func setReminders(done: Int, total: Int, for day: Date) {
        UserDefaults.standard.set(done, forKey: k("remDone", day)); UserDefaults.standard.set(total, forKey: k("remTotal", day))
    }
}
