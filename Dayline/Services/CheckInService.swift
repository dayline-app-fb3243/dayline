import Foundation
import UserNotifications
import CoreMotion
import SwiftData
import UIKit

/// Quick yes/no questions when Dayline isn't sure ("Going to sleep now?"). Answered right from the
/// notification with Apple's actions, without opening the app. Off by default (Profile > Check-in Questions).
@MainActor
enum CheckInService {
    static let enabledKey = "checkIns.enabled"
    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }

    enum Kind: String, CaseIterable {
        case sleep, wake, gym, grocery, run
        var question: String {
            switch self {
            case .sleep: "Going to sleep now?"
            case .wake: "Already up?"
            case .gym: "At the gym now?"
            case .grocery: "At the grocery store?"
            case .run: "Out for a run?"
            }
        }
        var category: String { "checkin.\(rawValue)" }
        /// Don't ask the same thing again within this time.
        var cooldown: TimeInterval { self == .run ? 3 * 3600 : (self == .gym || self == .grocery ? 4 * 3600 : 12 * 3600) }
    }

    /// Registers the Yes / No actions. Call at launch.
    static func registerCategories() {
        let yes = UNNotificationAction(identifier: "yes", title: "Yes", options: [], icon: UNNotificationActionIcon(systemImageName: "checkmark"))
        let no = UNNotificationAction(identifier: "no", title: "No", options: [], icon: UNNotificationActionIcon(systemImageName: "xmark"))
        let cats = Kind.allCases.map { UNNotificationCategory(identifier: $0.category, actions: [yes, no], intentIdentifiers: [], options: []) }
        UNUserNotificationCenter.current().setNotificationCategories(Set(cats))
        UNUserNotificationCenter.current().delegate = CheckInDelegate.shared
    }

    /// Sends a question now (once per cooldown).
    static func ask(_ kind: Kind, detail: String, force: Bool = false, now: Date = .now) async {
        guard enabled || force else { return }
        let key = "checkIns.last.\(kind.rawValue)"
        let last = UserDefaults.standard.double(forKey: key)
        guard force || now.timeIntervalSince1970 - last > kind.cooldown else { return }
        UserDefaults.standard.set(now.timeIntervalSince1970, forKey: key)
        let c = UNMutableNotificationContent()
        c.title = kind.question
        c.body = detail
        c.categoryIdentifier = kind.category
        c.userInfo = ["asked": now.timeIntervalSince1970]
        c.sound = .default
        c.interruptionLevel = .active
        try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "\(kind.category)-\(Int(now.timeIntervalSince1970))", content: c, trigger: nil))
    }

    /// Looks at the latest signals and asks at most one question. Runs on every app wake.
    static func evaluate(context: ModelContext, now: Date = .now, calendar: Calendar = .current) async {
        guard enabled, !DemoData.isDemo else { return }
        let hour = calendar.component(.hour, from: now)
        let visits = (try? context.fetch(FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrival, order: .reverse)]))) ?? []
        let current = visits.first { $0.departure == nil || $0.departure! > now }
        let charging = [.charging, .full].contains(UIDevice.current.batteryState)

        // Gym / grocery: just arrived somewhere that looks like it.
        if let v = current, now.timeIntervalSince(v.arrival) < 20 * 60 {
            if v.category == .gym { await ask(.gym, detail: "You\u{2019}re at \(v.placeName). Yes ticks off Gym on today\u{2019}s plan."); return }
            if v.category == .shopping, v.placeName.range(of: "market|grocery|foods|super", options: [.regularExpression, .caseInsensitive]) != nil {
                await ask(.grocery, detail: "You\u{2019}re at \(v.placeName)."); return
            }
        }
        let recent = await recentActivity(minutes: 20, now: now)
        // Run: motion shows running in the last 20 minutes.
        if recent.contains(where: { $0.running }) { await ask(.run, detail: "Yes adds it to your timeline."); return }
        // Sleep: late, at home, charging, and still.
        let still = !recent.isEmpty && recent.allSatisfy { $0.stationary || $0.unknown }
        if (hour >= 21 || hour < 3), current?.category == .home, charging, still {
            await ask(.sleep, detail: "Your phone is at home and charging. Yes ends today here."); return
        }
        // Wake: morning, first movement after the night's still stretch.
        if (4..<11).contains(hour), let wake = DayBoundary.shared.wakeUp(on: calendar.startOfDay(for: now)), now.timeIntervalSince(wake) < 45 * 60 {
            await ask(.wake, detail: "Yes sets your wake-up time to \(wake.formatted(date: .omitted, time: .shortened)).")
        }
    }

    private static func recentActivity(minutes: Double, now: Date) async -> [CMMotionActivity] {
        guard DayBoundary.motionAvailable, DayBoundary.motionAllowed else { return [] }
        let m = CMMotionActivityManager()
        return await withCheckedContinuation { c in
            m.queryActivityStarting(from: now.addingTimeInterval(-minutes * 60), to: now, to: .main) { a, _ in c.resume(returning: a ?? []) }
        }
    }

    /// What a Yes / No answer does.
    static func handle(kind: Kind, yes: Bool, asked: Date) async {
        guard yes else { return }
        let context = ModelStore.container.mainContext
        switch kind {
        case .sleep:
            DayBoundary.shared.setManual(sleep: asked)
            let c = UNMutableNotificationContent()
            c.body = "Got it. Good night. Today ends at \(asked.formatted(date: .omitted, time: .shortened))."
            try? await UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "checkin.sleep.done", content: c, trigger: nil))
        case .wake:
            DayBoundary.shared.setManual(wake: asked)
        case .gym:
            let day = DayBoundary.shared.window(for: DayBoundary.shared.today)
            let s = day.start, e = day.end
            let items = (try? context.fetch(FetchDescriptor<PlanItem>(predicate: #Predicate { $0.start >= s && $0.start < e }))) ?? []
            items.filter { $0.category == .gym }.forEach { $0.isDone = true }
        case .grocery:
            break   // the visit is already on the timeline; Yes just confirms the place
        case .run:
            let entry = JournalEntry(date: asked, kind: .text, text: "Went for a run", latitude: nil, longitude: nil)
            context.insert(entry)
        }
        try? context.save()
        await DayRefresher.refresh(context: context)
    }
}

/// Receives the answer even when the app isn't open.
final class CheckInDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = CheckInDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        guard content.categoryIdentifier.hasPrefix("checkin."),
              let kind = CheckInService.Kind(rawValue: String(content.categoryIdentifier.dropFirst("checkin.".count))) else { return }
        let asked = Date(timeIntervalSince1970: content.userInfo["asked"] as? Double ?? Date.now.timeIntervalSince1970)
        let yes = response.actionIdentifier == "yes"
        guard yes || response.actionIdentifier == "no" else { return }
        await CheckInService.handle(kind: kind, yes: yes, asked: asked)
    }

    /// Show check-ins as banners even while Dayline is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
