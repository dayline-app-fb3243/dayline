import SwiftUI
import SwiftData
import Vision
import CoreLocation

/// One search result: a place (and when you were there), with the reason it matched.
struct SearchHit: Identifiable {
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
        let keys = words.filter { !stop.contains($0) && !eatWords.contains($0) && Int($0) == nil }

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
                    let why = e.kind == .voice ? "Voice note: \u{201C}\(e.text.prefix(48))\u{201D}" : (place.lowercased().contains(k) ? "Place name" : "Journal: \u{201C}\(e.text.prefix(48))\u{201D}")
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
            for v in visits where inRange(v.arrival) && v.category != .home && (!wantsFood || v.category == .food || v.category == .coffee) {
                let mins = v.departure.map { Int($0.timeIntervalSince(v.arrival) / 60) }
                let len = mins.map { $0 >= 60 ? "\($0 / 60) h \($0 % 60) min" : "\($0) min" } ?? "Still here"
                let note = entries.first { e in e.kind == .text && abs(e.date.timeIntervalSince(v.arrival)) < 3 * 3600 && cal.isDate(e.date, inSameDayAs: v.arrival) }
                let why = note.map { "\(len) · \u{201C}\($0.text.prefix(40))\u{201D}" } ?? len
                hits.append(SearchHit(place: v.placeName, date: v.arrival, reason: why, symbol: v.category.symbol, coordinate: v.coordinate))
            }
        }
        return hits.sorted { $0.date > $1.date }
    }
}

/// Search screen. Preview flag "journal.search": A = bar at the top (pushed screen), B = bar at the bottom,
/// C = field always showing under the Journal title (results replace the list).
struct JournalSearchView: View {
    var barAtBottom = false
    @State var query: String
    @Query(sort: \JournalEntry.date, order: .reverse) var entries: [JournalEntry]
    @Query var visits: [Visit]
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack(spacing: 0) {
            if !barAtBottom { bar.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 6) }
            ScrollView {
                SearchResultsList(query: query, entries: entries, visits: visits).padding(.horizontal, 16).padding(.top, 8)
            }
            if barAtBottom { bar.padding(.horizontal, 16).padding(.vertical, 10) }
        }
        .background(AppBackgroundView())
        .navigationTitle(barAtBottom ? "Search" : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarVisibility(.hidden, for: .tabBar)
    }

    private var bar: some View {
        HStack(spacing: 10) {
            JournalSearchField(query: $query)
            if barAtBottom {
                Button { dismiss() } label: {
                    Image(systemName: "xmark").font(.system(size: 16, weight: .semibold)).foregroundStyle(.primary)
                        .frame(width: 48, height: 48)
                }
                .buttonStyle(.plain).glassEffect(.regular.interactive(), in: .circle).accessibilityLabel("Close")
            }
        }
    }
}

struct JournalSearchField: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search places, notes, photos\u{2026}", text: $query)
                .submitLabel(.search)
                .accessibilityIdentifier("searchField")
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary) }.buttonStyle(.plain)
            }
            Image(systemName: "mic.fill").foregroundStyle(.secondary)
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
                ForEach(hits) { h in SearchHitRow(hit: h) }
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
