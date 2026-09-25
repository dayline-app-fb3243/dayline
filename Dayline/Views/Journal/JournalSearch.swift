import SwiftUI
import SwiftData
import Vision
import CoreLocation

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
    private static let stop: Set<String> = ["where", "was", "were", "i", "the", "place", "take", "me", "to", "did", "have", "had",
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
        let words = q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        let cal = Calendar.current
        // Date words
        var day: Date?
        if let r = q.range(of: #"(\d+) days? ago"#, options: .regularExpression),
           let n = Int(q[r].split(separator: " ").first ?? "") {
            day = cal.date(byAdding: .day, value: -n, to: cal.startOfDay(for: now))
        } else if words.contains("yesterday") { day = cal.date(byAdding: .day, value: -1, to: cal.startOfDay(for: now)) }
        else if words.contains("today") { day = cal.startOfDay(for: now) }
        let lastWeek = q.contains("last week")
        let wantsFood = !eatWords.isDisjoint(with: words)
        // Plural to singular, so "danishes" finds "danish".
        let keys = words.filter { !stop.contains($0) && !eatWords.contains($0) && Int($0) == nil }.map { w -> String in
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
                if let k = keys.first(where: { text.contains($0) }) {
                    let why = e.kind == .voice ? "Voice memo: \u{201C}\(e.text.prefix(48))\u{201D}" : (place.lowercased().contains(k) ? "Place name" : "Journal: \u{201C}\(e.text.prefix(48))\u{201D}")
                    hits.append(SearchHit(place: place, date: e.date, reason: why, symbol: v?.category.symbol ?? "doc.text.fill", thumbnail: e.thumbnail, coordinate: e.coordinate ?? v?.coordinate))
                    continue
                }
                if e.kind == .photo {
                    let labels = labels(for: e)
                    if let k = keys.first(where: { key in labels.contains { $0.contains(key) || key.contains($0) } }) {
                        let shown = labels.filter { !$0.isEmpty }.prefix(3).joined(separator: ", ")
                        hits.append(SearchHit(place: place, date: e.date, reason: "Photo shows \(shown.isEmpty ? k : shown)", symbol: v?.category.symbol ?? "photo.fill", thumbnail: e.thumbnail, coordinate: e.coordinate ?? v?.coordinate))
                    }
                }
            }
            for v in visits where inRange(v.arrival) && keys.contains(where: { v.placeName.lowercased().contains($0) }) {
                if !hits.contains(where: { $0.place == v.placeName && cal.isDate($0.date, inSameDayAs: v.arrival) }) {
                    hits.append(SearchHit(place: v.placeName, date: v.arrival, reason: "You were here", symbol: v.category.symbol, coordinate: v.coordinate))
                }
            }
        } else if day != nil || lastWeek {
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
        return hits.sorted { $0.date > $1.date }
    }
}

/// Search screen, pushed from the Journal: the search bar at the top, results under it.
struct JournalSearchView: View {
    @State var query: String
    /// What the results show: set when you press Search on the keyboard (or tap a suggestion).
    @State private var submitted: String?
    private var previewStyle: Int {
        let args = ProcessInfo.processInfo.arguments
        guard let i = args.firstIndex(of: "-searchDesign"), i + 1 < args.count else { return 1 }
        return Int(args[i + 1]) ?? 1
    }
    @Query(sort: \JournalEntry.date, order: .reverse) var entries: [JournalEntry]
    @Query var visits: [Visit]

    var body: some View {
        VStack(spacing: 0) {
            JournalSearchField(query: $query, onSubmit: { submitted = query })
                .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6)
            ScrollView {
                if query.isEmpty && submitted == nil {
                    SearchLandingOption(style: previewStyle) { selected in query = selected; submitted = selected }
                        .padding(.horizontal, 16).padding(.top, 8)
                } else {
                    SearchResultsList(query: query.isEmpty ? "" : (submitted ?? ""), entries: entries, visits: visits, onPick: { query = $0; submitted = $0 })
                        .padding(.horizontal, 16).padding(.top, 8)
                }
            }
        }
        .background(AppBackgroundView())
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { if submitted == nil && !query.isEmpty { submitted = query } }
        .toolbarVisibility(.hidden, for: .tabBar)
    }
}

struct JournalSearchField: View {
    @Binding var query: String
    /// Return key ("Search") runs the search.
    var onSubmit: () -> Void = {}
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            // No mic here: the keyboard has its own dictation key.
            TextField("Search places, journal, photos\u{2026}", text: $query)
                .submitLabel(.search)
                .onSubmit(onSubmit)
                .autocorrectionDisabled()
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

struct SearchResultsList: View {
    var query: String
    var entries: [JournalEntry]
    var visits: [Visit]
    var onPick: (String) -> Void = { _ in }
    var body: some View {
        let hits = query.trimmingCharacters(in: .whitespaces).isEmpty ? [] : JournalSearch.run(query, entries: entries, visits: visits)
        VStack(alignment: .leading, spacing: 10) {
            if query.isEmpty {
                Text("Try").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                ForEach(["Where was I 4 days ago?", "The place I ate 4 days ago", "Croissant"], id: \.self) { s in
                    Label(s, systemImage: "magnifyingglass").font(.body).foregroundStyle(Theme.accent).padding(.leading, 4).padding(.vertical, 4)
                }
            } else if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                Text(hits.count == 1 ? "1 place" : "\(hits.count) places").font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).padding(.leading, 4)
                ForEach(hits) { h in
                    Button { MapJump.go(h) } label: { SearchHitRow(hit: h) }.buttonStyle(.plain)
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
        .background(Color(.systemBackground).opacity(0.85), in: .rect(cornerRadius: 20))
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
