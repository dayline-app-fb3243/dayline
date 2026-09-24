import Foundation
import SwiftData
import CoreLocation

/// One raw location check-in (taken every ~5-15 minutes, never continuously).
@Model
final class LocationSample {
    var timestamp: Date
    var latitude: Double
    var longitude: Double
    var horizontalAccuracy: Double
    var source: String   // "visit", "significant", "foreground", "photo"

    init(timestamp: Date, latitude: Double, longitude: Double, horizontalAccuracy: Double, source: String) {
        self.timestamp = timestamp
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.source = source
    }

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
}

enum PlaceCategory: String, Codable, CaseIterable, Sendable {
    case home, work, gym, food, coffee, outdoors, shopping, other

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .work: "briefcase.fill"
        case .gym: "dumbbell.fill"
        case .food: "fork.knife"
        case .coffee: "cup.and.saucer.fill"
        case .outdoors: "tree.fill"
        case .shopping: "bag.fill"
        case .other: "mappin"
        }
    }

    var colorName: String {
        switch self {
        case .home: "indigo"
        case .work: "blue"
        case .gym: "green"
        case .food: "orange"
        case .coffee: "brown"
        case .outdoors: "mint"
        case .shopping: "pink"
        case .other: "gray"
        }
    }
}

/// A stay at one place (from CLVisit or clustered samples).
@Model
final class Visit {
    var arrival: Date
    var departure: Date?
    var latitude: Double
    var longitude: Double
    var placeName: String
    var categoryRaw: String
    /// Rounded key used to recognise the same place across days.
    var placeKey: String
    /// Apple Maps place identifier (MKMapItem.Identifier.rawValue), used for phone, hours and directions.
    var mapItemID: String?
    var phoneNumber: String?

    init(arrival: Date, departure: Date?, latitude: Double, longitude: Double, placeName: String, category: PlaceCategory) {
        self.arrival = arrival
        self.departure = departure
        self.latitude = latitude
        self.longitude = longitude
        self.placeName = placeName
        self.categoryRaw = category.rawValue
        self.placeKey = Visit.key(latitude: latitude, longitude: longitude)
    }

    var category: PlaceCategory {
        get { PlaceCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }
    var duration: TimeInterval { (departure ?? .now).timeIntervalSince(arrival) }

    /// ~150 m grid key.
    static func key(latitude: Double, longitude: Double) -> String {
        String(format: "%.3f,%.3f", (latitude * 700).rounded() / 700, (longitude * 700).rounded() / 700)
    }
}

enum JournalKind: String, Codable, Sendable { case photo, voice, text }

@Model
final class JournalEntry {
    var date: Date
    var kindRaw: String
    var text: String
    /// PhotoKit local identifier for photo entries.
    var photoAssetID: String?
    /// Small JPEG copy so the timeline loads fast (and demo mode works without PhotoKit).
    @Attribute(.externalStorage) var thumbnail: Data?
    /// File name of the recording in the app's Documents/Voice folder.
    var audioFileName: String?
    var audioDuration: Double
    /// File name of a video in Documents/Video (the thumbnail is its poster frame).
    var videoFileName: String? = nil
    var videoDuration: Double = 0
    var latitude: Double?
    var longitude: Double?
    var isTranscribed: Bool

    init(date: Date, kind: JournalKind, text: String = "", photoAssetID: String? = nil, thumbnail: Data? = nil,
         audioFileName: String? = nil, audioDuration: Double = 0, latitude: Double? = nil, longitude: Double? = nil,
         isTranscribed: Bool = false) {
        self.date = date
        self.kindRaw = kind.rawValue
        self.text = text
        self.photoAssetID = photoAssetID
        self.thumbnail = thumbnail
        self.audioFileName = audioFileName
        self.audioDuration = audioDuration
        self.latitude = latitude
        self.longitude = longitude
        self.isTranscribed = isTranscribed
    }

    var kind: JournalKind { JournalKind(rawValue: kindRaw) ?? .text }
    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return .init(latitude: latitude, longitude: longitude)
    }
}

/// A schedule item. `isAuto` = inferred from the routine, not typed by the user.
@Model
final class PlanItem {
    var title: String
    var start: Date
    var end: Date
    var isAuto: Bool
    var reason: String
    var isDone: Bool
    var categoryRaw: String

    init(title: String, start: Date, end: Date, isAuto: Bool, reason: String = "", isDone: Bool = false, category: PlaceCategory = .other) {
        self.title = title
        self.start = start
        self.end = end
        self.isAuto = isAuto
        self.reason = reason
        self.isDone = isDone
        self.categoryRaw = category.rawValue
    }

    var category: PlaceCategory { PlaceCategory(rawValue: categoryRaw) ?? .other }
}

/// Final score for a finished day (today's score is computed live).
@Model
final class DayScore {
    @Attribute(.unique) var day: Date   // start of day
    var score: Int
    var label: String
    var summary: String
    var factorsJSON: Data?

    init(day: Date, score: Int, label: String, summary: String, factors: [ScoreFactor] = []) {
        self.day = day
        self.score = score
        self.label = label
        self.summary = summary
        self.factorsJSON = try? JSONEncoder().encode(factors)
    }

    var factors: [ScoreFactor] {
        guard let factorsJSON else { return [] }
        return (try? JSONDecoder().decode([ScoreFactor].self, from: factorsJSON)) ?? []
    }
}

struct ScoreFactor: Codable, Hashable, Identifiable, Sendable {
    enum Effect: String, Codable, Sendable { case up, neutral, pending }
    var id: String { title }
    var title: String
    var effect: Effect
    var points: Int
    /// Optional second line on the Day score page, e.g. "Up at 6:50 · goal 7:00".
    var detail: String? = nil
    /// Optional short text for the chip on the Today card, e.g. "Gym done".
    var chip: String? = nil
}

enum ModelStore {
    static let schema = Schema([LocationSample.self, Visit.self, JournalEntry.self, PlanItem.self, DayScore.self])

    @MainActor
    static let container: ModelContainer = {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-demo")
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("Could not open database: \(error)")
        }
    }()
}
