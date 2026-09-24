import SwiftUI
import MapKit

/// Preview flag "search.results" = "rich" (none picked yet): search states as cards instead of a plain list.
/// Empty field: recent places + things to try. No match: a clear message with ideas. Several matches: "Which one?"
/// with a small map for each. One confident match: a big card with the map, your photos there
/// (Apple Maps Look Around if you took none), and Go, which opens Apple Maps directions straight away.
struct RichSearchResults: View {
    var query: String
    var entries: [JournalEntry]
    var visits: [Visit]
    var onPick: (String) -> Void = { _ in }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits = q.isEmpty ? [] : JournalSearch.run(q, entries: entries, visits: visits)
        VStack(alignment: .leading, spacing: 14) {
            if q.isEmpty { emptyState }
            else if hits.isEmpty { noResults(q) }
            else if hits.count == 1 { ConfidentResultCard(hit: hits[0], photos: photos(for: hits[0]), visit: visit(for: hits[0])) }
            else { whichOne(hits) }
        }
    }

    // MARK: Empty field
    private var recent: [Visit] {
        var seen = Set<String>()
        return visits.filter { $0.category != .home && $0.category != .work }
            .sorted { $0.arrival > $1.arrival }
            .filter { seen.insert($0.placeName).inserted }
            .prefix(6).map { $0 }
    }
    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent places").font(.title3.weight(.semibold)).padding(.leading, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(recent, id: \.persistentModelID) { v in
                        Button { MapJump.go(SearchHit(place: v.placeName, date: v.arrival, reason: "", symbol: v.category.symbol, coordinate: v.coordinate)) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Image(systemName: v.category.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 40, height: 40).background(Theme.accent, in: .circle)
                                Text(v.placeName).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                Text(v.arrival.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                            }
                            .frame(width: 120, height: 128, alignment: .topLeading)
                            .padding(12)
                            .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
            Text("Try asking").font(.title3.weight(.semibold)).padding(.leading, 4).padding(.top, 8)
            VStack(spacing: 0) {
                ForEach(Array(["Where was I 4 days ago?", "The place I ate danishes last week", "Directions to the gym", "Photos from the park"].enumerated()), id: \.offset) { i, s in
                    Button { onPick(s) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            Text(s).foregroundStyle(.primary)
                            Spacer()
                            Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(.tertiary)
                        }
                        .padding(.horizontal, 16).frame(height: 50)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    if i < 3 { Divider().padding(.leading, 44) }
                }
            }
            .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
        }
    }

    // MARK: No match
    private func noResults(_ q: String) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "mappin.slash").font(.system(size: 44, weight: .regular)).foregroundStyle(.secondary).padding(.top, 40)
            Text("No places found").font(.title3.weight(.semibold))
            Text("Nothing in your timeline, journal or photos matches \u{201C}\(q)\u{201D}.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.horizontal, 24)
            VStack(alignment: .leading, spacing: 8) {
                Text("Try").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(["A place name, like \u{201C}Blue Door\u{201D}", "A day, like \u{201C}last Friday\u{201D}", "Something in a photo, like \u{201C}pasta\u{201D}"], id: \.self) {
                    Label($0, systemImage: "lightbulb").font(.subheadline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Several matches
    private func whichOne(_ hits: [SearchHit]) -> some View {
        let cal = Calendar.current
        let oneDay = hits.allSatisfy { cal.isDate($0.date, inSameDayAs: hits[0].date) }
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Which one did you mean?").font(.title3.weight(.semibold))
                Text(oneDay ? "\(hits.count) places on \(hits[0].date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))" : "\(hits.count) places match")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.leading, 4)
            ForEach(hits) { h in
                Button { MapJump.go(h) } label: {
                    HStack(spacing: 12) {
                        MiniPlaceMap(coordinate: h.coordinate, symbol: h.symbol).frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 14))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(h.place).font(.body.weight(.semibold))
                            Text(timeText(h)).font(.subheadline).foregroundStyle(.secondary)
                            if !h.reason.isEmpty { Text(h.reason).font(.footnote).foregroundStyle(.secondary).lineLimit(1) }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.subheadline.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                    .padding(10)
                    .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("searchHit")
            }
        }
    }
    private func timeText(_ h: SearchHit) -> String {
        let t = h.date.formatted(date: .omitted, time: .shortened)
        if let v = visit(for: h), let d = v.departure { return "\(t) \u{2013} \(d.formatted(date: .omitted, time: .shortened))" }
        return t
    }

    private func visit(for h: SearchHit) -> Visit? {
        visits.first { $0.placeName == h.place && Calendar.current.isDate($0.arrival, inSameDayAs: h.date) }
    }
    private func photos(for h: SearchHit) -> [Data] {
        guard let c = h.coordinate else { return [] }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        return entries.filter { e in
            guard e.thumbnail != nil, e.videoFileName == nil, let ec = e.coordinate, Calendar.current.isDate(e.date, inSameDayAs: h.date) else { return false }
            return CLLocation(latitude: ec.latitude, longitude: ec.longitude).distance(from: here) < 250
        }.sorted { $0.date < $1.date }.compactMap(\.thumbnail)
    }
}

struct MiniPlaceMap: View {
    var coordinate: CLLocationCoordinate2D?
    var symbol: String
    var distance: Double = 700
    var body: some View {
        if let c = coordinate {
            Map(initialPosition: .camera(MapCamera(centerCoordinate: c, distance: distance)), interactionModes: []) {
                Annotation("", coordinate: c, anchor: .bottom) { ApplePin(symbol: symbol, color: Theme.accent, big: false, dot: true) }
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
        } else {
            Image(systemName: symbol).foregroundStyle(.white).frame(maxWidth: .infinity, maxHeight: .infinity).background(Theme.accent)
        }
    }
}

/// One confident result: map, your photos there (or Look Around), when you were there, Go.
struct ConfidentResultCard: View {
    var hit: SearchHit
    var photos: [Data]
    var visit: Visit?
    @State private var scene: MKLookAroundScene?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MiniPlaceMap(coordinate: hit.coordinate, symbol: hit.symbol, distance: 900).frame(height: 150)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.place).font(.title2.weight(.bold))
                    Text(whenText).font(.subheadline).foregroundStyle(.secondary)
                }
                if !photos.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(Array(photos.enumerated()), id: \.offset) { _, d in
                                if let img = UIImage(data: d) {
                                    Image(uiImage: img).resizable().scaledToFill().frame(width: photos.count == 1 ? 300 : 150, height: 130).clipShape(.rect(cornerRadius: 14))
                                }
                            }
                        }
                    }
                    Label("Your photos from this visit", systemImage: "photo.on.rectangle").font(.caption).foregroundStyle(.secondary)
                } else if let scene {
                    LookAroundPreview(initialScene: scene, allowsNavigation: false, showsRoadLabels: false)
                        .frame(height: 130).clipShape(.rect(cornerRadius: 14))
                    Label("No photos from you here. Look Around from Apple Maps", systemImage: "binoculars").font(.caption).foregroundStyle(.secondary)
                }
                if !hit.reason.isEmpty {
                    Text(hit.reason).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                }
                HStack(spacing: 10) {
                    Button { openDirections() } label: {
                        Label("Go", systemImage: "arrow.triangle.turn.up.right.diamond.fill").font(.headline).frame(maxWidth: .infinity).frame(height: 50)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .background(Theme.accent, in: .capsule)
                    .accessibilityIdentifier("searchGo")
                    Button { MapJump.go(hit) } label: {
                        Image(systemName: "map").font(.headline).frame(width: 50, height: 50)
                    }
                    .buttonStyle(.plain).foregroundStyle(Theme.accent)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Show on Timeline")
                }
            }
            .padding(16)
        }
        .background(Color(.systemBackground).opacity(0.9))
        .clipShape(.rect(cornerRadius: 24))
        .accessibilityIdentifier("searchHit")
        .task {
            guard photos.isEmpty, let c = hit.coordinate else { return }
            scene = try? await MKLookAroundSceneRequest(coordinate: c).scene
        }
    }

    private var whenText: String {
        let day = hit.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        let t = hit.date.formatted(date: .omitted, time: .shortened)
        if let v = visit, let d = v.departure {
            let mins = Int(d.timeIntervalSince(v.arrival) / 60)
            let len = mins >= 60 ? "\(mins / 60) h \(mins % 60) min" : "\(mins) min"
            return "\(day) \u{00B7} \(t) \u{2013} \(d.formatted(date: .omitted, time: .shortened)) \u{00B7} \(len)"
        }
        return "\(day) \u{00B7} \(t)"
    }

    /// Opens Apple Maps with directions to the place straight away.
    private func openDirections() {
        guard let c = hit.coordinate else { return }
        let item = MKMapItem(placemark: MKPlacemark(coordinate: c))
        item.name = hit.place
        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
    }
}
