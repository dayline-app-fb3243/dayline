import Foundation
import UIKit
import CoreLocation
import CoreMotion
import SwiftData

/// Your day runs from when you wake up to when you fall asleep.
///
/// Sleep is read from the phone only (no Apple Health):
/// - Motion history (Motion & Fitness): the long still stretch at night. iOS keeps about 7 days of it,
///   so this works even if Dayline wasn't running overnight.
/// - Location: the phone stayed at one place (usually home) through that stretch.
/// - Charging: noted whenever the app runs; a phone charging at night makes a shorter stretch count.
/// Activity after midnight but before sleep counts toward the day before. The first motion after the
/// still stretch is the wake-up time. When a night can't be read, the day switches at 4 AM.
@MainActor
final class DayBoundary {
    static let shared = DayBoundary()

    struct Night: Codable, Equatable { var sleep: Date; var wake: Date?; var atHome: Bool }
    struct Span { var start: Date; var end: Date }

    static let fallbackHour = 4           // switch time when sleep can't be read
    static let latestSwitchHour = 9       // never move the switch later than this
    static let minSleep: TimeInterval = 3 * 3600
    static let minSleepCharging: TimeInterval = 2 * 3600
    static let shortPickup: TimeInterval = 10 * 60    // a quick look at the phone doesn't end the night
    static let moveMeters: CLLocationDistance = 200

    private let nightsKey = "dayBoundaryNights"
    private let chargeKey = "dayBoundaryCharging"
    private let motion = CMMotionActivityManager()
    private var nights: [String: Night]
    private var charging: [Span]        // times the phone was seen charging
    private var chargeStart: Date?

    private init() {
        let d = UserDefaults.standard
        nights = d.data(forKey: nightsKey).flatMap { try? JSONDecoder().decode([String: Night].self, from: $0) } ?? [:]
        charging = (d.array(forKey: chargeKey) as? [[Double]] ?? []).compactMap {
            $0.count == 2 ? Span(start: Date(timeIntervalSince1970: $0[0]), end: Date(timeIntervalSince1970: $0[1])) : nil
        }
    }

    static var motionAvailable: Bool { CMMotionActivityManager.isActivityAvailable() }
    static var motionAllowed: Bool { CMMotionActivityManager.authorizationStatus() == .authorized }

    // MARK: recording

    func start() {
        UIDevice.current.isBatteryMonitoringEnabled = true
        NotificationCenter.default.addObserver(forName: UIDevice.batteryStateDidChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { DayBoundary.shared.noteBattery() }
        }
        noteBattery()
    }

    /// Asks for Motion & Fitness with Apple's own alert (the first history query triggers it).
    func requestMotion() {
        guard Self.motionAvailable, CMMotionActivityManager.authorizationStatus() == .notDetermined else { return }
        motion.queryActivityStarting(from: .now.addingTimeInterval(-60), to: .now, to: .main) { _, _ in }
    }

    /// Called whenever the app runs (foreground, background refresh, location wake).
    func noteBattery(now: Date = .now) {
        let state = UIDevice.current.batteryState
        if state == .charging || state == .full {
            if chargeStart == nil { chargeStart = now }
            extendCharging(to: now)
        } else {
            chargeStart = nil
        }
    }

    private func extendCharging(to now: Date) {
        guard let s = chargeStart else { return }
        if let i = charging.lastIndex(where: { $0.start == s }) { charging[i].end = now } else { charging.append(Span(start: s, end: now)) }
        charging.removeAll { $0.end < now.addingTimeInterval(-14 * 86400) }
        UserDefaults.standard.set(charging.map { [$0.start.timeIntervalSince1970, $0.end.timeIntervalSince1970] }, forKey: chargeKey)
    }

    /// Re-reads motion history for the last 7 nights and stores what it finds.
    func refresh(context: ModelContext, calendar: Calendar = .current, now: Date = .now) async {
        noteBattery(now: now)
        guard !DemoData.isDemo, Self.motionAvailable, Self.motionAllowed else { return }
        let today = calendar.startOfDay(for: now)
        let from = calendar.date(byAdding: .day, value: -7, to: today)!
        let activities = await withCheckedContinuation { (c: CheckedContinuation<[CMMotionActivity], Never>) in
            motion.queryActivityStarting(from: from, to: now, to: .main) { a, _ in c.resume(returning: a ?? []) }
        }
        let still = Self.stillSpans(activities, until: now)
        let samples = (try? context.fetch(FetchDescriptor<LocationSample>(predicate: #Predicate { $0.timestamp >= from }))) ?? []
        let visits = ((try? context.fetch(FetchDescriptor<Visit>())) ?? []).filter { ($0.departure ?? now) >= from }
        for offset in 1...7 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let n = Self.detectNight(after: day, still: still, charging: charging, samples: samples, visits: visits, calendar: calendar, now: now)
            nights[Self.key(day)] = n
        }
        if let data = try? JSONEncoder().encode(nights) { UserDefaults.standard.set(data, forKey: nightsKey) }
    }

    // MARK: detection (pure, so it can be tested with made-up data)

    /// Still stretches from motion history; short movements (picking the phone up) are ignored.
    static func stillSpans(_ activities: [CMMotionActivity], until end: Date) -> [Span] {
        let sorted = activities.sorted { $0.startDate < $1.startDate }
        var spans: [Span] = []
        for (i, a) in sorted.enumerated() {
            let next = i + 1 < sorted.count ? sorted[i + 1].startDate : end
            let isStill = a.stationary && !a.walking && !a.running && !a.automotive && !a.cycling
            guard isStill, next > a.startDate else { continue }
            if let last = spans.last, a.startDate.timeIntervalSince(last.end) < shortPickup {
                spans[spans.count - 1].end = next
            } else {
                spans.append(Span(start: a.startDate, end: next))
            }
        }
        return spans
    }

    static func detectNight(after day: Date, still: [Span], charging: [Span], samples: [LocationSample], visits: [Visit],
                            calendar: Calendar = .current, now: Date = .now) -> Night? {
        let d0 = calendar.startOfDay(for: day)
        guard let next = calendar.date(byAdding: .day, value: 1, to: d0),
              let from = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: d0),
              let to = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: next) else { return nil }
        var best: (s: Date, e: Date, len: TimeInterval, home: Bool)? = nil
        for sp in still {
            let s = max(sp.start, from), e = min(sp.end, to, now)
            guard e > s else { continue }
            let len = e.timeIntervalSince(s)
            let charged = charging.reduce(0.0) { $0 + max(0, min($1.end, e).timeIntervalSince(max($1.start, s))) }
            // Location: must not have moved during the stretch.
            let pts = samples.filter { $0.timestamp >= s && $0.timestamp <= e }
                .map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            if let first = pts.first, pts.contains(where: { $0.distance(from: first) > moveMeters }) { continue }
            let home = visits.contains { $0.category == .home && $0.arrival <= s.addingTimeInterval(1800) && ($0.departure ?? now) >= e.addingTimeInterval(-1800) }
            let needed = (charged >= len * 0.5 || home) ? minSleepCharging : minSleep
            guard len >= needed else { continue }
            if best == nil || len > best!.len { best = (s, e, len, home) }
        }
        guard let b = best else { return nil }
        let stillGoing = b.e >= min(to, now).addingTimeInterval(-60) && now < to
        return Night(sleep: b.s, wake: stillGoing ? nil : b.e, atHome: b.home)
    }

    // MARK: reading

    static func key(_ day: Date) -> String { day.formatted(.iso8601.year().month().day()) }

    func night(after day: Date, calendar: Calendar = .current) -> Night? { nights[Self.key(calendar.startOfDay(for: day))] }

    /// When the day that ends on the night after `day` switches over to the next day.
    func switchTime(afterDay day: Date, calendar: Calendar = .current) -> Date {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!
        let fallback = calendar.date(bySettingHour: Self.fallbackHour, minute: 0, second: 0, of: next)!
        guard !DemoData.isDemo, let n = night(after: day, calendar: calendar) else { return fallback }
        let latest = calendar.date(bySettingHour: Self.latestSwitchHour, minute: 0, second: 0, of: next)!
        return min(max(n.sleep, next), latest)   // asleep before midnight: midnight is the switch
    }

    /// The time range that belongs to `day`.
    func window(for day: Date, calendar: Calendar = .current) -> DateInterval {
        let d0 = calendar.startOfDay(for: day)
        let start = switchTime(afterDay: calendar.date(byAdding: .day, value: -1, to: d0)!, calendar: calendar)
        let end = switchTime(afterDay: d0, calendar: calendar)
        return DateInterval(start: start, end: max(end, start))
    }

    /// The calendar date a moment belongs to (1 AM before sleep belongs to yesterday).
    func day(of date: Date, calendar: Calendar = .current) -> Date {
        let d0 = calendar.startOfDay(for: date)
        let prev = calendar.date(byAdding: .day, value: -1, to: d0)!
        return date < switchTime(afterDay: prev, calendar: calendar) ? prev : d0
    }

    var today: Date { day(of: .now) }

    /// Wake-up time for `day`: the first motion after the previous night's still stretch.
    func wakeUp(on day: Date, calendar: Calendar = .current) -> Date? {
        night(after: calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day))!, calendar: calendar)?.wake
    }
}
