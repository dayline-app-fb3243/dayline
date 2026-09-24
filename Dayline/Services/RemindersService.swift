import Foundation
import EventKit

/// Reads (never changes) reminders due today so they count toward Plans & Reminders.
@MainActor
final class RemindersService {
    static let shared = RemindersService()
    private let store = EKEventStore()

    static var allowed: Bool { EKEventStore.authorizationStatus(for: .reminder) == .fullAccess }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToReminders()) ?? false
    }

    /// Reminders due on `day`: how many are done out of the total.
    func counts(for day: Date, calendar: Calendar = .current) async -> (done: Int, total: Int) {
        guard Self.allowed else { return (0, 0) }
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start)!
        let open = store.predicateForIncompleteReminders(withDueDateStarting: start, ending: end, calendars: nil)
        let done = store.predicateForCompletedReminders(withCompletionDateStarting: start, ending: end, calendars: nil)
        let o: Int = await withCheckedContinuation { c in store.fetchReminders(matching: open) { c.resume(returning: $0?.count ?? 0) } }
        let d: Int = await withCheckedContinuation { c in store.fetchReminders(matching: done) { c.resume(returning: $0?.count ?? 0) } }
        return (d, o + d)
    }
}
