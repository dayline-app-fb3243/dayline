import AppIntents
import SwiftData
import Foundation

/// The kinds of places Siri understands, with everyday synonyms
/// ("the place I went out eating" -> restaurant).
enum PlaceKind: String, AppEnum {
    case restaurant, coffee, gym, park, shop, anyPlace

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Place Type"
    static let caseDisplayRepresentations: [PlaceKind: DisplayRepresentation] = [
        .restaurant: DisplayRepresentation(title: "restaurant",
                                           synonyms: ["place I ate", "place I went out eating", "place I ate at", "food place",
                                                      "dinner spot", "lunch spot", "brunch spot", "bar"]),
        .coffee: DisplayRepresentation(title: "coffee shop", synonyms: ["café", "cafe", "coffee place"]),
        .gym: DisplayRepresentation(title: "gym", synonyms: ["workout place", "fitness place"]),
        .park: DisplayRepresentation(title: "park", synonyms: ["beach", "trail", "outdoor spot"]),
        .shop: DisplayRepresentation(title: "store", synonyms: ["shop", "place I went shopping"]),
        .anyPlace: DisplayRepresentation(title: "place", synonyms: ["spot", "place I went"])
    ]

    var categories: [PlaceCategory] {
        switch self {
        case .restaurant: [.food]
        case .coffee: [.coffee]
        case .gym: [.gym]
        case .park: [.outdoors]
        case .shop: [.shopping]
        case .anyPlace: []
        }
    }

    var spoken: String {
        switch self {
        case .restaurant: "restaurant"
        case .coffee: "coffee shop"
        case .gym: "gym"
        case .park: "park"
        case .shop: "store"
        case .anyPlace: "place"
        }
    }
}

/// "Hey Siri, take me to the place I went out eating four days ago."
/// Finds the visit, shows a card in Siri with his photos from there and the phone number,
/// and the Go button opens Apple Maps directions.
struct FindPlaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Me to a Place I Went"
    static let description = IntentDescription(
        "Finds a place you've been, like where you ate four days ago, shows your photos from there, and gets directions in Apple Maps.")

    @Parameter(title: "Place type", default: .restaurant)
    var kind: PlaceKind

    @Parameter(title: "Day", description: "The day you went, like four days ago or last Friday.")
    var day: Date?

    @Parameter(title: "Days ago", description: "How many days ago you went.", inclusiveRange: (0, 365))
    var daysAgo: Int?

    static var parameterSummary: some ParameterSummary {
        Summary("Take me to the \(\.$kind) I went to on \(\.$day)") {
            \.$daysAgo
        }
    }

    init() {}
    init(kind: PlaceKind, daysAgo: Int?) {
        self.kind = kind
        self.daysAgo = daysAgo
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & OpensIntent {
        let context = ModelStore.container.mainContext
        let target: Date? = day ?? daysAgo.flatMap { Calendar.current.date(byAdding: .day, value: -$0, to: .now) }

        guard let visit = PlaceRecall.find(categories: kind.categories, on: target, context: context) else {
            let when = target.map { d -> String in
                let n = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: d),
                                                        to: Calendar.current.startOfDay(for: .now)).day ?? 0
                return n == 0 ? "today" : n == 1 ? "yesterday" : "\(n) days ago"
            }
            throw RecallError.notFound(kind: kind.spoken, day: when)
        }
        let place = await PlaceRecall.card(for: visit, context: context)
        try? context.save()
        let route = await RouteSnapshot.make(to: place.coordinate, name: place.name)

        // Show the card with a Go button; tapping Go opens Apple Maps.
        try await requestConfirmation(
            result: .result(dialog: "\(place.relativeDay.capitalizedFirst) you went to \(place.name). Want directions?",
                            view: PlaceSnippetView(place: place, route: route)),
            confirmationActionName: .go,
            showPrompt: false)

        return .result(opensIntent: OpenURLIntent(place.directionsURL),
                       dialog: "Getting directions to \(place.name).")
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
