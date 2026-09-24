import SwiftUI
import SwiftData
import MapKit

/// In-app version of the Siri feature: pick a type and a day, see the place, go.
struct PlaceRecallView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @State private var kind: PlaceKind = .restaurant
    @State private var daysAgo = 4
    @State private var place: RecalledPlace?
    @State private var notFound = false
    @State private var detailItem: MKMapItem?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Ask Siri: \"Take me to the place I went out eating 4 days ago.\"")
                    .font(.subheadline).foregroundStyle(.secondary)

                CapsuleSegmented(selection: $kind, options: [
                    (.restaurant, "Food"), (.coffee, "Coffee"), (.gym, "Gym"), (.park, "Park"), (.anyPlace, "Any")
                ])

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(0..<8, id: \.self) { n in
                            Button(n == 0 ? "Today" : n == 1 ? "Yesterday" : "\(n) days ago") { daysAgo = n }
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .foregroundStyle(daysAgo == n ? Color.white : Color.primary)
                                .background(daysAgo == n ? Color.blue : Color.primary.opacity(0.07), in: .capsule)
                                .buttonStyle(.plain)
                        }
                    }
                }

                if let place {
                    PlaceCard(place: place,
                              go: { openURL(place.directionsURL) },
                              call: { if let url = place.phoneURL { openURL(url) } },
                              info: { Task { detailItem = await PlaceRecall.mapItem(for: place) } })
                } else if notFound {
                    Card { Text("No \(kind.spoken) found for that day.").foregroundStyle(.secondary) }
                }

            }
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle("Find a place")
        .toolbarVisibility(.hidden, for: .tabBar)
        .task(id: "\(kind.rawValue)-\(daysAgo)") { await load() }
        .mapItemDetailSheet(item: $detailItem)
    }

    private func load() async {
        let day = Calendar.current.date(byAdding: .day, value: -daysAgo, to: .now)
        if let visit = PlaceRecall.find(categories: kind.categories, on: day, context: context) {
            place = await PlaceRecall.card(for: visit, context: context)
            notFound = false
        } else {
            place = nil
            notFound = true
        }
    }
}

/// Solid white card (matches the Timeline design) with Go Now plus round Call and Hours buttons.
struct PlaceCard: View {
    var place: RecalledPlace
    var go: () -> Void
    var call: () -> Void
    var info: () -> Void

    var body: some View {
        Card(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if !place.photos.isEmpty {
                    PhotoStrip(photos: place.photos, height: 120).padding([.horizontal, .top], 12)
                } else {
                    Map(initialPosition: .region(MKCoordinateRegion(center: place.coordinate, latitudinalMeters: 400,
                                                                      longitudinalMeters: 400))) {
                        Marker(place.name, systemImage: place.category.symbol, coordinate: place.coordinate)
                    }
                    .frame(height: 140).allowsHitTesting(false)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(place.name).font(.title3.weight(.bold))
                        Spacer()
                        Badge(text: place.relativeDay.capitalizedFirst, color: .blue)
                    }
                    Text(place.whenText).font(.subheadline).foregroundStyle(.secondary)
                    if let address = place.address { Text(address).font(.subheadline).foregroundStyle(.secondary) }
                }
                .padding(14)
                HStack(spacing: 10) {
                    Button(action: go) {
                        Label("Go Now", systemImage: "arrow.triangle.turn.up.right.diamond.fill").lineLimit(1).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
                    Button(action: call) { Image(systemName: "phone.fill") }
                        .buttonStyle(.bordered).buttonBorderShape(.circle).disabled(place.phone == nil)
                        .accessibilityLabel("Call")
                    Button(action: info) { Image(systemName: "clock") }
                        .buttonStyle(.bordered).buttonBorderShape(.circle)
                        .accessibilityLabel("Hours")
                }
                .controlSize(.large)
                .padding([.horizontal, .bottom], 14)
            }
        }
        .accessibilityIdentifier("placeCard")
    }
}
