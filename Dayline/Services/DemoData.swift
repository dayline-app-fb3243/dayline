import Foundation
import SwiftData
import UIKit

/// Sample data is on for `-demo` runs and always in the simulator, so the full experience shows right away.
enum SampleMode {
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
            ScoreFactor(part: .journal, title: "Journal", effect: .pending, points: 0, detail: "No note yet"),
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

    static func paceScore(_ scenario: String) -> ScoreEngine.Result {
        var f = [ScoreFactor(part: .bed, title: "Bed on time", effect: .up, points: 10, detail: "Asleep by 11:05 PM")]
        switch scenario {
        case "notup":
            f += [ScoreFactor(part: .wake, title: "Wake-up", effect: .pending, points: 0, detail: "Not up yet · goal 7:00"),
                  ScoreFactor(part: .moving, title: "Gym", effect: .pending, points: 0, detail: "Open until 8 PM")]
        case "gym":
            f += [ScoreFactor(part: .wake, title: "Woke up on time", effect: .up, points: 20, detail: "Up at 6:50 · goal 7:00"),
                  ScoreFactor(part: .work, title: "Work", effect: .up, points: 9, detail: "At the office since 9:00"),
                  ScoreFactor(part: .plans, title: "Plans", effect: .up, points: 11, detail: "2 of 4 done so far"),
                  ScoreFactor(part: .moving, title: "Gym", effect: .pending, points: 0, detail: "Still time · open until 8 PM")]
        default:
            f += [ScoreFactor(part: .wake, title: "Woke up on time", effect: .up, points: 20, detail: "Up at 6:50 · goal 7:00"),
                  ScoreFactor(part: .work, title: "Work", effect: .up, points: 15, detail: "9:00 to 5:10"),
                  ScoreFactor(part: .plans, title: "Plans", effect: .up, points: 16, detail: "3 of 4 done"),
                  ScoreFactor(part: .moving, title: "Gym", effect: .pending, points: 0, detail: "Missed · closed at 8 PM"),
                  ScoreFactor(part: .gotOut, title: "1 place", effect: .up, points: 4, detail: "Blue Door Coffee")]
        }
        let score = f.reduce(0) { $0 + $1.points }
        let pace = ScoreEngine.pace(factors: f, schedule: paceSchedule)
        let tip: String
        switch scenario {
        case "notup": tip = "Up now still gets you most of the wake-up points."
        case "gym": tip = "Gym before 8 PM gets you to \(min(100, score + 20))."
        case "nogym": tip = "A journal tonight gets you to \(min(100, score + 5))."
        default: tip = "Tomorrow: gym before 8 PM keeps you on track."
        }
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
        add(context, "Gym", .gym, gym, at(today, 7, 2), at(today, 7, 54))
        add(context, "Blue Door Coffee", .coffee, cafe, at(today, 8, 10), at(today, 8, 35))
        add(context, "Office", .work, work, at(today, 9, 0), at(today, 12, 25))
        add(context, "Lucia Trattoria", .food, lunch, at(today, 12, 35), nil)

        context.insert(JournalEntry(date: at(today, 8, 12), kind: .photo, text: "Coffee before work. Feeling focused today.",
                                    thumbnail: photo("demo-coffee") ?? swatch(.brown), latitude: cafe.0, longitude: cafe.1, isTranscribed: true))
        context.insert(JournalEntry(date: at(today, 8, 13), kind: .photo, thumbnail: photo("demo-park"), latitude: cafe.0, longitude: cafe.1))
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
            context.insert(LocationSample(timestamp: at(fourAgo, 19, 40), latitude: trattoria.0, longitude: trattoria.1,
                                          horizontalAccuracy: 30, source: "visit"))
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
        context.insert(JournalEntry(date: at(today, 11, 40), kind: .voice,
                                    text: "Finished the big project draft early. Feeling good about today.",
                                    audioDuration: 42, latitude: work.0, longitude: work.1, isTranscribed: true))
        try? context.save()
        RoutineLearner.fillToday(context: context)
        // Today's schedule exactly as in the design.
        for item in ((try? context.fetch(FetchDescriptor<PlanItem>())) ?? []) where calendar.isDateInToday(item.start) { context.delete(item) }
        let weekdays = Date.now.formatted(.dateTime.weekday(.wide)) + "s"
        context.insert(PlanItem(title: "Gym", start: at(today, 7, 0), end: at(today, 7, 52), isAuto: true, reason: "Learned from your routine", isDone: true, category: .gym))
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
                ScoreFactor(title: "Journal", effect: .up, points: 10, detail: "1 note"),
            ])
        }
        if score >= 45 {
            return ("A normal day. No gym, but you got your usual things done.", [
                ScoreFactor(title: "Woke up on time", effect: .up, points: 12, detail: "Up at 7:10 · goal 7:00"),
                ScoreFactor(title: "Gym", effect: .pending, points: 0, detail: "Skipped"),
                ScoreFactor(title: "Plans", effect: .up, points: 18, detail: "Most of what you usually do"),
                ScoreFactor(title: "Moving", effect: .up, points: 10, detail: "5,400 steps · 3.8 km"),
                ScoreFactor(title: "Late night", effect: .up, points: -4, detail: "Phone until 12:30 AM"),
                ScoreFactor(title: "Journal", effect: .up, points: 10, detail: "1 note"),
            ])
        }
        return ("A slow one. That's okay, rest counts too.", [
            ScoreFactor(title: "Woke up late", effect: .pending, points: 4, detail: "Up at 9:40 · goal 7:00"),
            ScoreFactor(title: "Gym", effect: .pending, points: 0, detail: "Skipped"),
            ScoreFactor(title: "Plans", effect: .neutral, points: 8, detail: "1 of 4 done"),
            ScoreFactor(title: "Moving", effect: .neutral, points: 4, detail: "1,900 steps · 1.3 km"),
            ScoreFactor(title: "Late night", effect: .up, points: -8, detail: "Phone until 2:15 AM"),
            ScoreFactor(title: "Journal", effect: .pending, points: 0, detail: "No note"),
        ])
    }

    private static func add(_ c: ModelContext, _ name: String, _ cat: PlaceCategory, _ p: (Double, Double), _ a: Date, _ d: Date?) {
        c.insert(Visit(arrival: a, departure: d, latitude: p.0, longitude: p.1, placeName: name, category: cat))
        c.insert(LocationSample(timestamp: a, latitude: p.0, longitude: p.1, horizontalAccuracy: 50, source: "visit"))
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
