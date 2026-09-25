import Foundation
import SwiftData
import UIKit

/// Sample data is on for `-demo` runs and always in the simulator, so the full experience shows right away.
enum SampleMode {
    /// Screenshot runs pass "-no.lookaround" so search screens skip Look Around imagery (heavy on CI Macs).
    static let noLookAround = ProcessInfo.processInfo.arguments.contains("-no.lookaround")
    static let on: Bool = {
        #if targetEnvironment(simulator)
        return true
        #else
        return ProcessInfo.processInfo.arguments.contains("-demo")
        #endif
    }()
}

/// Sample data for previews and the screen-recording demo (launch with `-demo`).
@MainActor
enum DemoData {
    static let base = (lat: 40.7359, lon: -73.9911)
    static let isDemo = SampleMode.on
    /// Screenshot-only "-demo.day late": a day that starts at 9 with a gap until work at noon.
    static var lateDay: Bool { UserDefaults.standard.string(forKey: "demo.day") == "late" }

    /// Today's score in demo mode, matching the approved design.
    /// "-demo.pace" (screenshots only) shows David's own example with a gym by 8 PM:
    /// "notup" = past the wake-up goal and not up; "gym" = up, gym still possible (on track);
    /// "nogym" = the gym's time ran out; "late" = gym and journal both ran out.
    static var todayScore: ScoreEngine.Result {
        let weekday = Date.now.formatted(.dateTime.weekday(.wide))
        let scenario = UserDefaults.standard.string(forKey: "demo.pace") ?? ""
        if !scenario.isEmpty { return paceScore(scenario) }
        // "-demo.score N" (screenshots only) shows a different score, e.g. a not-on-track day.
        let forced = UserDefaults.standard.integer(forKey: "demo.score")
        let score = forced > 0 ? forced : 74
        let factors = [
            ScoreFactor(part: .wake, title: "Woke up on time", effect: .up, points: 14, detail: "Up at 6:50 · goal 7:00", chip: "Up at 6:50"),
            ScoreFactor(part: .moving, title: "Gym", effect: .up, points: 18, detail: "Done · 52 min", chip: "Gym done"),
            ScoreFactor(part: .plans, title: "Plans", effect: .neutral, points: 16, detail: "3 of 4 done so far", chip: "At work"),
            ScoreFactor(part: .moving, title: "Moving", effect: .up, points: 10, detail: "6,240 steps · 4.1 km"),
            ScoreFactor(part: .bed, title: "Late night", effect: .up, points: -6, detail: "Phone until 1:10 AM"),
            ScoreFactor(part: .journal, title: "Journal", effect: .pending, points: 0, detail: "Not yet today"),
        ]
        return ScoreEngine.Result(
            score: score, label: forced > 0 ? ScoreEngine.label(for: score, finished: false) : "On track",
            summary: "Better than your \(weekday) average (68). A 30-min walk tonight gets you to 85+.",
            tip: "Keep going. A walk tonight gets you to 85+.",
            factors: factors,
            pace: ScoreEngine.pace(factors: factors, schedule: UserSchedule.current))
    }

    /// Settings used for the pace examples: up by 7, gym by 8 PM, bed at 11.
    static var paceSchedule: UserSchedule {
        var s = UserSchedule(); s.gym = true; s.walk = false; s.outside = false; s.gymBy = 20 * 60; return s
    }

    /// Screenshot-only day stories ("-demo.pace <name>"). The hour comes from the simulator clock, so each
    /// story can be shot at several times of day. Points follow the habit sizes in ScoreEngine (wake 20, bed 10,
    /// plans 20, work 15, moving 20, getting out 10, journal 5).
    static func paceScore(_ scenario: String) -> ScoreEngine.Result {
        let cal = Calendar.current
        let hour = cal.component(.hour, from: .now)
        let today = cal.startOfDay(for: .now)
        func F(_ part: ScoreEngine.Part, _ title: String, _ points: Int, _ detail: String, _ effect: ScoreFactor.Effect = .up) -> ScoreFactor {
            ScoreFactor(part: part, title: title, effect: effect, points: points, detail: detail)
        }
        func bonus(_ title: String, _ points: Int, _ detail: String) -> ScoreFactor {
            ScoreFactor(title: title, effect: .up, points: points, detail: detail, part: ScoreEngine.bonusPart)
        }
        func planItem(_ title: String, _ h: Int, _ m: Int, minutes: Int, done: Bool) -> PlanItem {
            let start = cal.date(bySettingHour: h, minute: m, second: 0, of: today)!
            return PlanItem(title: title, start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAuto: false, isDone: done)
        }
        var sched = paceSchedule, day = Date.now, plan: [PlanItem] = []
        var f: [ScoreFactor] = []
        var tip = ""
        switch scenario {
        case "notup":
            f = [F(.wake, "Wake-up", 0, "Not up yet · goal 7:00", .pending), F(.moving, "Gym", 0, "Open until 8 PM", .pending)]
            tip = "Up now still gets you most of the wake-up points."
        case "gym":
            f = [F(.wake, "Woke up on time", 20, "Up at 6:50"), F(.work, "Work", 9, "At the office since 9:00"),
                 F(.plans, "Plans", 11, "2 of 4 done so far"), F(.moving, "Gym", 0, "Still time · open until 8 PM", .pending)]
            tip = "Gym before 8 PM keeps you on track."
        case "nogym", "late":
            f = [F(.wake, "Woke up on time", 20, "Up at 6:50"), F(.work, "Work", 15, "9:00 to 5:10"), F(.plans, "Plans", 16, "3 of 4 done"),
                 F(.moving, "Gym", 0, "Missed · closed at 8 PM", .pending), F(.gotOut, "1 place", 4, "Blue Door Coffee")]
            tip = scenario == "late" ? "Tomorrow: gym before 8 PM keeps you on track." : "A journal tonight wins back a little."
        case "g3":
            // A night owl: up at 11, bed at 3:30 AM. Everything done, 3 AM is still their day.
            sched.wake = 11 * 60; sched.bed = 3 * 60 + 30; sched.gymBy = 22 * 60
            day = cal.date(byAdding: .day, value: -1, to: today)!
            f = [F(.wake, "Woke up on time", 20, "Up at 10:50"), F(.work, "Work", 15, "Full day"), F(.plans, "Plans", 20, "4 of 4 done"),
                 F(.moving, "Gym", 20, "Done · 9:30 PM"), F(.gotOut, "3 places", 10, "Out and about"), F(.journal, "Journaled", 5, "2 entries")]
            tip = "Bed by 3:30 keeps a great day great."
        case "b3":
            // Usual schedule (bed at 11), still up at 3 AM after a day that already slipped.
            day = cal.date(byAdding: .day, value: -1, to: today)!
            f = [F(.wake, "Woke up on time", 20, "Up at 6:55"), F(.work, "Work", 15, "9:00 to 5:05"), F(.plans, "Plans", 15, "3 of 4 done"),
                 F(.moving, "Gym", 0, "Missed · closed at 8 PM", .pending), F(.gotOut, "3 places", 10, "Out and about"),
                 F(.journal, "Journal", 0, "Nothing yet", .pending), F(.bed, "Still up", 0, "Phone at 3:00 AM · goal 11 PM", .pending)]
            tip = "Sleep now. Tomorrow starts fresh."
        case "g9":
            f = [F(.wake, "Woke up on time", 20, "Up at 6:45"), F(.moving, "Gym", 20, "Done · 7:05")]
            tip = "Great start. Work next."
        case "g15":
            f = [F(.wake, "Woke up on time", 20, "Up at 6:45"), F(.moving, "Gym", 20, "Done · 7:05"), F(.work, "Work", 11, "At the office since 8:55"),
                 F(.plans, "Plans", 10, "2 of 4 done")]
            tip = "Right on track. Finish your plans to keep it."
        case "b15":
            f = [F(.wake, "Late start", 0, "Up at 10:40 · goal 7:00", .pending), F(.work, "Work", 5, "Got in at 11:50"),
                 F(.plans, "Plans", 5, "1 of 4 done"), F(.moving, "Gym", 0, "Still open until 8 PM", .pending)]
            plan = [planItem("Lunch with Sam", 12, 30, minutes: 45, done: false), planItem("Standup", 11, 0, minutes: 15, done: false),
                    planItem("Call mom", 17, 0, minutes: 20, done: false), planItem("Groceries", 18, 30, minutes: 30, done: false)]
            tip = "Gym before 8 PM wins a lot back."
        case "b21":
            f = [F(.wake, "Up at 7:45", 12, "45 min late"), F(.work, "Work", 8, "Left at 1:30"), F(.plans, "Plans", 8, "1 of 4 done"),
                 F(.moving, "Gym", 0, "Missed · closed at 8 PM", .pending)]
            tip = "A journal tonight wins back a little."
        case "slip":
            // Good morning, then it slips from 1:30 PM: left work, missed lunch and coffee plans, then the gym.
            f = [F(.wake, "Woke up on time", 20, "Up at 6:50")]
            plan = [planItem("Lunch at Lucia", 12, 30, minutes: 45, done: false), planItem("Coffee with Sam", 15, 0, minutes: 30, done: false),
                    planItem("Groceries", 18, 0, minutes: 30, done: false), planItem("Read", 21, 30, minutes: 30, done: false)]
            if hour >= 13 { f.append(F(.work, "Work", 6, "Left at 1:30")) } else { f.append(F(.work, "Work", 2, "At the office since 9:00")) }
            if hour >= 20 { f.append(F(.moving, "Gym", 0, "Missed · closed at 8 PM", .pending)) }
            else { f.append(F(.moving, "Gym", 0, "Open until 8 PM", .pending)) }
            tip = hour < 13 ? "Great morning. Keep it going." : hour < 20 ? "Gym before 8 PM gets you back on track." : "Tomorrow: gym before 8 PM."
        case "allbad":
            f = [F(.wake, "Up at 8:50", 4, "Almost 2 hours late")]
            plan = [planItem("Standup", 10, 0, minutes: 15, done: false), planItem("Lunch with Sam", 12, 30, minutes: 45, done: false),
                    planItem("Coffee", 16, 0, minutes: 30, done: false), planItem("Groceries", 18, 0, minutes: 30, done: false)]
            if hour >= 12 { f.append(F(.work, "Work", 3, "Got in at 12:10")) }
            if hour >= 20 { f.append(F(.moving, "Gym", 0, "Missed · closed at 8 PM", .pending)) }
            tip = hour < 20 ? "Gym before 8 PM wins a lot back." : "Rest up. Tomorrow starts fresh."
        case "run":
            // A late start, then good things win it back: a run from Apple Health and lots of steps.
            f = [F(.wake, "Up at 9:00", 4, "Late start · goal 7:00")]
            if hour >= 13 { f += [F(.work, "Work", 8, "At the office since 12:00"), F(.journal, "Journaled", 5, "1 entry")] }
            if hour >= 15 { f.append(bonus("Run (make-up)", 12, "5.2 km · 31 min · from Apple Health")) }
            if hour >= 19 { f += [F(.work, "Work", 7, "Full afternoon"), bonus("Lots of steps", 8, "13,900 steps · probably a walk")] }
            tip = hour < 13 ? "A late start. Anything good wins it back: a run, a long walk, journaling." : hour < 15 ? "A run or a long walk would win points back." : "You did good. The run won back 12 points."
        case "recover":
            // Not a gym person: walks are the habit. A late start, then make-up actions win it back.
            sched = UserSchedule(); sched.gym = false; sched.walk = true
            f = [F(.wake, "Up at 8:40", 4, "Late start · goal 7:00")]
            if hour >= 12 {
                f += [F(.work, "Work", 8, "At the office since 9:40"), F(.journal, "Journaled", 5, "3 entries"),
                      bonus("Extra journaling", 6, "2 more entries than usual")]
            }
            if hour >= 17 {
                f += [F(.work, "Work", 7, "Full afternoon"), F(.plans, "Plans", 16, "3 of 4 done"),
                      bonus("Gym (make-up)", 15, "Not one of your habits, so it makes up for the late start")]
            }
            tip = hour < 12 ? "A late start. Extra journaling or a workout wins it back." : hour < 17 ? "Winning it back. A workout would finish the job." : "Made up for the late start."
        default:
            f = [F(.wake, "Woke up on time", 20, "Up at 6:50")]
        }
        let score = min(100, f.reduce(0) { $0 + $1.points })
        let pace = ScoreEngine.pace(factors: f, schedule: sched, day: day, plan: plan)
        return ScoreEngine.Result(score: score, label: ScoreEngine.label(for: score, finished: false),
                                  summary: tip, tip: tip, factors: f, pace: pace)
    }

    static func seed(_ context: ModelContext, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: .now)
        func at(_ day: Date, _ h: Int, _ m: Int) -> Date { calendar.date(bySettingHour: h, minute: m, second: 0, of: day)! }
        func place(_ dx: Double, _ dy: Double) -> (Double, Double) { (base.lat + dy, base.lon + dx) }

        let home = place(0, 0), gym = place(0.004, 0.003), cafe = place(0.009, 0.006),
            work = place(0.014, 0.012), park = place(0.020, 0.004), food = place(0.016, 0.009)

        // 45 days of history so the routine learner and charts have something to work with.
        var rng = SystemRandomNumberGenerator()
        for offset in (1...45).reversed() {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let weekend = calendar.isDateInWeekend(day)
            let wake = Int.random(in: 6...8, using: &rng)
            add(context, "Home", .home, home, at(day, 0, 0), at(day, wake, 30))
            if Bool.random(using: &rng) || offset % 3 == 0 {
                add(context, "Iron Works Gym", .gym, gym, at(day, wake, 45), at(day, wake + 1, 35))
            }
            if !weekend {
                add(context, "Office", .work, work, at(day, 9, 0), at(day, 12, 25))
                if calendar.component(.weekday, from: day) == 4 || Bool.random(using: &rng) {
                    add(context, "Riverside Noodle Bar", .food, food, at(day, 12, 35), at(day, 13, 20))
                }
                add(context, "Office", .work, work, at(day, 13, 30), at(day, 17, 0))
            } else {
                add(context, "Riverside Park", .outdoors, park, at(day, 11, 0), at(day, 13, 0))
            }
            add(context, "Home", .home, home, at(day, 17, 45), at(day, 23, 59))
            if offset % 4 == 2 && offset > 6 {
                context.insert(JournalEntry(date: at(day, 20, 10), kind: .text, text: "Good day overall."))
            }
        }

        // Today so far (matches the approved design: 4 places, about 3 km).
        let lunch = place(0.019, 0.016)
        if lateDay {
            // Screenshot-only "-demo.day late": up at 9, nothing known until work at noon, a lunch photo.
            add(context, "Office", .work, work, at(today, 12, 0), at(today, 12, 50))
            add(context, "Lucia Trattoria", .food, lunch, at(today, 13, 0), at(today, 13, 45))
            // A run after lunch, from Apple Health (a make-up: anything good wins points back).
            let run = JournalEntry(date: at(today, 14, 0), kind: .text, text: "Run · 5.2 km · 31 min", latitude: nil, longitude: nil)
            run.placeName = "Apple Health"
            context.insert(run)
            add(context, "Office", .work, work, at(today, 14, 40), nil)
            context.insert(JournalEntry(date: at(today, 13, 20), kind: .photo, text: "Lunch with the team.",
                                        thumbnail: photo("demo-coffee") ?? swatch(.brown), latitude: lunch.0, longitude: lunch.1, isTranscribed: true))
        } else {
        add(context, "Gym", .gym, gym, at(today, 7, 2), at(today, 7, 54))
        add(context, "Blue Door Coffee", .coffee, cafe, at(today, 8, 10), at(today, 8, 35))
        add(context, "Office", .work, work, at(today, 9, 0), at(today, 12, 25))
        add(context, "Lucia Trattoria", .food, lunch, at(today, 12, 35), nil)

        context.insert(JournalEntry(date: at(today, 8, 12), kind: .photo, text: "Coffee before work. Feeling focused today.",
                                    thumbnail: photo("demo-coffee") ?? swatch(.brown), latitude: cafe.0, longitude: cafe.1, isTranscribed: true))
        }
        // Photos from earlier this month, placed where they were taken.
        for (i, name) in ["demo-park", "demo-sunset", "demo-coffee"].enumerated() {
            let day = calendar.date(byAdding: .day, value: -(i * 3 + 6), to: today)!
            let p = [park, food, cafe][i]
            context.insert(JournalEntry(date: at(day, 12 + i * 3, 0), kind: .photo, thumbnail: photo(name), latitude: p.0, longitude: p.1))
        }
        // Dinner out four days ago, with photos: this is what "take me to where I ate 4 days ago" finds.
        let fourAgo = calendar.date(byAdding: .day, value: -4, to: today)!
        let trattoria = place(0.011, 0.015)
        do {
            let v = Visit(arrival: at(fourAgo, 19, 40), departure: at(fourAgo, 21, 5), latitude: trattoria.0, longitude: trattoria.1,
                          placeName: "Lucia Trattoria", category: .food)
            v.phoneNumber = "(212) 555-0148"
            context.insert(v)
            stops.append((at(fourAgo, 19, 40), at(fourAgo, 21, 5), trattoria))
            // That evening: home, out to dinner, home again (split the evening at home around it).
            stops.removeAll { $0.at == home && $0.arrival == at(fourAgo, 17, 45) }
            stops.append((at(fourAgo, 17, 45), at(fourAgo, 19, 15), home))
            stops.append((at(fourAgo, 21, 30), at(fourAgo, 23, 59), home))
            context.insert(JournalEntry(date: at(fourAgo, 19, 55), kind: .text, text: "Best cacio e pepe in a while. Come back with Sam.",
                                        latitude: trattoria.0, longitude: trattoria.1))
        }
        // Bakery the same morning, with photos: "the place I ate danishes 4 days ago" finds this one.
        // Photos: Wikimedia Commons, "Spandauer med syltetøj" by Nillerdk (CC BY 3.0), "Danish pastry" by RhinoMind (CC BY-SA 3.0).
        let bakery = place(0.006, 0.011)
        add(context, "Ferrara Bakery", .coffee, bakery, at(fourAgo, 9, 10), at(fourAgo, 9, 45))
        context.insert(JournalEntry(date: at(fourAgo, 9, 18), kind: .photo, text: "Cherry danish here is unreal.",
                                    thumbnail: photo("demo-danish"), latitude: bakery.0, longitude: bakery.1))
        context.insert(JournalEntry(date: at(fourAgo, 9, 19), kind: .photo, thumbnail: photo("demo-danish2"), latitude: bakery.0, longitude: bakery.1))
        writeTrack(context)
        if !lateDay { context.insert(JournalEntry(date: at(today, 11, 40), kind: .voice,
                                    text: "Finished the big project draft early. Feeling good about today.",
                                    audioDuration: 42, latitude: work.0, longitude: work.1, isTranscribed: true)) }
        try? context.save()
        RoutineLearner.fillToday(context: context)
        // Today's schedule exactly as in the design.
        for item in ((try? context.fetch(FetchDescriptor<PlanItem>())) ?? []) where calendar.isDateInToday(item.start) { context.delete(item) }
        let weekdays = Date.now.formatted(.dateTime.weekday(.wide)) + "s"
        if !lateDay { context.insert(PlanItem(title: "Gym", start: at(today, 7, 0), end: at(today, 7, 52), isAuto: true, reason: "Learned from your routine", isDone: true, category: .gym)) }
        context.insert(PlanItem(title: "Work", start: at(today, 9, 0), end: at(today, 17, 0), isAuto: true, reason: "Learned from your usual 9-5", category: .work))
        context.insert(PlanItem(title: "Lunch out", start: at(today, 12, 30), end: at(today, 13, 15), isAuto: true, reason: "You usually eat out on \(weekdays)", category: .food))
        context.insert(PlanItem(title: "Evening walk", start: at(today, 18, 0), end: at(today, 18, 45), isAuto: true, reason: "You usually walk after work", category: .outdoors))
        DayData.finalizePastDays(context: context)
        // Demo: a 6-day streak of 80+ days, one rough day before it, and a mostly good month (about 79 average).
        let recent = ((try? context.fetch(FetchDescriptor<DayScore>())) ?? [])
        let pattern = [84, 76, 88, 91, 72, 86, 79, 93, 81, 68, 87, 90, 77, 85, 82, 74, 89, 92, 70, 83]
        var history: [(Int, Int)] = [(1, 91), (2, 86), (3, 83), (4, 88), (5, 94), (6, 79 + 3), (7, 38)]
        for offset in 8...45 { history.append((offset, pattern[offset % pattern.count])) }
        // Best streak of 9 days, earlier in the month.
        let bestRun = [84, 88, 85, 91, 82, 86, 90, 93, 81]
        history = history.map { o, v in (19...28).contains(o) ? (o, o == 19 ? 74 : bestRun[o - 20]) : (o, v) }
        for (offset, value) in history {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let label = value >= 80 ? "Great day" : value >= 45 ? "Solid day" : "Rough day"
            let (summary, factors) = pastDay(value)
            if let s = recent.first(where: { $0.day == day }) {
                s.score = value; s.label = label; s.summary = summary; s.factorsJSON = try? JSONEncoder().encode(factors)
            } else {
                context.insert(DayScore(day: day, score: value, label: label, summary: summary, factors: factors))
            }
        }
        try? context.save()
    }

    /// What shaped a past demo day, so swiping back in Day score looks real.
    static func pastDay(_ score: Int) -> (String, [ScoreFactor]) {
        if score >= 80 {
            return ("Up early, gym, and a long walk.", [
                ScoreFactor(title: "Woke up on time", effect: .up, points: 16, detail: "Up at 6:45 · goal 7:00"),
                ScoreFactor(title: "Gym", effect: .up, points: 18, detail: "Done · 55 min"),
                ScoreFactor(title: "Plans", effect: .up, points: 20, detail: "Everything you usually do"),
                ScoreFactor(title: "Moving", effect: .up, points: 18, detail: "9,870 steps · 7.2 km"),
                ScoreFactor(title: "Late night", effect: .up, points: -2, detail: "Phone until 11:40 PM"),
                ScoreFactor(title: "Journal", effect: .up, points: 10, detail: "1 entry"),
            ])
        }
        if score >= 45 {
            return ("A normal day. No gym, but you got your usual things done.", [
                ScoreFactor(title: "Woke up on time", effect: .up, points: 12, detail: "Up at 7:10 · goal 7:00"),
                ScoreFactor(title: "Gym", effect: .pending, points: 0, detail: "Skipped"),
                ScoreFactor(title: "Plans", effect: .up, points: 18, detail: "Most of what you usually do"),
                ScoreFactor(title: "Moving", effect: .up, points: 10, detail: "5,400 steps · 3.8 km"),
                ScoreFactor(title: "Late night", effect: .up, points: -4, detail: "Phone until 12:30 AM"),
                ScoreFactor(title: "Journal", effect: .up, points: 10, detail: "1 entry"),
            ])
        }
        return ("A slow one. That's okay, rest counts too.", [
            ScoreFactor(title: "Woke up late", effect: .pending, points: 4, detail: "Up at 9:40 · goal 7:00"),
            ScoreFactor(title: "Gym", effect: .pending, points: 0, detail: "Skipped"),
            ScoreFactor(title: "Plans", effect: .neutral, points: 8, detail: "1 of 4 done"),
            ScoreFactor(title: "Moving", effect: .neutral, points: 4, detail: "1,900 steps · 1.3 km"),
            ScoreFactor(title: "Late night", effect: .up, points: -8, detail: "Phone until 2:15 AM"),
            ScoreFactor(title: "Journal", effect: .pending, points: 0, detail: "Nothing yet"),
        ])
    }

    /// Every demo stay, in order, so the GPS track can be written once all of them are known.
    private static var stops: [(arrival: Date, departure: Date?, at: (Double, Double))] = []

    private static func add(_ c: ModelContext, _ name: String, _ cat: PlaceCategory, _ p: (Double, Double), _ a: Date, _ d: Date?) {
        c.insert(Visit(arrival: a, departure: d, latitude: p.0, longitude: p.1, placeName: name, category: cat))
        stops.append((a, d, p))
    }

    /// Writes the demo GPS track the way the phone records it at the default check rate: one point every
    /// 5 minutes, staying put during a visit and following the Manhattan street grid between places
    /// (along a street, then up an avenue), so no line ever cuts across blocks.
    private static func writeTrack(_ c: ModelContext) {
        let list = stops.sorted { $0.arrival < $1.arrival }
        stops = []
        let step: TimeInterval = 5 * 60
        let mPerLat = 111_000.0, mPerLon = 111_000.0 * cos(base.lat * .pi / 180)
        let tilt = 29.0 * .pi / 180            // avenues run about 29° east of north
        let ave = (x: sin(tilt), y: cos(tilt)), street = (x: cos(tilt), y: -sin(tilt))
        var seed: UInt64 = 7
        func jitter() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return (Double(seed >> 33) / Double(1 << 31) - 0.5) * 8 }
        func put(_ t: Date, _ lat: Double, _ lon: Double, _ src: String) {
            c.insert(LocationSample(timestamp: t, latitude: lat + jitter() / mPerLat, longitude: lon + jitter() / mPerLon,
                                    horizontalAccuracy: 15, source: src))
        }
        for (i, s) in list.enumerated() {
            let next = i + 1 < list.count ? list[i + 1] : nil
            // Leave early enough to walk to the next place at about 80 m a minute.
            var travel: TimeInterval = 0, dx = 0.0, dy = 0.0
            if let n = next {
                dx = (n.at.1 - s.at.1) * mPerLon; dy = (n.at.0 - s.at.0) * mPerLat
                travel = (abs(dx * street.x + dy * street.y) + abs(dx * ave.x + dy * ave.y)) / 80 * 60
            }
            let stayEnd = min(s.departure ?? .now, next.map { $0.arrival.addingTimeInterval(-travel) } ?? .now)
            var t = s.arrival
            while t <= max(stayEnd, s.arrival) { put(t, s.at.0, s.at.1, "visit"); t += step }
            guard let n = next, travel > 60, abs(dx) + abs(dy) > 60 else { continue }
            // Street leg then avenue leg, or avenue first: pick the order that stays on real streets
            // (Stuy Town / Peter Cooper Village and the river have no grid to walk through).
            let sa = dx * street.x + dy * street.y, aa = dx * ave.x + dy * ave.y
            func offGrid(_ lat: Double, _ lon: Double) -> Bool {
                (lat > 40.7285 && lat < 40.7375 && lon > -73.9820 && lon < -73.9710) || lon > -73.9720 && lat < 40.745
            }
            func badCount(_ first: (x: Double, y: Double), _ f: Double, _ second: (x: Double, y: Double), _ g: Double) -> Int {
                (0...20).filter { k in
                    let u = Double(k) / 20 * 2
                    let (x, y) = u <= 1 ? (first.x * f * u, first.y * f * u)
                                        : (first.x * f + second.x * g * (u - 1), first.y * f + second.y * g * (u - 1))
                    return offGrid(s.at.0 + y / mPerLat, s.at.1 + x / mPerLon)
                }.count
            }
            let aveFirst = badCount(ave, aa, street, sa) < badCount(street, sa, ave, aa)
            let (a1, a2) = aveFirst ? (aa, sa) : (sa, aa)
            let dir1 = aveFirst ? ave : street, dir2 = aveFirst ? street : ave
            let corner = (x: dir1.x * a1, y: dir1.y * a1)
            let start = max(stayEnd, s.arrival), dur = n.arrival.timeIntervalSince(start)
            let total = abs(a1) + abs(a2)
            // The corner where the street leg turns onto the avenue: the phone logs a point when you change
            // direction, so the line turns the corner instead of cutting across the block.
            if abs(a1) > 30 && abs(a2) > 30 {
                put(start.addingTimeInterval(dur * abs(a1) / total), s.at.0 + corner.y / mPerLat, s.at.1 + corner.x / mPerLon, "gps")
            }
            t = start + step
            while t < n.arrival {
                let d = total * t.timeIntervalSince(start) / dur
                let (x, y) = d <= abs(a1)
                    ? (corner.x * d / max(abs(a1), 1), corner.y * d / max(abs(a1), 1))
                    : (corner.x + dir2.x * a2 * (d - abs(a1)) / max(abs(a2), 1), corner.y + dir2.y * a2 * (d - abs(a1)) / max(abs(a2), 1))
                put(t, s.at.0 + y / mPerLat, s.at.1 + x / mPerLon, "gps")
                t += step
            }
        }
    }

    private static func photo(_ name: String) -> Data? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "jpg") else { return nil }
        return try? Data(contentsOf: url)
    }

    private static func swatch(_ color: UIColor) -> Data? {
        let r = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        return r.jpegData(withCompressionQuality: 0.8) { ctx in
            let colors = [color.cgColor, UIColor.systemOrange.cgColor] as CFArray
            let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors, locations: [0, 1])!
            ctx.cgContext.drawLinearGradient(g, start: .zero, end: CGPoint(x: 200, y: 200), options: [])
        }
    }
}
