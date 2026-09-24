import Foundation
import SwiftData

/// Learns the user's routine from past visits and fills in today's schedule automatically.
/// Examples: "Work 9:00-5:00 (learned from your usual 9-5)", "Lunch out (you usually eat out on Wednesdays)".
@MainActor
enum RoutineLearner {
    struct Suggestion: Equatable {
        var title: String
        var start: DateComponents
        var end: DateComponents
        var reason: String
        var category: PlaceCategory
    }

    static func suggestions(for day: Date, visits: [Visit], calendar: Calendar = .current) -> [Suggestion] {
        let lookback = calendar.date(byAdding: .day, value: -28, to: calendar.startOfDay(for: day))!
        let history = visits.filter { $0.arrival >= lookback && $0.arrival < calendar.startOfDay(for: day) }
        guard !history.isEmpty else { return [] }

        var result: [Suggestion] = []
        let weekday = calendar.component(.weekday, from: day)
        let isWeekday = !calendar.isDateInWeekend(day)
        let byPlace = Dictionary(grouping: history, by: \.placeKey)

        // Home = place with the most overnight presence.
        let homeKey = byPlace.max { overnightCount($0.value, calendar) < overnightCount($1.value, calendar) }?.key

        // Work = non-home place with the most weekday daytime hours on 3+ different days.
        if isWeekday {
            let candidates = byPlace.filter { $0.key != homeKey }.compactMap { key, stays -> (String, [Visit], Double)? in
                let weekdayStays = stays.filter { !calendar.isDateInWeekend($0.arrival) && $0.duration > 2 * 3600 }
                let days = Set(weekdayStays.map { calendar.startOfDay(for: $0.arrival) })
                guard days.count >= 3 else { return nil }
                return (key, weekdayStays, weekdayStays.reduce(0) { $0 + $1.duration })
            }
            if let (_, stays, _) = candidates.max(by: { $0.2 < $1.2 }) {
                let arrive = median(stays.map { minutesOfDay($0.arrival, calendar) })
                let leave = median(stays.compactMap { $0.departure }.map { minutesOfDay($0, calendar) })
                result.append(Suggestion(title: "Work", start: comps(arrive), end: comps(leave),
                                         reason: "Learned from your usual \(short(arrive))–\(short(leave))", category: .work))
            }
        }

        // Habits on this weekday: same place (food, coffee, gym, outdoors) on 2+ of the last 4 same weekdays.
        let habitual = history.filter {
            calendar.component(.weekday, from: $0.arrival) == weekday &&
            [.food, .coffee, .gym, .outdoors].contains($0.category) && $0.placeKey != homeKey
        }
        for (_, stays) in Dictionary(grouping: habitual, by: \.categoryRaw) {
            let days = Set(stays.map { calendar.startOfDay(for: $0.arrival) })
            guard days.count >= 2, let category = stays.first?.category else { continue }
            let start = median(stays.map { minutesOfDay($0.arrival, calendar) })
            let length = max(30, median(stays.map { Int($0.duration / 60) }))
            let dayName = calendar.weekdaySymbols[weekday - 1]
            let (title, reason): (String, String) = switch category {
            case .food: ("Lunch out", "You usually eat out on \(dayName)s")
            case .coffee: ("Coffee", "Your usual \(dayName) coffee")
            case .gym: ("Gym", "You usually train on \(dayName)s")
            default: ("Time outside", "You're often outdoors on \(dayName)s")
            }
            result.append(Suggestion(title: title, start: comps(start), end: comps(start + length), reason: reason, category: category))
        }
        return result.sorted { ($0.start.hour ?? 0, $0.start.minute ?? 0) < ($1.start.hour ?? 0, $1.start.minute ?? 0) }
    }

    /// Adds learned items to today's plan once (never duplicates, never touches the user's own items).
    static func fillToday(context: ModelContext, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: .now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let existing = (try? context.fetch(FetchDescriptor<PlanItem>(predicate: #Predicate { $0.start >= today && $0.start < tomorrow }))) ?? []
        let visits = (try? context.fetch(FetchDescriptor<Visit>())) ?? []
        for s in suggestions(for: today, visits: visits, calendar: calendar) where !existing.contains(where: { $0.title == s.title }) {
            guard let start = calendar.date(bySettingHour: s.start.hour ?? 9, minute: s.start.minute ?? 0, second: 0, of: today),
                  let end = calendar.date(bySettingHour: s.end.hour ?? 10, minute: s.end.minute ?? 0, second: 0, of: today) else { continue }
            context.insert(PlanItem(title: s.title, start: start, end: end, isAuto: true, reason: s.reason, category: s.category))
        }
        try? context.save()
    }

    /// Marks plan items done when the user was at a matching place during the item.
    static func autoComplete(context: ModelContext, day: Date = .now, calendar: Calendar = .current) {
        if DemoData.isDemo { return } // demo keeps the schedule exactly as designed
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let items = (try? context.fetch(FetchDescriptor<PlanItem>(predicate: #Predicate { $0.start >= start && $0.start < end }))) ?? []
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival >= start && $0.arrival < end }))) ?? []
        for item in items where !item.isDone && item.category != .other {
            if visits.contains(where: { $0.category == item.category && $0.arrival < item.end && ($0.departure ?? .now) > item.start && $0.duration > 15 * 60 }) {
                item.isDone = true
            }
        }
        try? context.save()
    }

    // MARK: helpers
    private static func overnightCount(_ stays: [Visit], _ cal: Calendar) -> Int {
        stays.filter { v in
            let h = cal.component(.hour, from: v.arrival)
            return h >= 19 || h < 5 || v.duration > 8 * 3600
        }.count
    }
    private static func minutesOfDay(_ d: Date, _ cal: Calendar) -> Int { cal.component(.hour, from: d) * 60 + cal.component(.minute, from: d) }
    private static func median(_ xs: [Int]) -> Int { let s = xs.sorted(); return s.isEmpty ? 0 : s[s.count / 2] }
    private static func comps(_ minutes: Int) -> DateComponents {
        let rounded = (minutes / 15) * 15
        return DateComponents(hour: min(23, rounded / 60), minute: rounded % 60)
    }
    private static func short(_ minutes: Int) -> String {
        let h = ((minutes / 60) + 11) % 12 + 1
        let m = minutes % 60
        return m == 0 ? "\(h)" : String(format: "%d:%02d", h, m)
    }
}
