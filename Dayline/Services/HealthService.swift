import Foundation
import HealthKit
import SwiftData

/// Reads workouts from Apple Health (read only; Dayline never writes to Health).
@MainActor
final class HealthService {
    static let shared = HealthService()
    private let store = HKHealthStore()

    static var available: Bool { HKHealthStore.isHealthDataAvailable() }
    private var readTypes: Set<HKObjectType> {
        var s: Set<HKObjectType> = [HKObjectType.workoutType()]
        if let d = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { s.insert(d) }
        return s
    }

    /// Shows Apple's Health Access sheet.
    func requestAccess() async {
        guard Self.available else { return }
        try? await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Workouts that ended since `date` (runs, walks, gym).
    func workouts(since date: Date) async -> [HKWorkout] {
        guard Self.available else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: date, end: nil)
        let sort = [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
        return await withCheckedContinuation { c in
            let q = HKSampleQuery(sampleType: .workoutType(), predicate: predicate, limit: 50, sortDescriptors: sort) { _, samples, _ in
                c.resume(returning: (samples as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    /// Adds new Health workouts to the journal once each, so they show on the timeline.
    func importWorkouts(context: ModelContext, since date: Date) async {
        let known = Set(UserDefaults.standard.stringArray(forKey: "health.imported") ?? [])
        var seen = known
        for w in await workouts(since: date) where !known.contains(w.uuid.uuidString) {
            let mins = Int(w.duration / 60)
            let km = w.totalDistance?.doubleValue(for: .meterUnit(with: .kilo))
            let kind = Self.name(w.workoutActivityType)
            let text = km.map { String(format: "%@ · %.1f km · %d min", kind, $0, mins) } ?? "\(kind) · \(mins) min"
            let e = JournalEntry(date: w.startDate, kind: .text, text: text, latitude: nil, longitude: nil)
            e.placeName = "Apple Health"
            context.insert(e)
            seen.insert(w.uuid.uuidString)
        }
        UserDefaults.standard.set(Array(seen.suffix(300)), forKey: "health.imported")
        try? context.save()
    }

    static func name(_ t: HKWorkoutActivityType) -> String {
        switch t {
        case .running: "Run"
        case .walking: "Walk"
        case .cycling: "Ride"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength workout"
        case .highIntensityIntervalTraining: "HIIT"
        case .yoga: "Yoga"
        case .swimming: "Swim"
        default: "Workout"
        }
    }
}
