import SwiftUI
import SwiftData
import MapKit

enum MapRange: String, CaseIterable, Identifiable { case day = "Day", week = "Week", month = "Month", year = "Year"; var id: String { rawValue } }

/// Map of everywhere you went (day / week / month / year) plus the day's timeline.
struct TimelineScreen: View {
    @Environment(\.colorScheme) private var mapScheme
    @AppStorage("symbols.show") private var showSymbols = true
    @Query(sort: \Visit.arrival) private var visits: [Visit]
    @Query(sort: \LocationSample.timestamp) private var samples: [LocationSample]
    @Query(sort: \JournalEntry.date) private var journal: [JournalEntry]
    @State private var range: MapRange = .day
    @State private var anchor = Date.now
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @ObservedObject private var location = LocationService.shared
    @State private var showRoute = true
    @State private var showPhotos = true
    @State private var showJournal = true
    @State private var showPlaces = true
    /// Photo or journal pin tapped on the full map; opens that entry.
    @State private var openedEntry: JournalEntry?
    @State private var expanded = false
    @State private var region: MKCoordinateRegion?
    /// Route detail follows the Check Location setting: one point per check, snapped to streets.
    @AppStorage(LocationService.intervalKey) private var checkMinutes = 5
    @State private var streetRoute: [CLLocationCoordinate2D] = []
    @State private var is3D = false
    /// The map is centered on your current location (filled arrow). Cleared when you pan away.
    @State private var onMyLocation = false
    @State private var myCoordinate: CLLocationCoordinate2D?
    @State private var userMovedMap = false
    @State private var sheetOpen = UserDefaults.standard.bool(forKey: "map.sheetOpen")

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
                    TabTitle("Timeline")
                    rangeControls
                    if range == .day { dayPage } else { rangePage }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(AppBackgroundView())
            .navigationTitle("Timeline")
            .tabRoot()
            .fullScreenCover(isPresented: $expanded) {
                fullMap
                    .onDisappear { is3D = false; onMyLocation = false; centerOnCurrentLocation(force: true) }
            }
            .onChange(of: range) { onMyLocation = false; userMovedMap = false; centerOnCurrentLocation() }
            .onChange(of: anchor) { onMyLocation = false; userMovedMap = false; centerOnCurrentLocation() }
            .onChange(of: location.lastSample) { centerOnCurrentLocation() }
            .onAppear { centerOnCurrentLocation() }
            .onReceive(NotificationCenter.default.publisher(for: .showOnMap)) { _ in openJump() }
            .onAppear { openJump() }
        }
    }

    private var dayVisits: [Visit] { rangeVisits.sorted { $0.arrival < $1.arrival } }
    private func stopRow(_ v: Visit) -> some View {
        HStack(spacing: 12) {
            if showSymbols {
                Image(systemName: v.category.symbol).font(.subheadline).foregroundStyle(Theme.accent)
                    .frame(width: 30, height: 30).background(Theme.accent.opacity(0.14), in: .circle)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(v.placeName).font(.body)
                Text(stopRange(v)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
        }
    }
    private func stopRange(_ v: Visit) -> String {
        let f = DayActivityList.clock
        return "\(f.string(from: v.arrival)) – \(v.departure.map { f.string(from: $0) } ?? "now")"
    }
    // MARK: Day, Week / Month / Year pages

    private var photoItems: [(image: UIImage, date: Date, entry: JournalEntry)] {
        journal.filter { interval.contains($0.date) && $0.kind == .photo }
            .sorted { $0.date < $1.date }
            .compactMap { e in e.thumbnail.flatMap(UIImage.init(data:)).map { ($0, e.date, e) } }
    }
    /// The entry's saved place, else the visit closest to where the photo was taken.
    private func placeName(of entry: JournalEntry) -> String? {
        JournalGroup.placeName(for: entry, visits: visits)
    }
    private func photoCaption(_ entry: JournalEntry) -> String {
        let date = entry.date
        return switch range {
        case .day: [placeName(of: entry), DayActivityList.clock.string(from: date)].compactMap { $0 }.joined(separator: " · ")
        case .week: [date.formatted(.dateTime.weekday(.abbreviated)), placeName(of: entry)].compactMap { $0 }.joined(separator: " · ")
        case .month: [date.formatted(.dateTime.month(.abbreviated).day()), placeName(of: entry)].compactMap { $0 }.joined(separator: " · ")
        case .year: date.formatted(.dateTime.month(.wide))
        }
    }
    private func photoRow(width: CGFloat, height: CGFloat, captions: Bool) -> some View {
        let items = Array(photoItems.prefix(range == .day ? 20 : 12))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { k in
                    // Opens the photo's journal entry: full photo, place and time, and any words or voice note.
                    NavigationLink {
                        JournalEntryView(group: JournalGroup(entries: [items[k].entry], place: placeName(of: items[k].entry)))
                    } label: {
                    Image(uiImage: items[k].image).resizable().scaledToFill().frame(width: width, height: height)
                        .overlay(alignment: .bottomLeading) {
                            if captions {
                                Text(photoCaption(items[k].entry)).font(.caption.weight(.semibold)).foregroundStyle(.white)
                                    .lineLimit(1).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .clipShape(.rect(cornerRadius: 18))
                        .contentShape(.rect(cornerRadius: 18))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("timelinePhoto")
                }
            }
        }
    }
    private func stopList(_ list: [Visit]) -> some View {
        Card(padding: 0) {
            VStack(spacing: 0) {
                ForEach(Array(list.enumerated()), id: \.offset) { i, v in
                    stopRow(v).padding(.horizontal, 14).padding(.vertical, 10)
                    if i < list.count - 1 { Divider().padding(.leading, 56) }
                }
            }
        }
    }
    /// Day: map, title, captioned photos in a row, then stops grouped by part of day.
    @ViewBuilder private var dayPage: some View {
        mapCard(height: 170, hint: true)
        if !DemoData.isDemo && visits.isEmpty && samples.isEmpty && journal.isEmpty {
            ContentUnavailableView("No timeline yet", systemImage: "mappin.and.ellipse",
                                   description: Text("Your places and photos will appear here as Dayline learns your day."))
                .accessibilityIdentifier("timelineEmptyState")
        }
        Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
        photoRow(width: 150, height: 190, captions: true)
        let parts = [("Morning", 0, 12), ("Afternoon", 12, 17), ("Evening", 17, 24)]
        ForEach(parts.indices, id: \.self) { pi in
            let part = parts[pi]
            let list = dayVisits.filter { let h = Calendar.current.component(.hour, from: $0.arrival); return h >= part.1 && h < part.2 }
            if !list.isEmpty {
                Text(part.0).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 2)
                stopList(list)
            }
        }
    }
    /// Week / Month / Year: map, title, the range's photos in a row, then the places card.
    @ViewBuilder private var rangePage: some View {
        mapCard(height: 200, hint: false)
        if !DemoData.isDemo && visits.isEmpty && samples.isEmpty && journal.isEmpty {
            ContentUnavailableView("No timeline yet", systemImage: "mappin.and.ellipse",
                                   description: Text("Your places and photos will appear here as Dayline learns your day."))
                .accessibilityIdentifier("timelineEmptyState")
        }
        Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
        HStack(spacing: 6) {
            infoChip("\(placeCount)", "places"); infoChip(distanceText, "moved"); infoChip("\(photoItems.count)", "photos")
        }
        if !photoItems.isEmpty {
            photoRow(width: 150, height: 190, captions: true)
        }
        MostVisitedList(clusters: placeClusters)
    }

    /// A search result was tapped: show that day, and open the full map at that place.
    private func openJump() {
        guard let p = MapJump.pending else { return }
        MapJump.pending = nil
        range = .day
        anchor = p.date
        DispatchQueue.main.async {
            if let c = p.coordinate { camera = .camera(MapCamera(centerCoordinate: c, distance: 2500)) }
            expanded = true
        }
    }

    private var map: some View { mapView(interactive: true) }

    private func mapView(interactive: Bool, showsControls: Bool = true) -> some View {
        Map(position: $camera, interactionModes: interactive ? .all : []) {
            UserAnnotation()
            if showRoute {
                if range == .day && streetRoute.count > 1 {
                    MapPolyline(coordinates: streetRoute)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                } else if range == .day {
                    MapPolyline(coordinates: Self.thinned(rangeSamples, minutes: checkMinutes))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                } else {
                    // Every trip in the range as its own line (never joined across days), thinned so a year stays fast.
                    let segs = routeSegments
                    ForEach(segs.indices, id: \.self) { i in
                        MapPolyline(coordinates: segs[i])
                            .stroke(Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            if showPlaces && range == .day {
                ForEach(rangeVisits) { v in
                    Annotation("", coordinate: v.coordinate, anchor: .bottom) {
                        ApplePin(symbol: v.category.symbol, color: Theme.accent, big: false, dot: true)
                    }
                }
            } else if showPlaces {
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
                    Annotation("", coordinate: entry.coordinate!, anchor: .bottom) {
                        Button { openedEntry = entry } label: {
                            ApplePin(symbol: "doc.text.fill", color: Theme.accent, big: false, dot: true)
                        }
                        .buttonStyle(.plain).allowsHitTesting(interactive)
                        .accessibilityLabel("Journal entry").accessibilityIdentifier("mapJournalPin")
                    }
                }
            }
            if showPhotos { ForEach(rangePhotos.suffix(40)) { entry in
                Annotation("", coordinate: entry.coordinate!, anchor: .bottom) {
                    if let data = entry.thumbnail, let image = UIImage(data: data) {
                        Button { openedEntry = entry } label: {
                            ApplePhotoPin(image: image, big: false, dot: true)
                        }
                        .buttonStyle(.plain).allowsHitTesting(interactive)
                        .accessibilityLabel("Photo").accessibilityIdentifier("mapPhotoPin")
                    }
                }
            } }
        }
        .mapStyle((is3D || interactive) && !showsControls ? .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
                                         : .standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, SystemMapAppearance.scheme)
        .mapControls { MapCompass(); MapScaleView() }
        .mapControlVisibility(showsControls ? .automatic : .hidden)
        .onMapCameraChange(frequency: .onEnd) { context in
            region = context.region
            // Panned away from where you are: the arrow goes back to outline.
            if onMyLocation && myCoordinate == nil { myCoordinate = context.region.center }
            else if onMyLocation, let me = myCoordinate {
                let c = context.region.center
                if CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: CLLocation(latitude: me.latitude, longitude: me.longitude)) > 120 {
                    onMyLocation = false
                    userMovedMap = true
                }
            }
            // Two-finger tilt flips the 2D/3D label, like Apple Maps.
            if interactive { is3D = context.camera.pitch > 10 }
        }
        .task(id: "\(checkMinutes)-\(interval.start.timeIntervalSince1970)-\(range == .day)") { await buildStreetRoute() }
    }

    /// Default to a neighborhood-scale camera. Never substitute a guessed city for missing permission.
    private func centerOnCurrentLocation(force: Bool = false) {
        guard force || (!onMyLocation && !userMovedMap) else { return }
        if force { userMovedMap = false }
        guard let fix = location.lastLocation, fix.horizontalAccuracy >= 0,
              abs(fix.timestamp.timeIntervalSinceNow) < 15 * 60 else {
            // MapKit waits for an authorized live fix rather than framing an empty continent.
            camera = .userLocation(fallback: .automatic)
            return
        }
        myCoordinate = fix.coordinate
        camera = .camera(MapCamera(centerCoordinate: fix.coordinate, distance: 2200, heading: 0, pitch: 0))
        onMyLocation = true
    }

    /// One tap returns to the user's actual location, at neighborhood scale.
    private func recenterOnMe() { withAnimation(.snappy) { centerOnCurrentLocation(force: true) } }

    private func buildStreetRoute() async {
        guard range == .day else { streetRoute = []; return }
        // Only the points where you moved: checks during a stay are all the same spot.
        let pts = Self.moving(Self.thinned(rangeSamples, minutes: checkMinutes))
        guard pts.count > 1 else { streetRoute = []; return }
        var all: [CLLocationCoordinate2D] = []
        for (a, b) in zip(pts, pts.dropFirst()) {
            let r = MKDirections.Request()
            r.source = MKMapItem(placemark: MKPlacemark(coordinate: a))
            r.destination = MKMapItem(placemark: MKPlacemark(coordinate: b))
            r.transportType = .walking
            if let res = try? await MKDirections(request: r).calculate(), let poly = res.routes.first?.polyline {
                var seg = [CLLocationCoordinate2D](repeating: .init(), count: poly.pointCount)
                poly.getCoordinates(&seg, range: NSRange(location: 0, length: poly.pointCount))
                all += seg
            } else { all += [a, b] }
        }
        streetRoute = all
    }

    /// Drops points within 60 m of the last kept one (the checks while you stay somewhere).
    private static func moving(_ pts: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []
        for p in pts {
            if let last = out.last,
               CLLocation(latitude: last.latitude, longitude: last.longitude).distance(from: CLLocation(latitude: p.latitude, longitude: p.longitude)) < 60 { continue }
            out.append(p)
        }
        if let l = pts.last, let o = out.last, (o.latitude, o.longitude) != (l.latitude, l.longitude) { out.append(l) }
        return out
    }

    /// Week / month / year: the route split into separate trips. A new line starts after a long gap
    /// (overnight, or the phone was off) or a jump no one could make between two checks, so days are never
    /// joined with straight lines across the city.
    private var routeSegments: [[CLLocationCoordinate2D]] {
        let pts = rangeSamples.sorted { $0.timestamp < $1.timestamp }
        var segs: [[CLLocationCoordinate2D]] = [], cur: [CLLocationCoordinate2D] = []
        var last: LocationSample?
        for s in pts {
            if let l = last {
                let gap = s.timestamp.timeIntervalSince(l.timestamp)
                let meters = CLLocation(latitude: l.latitude, longitude: l.longitude).distance(from: CLLocation(latitude: s.latitude, longitude: s.longitude))
                // Over 40 min apart, or faster than ~40 km/h between checks (not a walk or a short ride).
                if gap > 40 * 60 || meters / max(gap, 1) > 11 {
                    if cur.count > 1 { segs.append(cur) }
                    cur = []
                }
            }
            cur.append(s.coordinate); last = s
        }
        if cur.count > 1 { segs.append(cur) }
        // The checks while you stay somewhere are all the same spot; keep only where you moved.
        segs = segs.map(Self.moving).filter { $0.count > 1 }
        // Keep a year fast: at most ~3000 points in total.
        let total = segs.reduce(0) { $0 + $1.count }
        guard total > 3000 else { return segs }
        let step = total / 3000 + 1
        return segs.map { seg in stride(from: 0, to: seg.count, by: step).map { seg[$0] } + [seg[seg.count - 1]] }
    }

    /// Keep one sample per check (at least `minutes` apart), like the phone would record at that rate.
    private static func thinned(_ samples: [LocationSample], minutes: Int) -> [CLLocationCoordinate2D] {
        var out: [LocationSample] = []
        for s in samples.sorted(by: { $0.timestamp < $1.timestamp }) {
            if let last = out.last, s.timestamp.timeIntervalSince(last.timestamp) < Double(minutes) * 60 - 5 { continue }
            out.append(s)
        }
        if let last = samples.max(by: { $0.timestamp < $1.timestamp }), out.last?.timestamp != last.timestamp { out.append(last) }
        return out.map(\.coordinate)
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
                    Image(systemName: "arrow.up.left.and.arrow.down.right").font(.scaled(size: 13, weight: .bold))
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
            // Like Apple Maps: the Maps logo and Legal sit just above the bottom panel (not under it), and the map
            // frames your places in the space above the panel.
            .safeAreaPadding(.bottom, Self.panelTop + 8)
            .ignoresSafeArea()
            .sheet(item: $openedEntry) { entry in
                NavigationStack {
                    JournalEntryView(group: JournalGroup(entries: [entry],
                                                         place: placeName(of: entry)))
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done", systemImage: "xmark") { openedEntry = nil }
                                    .accessibilityIdentifier("closeEntry")
                            }
                        }
                }
            }
            .overlay(alignment: .top) {
                HStack {
                    Button { expanded = false } label: {
                        Image(systemName: "chevron.left").font(.scaled(size: 18, weight: .semibold))
                            .foregroundStyle(.primary).frame(width: 44, height: 44)
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
                            // Like Apple Maps, a 2D/3D button sits on top of the location button in one glass capsule.
                            // The location button always goes to your current location.
                            VStack(spacing: 0) {
                                Button { withAnimation(.smooth(duration: 0.8)) { set3D(!is3D) } } label: {
                                    // Shows the current mode; each tap switches 2D <-> 3D.
                                    Text(is3D ? "3D" : "2D").font(.headline)
                                        .foregroundStyle(.primary).frame(width: 54, height: 58).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(is3D ? "Show 2D map" : "Show 3D map")
                                .accessibilityIdentifier("toggle3D")
                                Button { recenterOnMe() } label: {
                                    // Filled = the map is centered on you; outline as soon as you pan away. Not a follow mode.
                                    Image(systemName: onMyLocation ? "location.fill" : "location")
                                        .font(.title3)
                                        .foregroundStyle(.primary).frame(width: 54, height: 58).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show my location")
                                .accessibilityIdentifier("locateMe")
                            }
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                    }
                }
                // Same 16pt gap above the panel as from the right edge.
                .padding(.trailing, 16).padding(.bottom, 16 + Self.panelTop - Self.homeInset)
            }
            .overlay(alignment: .bottom) {
                backSheet.ignoresSafeArea(.container, edges: .bottom)
            }
    }

    /// Find My style panel: one bigger glass panel sits behind the range bar. Closed, only its thin
    /// outline and grabber show around the bar; pulled up, the same panel grows and the switches come out
    /// from behind the bar. The bar itself never moves.
    /// iPhone screen corner radius (iPhone 16/17 Pro class), the panel's inset from the edges, and the closed
    /// panel's top measured from the bottom of the screen (bar 48 + 14 above and below + inset).
    private static let screenCorner: CGFloat = 55
    private static let panelInset: CGFloat = 8
    private static let panelTop: CGFloat = 48 + 28 + panelInset
    private static let homeInset: CGFloat = 34

    private var backSheet: some View {
        // Concentric with the screen corners, 8pt in from the edges like Apple Maps' panel.
        let shape = RoundedRectangle(cornerRadius: Self.screenCorner - Self.panelInset, style: .continuous)
        return VStack(spacing: 0) {
            if sheetOpen {
                Color.clear.frame(height: 24)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map").font(.largeTitle.weight(.bold))
                        Text("\(title) · \(daySummary)").font(.subheadline).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    VStack(spacing: 0) {
                        findMyRow("Journal", rowSubtitle(.notes), $showJournal)
                        Divider().padding(.leading, 20)
                        findMyRow("Photos", rowSubtitle(.photos), $showPhotos)
                        Divider().padding(.leading, 20)
                        findMyRow("Route", rowSubtitle(.route), $showRoute)
                        Divider().padding(.leading, 20)
                        findMyRow("Places", rowSubtitle(.places), $showPlaces)
                    }
                    .findMyCard()
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Slides up from behind the bar, inside the panel's clip.
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) })
                // Same gap on all sides, like Apple Maps: the bar sits centered in the closed panel.
                .padding(.horizontal, 12).padding(.top, sheetOpen ? 0 : 14).padding(.bottom, 14)
                .zIndex(1)
        }
        .overlay(alignment: .top) {
            // Grabber lives in the panel's top gap, so it takes no extra height.
            Capsule().fill(Color.secondary.opacity(0.55)).frame(width: 38, height: 5)
                .padding(.top, 5)
                .frame(width: 140, height: 22, alignment: .top).contentShape(.rect)
                .onTapGesture { withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) { sheetOpen.toggle() } }
                .accessibilityIdentifier("mapGrabber")
        }
        .clipShape(shape)
        .glassEffect(.regular, in: shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.45), lineWidth: 0.8))
        .overlay(shape.strokeBorder(Color.black.opacity(0.08), lineWidth: 0.5).padding(-0.5))
        .padding(.horizontal, Self.panelInset).padding(.bottom, Self.panelInset)
        .gesture(DragGesture(minimumDistance: 12).onEnded { g in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                if g.translation.height < -30 { sheetOpen = true } else if g.translation.height > 30 { sheetOpen = false }
            }
        })
    }


    private func findMyRow(_ title: String, _ detail: String?, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle(title, isOn: on).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, detail == nil ? 16 : 13)
        .accessibilityIdentifier("layer\(title)")
    }


    /// Tilts the camera over the day's places (3D) or flattens it back (2D).
    private func set3D(_ on: Bool) {
        is3D = on
        let pts = rangeVisits.map(\.coordinate)
        guard !pts.isEmpty else { return }
        let lat = pts.map(\.latitude), lon = pts.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lat.min()! + lat.max()!) / 2, longitude: (lon.min()! + lon.max()!) / 2)
        let spanM = max((lat.max()! - lat.min()!) * 111_000, (lon.max()! - lon.min()!) * 85_000, 600)
        camera = on ? .camera(MapCamera(centerCoordinate: center, distance: spanM * 2.6, heading: 30, pitch: 60))
                    : .automatic
    }


    private func infoChip(_ value: String, _ label: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value).font(.footnote.bold())
            Text(label).font(.footnote).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 11).padding(.vertical, 6)
        .glassEffect(.regular, in: .capsule)
    }


    private var placeCount: Int { Set(rangeVisits.filter { $0.category != .home }.map(\.placeKey)).count }
    private var meters: Double {
        zip(rangeSamples, rangeSamples.dropFirst()).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        }
    }
    private enum RowKind { case notes, photos, route, places }
    private func rowSubtitle(_ kind: RowKind) -> String {
        switch kind {
        case .notes: "Shows where you journaled"
        case .photos: "Shows your photos on the map"
        case .route: "Shows the way you went"
        case .places: "Shows the places you spent time"
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
            // Real Liquid Glass bar, same material as the chips below.
            CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) })
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

    private var daySummary: String {
        let places = Set(rangeVisits.filter { $0.category != .home }.map(\.placeKey)).count
        let km = zip(rangeSamples, rangeSamples.dropFirst()).reduce(0.0) { total, pair in
            total + CLLocation(latitude: pair.0.latitude, longitude: pair.0.longitude)
                .distance(from: CLLocation(latitude: pair.1.latitude, longitude: pair.1.longitude))
        } / 1000
        _ = km
        return "\(places) place\(places == 1 ? "" : "s") · \(distanceText)"
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
        // One place saved as two nearby spots shows once: same name AND within about 150 m.
        // Two different places with the same name (two Starbucks) stay separate.
        var groups: [[Visit]] = []
        for v in rangeVisits.filter({ $0.category != .home }) {
            let here = CLLocation(latitude: v.coordinate.latitude, longitude: v.coordinate.longitude)
            if let g = groups.firstIndex(where: { g in
                g[0].placeName.caseInsensitiveCompare(v.placeName) == .orderedSame &&
                CLLocation(latitude: g[0].coordinate.latitude, longitude: g[0].coordinate.longitude).distance(from: here) <= 150
            }) {
                groups[g].append(v)
            } else {
                groups.append([v])
            }
        }
        return groups.map { stays in
            let first = stays[0]
            return Cluster(key: first.placeKey, name: first.placeName, coordinate: first.coordinate, hours: stays.reduce(0) { $0 + $1.duration } / 3600,
                           visits: stays.count, category: first.category)
        }
    }
}

/// Vertical list of places with times, photos and voice notes for one day.
let TimelineClock: DateFormatter = { let f = DateFormatter(); f.dateFormat = "h:mm"; return f }()

/// Plain "Most visited" list for week / month / year: no card behind it.
struct MostVisitedList: View {
    var clusters: [TimelineScreen.Cluster]
    /// Preview flag "visited.icon" (David picks, Sep 24): "tile" = blue tile (default, now);
    /// A = no icon; B = bold blue symbol, no tile; C = blue symbol in a light round circle (Maps style).
    /// Global "Show Symbols" (Profile > Look). On = C (round tint), off = no symbol (option A).
    @AppStorage("symbols.show") private var showSymbols = true
    @ViewBuilder private func icon(_ c: TimelineScreen.Cluster) -> some View {
        if showSymbols {
            Image(systemName: c.category.symbol).font(.subheadline).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34).background(Theme.accent.opacity(0.14), in: .circle)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Most visited").font(.subheadline.weight(.semibold)).helperText()
                .padding(.horizontal, 4).padding(.top, 8).padding(.bottom, 2)
            let top = Array(clusters.sorted { $0.hours > $1.hours }.prefix(6))
            if top.isEmpty {
                Text("No places in this period yet.").font(.subheadline).foregroundStyle(.secondary).padding(4)
            }
            ForEach(Array(top.enumerated()), id: \.element.key) { i, c in
                if i > 0 { Divider().padding(.leading, showSymbols ? 50 : 4) }
                HStack(spacing: 12) {
                    icon(c)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(c.name).font(.body).lineLimit(1)
                        Text("\(c.visits) visit\(c.visits == 1 ? "" : "s")").font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(c.hours >= 1 ? "\(Int(c.hours.rounded()))h" : "\(Int(c.hours * 60)) min").font(.body).monospacedDigit().foregroundStyle(.secondary)
                }
                .padding(.vertical, 10).padding(.horizontal, 4)
            }
        }
    }
}


private extension View {
    /// Rounded translucent card like the groups in Find My's sheet.
    func findMyCard() -> some View {
        glassEffect(.regular.tint(Color.white.opacity(0.06)), in: .rect(cornerRadius: 26, style: .continuous))
    }
}
