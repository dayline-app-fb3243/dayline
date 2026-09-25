import SwiftUI
import SwiftData
import Vision
import CoreLocation
import MapKit

/// Tapping a search result: switch to the Timeline tab and open the full map on that day, at that place.
extension Notification.Name { static let showOnMap = Notification.Name("dayline.showOnMap") }
@MainActor
enum MapJump {
    static var pending: (date: Date, coordinate: CLLocationCoordinate2D?)?
    static func go(_ hit: SearchHit) {
        pending = (hit.date, hit.coordinate)
        NotificationCenter.default.post(name: .showOnMap, object: nil)
    }
}

/// One search result: a place (and when you were there), with the reason it matched.
struct SearchHit: Identifiable, Hashable {
    static func == (a: SearchHit, b: SearchHit) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
    let id = UUID()
    var place: String
    var date: Date
    var reason: String
    var symbol: String
    var thumbnail: Data?
    var coordinate: CLLocationCoordinate2D?
}

/// Search over your own timeline and journal, on the phone. Works on every iPhone:
/// it understands dates ("4 days ago", "yesterday", "last week"), place names, journal text and voice
/// transcripts, and what's in your journal photos (Vision labels, saved when the photo is added).
/// On phones with Apple Intelligence the on-device model can take over free-form questions (planned).
@MainActor
enum JournalSearch {
    private static let stop: Set<String> = ["where", "was", "were", "i", "the", "place", "places", "take", "me", "to", "did", "have", "had",
        "a", "an", "at", "in", "my", "what", "days", "day", "ago", "last", "week", "yesterday", "today", "go", "went", "eat", "ate",
        "eating", "show", "find", "of", "on", "that", "this", "when", "is", "it", "some", "for", "with", "and", "get", "got"]
    private static let eatWords: Set<String> = ["ate", "eat", "eating", "dinner", "lunch", "breakfast", "food"]

    /// Photo labels, cached per entry (Vision runs once per photo).
    private static var labelCache: [PersistentIdentifier: [String]] = [:]
    static func labels(for entry: JournalEntry) -> [String] {
        if let c = labelCache[entry.persistentModelID] { return c }
        var out: [String] = []
        if let data = entry.thumbnail, let img = UIImage(data: data)?.cgImage {
            let req = VNClassifyImageRequest()
            #if targetEnvironment(simulator)
            req.usesCPUOnly = true   // the simulator has no Neural Engine
            #endif
            try? VNImageRequestHandler(cgImage: img).perform([req])
            out = (req.results ?? []).filter { $0.confidence > 0.25 }.prefix(6)
                .map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        }
        labelCache[entry.persistentModelID] = out
        return out
    }

    static func run(_ query: String, entries: [JournalEntry], visits: [Visit], now: Date = .now) -> [SearchHit] {
        let q = query.lowercased()
        let normalized = q.replacingOccurrences(of: "two days", with: "2 days")
            .replacingOccurrences(of: "three days", with: "3 days")
            .replacingOccurrences(of: "four days", with: "4 days")
        let words = normalized.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let cal = Calendar.current
        // Date words
        var day: Date?
        if let r = normalized.range(of: #"(\d+) days? ago"#, options: .regularExpression),
           let n = Int(normalized[r].split(separator: " ").first ?? "") {
            day = cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: now))
        } else if words.contains("yesterday") { day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) }
        else if words.contains("today") { day = cal.startOfDay(for: now) }
        let lastWeek = q.contains("last week")
        let wantsFood = !eatWords.isDisjoint(with: words)
        let wantsPhotos = words.contains("photos") || words.contains("photo")
        let wantsJournal = words.contains("journal") || words.contains("notes")
        let generic = words.contains("where") || words.contains("place") || words.contains("places")
        // Plural to singular, so "danishes" finds "danish".
        let keys = words.filter { !stop.contains($0) && !eatWords.contains($0) && !["photos", "photo", "journal", "notes"].contains($0) && Int($0) == nil }.map { w -> String in
            if w.count > 5 && w.hasSuffix("es") { return String(w.dropLast(2)) }
            if w.count > 4 && w.hasSuffix("s") && !w.hasSuffix("ss") { return String(w.dropLast()) }
            return w
        }

        func inRange(_ d: Date) -> Bool {
            if let day { return cal.isDate(d, inSameDayAs: day) }
            if lastWeek { return d >= cal.date(byAdding: .day, value: -8, to: now)! && d <= now }
            return true
        }
        func nearestVisit(_ e: JournalEntry) -> Visit? {
            visits.filter { abs($0.arrival.timeIntervalSince(e.date)) < 3 * 3600 && cal.isDate($0.arrival, inSameDayAs: e.date) }
                .min { abs($0.arrival.timeIntervalSince(e.date)) < abs($1.arrival.timeIntervalSince(e.date)) }
        }
        var hits: [SearchHit] = []
        // Keyword matches in the journal: text, voice transcripts, titles, and what's in the photos.
        if !keys.isEmpty {
            for e in entries where inRange(e.date) {
                let v = nearestVisit(e)
                let place = e.placeName ?? v?.placeName ?? "Journal"
                let text = [e.text, e.title ?? "", place].joined(separator: " ").lowercased()
                if keys.allSatisfy({ SearchSuggestions.matches($0, in: text) }) {
                    let k = keys[0]
                    let why = e.kind == .voice ? "Voice memo: \u{201C}\(e.text.prefix(48))\u{201D}" : (place.lowercased().contains(k) ? "Place name" : "Journal: \u{201C}\(e.text.prefix(48))\u{201D}")
                    hits.append(SearchHit(place: place, date: e.date, reason: why, symbol: v?.category.symbol ?? "doc.text.fill", thumbnail: e.thumbnail, coordinate: e.coordinate ?? v?.coordinate))
                    continue
                }
                if e.kind == .photo {
                    let labels = labels(for: e)
                    if keys.allSatisfy({ key in labels.contains { SearchSuggestions.matches(key, in: $0) } }) {
                        let k = keys[0]
                        let shown = labels.filter { !$0.isEmpty }.prefix(3).joined(separator: ", ")
                        hits.append(SearchHit(place: place, date: e.date, reason: "Photo shows \(shown.isEmpty ? k : shown)", symbol: v?.category.symbol ?? "photo.fill", thumbnail: e.thumbnail, coordinate: e.coordinate ?? v?.coordinate))
                    }
                }
            }
            for v in visits where inRange(v.arrival) && keys.allSatisfy({ SearchSuggestions.matches($0, in: v.placeName) }) {
                if !hits.contains(where: { $0.place == v.placeName && cal.isDate($0.date, inSameDayAs: v.arrival) }) {
                    hits.append(SearchHit(place: v.placeName, date: v.arrival, reason: "You were here", symbol: v.category.symbol, coordinate: v.coordinate))
                }
            }
        } else if wantsPhotos || wantsJournal {
            for e in entries where inRange(e.date) && ((wantsPhotos && e.kind == .photo) || (wantsJournal && e.kind != .photo)) {
                let v = nearestVisit(e)
                hits.append(SearchHit(place: e.placeName ?? v?.placeName ?? "Journal", date: e.date,
                                      reason: e.kind == .photo ? "Photo" : "Journal entry", symbol: e.kind == .photo ? "photo.fill" : "doc.text.fill",
                                      thumbnail: e.thumbnail, coordinate: e.coordinate ?? v?.coordinate))
            }
        } else if day != nil || lastWeek || generic {
            // "Where was I 4 days ago" / "the place I ate 4 days ago": the visits that day.
            for v in visits where inRange(v.arrival) && v.category != .home && (!wantsFood || v.category == .food) {
                let mins = v.departure.map { Int($0.timeIntervalSince(v.arrival) / 60) }
                let len = mins.map { $0 >= 60 ? "\($0 / 60) h \($0 % 60) min" : "\($0) min" } ?? "Still here"
                let note = entries.first { e in e.kind == .text && abs(e.date.timeIntervalSince(v.arrival)) < 3 * 3600 && cal.isDate(e.date, inSameDayAs: v.arrival) }
                let why = note.map { "\(len) · \u{201C}\($0.text)\u{201D}" } ?? len
                hits.append(SearchHit(place: v.placeName, date: v.arrival, reason: why, symbol: v.category.symbol, coordinate: v.coordinate))
            }
        }
        // One result per place per day.
        var seen = Set<String>()
        hits = hits.filter { seen.insert("\($0.place)|\(cal.startOfDay(for: $0.date).timeIntervalSince1970)").inserted }
        return Array(hits.sorted { $0.date > $1.date }.prefix(generic && day == nil && !lastWeek ? 20 : 200))
    }
}

/// Search screen, pushed from the Journal: the search bar at the top, results under it.
struct JournalSearchView: View {
    @State var query: String
    @FocusState private var searchFocused: Bool
    private var previewStyle: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-searchDesign"), i + 1 < args.count else { return 1 }
        return Int(args[i + 1]) ?? 1
    }
    @Query(sort: \JournalEntry.date, order: .reverse) var entries: [JournalEntry]
    @Query var visits: [Visit]

    var body: some View {
        VStack(spacing: 0) {
            JournalSearchField(query: $query, focused: $searchFocused, onSubmit: { searchFocused = false })
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
            ScrollView {
                if query.isEmpty {
                    SearchLandingOption(style: previewStyle) { selected in query = selected; searchFocused = false }
                        .padding(.horizontal, 16).padding(.top, 8)
                } else {
                    SearchResultsList(query: query, entries: entries, visits: visits, onPick: { query = $0; searchFocused = false })
                        .padding(.horizontal, 16).padding(.top, 8)
                }
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-searchKeyboard") { searchFocused = true }
        }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

struct JournalSearchField: View {
    @Binding var query: String
    /// Return key ("Search") runs the search.
    var focused: FocusState<Bool>.Binding
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            // No mic here: the keyboard has its own dictation key.
            TextField("Search places, journal, photos\u{2026}", text: $query)
                .submitLabel(.search)
                .focused(focused)
                .onSubmit(onSubmit)
                .autocorrectionDisabled(false)
                .accessibilityIdentifier("searchField")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
            }
        }
        .font(.body)
        .padding(.horizontal, 16).frame(height: 48)
        .glassEffect(.regular, in: .capsule)
    }
}

/// Typeahead uses actual saved places and journal words, plus relative-day questions.
/// It never invents a visit or journal entry; suggestions only complete the query.
@MainActor
enum SearchSuggestions {
    static func candidates(_ query: String, entries: [JournalEntry], visits: [Visit]) -> [String] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        let places = Array(Set(visits.map(\.placeName) + entries.compactMap(\.placeName)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        let context = ["Where was I yesterday?", "Where was I 2 days ago?", "Where was I last week?",
                       "Where did I eat yesterday?", "Photos from yesterday", "Journal from last week"]
        let words = Array(Set(entries.flatMap { $0.text.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init) }
            .filter { $0.count > 3 })).sorted()
        let all = context + places + words
        let direct = all.filter { $0.lowercased().hasPrefix(q) }
        let starts = all.filter { $0.lowercased().contains(q) && !direct.contains($0) }
        let fuzzy = all.filter { item in
            let tokens = item.lowercased().split(separator: " ").map(String.init)
            let typed = q.split(separator: " ").map(String.init)
            let partial = typed.last ?? q
            let lastMatches = tokens.contains { distance(String($0.prefix(partial.count)), partial) <= (partial.count > 5 ? 2 : 1) }
            let prefixMatches = typed.count > 1 && typed.dropLast().allSatisfy { word in
                tokens.contains { distance(String($0.prefix(word.count)), word) <= (word.count > 5 ? 2 : 1) }
            }
            return !direct.contains(item) && !starts.contains(item) && partial.count >= 3 &&
                lastMatches && (typed.count == 1 || prefixMatches)
        }
        return Array((direct + starts + fuzzy).prefix(5))
    }
    private static func distance(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        var prev = Array(0...y.count)
        for (i, c) in x.enumerated() {
            var next = [i + 1] + Array(repeating: 0, count: y.count)
            for (j, d) in y.enumerated() {
                next[j + 1] = min(prev[j + 1] + 1, next[j] + 1, prev[j] + (c == d ? 0 : 1))
            }
            prev = next
        }
        return prev[y.count]
    }
    static func matches(_ search: String, in text: String) -> Bool {
        let q = search.lowercased(), t = text.lowercased()
        if t.contains(q) { return true }
        guard q.count >= 3 else { return false }
        return t.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .contains { word in distance(String(word), q) <= (q.count > 5 ? 2 : 1) }
    }
}

struct SearchResultsList: View {
    var query: String
    var entries: [JournalEntry]
    var visits: [Visit]
    var onPick: (String) -> Void = { _ in }
    var body: some View {
        let hits = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : JournalSearch.run(query, entries: entries, visits: visits)
        let suggestions = SearchSuggestions.candidates(query, entries: entries, visits: visits)
        VStack(alignment: .leading, spacing: 10) {
            if !query.isEmpty && !suggestions.isEmpty {
                Text("Suggestions").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                Card(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(Array(suggestions.enumerated()), id: \.offset) { i, suggestion in
                            Button { onPick(suggestion) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                                    Text(suggestion).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.left").foregroundStyle(.tertiary)
                                }.font(.body).padding(.horizontal, 16).padding(.vertical, 12)
                            }.buttonStyle(.plain)
                            if i < suggestions.count - 1 { Divider().padding(.leading, 46) }
                        }
                    }
                }
            }
            if query.isEmpty {
                Text("Try").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                ForEach(["Where was I 4 days ago?", "The place I ate 4 days ago", "Croissant"], id: \.self) { s in
                    Label(s, systemImage: "magnifyingglass").font(.body).foregroundStyle(Theme.accent).padding(.leading, 4).padding(.vertical, 4)
                }
            } else if hits.isEmpty && suggestions.isEmpty {
                ContentUnavailableView.search(text: query)
            } else if hits.isEmpty {
                Text("Choose a suggestion or keep typing").font(.footnote).foregroundStyle(.secondary).padding(.leading, 4)
            } else {
                Text(hits.count == 1 ? "1 place" : "\(hits.count) places").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                ForEach(hits) { h in
                    NavigationLink { SearchPlaceView(hit: h, visits: visits) } label: { SearchHitRow(hit: h) }
                        .buttonStyle(.plain)
                }
            }
        }
    }
}

struct SearchHitRow: View {
    var hit: SearchHit
    var body: some View {
        HStack(spacing: 12) {
            if let d = hit.thumbnail, let img = UIImage(data: d) {
                Image(uiImage: img).resizable().scaledToFill().frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 12))
            } else {
                Image(systemName: hit.symbol).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 56, height: 56).background(Theme.accent, in: .rect(cornerRadius: 12))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.place).font(.body.weight(.semibold))
                Text(hit.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())).font(.subheadline).foregroundStyle(.secondary)
                Text(hit.reason).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "map").font(.body.weight(.semibold)).foregroundStyle(Theme.accent)
        }
        .padding(12)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityIdentifier("searchHit")
    }
}

/// Five app-style ways to make the empty search page useful without changing search results.
/// Every suggestion is a working search, never a decorative placeholder.
struct SearchLandingOption: View {
    let style: Int
    let pick: (String) -> Void
    private let suggestions: [(String, String)] = [
        ("Where was I 4 days ago?", "calendar"),
        ("The place I ate 4 days ago", "fork.knife"),
        ("Croissant", "photo")
    ]
    private var lastPlaces: [(String, String)] {
        [("Blue Door Coffee", "cup.and.saucer"), ("Gym", "dumbbell"), ("Office", "building.2")]
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch style {
            case 2:
                section("Search your day", systemImage: "magnifyingglass") {
                    Text("Places, journal notes, and photos, all in one search.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                section("Try asking") { suggestionRows }
            case 3:
                section("Recent places") { placeRows }
                section("Find something") { suggestionRows }
            case 4:
                SectionHeader("Search by")
                HStack(spacing: 10) {
                    category("Places", "mappin", "Blue Door Coffee")
                    category("Photos", "photo", "Croissant")
                    category("Journal", "text.book.closed", "Gym")
                }
                section("Try asking") { suggestionRows }
            case 5:
                section("Find a day") {
                    VStack(spacing: 0) {
                        row("Today", symbol: "sun.max", query: "Today")
                        Divider().padding(.leading, 50)
                        row("Yesterday", symbol: "clock.arrow.circlepath", query: "Yesterday")
                        Divider().padding(.leading, 50)
                        row("Last week", symbol: "calendar", query: "Last week")
                    }
                }
                section("Recent places") { placeRows }
            default:
                section("Try asking") { suggestionRows }
                section("Recent places") { placeRows }
            }
        }
    }
    private var suggestionRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggestions.enumerated()), id: \.offset) { i, item in
                row(item.0, symbol: item.1, query: item.0)
                if i < suggestions.count - 1 { Divider().padding(.leading, 50) }
            }
        }
    }
    private var placeRows: some View {
        VStack(spacing: 0) {
            ForEach(Array(lastPlaces.enumerated()), id: \.offset) { i, item in
                row(item.0, symbol: item.1, query: item.0)
                if i < lastPlaces.count - 1 { Divider().padding(.leading, 50) }
            }
        }
    }
    private func section<C: View>(_ title: String, systemImage: String? = nil, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
            content().frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        }
    }
    private func row(_ title: String, symbol: String, query: String) -> some View {
        Button { pick(query) } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol).font(.body).foregroundStyle(Theme.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.accent.opacity(0.12), in: .circle)
                Text(title).font(.body).foregroundStyle(.primary)
                Spacer(minLength: 0)
                Image(systemName: "arrow.up.left").font(.footnote).foregroundStyle(.tertiary)
            }.padding(.horizontal, 14).padding(.vertical, 9).contentShape(.rect)
        }.buttonStyle(.plain)
    }
    private func category(_ title: String, _ symbol: String, _ query: String) -> some View {
        Button { pick(query) } label: {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol).font(.title3).foregroundStyle(Theme.accent)
                Text(title).font(.subheadline).foregroundStyle(.primary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, minHeight: 73, alignment: .leading)
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius))
        }.buttonStyle(.plain)
    }
}

/// Search keeps its own navigation stack. Back returns to the exact query and results,
/// while directions open Apple Maps only when the user taps the explicit Maps link.
struct SearchPlaceView: View {
    let hit: SearchHit
    let visits: [Visit]
    @Environment(\.modelContext) private var context
    @State private var recalled: RecalledPlace?
    private var match: Visit? {
        let candidates = visits.filter { $0.placeName == hit.place }
        return candidates.min { abs($0.arrival.timeIntervalSince(hit.date)) < abs($1.arrival.timeIntervalSince(hit.date)) }
    }
    private var location: CLLocationCoordinate2D? { hit.coordinate ?? recalled?.coordinate ?? match?.coordinate }
    private var mapsURL: URL? {
        if let recalled { return recalled.directionsURL }
        guard let location else { return nil }
        var components = URLComponents(string: "https://maps.apple.com/")!
        components.queryItems = [.init(name: "daddr", value: "\(location.latitude),\(location.longitude)"),
                                 .init(name: "q", value: hit.place), .init(name: "dirflg", value: "d")]
        return components.url
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let coordinate = location {
                    Map(initialPosition: .camera(MapCamera(centerCoordinate: coordinate, distance: 1000))) {
                        Marker(hit.place, coordinate: coordinate).tint(Theme.accent)
                    }
                    .mapStyle(.standard)
                    .frame(height: 220)
                    .clipShape(.rect(cornerRadius: Theme.cardRadius))
                    .allowsHitTesting(false)
                } else if let data = hit.thumbnail, let image = UIImage(data: data) {
                    Image(uiImage: image).resizable().scaledToFill().frame(height: 220).clipped()
                        .clipShape(.rect(cornerRadius: Theme.cardRadius))
                }
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(hit.place).font(.title2.weight(.semibold))
                        Text(hit.reason).font(.body).foregroundStyle(.secondary)
                        Text("Visited \(hit.date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().hour().minute()))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let recalled { Text("\(recalled.timesVisited) visits").font(.subheadline).foregroundStyle(.secondary) }
                        if let mapsURL {
                            Link(destination: mapsURL) { Label("Directions in Apple Maps", systemImage: "arrow.triangle.turn.up.right.diamond.fill") }
                                .font(.body.weight(.semibold)).padding(.top, 8)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let recalled, !recalled.photos.isEmpty {
                    Text("Photos").font(.headline).padding(.leading, 4)
                    PhotoStrip(photos: recalled.photos, height: 140)
                } else if let data = hit.thumbnail, let image = UIImage(data: data) {
                    Text("Photo").font(.headline).padding(.leading, 4)
                    Image(uiImage: image).resizable().scaledToFit().clipShape(.rect(cornerRadius: 16))
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
        }
        .background(AppBackgroundView())
        .navigationTitle(hit.place).navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("searchPlacePage")
        .task {
            if let match { recalled = await PlaceRecall.card(for: match, context: context) }
        }
    }
}
