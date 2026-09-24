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

        SharedStore.save(WidgetSnapshot(date: .now, score: result.score, label: result.label,
                                        summary: result.tip ?? result.summary, nextTitle: next?.title,
                                        nextStart: next?.start, streakDays: streak, recentScores: Array(recent),
                                        friendTags: FriendStore.friends.prefix(2).map { f in
                                            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                                            UIColor(f.color).getRed(&r, green: &g, blue: &b, alpha: &a)
                                            return .init(initial: String(f.name.prefix(1)), red: r, green: g, blue: b)
                                        }))
        WidgetCenter.shared.reloadAllTimelines()
        await Notifications.scoreReached(result.score, day: today)
    }
}

enum Notifications {
    static func requestPermission() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// Only two notifications exist: someone asks to follow you, and today hits 80.
    /// Also clears the old morning recap / 9 PM check-in from earlier installs.
    static func scoreReached(_ score: Int, day today: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["morning-recap", "evening-checkin"])
        guard score >= 80, !DemoData.isDemo else { return }
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
