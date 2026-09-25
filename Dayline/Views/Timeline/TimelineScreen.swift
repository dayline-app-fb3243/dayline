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
    /// Preview flag "route.style" (awaiting David's pick): now = straight lines between points,
    /// snap = path snapped to streets with Apple directions, gps = precise GPS-style track.
    @AppStorage("route.style") private var routeStyle = "snap"
    /// Route detail follows the Check Location setting: one point per check, snapped to streets.
    @AppStorage(LocationService.intervalKey) private var checkMinutes = 5
    @State private var streetRoute: [CLLocationCoordinate2D] = []
    /// Preview flag "map.3d" (awaiting David's pick): the full-screen map opens tilted in 3D with real buildings,
    /// and gets a 2D/3D button. The route is drawn into the map, so it tilts with it.
    @AppStorage("map.3d") private var map3DFlag = true
    @State private var is3D = false
    /// The map is centered on your current location (filled arrow). Cleared when you pan away.
    @State private var onMyLocation = false
    @State private var myCoordinate: CLLocationCoordinate2D?
    /// Preview flag "pin.style" (awaiting David's pick): "" = current pins, A = big Apple pin with dot,
    /// B = compact Apple pin with tail, C = native Apple Maps marker.
    @AppStorage("pin.style") private var pinStyle = "D"
    /// "map.sheet": G (default; option F in the preview sheets) = Apple Maps style outline panel with the Day/Week/Month/Year pill
    /// centered inside; pulling up grows only the outline, with the F glass card inside.
    /// A = Find My card, B = Settings-style icons, C = compact (older options).
    @AppStorage("map.sheet") private var mapSheet = "G"
    /// Preview flag "map.grabber": where the grabber sits so the range words stay centered.
    /// A = grabber drawn over the top edge (takes no space), B = grabber just above the bar, C = even space above and below the words.
    @AppStorage("map.grabber") private var grabber = "C"
    @AppStorage("map.sheetRows") private var sheetRows = "F"
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
                    if range == .day && !tlPage.isEmpty {
                        dayPageSample
                    } else if range == .day {
                        // Day: small map on top (tap for full screen), then one photo card per stop.
                        mapCard(height: 150, hint: true)
                        Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
                        HStack(spacing: 6) {
                            infoChip("\(placeCount)", "places")
                            infoChip(distanceText, "moved")
                            infoChip("\(rangePhotos.count)", "photos")
                        }
                        DayPhotoCards(visits: rangeVisits, journal: journal.filter { interval.contains($0.date) })
                    } else if tlPage.hasPrefix("4") {
                        rangePage4
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
            .tabRoot()
            .fullScreenCover(isPresented: $expanded) {
                fullMap
                    .onDisappear { is3D = false; onMyLocation = false; camera = .automatic }
            }
            .onChange(of: range) { onMyLocation = false; camera = .automatic }
            .onChange(of: anchor) { onMyLocation = false; camera = .automatic }
            .onReceive(NotificationCenter.default.publisher(for: .showOnMap)) { _ in openJump() }
            .onAppear { openJump() }
        }
    }

    /// Preview "timeline.page" 1-5: Day view layouts ("" = the current one). Sample-only until one is picked.
    /// 1 = big map with the numbers on it. 2 = a line through the day with a pin per stop and photos inline.
    /// 3 = numbers first as big tiles, then map and cards. 4 = photos in a side-scrolling row, stops listed below.
    /// 5 = map, then stops grouped into Morning / Afternoon / Evening.
    /// 4a-4c = more takes on 4: a = place and time on each photo, b = numbers row and square photos,
    /// c = captioned photos with stops grouped by part of day. With any 4 sample, Week / Month / Year use the same style.
    @AppStorage("timeline.page") private var tlPage = ""
    private var dayVisits: [Visit] { rangeVisits.sorted { $0.arrival < $1.arrival } }
    private func photos(for v: Visit) -> [UIImage] {
        let end = v.departure ?? .now
        return journal.filter { $0.kind == .photo && $0.date >= v.arrival && $0.date <= end }
            .compactMap { $0.thumbnail.flatMap(UIImage.init(data:)) }
    }
    private func stopRow(_ v: Visit) -> some View {
        HStack(spacing: 12) {
            Image(systemName: v.category.symbol).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 30, height: 30).background(Theme.accent.opacity(0.14), in: .circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(v.placeName).font(.body.weight(.semibold))
                Text(stopRange(v)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            }
            Spacer()
        }
    }
    private func stopRange(_ v: Visit) -> String {
        let f = DayActivityList.clock
        return "\(f.string(from: v.arrival)) – \(v.departure.map { f.string(from: $0) } ?? "now")"
    }
    private func bigTile(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title2.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 12)
        .background(.background, in: .rect(cornerRadius: 18, style: .continuous))
    }
    @ViewBuilder private var dayPageSample: some View {
        switch tlPage {
        case "1":
            mapCard(height: 320, hint: true)
                .overlay(alignment: .bottom) {
                    GlassEffectContainer(spacing: 6) {
                        HStack(spacing: 6) {
                            glassChip("\(placeCount)", "places"); glassChip(distanceText, "moved"); glassChip("\(rangePhotos.count)", "photos")
                        }
                    }
                    .padding(10)
                }
            Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
            DayPhotoCards(visits: rangeVisits, journal: journal.filter { interval.contains($0.date) })
        case "2":
            mapCard(height: 150, hint: true)
            Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
            Card(padding: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(dayVisits.enumerated()), id: \.offset) { i, v in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(spacing: 0) {
                                Rectangle().fill(i == 0 ? .clear : Theme.accent.opacity(0.35)).frame(width: 2, height: 10)
                                Image(systemName: v.category.symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                                    .frame(width: 28, height: 28).background(Theme.accent, in: .circle)
                                Rectangle().fill(i == dayVisits.count - 1 ? .clear : Theme.accent.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text(v.placeName).font(.body.weight(.semibold)).padding(.top, 12)
                                Text(stopRange(v)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                                let pics = photos(for: v)
                                if !pics.isEmpty {
                                    HStack(spacing: 6) {
                                        ForEach(pics.indices.prefix(3), id: \.self) { k in
                                            Image(uiImage: pics[k]).resizable().scaledToFill().frame(width: 72, height: 72).clipShape(.rect(cornerRadius: 10))
                                        }
                                    }
                                }
                            }
                            .padding(.bottom, 12)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                    }
                }
            }
        case "3":
            HStack(spacing: 8) {
                bigTile("\(placeCount)", "places"); bigTile(distanceText, "moved"); bigTile("\(rangePhotos.count)", "photos")
            }
            mapCard(height: 180, hint: true)
            DayPhotoCards(visits: rangeVisits, journal: journal.filter { interval.contains($0.date) })
        case "4", "4a", "4b", "4c":
            day4
        default:
            mapCard(height: 170, hint: true)
            let parts = [("Morning", 0, 12), ("Afternoon", 12, 17), ("Evening", 17, 24)]
            ForEach(parts.indices, id: \.self) { pi in
                let part = parts[pi]
                let list = dayVisits.filter { let h = Calendar.current.component(.hour, from: $0.arrival); return h >= part.1 && h < part.2 }
                if !list.isEmpty {
                    Text(part.0).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 4)
                    Card(padding: 0) {
                        VStack(spacing: 0) {
                            ForEach(Array(list.enumerated()), id: \.offset) { i, v in
                                stopRow(v).padding(.horizontal, 14).padding(.vertical, 10)
                                if i < list.count - 1 { Divider().padding(.leading, 56) }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Timeline sample 4 and its variants (Day), plus Week / Month / Year in the same style

    private var photoItems: [(image: UIImage, date: Date)] {
        journal.filter { interval.contains($0.date) && $0.kind == .photo }
            .sorted { $0.date < $1.date }
            .compactMap { e in e.thumbnail.flatMap(UIImage.init(data:)).map { ($0, e.date) } }
    }
    private func placeName(at date: Date) -> String? {
        visits.first { date >= $0.arrival && date <= ($0.departure ?? .now) }?.placeName
    }
    private func photoCaption(_ date: Date) -> String {
        switch range {
        case .day: [placeName(at: date), DayActivityList.clock.string(from: date)].compactMap { $0 }.joined(separator: " · ")
        case .week: [date.formatted(.dateTime.weekday(.abbreviated)), placeName(at: date)].compactMap { $0 }.joined(separator: " · ")
        case .month: [date.formatted(.dateTime.month(.abbreviated).day()), placeName(at: date)].compactMap { $0 }.joined(separator: " · ")
        case .year: date.formatted(.dateTime.month(.wide))
        }
    }
    private func photoRow(width: CGFloat, height: CGFloat, captions: Bool) -> some View {
        let items = Array(photoItems.prefix(range == .day ? 20 : 12))
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(items.indices, id: \.self) { k in
                    Image(uiImage: items[k].image).resizable().scaledToFill().frame(width: width, height: height)
                        .overlay(alignment: .bottomLeading) {
                            if captions {
                                Text(photoCaption(items[k].date)).font(.caption.weight(.semibold)).foregroundStyle(.white)
                                    .lineLimit(1).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                            }
                        }
                        .clipShape(.rect(cornerRadius: 18))
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
    private var numbersRow: some View {
        HStack(spacing: 6) {
            infoChip("\(placeCount)", "places"); infoChip(distanceText, "moved"); infoChip("\(photoItems.count)", "photos")
        }
    }
    @ViewBuilder private var day4: some View {
        mapCard(height: 170, hint: true)
        Text(title).font(.title2.bold()).padding(.horizontal, 2).padding(.top, 4)
        switch tlPage {
        case "4a":
            photoRow(width: 170, height: 210, captions: true)
            stopList(dayVisits)
        case "4b":
            numbersRow
            photoRow(width: 120, height: 120, captions: false)
            stopList(dayVisits)
        case "4c":
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
        default:
            photoRow(width: 150, height: 190, captions: false)
            stopList(dayVisits)
        }
    }
    /// Week / Month / Year when a sample-4 page is on: map, title, the range's photos in a row, then the places card.
    @ViewBuilder private var rangePage4: some View {
        mapCard(height: 200, hint: false)
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
                if range == .day && routeStyle != "now" && streetRoute.count > 1 {
                    MapPolyline(coordinates: streetRoute)
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: routeStyle == "gps" ? 3.5 : 5, lineCap: .round, lineJoin: .round))
                } else if range == .day {
                    MapPolyline(coordinates: Self.thinned(rangeSamples, minutes: checkMinutes))
                        .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                } else {
                    // Every trip in the range as its own line (never joined across days), thinned so a year stays fast.
                    let segs = routeSegments
                    ForEach(segs.indices, id: \.self) { i in
                        MapPolyline(coordinates: segs[i])
                            // Preview flag "route.blue": every route line the same solid theme blue.
                            .stroke(UserDefaults.standard.bool(forKey: "route.blue") ? Theme.accent : Theme.accent.opacity(0.45), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            if range == .day {
                ForEach(rangeVisits) { v in
                    if pinStyle == "C" {
                        Marker("", systemImage: v.category.symbol, coordinate: v.coordinate).tint(v.category.pinColor)
                    } else if !pinStyle.isEmpty {
                        Annotation("", coordinate: v.coordinate, anchor: .bottom) {
                            ApplePin(symbol: v.category.symbol, color: pinStyle == "D" ? Theme.accent : v.category.pinColor, big: pinStyle == "A", dot: pinStyle == "D" ? true : nil)
                        }
                    } else {
                    Annotation("", coordinate: v.coordinate) {
                        Image(systemName: v.category.symbol).font(.scaled(size: 13, weight: .bold)).foregroundStyle(Theme.accent)
                            .markerBackground(Color.white, size: 32, isMapPin: true).shadow(color: .black.opacity(0.2), radius: 5, y: 2)
                    }
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
                    if pinStyle == "C" {
                        Marker("", systemImage: "book.closed.fill", coordinate: entry.coordinate!).tint(.purple)
                    } else if !pinStyle.isEmpty {
                        Annotation("", coordinate: entry.coordinate!, anchor: .bottom) {
                            ApplePin(symbol: pinStyle == "D" ? "doc.text.fill" : "book.closed.fill", color: pinStyle == "D" ? Theme.accent : .purple, big: pinStyle == "A", dot: pinStyle == "D" ? true : nil)
                        }
                    } else {
                    Annotation("", coordinate: entry.coordinate!) {
                        Image(systemName: "pencil")
                            .font(.caption.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 34, height: 34).background(Theme.accent, in: .circle)
                            .overlay(Circle().stroke(.white, lineWidth: 3)).shadow(radius: 4)
                    }
                    }
                }
            }
            if showPhotos { ForEach(rangePhotos.suffix(40)) { entry in
                if pinStyle == "C" {
                    Marker("", systemImage: "photo.fill", coordinate: entry.coordinate!).tint(.teal)
                } else if !pinStyle.isEmpty {
                    Annotation("", coordinate: entry.coordinate!, anchor: .bottom) {
                        if let data = entry.thumbnail, let image = UIImage(data: data) {
                            ApplePhotoPin(image: image, big: pinStyle == "A", dot: pinStyle == "D" ? true : nil)
                        }
                    }
                } else {
                Annotation("", coordinate: entry.coordinate!) {
                    if let data = entry.thumbnail, let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill().frame(width: 48, height: 48)
                            .clipShape(.rect(cornerRadius: 14)).overlay(RoundedRectangle(cornerRadius: 14).stroke(.white, lineWidth: 3)).shadow(color: .black.opacity(0.25), radius: 6, y: 3)
                    }
                }
                }
            } }
        }
        .mapStyle((is3D || (map3DFlag && interactive)) && !showsControls ? .standard(elevation: .realistic, pointsOfInterest: .excludingAll)
                                         : .standard(emphasis: .muted, pointsOfInterest: .excludingAll))
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
                }
            }
            // Two-finger tilt flips the 2D/3D label, like Apple Maps.
            if interactive && map3DFlag { is3D = context.camera.pitch > 10 }
        }
        .task(id: "\(routeStyle)-\(checkMinutes)-\(interval.start.timeIntervalSince1970)-\(range == .day)") { await buildStreetRoute() }
    }

    /// Location keeps being recorded in the background either way; this only moves the map.
    /// One tap = center on where you are now (no following, no heading).
    private func recenterOnMe() {
        guard let me = LocationService.shared.lastLocation?.coordinate else {
            // No fix cached yet: let MapKit find you, and remember where it centered (first camera stop).
            myCoordinate = nil
            withAnimation(.snappy) { camera = .userLocation(fallback: .automatic) }
            onMyLocation = true
            return
        }
        myCoordinate = me
        let distance = max(800, min(4000, (region?.span.latitudeDelta ?? 0.02) * 111_000))
        withAnimation(.snappy) { camera = .camera(MapCamera(centerCoordinate: me, distance: distance, heading: 0, pitch: is3D ? 60 : 0)) }
        onMyLocation = true
    }

    private func buildStreetRoute() async {
        guard routeStyle != "now", range == .day else { streetRoute = []; return }
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
        if routeStyle == "gps" { all = Self.gpsTrack(all) }
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

    /// Densify every ~12 m and add a few meters of wobble, like a real GPS track.
    private static func gpsTrack(_ route: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var out: [CLLocationCoordinate2D] = []; var seed: UInt64 = 42
        func rnd() -> Double { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Double(seed >> 33) / Double(1 << 31) - 0.5 }
        for (a, b) in zip(route, route.dropFirst()) {
            let d = CLLocation(latitude: a.latitude, longitude: a.longitude).distance(from: CLLocation(latitude: b.latitude, longitude: b.longitude))
            let n = max(1, Int(d / 12))
            for i in 0..<n {
                let t = Double(i) / Double(n)
                let j = 0.00004 // about 4 m
                out.append(.init(latitude: a.latitude + (b.latitude - a.latitude) * t + rnd() * j,
                                 longitude: a.longitude + (b.longitude - a.longitude) * t + rnd() * j))
            }
        }
        if let last = route.last { out.append(last) }
        return out
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
            .ignoresSafeArea()
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
                        if mapSheet.isEmpty {
                        VStack(spacing: 0) {
                            mapToggle("Route", "point.topleft.down.to.point.bottomright.curvepath", $showRoute)
                            mapToggle("Photos", "photo", $showPhotos)
                            mapToggle("Journal", "doc.text", $showJournal)
                        }
                        .padding(4)
                        .glassEffect(.regular, in: .capsule)
                        }
                        if map3DFlag {
                            // map.3d: like Apple Maps, a 2D/3D button sits on top of the location button in one glass capsule.
                            // The location button always goes to your current location.
                            VStack(spacing: 0) {
                                Button { withAnimation(.smooth(duration: 0.8)) { set3D(!is3D) } } label: {
                                    // Shows the current mode; each tap switches 2D <-> 3D.
                                    Text(is3D ? "3D" : "2D").font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(.primary).frame(width: 54, height: 58).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(is3D ? "Show 2D map" : "Show 3D map")
                                .accessibilityIdentifier("toggle3D")
                                Button { recenterOnMe() } label: {
                                    // Filled = the map is centered on you; outline as soon as you pan away. Not a follow mode.
                                    Image(systemName: onMyLocation ? "location.fill" : "location")
                                        .font(.system(size: 20, weight: .semibold))
                                        .foregroundStyle(.primary).frame(width: 54, height: 58).contentShape(.rect)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Show my location")
                                .accessibilityIdentifier("locateMe")
                            }
                            .padding(.vertical, 6)
                            .glassEffect(.regular, in: .capsule)
                        } else {
                        Button { recenterOnMe() } label: {
                            Image(systemName: onMyLocation ? "location.fill" : "location").font(.scaled(size: 20, weight: .semibold))
                                .foregroundStyle(.primary).frame(width: 64, height: 64)
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .accessibilityLabel("Show my location")
                        .accessibilityIdentifier("locateMe")
                        }
                    }
                }
                // Clear space above the range bar / the taller Find My style panel.
                .padding(.trailing, 16).padding(.bottom, mapSheet == "G" ? 112 : 92)
            }
            .overlay(alignment: .bottom) {
                if mapSheet.isEmpty {
                CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) }, plain: true)
                    .padding(4)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.horizontal, 16).padding(.bottom, 6)
                } else if mapSheet == "G" {
                    backSheet
                } else {
                    pullUpBar
                }
            }
    }

    /// map.sheet "G" (Find My style): one bigger glass panel sits behind the range bar. Closed, only its thin
    /// outline and grabber show around the bar; pulled up, the same panel grows and the switches come out
    /// from behind the bar. The bar itself never moves.
    private var backSheet: some View {
        let shape = RoundedRectangle(cornerRadius: sheetOpen ? 38 : 44, style: .continuous)
        return VStack(spacing: 0) {
            if sheetOpen {
                Color.clear.frame(height: 24)
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map").font(.largeTitle.weight(.bold))
                        Text("\(title) · \(daySummary)").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 20)
                    // Preview flag "map.sheetRows" inside panel G: D = one card, E = separate cards with a line, F = one card with a line.
                    if sheetRows == "E" {
                        VStack(spacing: 10) {
                            findMyRow("Journal", rowSubtitle(.notes), $showJournal).findMyCard(glass: true)
                            findMyRow("Photos", rowSubtitle(.photos), $showPhotos).findMyCard(glass: true)
                            findMyRow("Route", rowSubtitle(.route), $showRoute).findMyCard(glass: true)
                        }
                        .padding(.horizontal, 12)
                    } else {
                        VStack(spacing: 0) {
                            findMyRow("Journal", sheetRows == "F" ? rowSubtitle(.notes) : nil, $showJournal)
                            Divider().padding(.leading, 20)
                            findMyRow("Photos", sheetRows == "F" ? rowSubtitle(.photos) : nil, $showPhotos)
                            Divider().padding(.leading, 20)
                            findMyRow("Route", sheetRows == "F" ? rowSubtitle(.route) : nil, $showRoute)
                        }
                        .findMyCard(glass: true)
                        .padding(.horizontal, 12)
                    }
                }
                .padding(.bottom, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                // Slides up from behind the bar, inside the panel's clip.
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) }, plain: true)
                .padding(.horizontal, 4).padding(.vertical, 6)
                .glassEffect(.regular, in: .capsule)
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
        .padding(.horizontal, 8).padding(.bottom, 2)
        .gesture(DragGesture(minimumDistance: 12).onEnded { g in
            withAnimation(.spring(response: 0.5, dampingFraction: 0.86)) {
                if g.translation.height < -30 { sheetOpen = true } else if g.translation.height > 30 { sheetOpen = false }
            }
        })
    }

    /// Range bar with a grabber; pull up (or tap the grabber) to show the map layer switches, like Find My.
    private var pullUpBar: some View {
        VStack(spacing: 0) {
            if grabber.isEmpty || sheetOpen {
            Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 36, height: 5)
                .padding(.top, 7).padding(.bottom, sheetOpen ? 10 : 2)
                .frame(maxWidth: .infinity).contentShape(.rect)
                .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { sheetOpen.toggle() } }
                .accessibilityIdentifier("mapGrabber")
            }
            if sheetOpen && ["D", "E", "F"].contains(mapSheet) {
                // D/E/F: more like the Find My "Me" sheet. D = big title + summary, one card, taller bold rows.
                // E = D with each switch in its own card and a short line under it. F = D with a line under each row, one card.
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Map").font(.largeTitle.weight(.bold))
                        Text("\(title) · \(daySummary)").font(.body.weight(.medium)).foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    if mapSheet == "E" {
                        VStack(spacing: 12) {
                            findMyRow("Journal", rowSubtitle(.notes), $showJournal).findMyCard()
                            findMyRow("Photos", rowSubtitle(.photos), $showPhotos).findMyCard()
                            findMyRow("Route", rowSubtitle(.route), $showRoute).findMyCard()
                        }
                        .padding(.horizontal, 16)
                    } else {
                        VStack(spacing: 0) {
                            findMyRow("Journal", mapSheet == "F" ? rowSubtitle(.notes) : nil, $showJournal)
                            Divider().padding(.leading, 20)
                            findMyRow("Photos", mapSheet == "F" ? rowSubtitle(.photos) : nil, $showPhotos)
                            Divider().padding(.leading, 20)
                            findMyRow("Route", mapSheet == "F" ? rowSubtitle(.route) : nil, $showRoute)
                        }
                        .findMyCard()
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 4).padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if sheetOpen {
                VStack(alignment: .leading, spacing: mapSheet == "C" ? 8 : 14) {
                    if mapSheet != "C" {
                        Text("Show on Map").font(.title2.weight(.bold)).padding(.horizontal, 20)
                    }
                    VStack(spacing: 0) {
                        layerRow("Journal", "book.closed.fill", $showJournal)
                        Divider().padding(.leading, mapSheet == "A" ? 20 : 58)
                        layerRow("Photos", "photo.fill", $showPhotos)
                        Divider().padding(.leading, mapSheet == "A" ? 20 : 58)
                        layerRow("Route", "point.topleft.down.to.point.bottomright.curvepath", $showRoute)
                    }
                    .background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 22))
                    .padding(.horizontal, 12)
                }
                .padding(.bottom, 12)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) }, plain: true)
                .padding(.horizontal, 4)
                .padding(.top, !grabber.isEmpty && !sheetOpen ? (grabber == "C" ? 12 : 4) : 0)
                .padding(.bottom, grabber == "C" && !sheetOpen ? 12 : 4)
        }
        .overlay(alignment: .top) {
            if !grabber.isEmpty && !sheetOpen {
                Capsule().fill(Color.secondary.opacity(0.5)).frame(width: 36, height: 5)
                    .padding(.top, grabber == "A" ? 3 : (grabber == "C" ? 6 : 0))
                    .offset(y: grabber == "B" ? -12 : 0)
                    .frame(width: 120, height: 20, alignment: .top).contentShape(.rect)
                    .onTapGesture { withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { sheetOpen.toggle() } }
                    .accessibilityIdentifier("mapGrabber")
            }
        }
        .glassEffect(.regular, in: .rect(cornerRadius: sheetOpen ? 34 : 30))
        .padding(.horizontal, 12).padding(.bottom, 6)
        .gesture(DragGesture(minimumDistance: 12).onEnded { g in
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                if g.translation.height < -30 { sheetOpen = true } else if g.translation.height > 30 { sheetOpen = false }
            }
        })
    }

    private func findMyRow(_ title: String, _ detail: String?, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                if let detail { Text(detail).font(.subheadline).foregroundStyle(.secondary) }
            }
            Spacer()
            Toggle(title, isOn: on).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, 20).padding(.vertical, detail == nil ? 16 : 13)
        .accessibilityIdentifier("layer\(title)")
    }

    private func layerRow(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            if mapSheet == "B" || mapSheet == "C" {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(Theme.accent, in: .rect(cornerRadius: 8))
            }
            Text(title).font(.body)
            Spacer()
            Toggle(title, isOn: on).labelsHidden().tint(Theme.accent)
        }
        .padding(.horizontal, mapSheet == "A" ? 20 : 14).padding(.vertical, 10)
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

    private func mapToggle(_ title: String, _ symbol: String, _ on: Binding<Bool>) -> some View {
        Button { withAnimation(.snappy) { on.wrappedValue.toggle() } } label: {
            Image(systemName: symbol).font(.scaled(size: 19, weight: .semibold))
                // Preview flag "toggle.black": off = black like the tab bar, on = blue.
                .foregroundStyle(on.wrappedValue ? Theme.accent : (UserDefaults.standard.bool(forKey: "toggle.black") ? Color.primary : Color.secondary))
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
    /// Preview flag "map.subtitles" (gray line under Journal / Photos / Route), awaiting David's pick:
    /// B (default) = the same words for every range ("Shows where you journaled"), A = follows the range ("Where you journaled this month"),
    /// C = what's in the range ("4 entries this month"). "" = the old words that always said "today".
    @AppStorage("map.subtitles") private var subtitleStyle = "B"
    private enum RowKind { case notes, photos, route }
    private func rowSubtitle(_ kind: RowKind) -> String {
        let when = switch range { case .day: "today"; case .week: "this week"; case .month: "this month"; case .year: "this year" }
        switch (subtitleStyle, kind) {
        case ("A", .notes): return "Where you journaled \(when)"
        case ("A", .photos): return "Photos you took \(when)"
        case ("A", .route): return "The way you went \(when)"
        case ("B", .notes): return "Shows where you journaled"
        case ("B", .photos): return "Shows your photos on the map"
        case ("B", .route): return "Shows the way you went"
        case ("C", .notes): let n = rangeNotes.count; return "\(n) entr\(n == 1 ? "y" : "ies") \(when)"
        case ("C", .photos): let n = rangePhotos.count; return "\(n) photo\(n == 1 ? "" : "s") \(when)"
        case ("C", .route): return "\(distanceText) \(when)"
        case (_, .notes): return "Where you journaled today"
        case (_, .photos): return "Photos you took today"
        case (_, .route): return "The way you went"
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
            CapsuleSegmented(selection: $range, options: MapRange.allCases.map { ($0, $0.rawValue) }, plain: true)
                .glassEffect(.regular, in: .capsule)
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
            layerToggle("Journal", "doc.text", Theme.journal, $showJournal)
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
                .background(on.wrappedValue ? AnyShapeStyle(color) : AnyShapeStyle(.clear), in: .capsule)
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
        // Grouped by name, so one place saved as two nearby spots (same name) shows once.
        Dictionary(grouping: rangeVisits.filter { $0.category != .home }, by: { $0.placeName.lowercased() }).compactMap { key, stays in
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
    /// Preview flag "visited.icon" (David picks, Sep 24): "tile" = blue tile (default, now);
    /// A = no icon; B = bold blue symbol, no tile; C = blue symbol in a light round circle (Maps style).
    @AppStorage("visited.icon") private var visitedIcon = "C" // B dropped
    /// Global "Show Symbols" (Profile > Look). On = C (round tint), off = no symbol (option A).
    @AppStorage("symbols.show") private var showSymbols = true
    private var iconStyle: String { showSymbols ? visitedIcon : "A" }
    @ViewBuilder private func icon(_ c: TimelineScreen.Cluster) -> some View {
        switch iconStyle {
        case "A": EmptyView()
        case "B": Image(systemName: c.category.symbol).font(.title3.weight(.bold)).foregroundStyle(Theme.accent).frame(width: 30, height: 30)
        case "C": Image(systemName: c.category.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Theme.accent)
                .frame(width: 34, height: 34).background(Theme.accent.opacity(0.14), in: .circle)
        default: CategoryIcon(category: c.category, size: 30)
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
                if i > 0 { Divider().padding(.leading, iconStyle == "A" ? 4 : 50) }
                HStack(spacing: 12) {
                    icon(c)
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
    @State private var openGroup: JournalGroup?

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
                        // Same as the Journal cards (David, Sep 24): photos inside the card with a white border,
                        // a big photo and a narrow one side by side.
                        GeometryReader { g in
                            let shown = Array(photos.prefix(2)); let gap: CGFloat = 6
                            HStack(spacing: gap) {
                                ForEach(Array(shown.enumerated()), id: \.offset) { i, img in
                                    let w = shown.count == 1 ? g.size.width : (i == 0 ? (g.size.width - gap) * 0.62 : (g.size.width - gap) * 0.38)
                                    Color.clear.frame(width: w, height: g.size.height)
                                        .overlay { Image(uiImage: img).resizable().scaledToFill() }
                                        .clipShape(.rect(cornerRadius: 16, style: .continuous))
                                }
                            }
                        }
                        .frame(height: 140)
                        .padding([.horizontal, .top], 10)
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
                            // Same voice-note design as the Journal.
                            VoiceBubble(seconds: voice.audioDuration, words: voice.text, transcribed: voice.isTranscribed,
                                        seed: voice.audioFileName ?? "\(voice.date)",
                                        audioURL: voice.audioFileName.map { VoiceNoteService.folder.appending(path: $0) })
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                }
                .background(Color(.secondarySystemGroupedBackground).opacity(0.92), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
                .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
                .contentShape(.rect(cornerRadius: Theme.cardRadius))
                .onTapGesture { if !items.isEmpty { openGroup = JournalGroup(entries: items, place: visit.placeName) } }
                .accessibilityIdentifier("stop-\(visit.placeName)")
            }
        }
        .navigationDestination(isPresented: Binding(get: { openGroup != nil }, set: { if !$0 { openGroup = nil } })) {
            if let openGroup { JournalEntryView(group: openGroup) }
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

private extension View {
    /// Rounded translucent card like the groups in Find My's sheet.
    /// glass: real Liquid Glass (see-through, map color shows), like the cards in Find My's "Me" sheet.
    @ViewBuilder func findMyCard(glass: Bool = false) -> some View {
        if glass { glassEffect(.regular.tint(Color.white.opacity(0.06)), in: .rect(cornerRadius: 26, style: .continuous)) }
        else { background(Color.primary.opacity(0.06), in: .rect(cornerRadius: 26, style: .continuous)) }
    }
}
