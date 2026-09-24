import SwiftUI
import SwiftData
import MapKit

enum MapRange: String, CaseIterable, Identifiable { case day = "Day", week = "Week", month = "Month", year = "Year"; var id: String { rawValue } }

/// Map of everywhere you went (day / week / month / year) plus the day's timeline.
struct TimelineScreen: View {
    @Query(sort: \Visit.arrival) private var visits: [Visit]
    @Query(sort: \LocationSample.timestamp) private var samples: [LocationSample]
    @Query(sort: \JournalEntry.date) private var journal: [JournalEntry]
    @State private var range: MapRange = .day
    @State private var anchor = Date.now
    @State private var camera: MapCameraPosition = .automatic
    @State private var showRoute = true
    @State private var showPhotos = true
    @State private var showJournal = true
    @State private var expanded = false
    @State private var region: MKCoordinateRegion?

    private var interval: DateInterval {
        let cal = Calendar.current
        let component: Calendar.Component = switch range { case .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year }
        return cal.dateInterval(of: component, for: anchor) ?? DateInterval(start: anchor, duration: 86_400)
    }
    private var rangeVisits: [Visit] { visits.filter { interval.contains($0.arrival) } }
    private var rangeSamples: [LocationSample] { samples.filter { interval.contains($0.timestamp) } }
    private var rangePhotos: [JournalEntry] { journal.filter { $0.kind == .photo && $0.coordinate != nil && interval.contains($0.date) } }
    private var rangeNotes: [JournalEntry] { journal.filter { $0.kind != .photo && $0.coordinate != nil && interval.contains($0.date) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    rangeControls
                    if range == .day {
                        // Day: small map on top (tap for full screen), then one photo card per stop.
                        mapCard(height: 150, hint: true)
                        Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
                        HStack(spacing: 6) {
                            infoChip("\(placeCount)", "places")
                            infoChip(distanceText, "moved")
                            infoChip("\(rangePhotos.count)", "photos")
                        }
                        DayPhotoCards(visits: rangeVisits, journal: journal.filter { interval.contains($0.date) })
                    } else {
                        // Week / month / year: every place and route in the range, stats on the map, then a plain list.
                        mapCard(height: 330, hint: false)
                            .overlay(alignment: .bottom) {
                                GlassEffectContainer(spacing: 6) {
                                    HStack(spacing: 6) {
                                        glassChip("\(placeCount)", "places")
                                        glassChip(distanceText, "moved")
                                        glassChip("\(rangeSamples.count)", "check-ins")
                                    }
                                }
                                .padding(10)
                            }
                        MostVisitedList(clusters: placeClusters)
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .navigationTitle("Timeline")
            .navigationBarTitleDisplayMode(.large)
            .backgroundNavBar()
            .fullScreenCover(isPresented: $expanded) { fullMap }
            .onChange(of: range) { camera = .automatic }
            .onChange(of: anchor) { camera = .automatic }
        }
    }

    private var map: some View { mapView(interactive: true) }

    private func mapView(interactive: Bool, showsControls: Bool = true) -> some View {
        Map(position: $camera, interactionModes: interactive ? .all : []) {
            UserAnnotation()
            if showRoute {
                if range == .day {
                    MapPolyline(coordinates: rangeSamples.map(\.coordinate))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                } else {
                    // Full route for the whole range, thinned so a year stays fast.
                    MapPolyline(coordinates: thinnedRoute)
                        .stroke(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }
            }
            if range == .day {
                ForEach(rangeVisits.filter { $0.category != .home }) { v in
                    Annotation("", coordinate: v.coordinate) {
                        Image(systemName: v.category.symbol).font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                            .frame(width: 32, height: 32).background(.white, in: .circle).shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    }
                }
            } else {
                // Every place you went in the range; bigger dot = more time there.
                ForEach(placeClusters, id: \.key) { cluster in
                    Annotation("", coordinate: cluster.coordinate) {
                        let size = 14 + min(cluster.hours, 200) / 200 * 12
                        Circle().fill(Theme.accent).frame(width: size, height: size)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(color: .black.opacity(0.2), radius: 3, y: 1)
                    }
                }
            }
            if showJournal {
                ForEach(rangeNotes.suffix(40)) { entry in
                    Annotation("", coordinate: entry.coordinate!) {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.accent, in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 4)
                    }
                }
            }
            if showPhotos { ForEach(rangePhotos.suffix(40)) { entry in
                Annotation("", coordinate: entry.coordinate!) {
                    if let data = entry.thumbnail, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48)
                            .clipShape(.rect(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white, lineWidth: 3)).shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    }
                }
            } }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapCompass(); MapScaleView() }
        .mapControlVisibility(showsControls ? .automatic : .hidden)
        .onMapCameraChange(frequency: .onEnd) { context in region = context.region }
    }

    /// Map card: tap anywhere to open the full-screen map.
    private func mapCard(height: CGFloat, hint: Bool) -> some View {
        mapView(interactive: false, showsControls: false)
            .frame(height: height)
            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
            .contentShape(.rect(cornerRadius: Theme.cardRadius))
            .onTapGesture { expanded = true }
            .overlay(alignment: .topTrailing) {
                Button { expanded = true } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.primary).frame(width: 34, height: 34)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .circle)
                .accessibilityLabel("Open map")
                .padding(10)
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mapCard")
    }

    /// Full-screen map: back + title on top, glass toggles and locate at the bottom right, range picker at the bottom.
    private var fullMap: some View {
        mapView(interactive: true, showsControls: false)
            .ignoresSafeArea()
            .overlay(alignment: .top) {
                HStack {
                    Button { expanded = false } label: {
                        Image(systemName: "chevron.left").font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.accent).frame(width: 44, height: 44)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .accessibilityLabel("Back")
                    .accessibilityIdentifier("closeMap")
                    Spacer(minLength: 8)
                    Text("\(title) · \(daySummary)").font(.subheadline.weight(.semibold)).lineLimit(1)
                        .padding(.horizontal, 16).padding(.vertical, 11)
                        .glassEffect(.regular, in: .capsule)
                    Spacer(minLength: 8)
                    Color.clear.frame(width: 44, height: 44)
                }
                .padding(.horizontal, 16).padding(.top, 4)
            }
            .overlay(alignment: .bottomTrailing) {
                GlassEffectContainer(spacing: 14) {
                    VStack(spacing: 14) {
                        VStack(spacing: 0) {
                            mapToggle("Route", "point.topleft.down.to.point.bottomright.curvepath", $showRoute)
                            mapToggle("Photos", "photo", $showPhotos)
                            mapToggle("Journal", "doc.text", $showJournal)
                        }
                        .padding(4)
                        .glassEffect(.regular, in: .capsule)
                        Button { withAnimation(.snappy) { camera = .userLocation(fallback: .automatic) } } label: {
                            Image(systemName: "location.fill").font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(Theme.accent).frame(width: 64, height: 64)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Show my location")
                        .accessibilityIdentifier("locateMe")
                    }
                }
                .padding(.trailing, 16).padding(.bottom, 72)
            }
            .overlay(alignment: .bottom) {
                CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) }, plain: true)
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16).padding(.bottom, 6)
            }
    }

    private func mapToggle(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { on.wrappedValue.toggle() } } label: {
            Image(systemName: symbol).font(.system(size: 19, weight: .semibold))
                .foregroundStyle(on.wrappedValue ? Theme.accent : Color.secondary)
                .frame(width: 56, height: 56)
                .contentShape(.circle)
                .glassEffect(on.wrappedValue ? .regular.interactive() : .identity, in: .circle)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
        .accessibilityIdentifier("toggle\(title)")
    }

    private func infoChip(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.footnote.bold())
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }

    private func glassChip(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.subheadline.bold())
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .glassEffect(.regular, in: .capsule)
    }

    private var placeCount: Int { Set(rangeVisits.filter { $0.category != .home }.map(\.placeKey)).count }
    private var meters: Double {
        zip(rangeSamples, rangeSamples.dropFirst()).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
    }
    private var distanceText: String {
        Measurement(value: meters, unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0...1))))
    }
    private var thinnedRoute: [CLLocationCoordinate2D] {
        let pts = rangeSamples
        guard pts.count > 1500 else { return pts.map(\.coordinate) }
        let step = pts.count / 1500 + 1
        return stride(from: 0, to: pts.count, by: step).map { pts[$0].coordinate }
    }

    private var rangeControls: some View {
        VStack(spacing: 8) {
            Picker("Range", selection: $range) {
                ForEach(MapRange.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            if range != .day {
                HStack {
                    Button("Previous", systemImage: "chevron.left") { step(-1) }.labelStyle(.iconOnly)
                    Text(title).font(.headline).frame(maxWidth: .infinity)
                    Button("Next", systemImage: "chevron.right") { step(1) }.labelStyle(.iconOnly)
                        .disabled(interval.end > .now)
                }
                .buttonStyle(.glass)
            }
        }
    }

    private var layerToggles: some View {
        HStack(spacing: 6) {
            layerToggle("Route", "point.topleft.down.to.point.bottomright.curvepath", Theme.route, $showRoute)
            layerToggle("Photos", "photo", Theme.photos, $showPhotos)
            layerToggle("Journal", "pencil", Theme.journal, $showJournal)
        }
    }

    private var daySummary: String {
        let places = Set(rangeVisits.filter { $0.category != .home }.map(\.placeKey)).count
        let km = zip(rangeSamples, rangeSamples.dropFirst()).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        } / 1000
        _ = km
        return "\(places) place\(places == 1 ? "" : "s") · \(distanceText)"
    }

    private func layerToggle(_ title: String, _ symbol: String, _ color: Color, _ on: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { on.wrappedValue.toggle() } } label: {
            Label(title, systemImage: symbol).font(.footnote.weight(.semibold)).labelStyle(.titleOnly)
                .padding(.horizontal, 11).padding(.vertical, 7)
                .foregroundStyle(on.wrappedValue ? .white : .primary)
                .background(on.wrappedValue ? AnyShapeStyle(color.gradient) : AnyShapeStyle(.clear), in: .capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(on.wrappedValue ? .identity : .regular.interactive(), in: .capsule)
        .accessibilityIdentifier("toggle\(title)")
    }

    private var title: String {
        switch range {
        case .day: Calendar.current.isDateInToday(anchor) ? "Today" : anchor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        case .week: "Week of " + interval.start.formatted(.dateTime.month(.abbreviated).day())
        case .month: anchor.formatted(.dateTime.month(.wide).year())
        case .year: anchor.formatted(.dateTime.year())
        }
    }

    private func step(_ n: Int) {
        let component: Calendar.Component = switch range { case .day: .day; case .week: .weekOfYear; case .month: .month; case .year: .year }
        anchor = Calendar.current.date(byAdding: component, value: n, to: anchor) ?? anchor
    }

    struct Cluster { var key: String; var name: String; var coordinate: CLLocationCoordinate2D; var hours: Double; var visits: Int; var category: PlaceCategory }
    private var placeClusters: [Cluster] {
        Dictionary(grouping: rangeVisits.filter { $0.category != .home }, by: \.placeKey).compactMap { key, stays in
            guard let first = stays.first else { return nil }
            return Cluster(key: key, name: first.placeName, coordinate: first.coordinate, hours: stays.reduce(0) { $0 + $1.duration } / 3600,
                           visits: stays.count, category: first.category)
        }
    }
}

/// Vertical list of places with times, photos and voice notes for one day.
let TimelineClock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()

/// Plain "Most visited" list for week / month / year: no card behind it.
struct MostVisitedList: View {
    var clusters: [TimelineScreen.Cluster]
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Most visited").font(.footnote).helperText().textCase(.uppercase)
                .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 2)
            let top = Array(clusters.sorted { $0.hours > $1.hours }.prefix(6))
            if top.isEmpty {
                Text("No places in this period yet.").font(.subheadline).foregroundStyle(.secondary).padding(4)
            }
            ForEach(Array(top.enumerated()), id: \.element.key) { i, c in
                if i > 0 { Divider().padding(.leading, 50) }
                HStack(spacing: 12) {
                    CategoryIcon(category: c.category, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.body.weight(.semibold)).lineLimit(1)
                        Text("\(c.visits) visit\(c.visits == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(c.hours >= 1 ? "\(Int(c.hours.rounded()))h" : "\(Int(c.hours * 60)) min").font(.subheadline.weight(.bold))
                }
                .padding(.vertical, 10).padding(.horizontal, 4)
            }
        }
    }
}

/// Day view: one card per stop, with that stop's photos across the top and any voice note inside.
struct DayPhotoCards: View {
    var visits: [Visit]
    var journal: [JournalEntry]

    var body: some View {
        VStack(spacing: 10) {
            if stops.isEmpty {
                ContentUnavailableView("No places yet", systemImage: "location",
                                       description: Text("Your timeline builds itself as you move around."))
            }
            ForEach(stops) { visit in
                let items = journal.filter { $0.date >= visit.arrival && $0.date < (visit.departure ?? .distantFuture) }
                let photos = items.compactMap { $0.kind == .photo ? $0.thumbnail.flatMap(UIImage.init(data:)) : nil }
                let voice = items.first { $0.kind == .voice }
                VStack(alignment: .leading, spacing: 0) {
                    if !photos.isEmpty {
                        HStack(spacing: 3) {
                            ForEach(Array(photos.prefix(2).enumerated()), id: \.offset) { _, img in
                                Color.clear.frame(maxWidth: .infinity).frame(height: 120)
                                    .overlay { Image(uiImage: img).resizable().scaledToFill() }
                                    .clipped()
                            }
                        }
                    }
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(alignment: .center) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(visit.placeName).font(.headline)
                                Text(timeText(visit)).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if visit.departure == nil {
                                Text("Here now").font(.caption.weight(.bold)).foregroundStyle(.white)
                                    .padding(.horizontal, 9).padding(.vertical, 4)
                                    .background(Theme.accent, in: .capsule)
                            } else {
                                CategoryIcon(category: visit.category, size: 30)
                            }
                        }
                        if let voice {
                            HStack(spacing: 10) {
                                Image(systemName: "play.fill").font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 28, height: 28).background(Theme.accent, in: .circle)
                                Text(voice.text.isEmpty ? "Voice note" : "\"\(voice.text)\"").font(.footnote).lineLimit(1)
                                Spacer()
                                Text(Duration.seconds(voice.audioDuration).formatted(.time(pattern: .minuteSecond)))
                                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
                            }
                            .padding(8)
                            .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 14, style: .continuous))
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .background(Color(.secondarySystemGroupedBackground).opacity(0.92), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
                .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
            }
        }
    }

    private var stops: [Visit] { visits.filter { $0.category != .home || $0.duration < 12 * 3600 }.sorted { $0.arrival < $1.arrival } }

    private func timeText(_ v: Visit) -> String {
        guard let d = v.departure else { return "Since \(v.arrival.shortTime)" }
        let minutes = Int(d.timeIntervalSince(v.arrival) / 60)
        let dur = minutes < 60 ? "\(minutes) min" : "\(minutes / 60) h \(minutes % 60) min"
        return "\(TimelineClock.string(from: v.arrival)) – \(TimelineClock.string(from: d)) · \(dur)"
    }
}
