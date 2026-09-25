import Foundation
import UIKit
import SwiftUI
import SwiftData
import WidgetKit
import UserNotifications
import BackgroundTasks

/// Central "update everything" step: learn routine, tick off plan items, score the day,
/// update widgets and send the "80 reached" notification. Runs on launch, on foreground and in background refresh.
@MainActor
enum DayRefresher {
    static func refresh(context: ModelContext) async {
        await DayBoundary.shared.refresh(context: context)
        let today = DayBoundary.shared.today
        if !DemoData.isDemo {
            await HealthService.shared.importWorkouts(context: context, since: DayBoundary.shared.window(for: today).start)
            await CheckInService.evaluate(context: context)
            let w = DayBoundary.shared.window(for: today)
            DayCache.setSteps(await StepGoal.steps(from: w.start, to: min(w.end, .now)), for: today)
            let r = await RemindersService.shared.counts(for: today)
            DayCache.setReminders(done: r.done, total: r.total, for: today)
            await StepGoal.refresh()
            GymHours.learn(context: context)
            await GymHours.refresh(context: context)
        }
        await PhotoService.shared.importPhotos(on: today, context: context)
        RoutineLearner.fillToday(context: context)
        RoutineLearner.autoComplete(context: context)
        DayData.finalizePastDays(context: context)

        let result = ScoreEngine.score(DayData.input(for: today, context: context))
        let streak = DayData.streak(context: context)
        let plan = DayData.input(for: today, context: context).plan
        let next = plan.filter { !$0.isDone && $0.end > .now }.sorted { $0.start < $1.start }.first
        let recent = ((try? context.fetch(FetchDescriptor<DayScore>(sortBy: [SortDescriptor(\.day, order: .reverse)]))) ?? [])
            .prefix(6).reversed().map(\.score) + [result.score]

        // A migration reads the opt-in preference once; routine refresh never turns sync on.
        SharedBackgroundStore.defaults.set(UserDefaults.standard.bool(forKey: SharedBackgroundStore.syncKey), forKey: SharedBackgroundStore.syncKey)
        if SharedBackgroundStore.syncEnabled {
            SharedBackgroundStore.defaults.set(UserDefaults.standard.string(forKey: SharedBackgroundStore.presetKey) ?? "system", forKey: SharedBackgroundStore.presetKey)
            SharedBackgroundStore.defaults.set(UserDefaults.standard.string(forKey: SharedBackgroundStore.styleKey) ?? "blur", forKey: SharedBackgroundStore.styleKey)
        }
        SharedStore.save(WidgetSnapshot(date: .now, score: result.score, label: result.label,
                                        summary: result.tip ?? result.summary, nextTitle: next?.title,
                                        nextStart: next?.start, streakDays: streak, recentScores: Array(recent),
                                        friendTags: FriendStore.friends.prefix(3).map { f in
                                            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                            UIColor(f.color).getRed(&r, green: &g, blue: &b, alpha: &a)
                                            return .init(initial: String(f.name.prefix(1)), red: r, green: g, blue: b,
                                                         name: f.name, streak: f.current)
                                        }))
        WidgetCenter.shared.reloadAllTimelines()
        await Notifications.scoreReached(result.score, day: today)
    }
}

enum Notifications {
    /// Per-type switches from Profile > Notifications (default on).
    static func allowed(_ key: String) -> Bool {
        let d = UserDefaults.standard
        return (d.object(forKey: "notify.all") as? Bool ?? true) && (d.object(forKey: key) as? Bool ?? true)
    }

    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// The reminder is opt-in. No hour is assumed on the user's behalf.
    static func cancelJournalReminder() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["journal-daily"])
    }

    static func scheduleJournalReminder() async {
        cancelJournalReminder()
        guard !DemoData.isDemo, UserDefaults.standard.bool(forKey: "notify.journal.daily"),
              let hour = UserDefaults.standard.object(forKey: "notify.journal.hour") as? Int,
              (0...23).contains(hour),
              let minute = UserDefaults.standard.object(forKey: "notify.journal.minute") as? Int,
              (0...59).contains(minute) else { return }
        await requestPermission()
        let content = UNMutableNotificationContent()
        content.title = "A moment for your journal"
        content.body = "How did your day go? Add a note, photo or voice memo."
        content.sound = .default
        var components = DateComponents()
        components.hour = hour
        components.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "journal-daily", content: content, trigger: trigger))
    }

    /// Only two notifications exist: someone asks to follow you, and today hits 80.
    /// Also clears the old morning recap / 9 PM check-in from earlier installs.
    static func scoreReached(_ score: Int, day today: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning-recap", "evening-checkin"])
        guard score >= 80, !DemoData.isDemo, Self.allowed("notify.score80") else { return }
        let day = today.formatted(.iso8601.year().month().day())
        let key = "notified80-\(day)"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        let content = UNMutableNotificationContent()
        content.title = "You hit 80 today"
        content.body = "Today counts toward your streak."
        content.sound = .default
        try? await center.add(UNNotificationRequest(identifier: key, content: content, trigger: nil))
    }

    /// Someone asked to follow your streak. (Friends are demo data for now, so nothing calls this
    /// until real sharing is connected.)
    static func followRequest(from name: String) async {
        guard allowed("notify.follows") else { return }
        let content = UNMutableNotificationContent()
        content.title = "\(name) wants to follow you"
        content.body = "They'd see your streak only."
        content.sound = .default
        try? await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: "follow-\(name)-\(Date.now.timeIntervalSince1970)", content: content, trigger: nil))
    }
}

enum BackgroundRefresh {
    static let identifier = "app.dayline.refresh"

    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }
}
