import Foundation
import CoreLocation
import MapKit

/// Names a visit ("Blue Bottle Coffee", "Gym") and guesses its category.
@MainActor
final class PlaceNamer {
    static let shared = PlaceNamer()
    private let geocoder = CLGeocoder()

    func name(_ visit: Visit) async {
        let location = CLLocation(latitude: visit.latitude, longitude: visit.longitude)

        // 1. Nearby point of interest (gives categories like gym / restaurant).
        let request = MKLocalPointsOfInterestRequest(center: location.coordinate, radius: 60)
        if let response = try? await MKLocalSearch(request: request).start(),
           let item = response.mapItems.first {
            visit.placeName = item.name ?? visit.placeName
            visit.category = Self.category(for: item.pointOfInterestCategory)
            return
        }
        // 2. Fall back to a street name.
        if let mark = try? await geocoder.reverseGeocodeLocation(location).first {
            visit.placeName = mark.name ?? mark.thoroughfare ?? "Place"
        }
    }

    static func category(for poi: MKPointOfInterestCategory?) -> PlaceCategory {
        guard let poi else { return .other }
        switch poi {
        case .fitnessCenter: return .gym
        case .restaurant, .bakery, .brewery, .winery, .foodMarket: return .food
        case .cafe: return .coffee
        case .park, .beach, .nationalPark, .campground, .marina: return .outdoors
        case .store: return .shopping
        default: return .other
        }
    }
}
