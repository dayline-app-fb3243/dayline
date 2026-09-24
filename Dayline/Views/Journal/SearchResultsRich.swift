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
    /// Preview flag "search.recent" (none picked yet): Recent places as Apple Maps "Guides" style photo cards.
    /// A = tall, name at the bottom. B = wide. C = tall with a label saying where the photo came from.
    @AppStorage("search.recent") private var recentStyle = ""
    @AppStorage("search.one") private var oneStyle = ""
    @AppStorage("search.detail") private var detailStyle = ""
    @State private var sheetHit: SearchHit?
    @State private var pushedHit: SearchHit?
    @State private var expanded: UUID?
    private func data(_ h: SearchHit) -> PlaceDetailData { PlaceDetailData(hit: h, visit: visit(for: h), photos: photos(for: h)) }

    var body: some View {
        let q = query.trimmingCharacters(in: .whitespaces)
        let hits = q.isEmpty ? [] : JournalSearch.run(q, entries: entries, visits: visits)
        VStack(alignment: .leading, spacing: 14) {
            if q.isEmpty { emptyState }
            else if hits.isEmpty { noResults(q) }
            else if hits.count == 1 {
                if oneStyle.isEmpty { ConfidentResultCard(hit: hits[0], photos: photos(for: hits[0]), visit: visit(for: hits[0])) }
                else { SinglePlaceResult(data: data(hits[0]), style: oneStyle) }
            }
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
                HStack(spacing: 12) {
                    ForEach(recent, id: \.persistentModelID) { v in
                        Button { MapJump.go(SearchHit(place: v.placeName, date: v.arrival, reason: "", symbol: v.category.symbol, coordinate: v.coordinate)) } label: {
                            if recentStyle.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Image(systemName: v.category.symbol).font(.system(size: 17, weight: .semibold)).foregroundStyle(.white)
                                        .frame(width: 40, height: 40).background(Theme.accent, in: .circle)
                                    Text(v.placeName).font(.subheadline.weight(.semibold)).lineLimit(2).multilineTextAlignment(.leading)
                                    Text(v.arrival.formatted(.relative(presentation: .named))).font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(width: 120, height: 128, alignment: .topLeading)
                                .padding(12)
                                .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
                            } else {
                                GuidePlaceCard(visit: v, photo: photos(forVisit: v).first, style: recentStyle)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollClipDisabled()
            let personal = SearchSuggestions.personal(visits: visits, entries: entries)
            if !personal.isEmpty {
                Text("Suggested for you").font(.title3.weight(.semibold)).padding(.leading, 4).padding(.top, 8)
                suggestionList(personal)
            }
            Text("You can ask anything, like").font(.title3.weight(.semibold)).padding(.leading, 4).padding(.top, 8)
            suggestionList(SearchSuggestions.examples)
        }
    }

    private func suggestionList(_ items: [SearchSuggestion]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { i, item in
                Button { onPick(item.query) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: item.symbol).font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(item.why == nil ? Color.secondary : Theme.accent).frame(width: 22)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.query).foregroundStyle(.primary).multilineTextAlignment(.leading)
                            if let why = item.why { Text(why).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 10).frame(minHeight: 50)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                if i < items.count - 1 { Divider().padding(.leading, 50) }
            }
        }
        .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
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
                Button {
                    switch detailStyle {
                    case "A": sheetHit = h
                    case "B": pushedHit = h
                    case "C": withAnimation(.snappy) { expanded = expanded == h.id ? nil : h.id }
                    default: MapJump.go(h)
                    }
                } label: {
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
                if detailStyle == "C" && expanded == h.id {
                    InlinePlaceDetail(data: data(h)).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .sheet(item: $sheetHit) { h in PlaceDetailSheet(data: data(h)) }
        .navigationDestination(item: $pushedHit) { h in PlaceDetailScreen(data: data(h)) }
    }
    private func timeText(_ h: SearchHit) -> String {
        let t = h.date.formatted(date: .omitted, time: .shortened)
        if let v = visit(for: h), let d = v.departure { return "\(t) \u{2013} \(d.formatted(date: .omitted, time: .shortened))" }
        return t
    }

    private func visit(for h: SearchHit) -> Visit? {
        visits.first { $0.placeName == h.place && Calendar.current.isDate($0.arrival, inSameDayAs: h.date) }
    }
    private func photos(forVisit v: Visit) -> [Data] {
        photos(for: SearchHit(place: v.placeName, date: v.arrival, reason: "", symbol: v.category.symbol, coordinate: v.coordinate))
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
                    .buttonStyle(.plain).foregroundStyle(.primary)
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


/// Apple Maps "Guides Nearby" style card: full-bleed photo, bold name over a dark fade at the bottom.
/// Photo: yours from that visit, else Apple Maps Look Around, else a colored card with the place icon.
struct GuidePlaceCard: View {
    var visit: Visit
    var photo: Data?
    var style: String
    @State private var lookAround: UIImage?
    @State private var triedLookAround = false

    private var size: CGSize { style == "B" ? CGSize(width: 250, height: 170) : CGSize(width: 170, height: 230) }
    private var source: String? {
        if photo != nil { return "Your photo" }
        if lookAround != nil { return "Look Around" }
        return nil
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Group {
                if let d = photo, let img = UIImage(data: d) {
                    Image(uiImage: img).resizable().scaledToFill()
                } else if let lookAround {
                    Image(uiImage: lookAround).resizable().scaledToFill()
                } else {
                    LinearGradient(colors: [Theme.accent.mix(with: .white, by: 0.25), Theme.accent.mix(with: .black, by: 0.25)], startPoint: .top, endPoint: .bottom)
                        .overlay(Image(systemName: visit.category.symbol).font(.system(size: 54, weight: .semibold)).foregroundStyle(.white.opacity(0.85)).offset(y: -24))
                }
            }
            .frame(width: size.width, height: size.height)
            .clipped()
            LinearGradient(stops: [.init(color: .black.opacity(0), location: 0.35), .init(color: .black.opacity(0.72), location: 1)], startPoint: .top, endPoint: .bottom)
            VStack(alignment: .leading, spacing: 3) {
                Label(visit.category.rawValue.capitalized, systemImage: visit.category.symbol)
                    .font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
                Text(visit.placeName).font(.system(size: 20, weight: .heavy)).foregroundStyle(.white)
                    .lineLimit(2).multilineTextAlignment(.leading)
                Text(visit.arrival.formatted(.relative(presentation: .named)).capitalizedFirst).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.85))
            }
            .padding(14)
        }
        .frame(width: size.width, height: size.height)
        .overlay(alignment: .topLeading) {
            if style == "C", let source {
                Label(source, systemImage: photo != nil ? "photo" : "binoculars.fill")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(.black.opacity(0.35), in: .capsule)
                    .padding(10)
            }
        }
        .clipShape(.rect(cornerRadius: 28))
        .shadow(color: .black.opacity(0.12), radius: 8, y: 4)
        .task {
            guard photo == nil, !triedLookAround else { return }
            triedLookAround = true
            guard let scene = try? await MKLookAroundSceneRequest(coordinate: visit.coordinate).scene else { return }
            let opts = MKLookAroundSnapshotter.Options()
            opts.size = CGSize(width: size.width * 2, height: size.height * 2)
            lookAround = try? await MKLookAroundSnapshotter(scene: scene, options: opts).snapshot.image
        }
    }
}


struct SearchSuggestion { var query: String; var why: String?; var symbol: String }

/// Suggestions from what you actually do (a place you go on this weekday, a note or photos you just added),
/// plus two general examples so people see what they can ask.
@MainActor
enum SearchSuggestions {
    static let examples: [SearchSuggestion] = [
        SearchSuggestion(query: "How many places was I at in the last 48 hours?", why: nil, symbol: "sparkle.magnifyingglass"),
        SearchSuggestion(query: "Where did I eat 4 days ago?", why: nil, symbol: "sparkle.magnifyingglass"),
    ]

    static func personal(visits: [Visit], entries: [JournalEntry], now: Date = .now) -> [SearchSuggestion] {
        let cal = Calendar.current
        var out: [SearchSuggestion] = []
        let today = cal.startOfDay(for: now)
        let weekdayName = now.formatted(.dateTime.weekday(.wide))
        // 1) A place you went on this weekday in at least 2 of the last 3 weeks.
        let pastSameDays = (1...3).compactMap { cal.date(byAdding: .day, value: -7 * $0, to: today) }
        var counts: [String: (n: Int, cat: PlaceCategory)] = [:]
        for day in pastSameDays {
            let names = Set(visits.filter { cal.isDate($0.arrival, inSameDayAs: day) && $0.category != .home && $0.category != .work }.map(\.placeName))
            for n in names {
                let cat = visits.first { $0.placeName == n }?.category ?? .other
                counts[n, default: (0, cat)].n += 1
            }
        }
        let doneToday = Set(visits.filter { cal.isDate($0.arrival, inSameDayAs: today) }.map(\.placeName))
        for (name, v) in counts.sorted(by: { $0.value.n > $1.value.n }) where v.n >= 2 {
            let why = v.n == 3 ? "You went the last 3 \(weekdayName)s" : "You went 2 of the last 3 \(weekdayName)s"
            out.append(SearchSuggestion(query: doneToday.contains(name) ? "When was I at \(name) today?" : "Directions to \(name)",
                                        why: why, symbol: v.cat.symbol))
            if out.count == 2 { break }
        }
        // 2) Your latest note at a place (last 7 days).
        let week = cal.date(byAdding: .day, value: -7, to: now)!
        if let note = entries.filter({ $0.date >= week && !$0.text.isEmpty && $0.kind != .voice }).sorted(by: { $0.date > $1.date })
            .first(where: { e in placeName(e, visits) != nil }), let place = placeName(note, visits) {
            out.append(SearchSuggestion(query: "What did I write at \(place)?", why: "Your note from \(note.date.formatted(.dateTime.weekday(.wide)))", symbol: "text.quote"))
        }
        // 3) A place where you took photos recently.
        if let photo = entries.filter({ $0.date >= week && $0.thumbnail != nil }).sorted(by: { $0.date > $1.date })
            .first(where: { e in placeName(e, visits) != nil }), let place = placeName(photo, visits),
           !out.contains(where: { $0.query.contains(place) }) {
            let n = entries.filter { $0.thumbnail != nil && cal.isDate($0.date, inSameDayAs: photo.date) && placeName($0, visits) == place }.count
            out.append(SearchSuggestion(query: "Photos from \(place)", why: "\(n) photo\(n == 1 ? "" : "s") \(photo.date.formatted(.relative(presentation: .named)))", symbol: "photo.on.rectangle"))
        }
        return Array(out.prefix(4))
    }

    private static func placeName(_ e: JournalEntry, _ visits: [Visit]) -> String? {
        if let p = e.placeName { return p }
        return visits.first { $0.arrival <= e.date && e.date <= ($0.departure ?? .distantFuture) && $0.category != .home }?.placeName
    }
}


/// search.detail C: the tapped row opens in place under it.
struct InlinePlaceDetail: View {
    var data: PlaceDetailData
    @State private var showHours = false
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HoursStatusLine(info: data.info)
            PlacePhotoStrip(data: data, height: 110)
            PlaceActionButtons(data: data, showHours: $showHours)
            if showHours { WeekHours(info: data.info) }
        }
        .padding(14)
        .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
        .padding(.top, -4)
    }
}
