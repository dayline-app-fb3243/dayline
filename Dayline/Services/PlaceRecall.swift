import Foundation
import SwiftData
import MapKit
import CoreLocation

/// Everything the place card needs, as plain values (safe to pass into Siri snippets).
struct RecalledPlace: Identifiable, Sendable {
    var id: String { "\(placeKey)-\(arrival.timeIntervalSince1970)" }
    var name: String
    var category: PlaceCategory
    var arrival: Date
    var departure: Date?
    var latitude: Double
    var longitude: Double
    var placeKey: String
    var phone: String?
    var address: String?
    var mapItemID: String?
    var photos: [Data]
    var timesVisited: Int

    var coordinate: CLLocationCoordinate2D { .init(latitude: latitude, longitude: longitude) }

    /// Apple Maps directions from the current location.
    var directionsURL: URL {
        var c = URLComponents(string: "https://maps.apple.com/")!
        c.queryItems = [
            .init(name: "daddr", value: "\(latitude),\(longitude)"),
            .init(name: "q", value: name),
            .init(name: "dirflg", value: "d")
        ]
        return c.url!
    }

    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return URL(string: "tel:\(digits)")
    }

    /// "Thu, Sep 19 · 7:40 PM · 1 h 10 min"
    var whenText: String {
        var parts = [arrival.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()),
                     arrival.formatted(date: .omitted, time: .shortened)]
        if let departure {
            let minutes = Int(departure.timeIntervalSince(arrival) / 60)
            parts.append(minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min")
        }
        return parts.joined(separator: " · ")
    }

    /// "4 days ago", "yesterday"
    var relativeDay: String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: arrival), to: cal.startOfDay(for: .now)).day ?? 0
        switch days {
        case 0: return "today"
        case 1: return "yesterday"
        default: return "\(days) days ago"
        }
    }
}

enum RecallError: Error, CustomLocalizedStringResourceConvertible {
    case notFound(kind: String, day: String?)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .notFound(kind, day?):
            return "I couldn't find a \(kind) you went to \(day). Dayline only knows places from after you started using it."
        case let .notFound(kind, nil):
            return "I couldn't find a \(kind) you've been to yet."
        }
    }
}

/// Finds past visits from plain-language requests like "where I ate four days ago".
@MainActor
enum PlaceRecall {
    /// Picks the best matching visit: on `day` if given (the longest stay that day), otherwise the most recent.
    static func find(categories: [PlaceCategory], on day: Date?, context: ModelContext,
                     calendar: Calendar = .current) -> Visit? {
        let wanted = Set(categories.map(\.rawValue))
        var descriptor = FetchDescriptor<Visit>(sortBy: [SortDescriptor(\.arrival, order: .reverse)])
        if let day {
            let window = DayBoundary.shared.window(for: day, calendar: calendar)
            let start = window.start, end = window.end
            descriptor.predicate = #Predicate { $0.arrival >= start && $0.arrival < end }
        } else {
            descriptor.fetchLimit = 500
        }
        let visits = ((try? context.fetch(descriptor)) ?? []).filter { v in
            wanted.isEmpty ? v.category != .home && v.category != .work : wanted.contains(v.categoryRaw)
        }
        if day != nil { return visits.max { $0.duration < $1.duration } }
        return visits.first
    }

    /// Builds the card: photos taken there during the visit, visit count, phone number from Apple Maps.
    static func card(for visit: Visit, context: ModelContext, lookUpDetails: Bool = true) async -> RecalledPlace {
        let from = visit.arrival.addingTimeInterval(-15 * 60)
        let to = (visit.departure ?? .now).addingTimeInterval(15 * 60)
        let entries = (try? context.fetch(FetchDescriptor<JournalEntry>(
            predicate: #Predicate { $0.date >= from && $0.date <= to },
            sortBy: [SortDescriptor(\.date)]))) ?? []
        let here = CLLocation(latitude: visit.latitude, longitude: visit.longitude)
        let photos = entries.filter { entry in
            guard entry.kind == .photo, let thumb = entry.thumbnail, !thumb.isEmpty else { return false }
            guard let c = entry.coordinate else { return entry.placeName == visit.placeName }
            if let name = entry.placeName, name != visit.placeName { return false }
            return CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: here) < 120
        }.compactMap(\.thumbnail)

        let key = visit.placeKey
        let count = (try? context.fetchCount(FetchDescriptor<Visit>(predicate: #Predicate { $0.placeKey == key }))) ?? 1

        var place = RecalledPlace(name: visit.placeName, category: visit.category, arrival: visit.arrival,
                                  departure: visit.departure, latitude: visit.latitude, longitude: visit.longitude,
                                  placeKey: visit.placeKey, phone: visit.phoneNumber, address: nil,
                                  mapItemID: visit.mapItemID, photos: Array(photos.prefix(6)), timesVisited: count)
        if lookUpDetails, let item = await mapItem(for: place) {
            place.phone = place.phone ?? item.phoneNumber
            place.mapItemID = place.mapItemID ?? item.identifier?.rawValue
            place.address = item.placemark.thoroughfare.map { street in
                [item.placemark.subThoroughfare, street].compactMap { $0 }.joined(separator: " ")
            }
            visit.phoneNumber = place.phone
            visit.mapItemID = place.mapItemID
        }
        return place
    }

    /// Looks the place up in Apple Maps by id, or by name right at that spot.
    static func mapItem(for place: RecalledPlace) async -> MKMapItem? {
        if let raw = place.mapItemID, let id = MKMapItem.Identifier(rawValue: raw),
           let item = try? await MKMapItemRequest(mapItemIdentifier: id).mapItem {
            return item
        }
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = place.name
        request.region = MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 300, longitudinalMeters: 300)
        request.resultTypes = .pointOfInterest
        guard let items = try? await MKLocalSearch(request: request).start().mapItems else { return nil }
        let here = CLLocation(latitude: place.latitude, longitude: place.longitude)
        return items.min {
            ($0.placemark.location?.distance(from: here) ?? .infinity) < ($1.placemark.location?.distance(from: here) ?? .infinity)
        }
    }

}
