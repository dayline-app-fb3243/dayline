import Foundation
import CoreLocation
import SwiftData

/// Location tracking with a user-picked check rate (Profile > Check Location: 1, 5 or 10 minutes).
///
/// Always on (near-zero battery):
///  - Visit monitoring (arrive / leave a place)
///  - Significant location changes (~500 m moves)
/// On top of that, background location updates at low accuracy, keeping at most one
/// point per chosen interval. Faster checks give exact routes but use more battery.
@MainActor
final class LocationService: NSObject, ObservableObject {
    static let shared = LocationService()

    @Published private(set) var authorization: CLAuthorizationStatus = .notDetermined
    @Published private(set) var lastSample: Date?
    /// Last known location (cached by iOS, no new GPS fix).
    var lastLocation: CLLocation? { manager.location }

    /// Minutes between saved points. 1, 5 or 10. Default 5.
    static let intervalKey = "location.checkMinutes"
    static let choices = [1, 5, 10]
    var checkMinutes: Int {
        let v = UserDefaults.standard.integer(forKey: Self.intervalKey)
        return Self.choices.contains(v) ? v : 5
    }
    var minimumInterval: TimeInterval { TimeInterval(checkMinutes * 60) }
    private let manager = CLLocationManager()

    private override init() {
        super.init()
        manager.delegate = self
        manager.pausesLocationUpdatesAutomatically = true
        manager.activityType = .other
        authorization = manager.authorizationStatus
    }

    func requestPermission() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse: manager.requestAlwaysAuthorization()
        default: break
        }
    }

    /// Starts the low-power background signals. Safe to call on every launch.
    func start() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        manager.startMonitoringVisits()
        if CLLocationManager.significantLocationChangeMonitoringAvailable() {
            manager.startMonitoringSignificantLocationChanges()
        }
        applyInterval()
    }

    /// Called on start and whenever the user picks a new rate.
    func setCheckMinutes(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: Self.intervalKey)
        applyInterval()
    }

    private func applyInterval() {
        let status = manager.authorizationStatus
        guard status == .authorizedAlways || status == .authorizedWhenInUse else { return }
        switch checkMinutes {
        case 1:  manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters; manager.distanceFilter = 25
        case 5:  manager.desiredAccuracy = kCLLocationAccuracyHundredMeters; manager.distanceFilter = 100
        default: manager.desiredAccuracy = kCLLocationAccuracyKilometer; manager.distanceFilter = 250
        }
        manager.allowsBackgroundLocationUpdates = status == .authorizedAlways
        manager.showsBackgroundLocationIndicator = false
        manager.startUpdatingLocation()
    }

    // MARK: - Storage

    private func record(_ location: CLLocation, source: String) {
        if source != "visit", let last = lastSample, location.timestamp.timeIntervalSince(last) < minimumInterval { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 1500 else { return }
        let context = ModelStore.container.mainContext
        context.insert(LocationSample(timestamp: location.timestamp,
                                      latitude: location.coordinate.latitude,
                                      longitude: location.coordinate.longitude,
                                      horizontalAccuracy: location.horizontalAccuracy,
                                      source: source))
        try? context.save()
        lastSample = location.timestamp
        if source != "visit" { detectStay(context: context, at: location) }
        DayBoundary.shared.noteBattery()   // charging at night helps tell when you fell asleep
    }

    /// Our own stay check on top of Apple's visits: 15 minutes of checks (3 in a row at the default
    /// 5-minute rate) within 100 m of each other is a stay. Walking past a place never lasts that long.
    /// Moving 150 m away from an open stay ends it at the last check that was still there.
    private func detectStay(context: ModelContext, at location: CLLocation) {
        let since = location.timestamp.addingTimeInterval(-3 * 3600)
        let recent = ((try? context.fetch(FetchDescriptor<LocationSample>(predicate: #Predicate { $0.timestamp >= since },
                                                                           sortBy: [SortDescriptor(\.timestamp)]))) ?? [])
        func loc(_ s: LocationSample) -> CLLocation { CLLocation(latitude: s.latitude, longitude: s.longitude) }
        let openVisits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.departure == nil }))) ?? []
        for v in openVisits where CLLocation(latitude: v.latitude, longitude: v.longitude).distance(from: location) > 150 {
            let lastThere = recent.last { loc($0).distance(from: CLLocation(latitude: v.latitude, longitude: v.longitude)) <= 100 }
            v.departure = lastThere?.timestamp ?? location.timestamp
        }
        // The run of checks, newest first, that all sit within 100 m of this one.
        var run: [LocationSample] = []
        for s in recent.reversed() { if loc(s).distance(from: location) <= 100 { run.append(s) } else { break } }
        guard let first = run.last, location.timestamp.timeIntervalSince(first.timestamp) >= 15 * 60,
              !openVisits.contains(where: { $0.departure == nil && CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: location) <= 150 })
        else { try? context.save(); return }
        let lat = run.map(\.latitude).reduce(0, +) / Double(run.count), lon = run.map(\.longitude).reduce(0, +) / Double(run.count)
        let v = Visit(arrival: first.timestamp, departure: nil, latitude: lat, longitude: lon, placeName: "Place", category: .other)
        context.insert(v)
        try? context.save()
        Task { await PlaceNamer.shared.name(v) }
    }

    private func record(visit: CLVisit) {
        let context = ModelStore.container.mainContext
        let arrival = visit.arrivalDate == .distantPast ? .now : visit.arrivalDate
        let departure: Date? = visit.departureDate == .distantFuture ? nil : visit.departureDate
        let lat = visit.coordinate.latitude, lon = visit.coordinate.longitude
        let key = Visit.key(latitude: lat, longitude: lon)

        // Close an open visit at the same place instead of duplicating it.
        // (Also one our own stay check already opened within 150 m, so a stay is never counted twice.)
        let open = FetchDescriptor<Visit>(predicate: #Predicate { $0.departure == nil })
        let here = CLLocation(latitude: lat, longitude: lon)
        if let existing = ((try? context.fetch(open)) ?? []).first(where: {
            $0.placeKey == key || CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here) <= 150 }) {
            existing.departure = departure
        } else {
            let newVisit = Visit(arrival: arrival, departure: departure, latitude: lat, longitude: lon,
                                 placeName: "Place", category: .other)
            context.insert(newVisit)
            Task { await PlaceNamer.shared.name(newVisit) }
        }
        try? context.save()
        record(CLLocation(coordinate: visit.coordinate, altitude: 0, horizontalAccuracy: visit.horizontalAccuracy,
                          verticalAccuracy: -1, timestamp: arrival), source: "visit")
    }
}

extension LocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse { manager.requestAlwaysAuthorization() }
            self.start()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            for location in locations { self.record(location, source: "change") }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            self.record(visit: visit)
            // A new visit can push the day to 80, so rescore (and maybe notify).
            await DayRefresher.refresh(context: ModelStore.container.mainContext)
        }
    }

    nonisolated func locationManagerDidPauseLocationUpdates(_ manager: CLLocationManager) {}
    nonisolated func locationManagerDidResumeLocationUpdates(_ manager: CLLocationManager) {}

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
