import Foundation

/// Small, Codable summary the app writes to the shared App Group
/// so widgets, Siri and notifications can read it without opening the database.
struct WidgetSnapshot: Codable, Equatable, Sendable {
    var date: Date
    var score: Int
    /// No score has been observed yet, even if the scoring engine can produce a numeric zero.
    var hasDayData: Bool
    var label: String
    var summary: String
    var nextTitle: String?
    var nextStart: Date?
    var streakDays: Int
    var recentScores: [Int]
    /// Friends shown as small faces on the Streak widget (streaks only; nothing else is shared).
    var friendTags: [FriendTag]? = nil

    struct FriendTag: Codable, Equatable, Sendable {
        var initial: String
        var red: Double, green: Double, blue: Double
        var name: String? = nil
        var streak: Int? = nil
    }

    static let placeholder = WidgetSnapshot(
        date: .now, score: 0, hasDayData: false, label: "No day yet",
        summary: "Open Dayline to get started.",
        nextTitle: nil, nextStart: nil,
        streakDays: 0, recentScores: [], friendTags: []
    )

    /// Gallery-only sample. Never used as a new user's actual widget state.
    static let gallerySample = WidgetSnapshot(
        date: .now, score: 74, hasDayData: true, label: "On track",
        summary: "Up early and gym done. Keep it going.",
        nextTitle: "Lunch out", nextStart: Calendar.current.date(bySettingHour: 12, minute: 30, second: 0, of: .now),
        streakDays: 6, recentScores: [82, 64, 90, 71, 88, 93, 74],
        friendTags: [.init(initial: "S", red: 1, green: 0.23, blue: 0.19), .init(initial: "J", red: 0.2, green: 0.78, blue: 0.35)]
    )
}

enum SharedStore {
    static let appGroup = "group.app.dayline.shared"
    private static let key = "widgetSnapshot"

    /// No fallback to a process-local default: that would show stale data as if synced.
    static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func save(_ snapshot: WidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: key)
    }

    static func load() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
