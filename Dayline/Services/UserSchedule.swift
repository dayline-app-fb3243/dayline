import Foundation
import CoreLocation
import CoreMotion
import HealthKit

/// One set of work hours, e.g. Mon-Thu 9-5 or Friday 9-3. Minutes after midnight.
struct WorkBlock: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var days: Set<Int>          // Calendar weekday: 1 = Sunday ... 7 = Saturday
    var start: Int = 9 * 60
    var end: Int = 17 * 60

    var daysText: String {
        let order = [2, 3, 4, 5, 6, 7, 1]
        let sorted = order.filter(days.contains)
        guard !sorted.isEmpty else { return "No days" }
        if sorted.count == 7 { return "Every Day" }
        if Set(sorted) == [2, 3, 4, 5, 6] { return "Weekdays" }
        if Set(sorted) == [1, 7] { return "Weekends" }
        let f = DateFormatter()
        if sorted.count == 1 { return f.weekdaySymbols[sorted[0] - 1] }
        // Consecutive run: "Mon – Thu"
        let idx = sorted.compactMap { order.firstIndex(of: $0) }
        if let a = idx.first, let b = idx.last, b - a == idx.count - 1 {
            return "\(f.shortWeekdaySymbols[sorted.first! - 1]) \u{2013} \(f.shortWeekdaySymbols[sorted.last! - 1])"
        }
        return sorted.map { f.shortWeekdaySymbols[$0 - 1] }.joined(separator: ", ")
    }
    var hoursText: String { "\(UserSchedule.timeText(start)) \u{2013} \(UserSchedule.timeText(end))" }
}

/// A place the user set by hand (Home, Work or their own).
struct SavedPlace: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var kind: String            // "home", "work", "other"
    var name: String
    var address: String
    var latitude: Double
    var longitude: Double
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

/// The person's usual day. Scoring is built from it so everyone can reach 100 with their own routine.
struct UserSchedule: Codable, Equatable, Sendable {
    var wake: Int = 7 * 60
    var bed: Int = 23 * 60
    var works = true
    var workBlocks: [WorkBlock] = [WorkBlock(days: [2, 3, 4, 5], start: 9 * 60, end: 17 * 60),
                                   WorkBlock(days: [6], start: 9 * 60, end: 15 * 60)]
    var gym = false
    /// When your gym closes: the gym counts as missed after this. Optional so older saved settings still load.
    var gymBy: Int? = nil
    var gymDeadline: Int { gymBy ?? 20 * 60 }
    var walk = true
    var outside = false
    var getOut = true
    var journal = true
    var stepGoal: Int = 7500
    var places: [SavedPlace] = []

    static let key = "userSchedule.v1"

    static var current: UserSchedule {
        get {
            guard let d = UserDefaults.standard.data(forKey: key), let s = try? JSONDecoder().decode(UserSchedule.self, from: d) else { return UserSchedule() }
            return s
        }
        set {
            if let d = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(d, forKey: key) }
        }
    }

    static func timeText(_ minutes: Int) -> String {
        var c = DateComponents(); c.hour = minutes / 60; c.minute = minutes % 60
        let d = Calendar.current.date(from: c) ?? .now
        return d.formatted(date: .omitted, time: .shortened)
    }
    static func date(_ minutes: Int, on day: Date, calendar: Calendar = .current) -> Date {
        calendar.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: day) ?? day
    }
    static func minutes(of date: Date, calendar: Calendar = .current) -> Int {
        calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
    }

    /// Work hours for a given day, if it's a work day.
    func work(on day: Date, calendar: Calendar = .current) -> WorkBlock? {
        guard works else { return nil }
        let wd = calendar.component(.weekday, from: day)
        return workBlocks.first { $0.days.contains(wd) }
    }

    var rangeText: String { "\(Self.timeText(wake)) \u{2013} \(Self.timeText(bed))" }
    var home: SavedPlace? { places.first { $0.kind == "home" } }
    var workPlace: SavedPlace? { places.first { $0.kind == "work" } }
    /// Your gym: picked in Places, or learned after 10 days there (see GymHours.learn).
    var gymPlace: SavedPlace? { places.first { $0.kind == "gym" } }
}

/// Sets the personal step goal from the usual daily steps over the last weeks (Motion history).
enum StepGoal {
    static func refresh() async {
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized else { return }
        let pedometer = CMPedometer()
        let cal = Calendar.current
        var totals: [Int] = []
        let today = cal.startOfDay(for: .now)
        for offset in 1...21 {   // Motion keeps about a week on most phones; take what's there
            guard let start = cal.date(byAdding: .day, value: -offset, to: today),
                  let end = cal.date(byAdding: .day, value: 1, to: start) else { continue }
            let steps: Int? = await withCheckedContinuation { cont in
                pedometer.queryPedometerData(from: start, to: end) { data, _ in cont.resume(returning: data?.numberOfSteps.intValue) }
            }
            if let steps, steps > 0 { totals.append(steps) }
        }
        guard totals.count >= 3 else { return }
        let sorted = totals.sorted()
        let median = sorted[sorted.count / 2]
        let goal = max(3000, Int((Double(median) / 500).rounded()) * 500)
        var s = UserSchedule.current; s.stepGoal = goal; UserSchedule.current = s
    }

    static func steps(from start: Date, to end: Date) async -> Int {
        // HealthKit includes the paired Watch as well as the phone; the cumulative query avoids
        // counting duplicate records from several sources. Use phone Motion only if Health is unavailable.
        if HKHealthStore.isHealthDataAvailable(),
           let type = HKObjectType.quantityType(forIdentifier: .stepCount) {
            let store = HKHealthStore()
            let health: Int? = await withCheckedContinuation { cont in
                let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
                let q = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                    guard error == nil, let n = result?.sumQuantity()?.doubleValue(for: .count()) else {
                        cont.resume(returning: nil); return
                    }
                    cont.resume(returning: Int(n))
                }
                store.execute(q)
            }
            if let health { return health }
        }
        guard CMPedometer.isStepCountingAvailable(), CMPedometer.authorizationStatus() == .authorized else { return 0 }
        return await withCheckedContinuation { cont in
            CMPedometer().queryPedometerData(from: start, to: end) { data, _ in cont.resume(returning: data?.numberOfSteps.intValue ?? 0) }
        }
    }
}
