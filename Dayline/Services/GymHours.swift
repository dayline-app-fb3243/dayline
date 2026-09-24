import Foundation
import SwiftData

/// Real closing time of your gym, for the "Go By" deadline in the day score.
/// Apple's MapKit doesn't give apps opening hours, so this asks Google Places (Text Search, New) when an
/// API key is set in Info.plist ("PlacesAPIKey"). No key, or hours unknown: the Go By setting is used.
/// Flag "gym.hours": on by default. Off = always the Go By setting.
enum GymHours {
    static let flagKey = "gym.hours"
    private static let cacheKey = "gymHours.v1"

    struct Cached: Codable {
        var name: String
        /// Calendar weekday (1 = Sunday ... 7 = Saturday) -> closing time in minutes after midnight. Missing = closed.
        var closes: [Int: Int]
        var fetched: Date
        var sample = false
    }

    static var enabled: Bool { UserDefaults.standard.object(forKey: flagKey) as? Bool ?? true }
    static var apiKey: String? {
        let k = (Bundle.main.object(forInfoDictionaryKey: "PlacesAPIKey") as? String ?? "").trimmingCharacters(in: .whitespaces)
        return k.isEmpty || k.hasPrefix("$(") ? nil : k
    }

    static var cached: Cached? {
        if DemoData.isDemo {
            // Demo gym: sample hours, closing at 8 PM every day (matches the demo day stories), marked as a sample.
            return Cached(name: "Iron Works Gym", closes: Dictionary(uniqueKeysWithValues: (1...7).map { ($0, 20 * 60) }), fetched: .now, sample: true)
        }
        guard let d = UserDefaults.standard.data(forKey: cacheKey) else { return nil }
        return try? JSONDecoder().decode(Cached.self, from: d)
    }

    /// The gym's closing time on that day, when the preview is on and hours are known.
    static func closing(on day: Date, calendar: Calendar = .current) -> Int? {
        guard enabled, let c = cached else { return nil }
        return c.closes[calendar.component(.weekday, from: day)]
    }

    /// Looks up your usual gym (the gym you visit most) about once a week. Does nothing without a key.
    @MainActor static func refresh(context: ModelContext) async {
        guard enabled, !DemoData.isDemo, let key = apiKey else { return }
        learn(context: context)
        guard let top = UserSchedule.current.gymPlace else { return }
        // Fresh for a week, unless you picked a different gym.
        if let c = cached, c.name == top.name, Date.now.timeIntervalSince(c.fetched) < 7 * 86_400 { return }

        var req = URLRequest(url: URL(string: "https://places.googleapis.com/v1/places:searchText")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(key, forHTTPHeaderField: "X-Goog-Api-Key")
        req.setValue("places.displayName,places.regularOpeningHours", forHTTPHeaderField: "X-Goog-FieldMask")
        let body: [String: Any] = [
            "textQuery": top.name == "Gym" && !top.address.isEmpty ? top.address : top.name, "maxResultCount": 1,
            "locationBias": ["circle": ["center": ["latitude": top.latitude, "longitude": top.longitude], "radius": 200.0]],
        ]
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let closes = parse(data) else { return }
        let c = Cached(name: top.name, closes: closes, fetched: .now)
        if let d = try? JSONEncoder().encode(c) { UserDefaults.standard.set(d, forKey: cacheKey) }
    }

    /// No gym picked in Places yet: a place Apple Maps calls a gym, visited on 10 different days in the
    /// last 60, becomes your gym.
    @MainActor static func learn(context: ModelContext) {
        var sched = UserSchedule.current
        guard sched.gymPlace == nil else { return }
        let since = Date.now.addingTimeInterval(-60 * 86_400)
        let visits = (try? context.fetch(FetchDescriptor<Visit>(predicate: #Predicate { $0.arrival > since }))) ?? []
        let byPlace = Dictionary(grouping: visits.filter { $0.category == .gym }, by: \.placeKey)
        let cal = Calendar.current
        guard let (_, list) = byPlace.max(by: { Set($0.value.map { cal.startOfDay(for: $0.arrival) }).count < Set($1.value.map { cal.startOfDay(for: $0.arrival) }).count }),
              Set(list.map { cal.startOfDay(for: $0.arrival) }).count >= 10, let v = list.last else { return }
        sched.places.append(SavedPlace(kind: "gym", name: v.placeName, address: "", latitude: v.latitude, longitude: v.longitude))
        UserSchedule.current = sched
    }

    /// Google periods: open/close with day 0 = Sunday. A close after midnight counts as 11:59 PM that day.
    static func parse(_ data: Data) -> [Int: Int]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let place = (json["places"] as? [[String: Any]])?.first,
              let periods = (place["regularOpeningHours"] as? [String: Any])?["periods"] as? [[String: Any]] else { return nil }
        var out: [Int: Int] = [:]
        for p in periods {
            guard let open = p["open"] as? [String: Any], let openDay = open["day"] as? Int else { continue }
            let wd = openDay + 1
            guard let close = p["close"] as? [String: Any], let closeDay = close["day"] as? Int else { out[wd] = 24 * 60 - 1; continue } // open 24 h
            let m = (close["hour"] as? Int ?? 0) * 60 + (close["minute"] as? Int ?? 0)
            out[wd] = max(out[wd] ?? 0, closeDay == openDay ? m : 24 * 60 - 1)
        }
        return out.isEmpty ? nil : out
    }
}
