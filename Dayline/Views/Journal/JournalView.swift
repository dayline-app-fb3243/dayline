import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation

struct JournalView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var visits: [Visit]
    @State private var search = ""
    @State private var editingGroup: JournalGroup?

    private var filtered: [JournalEntry] {
        search.isEmpty ? entries : entries.filter { $0.text.localizedCaseInsensitiveContains(search) }
    }
    /// Newest day first; inside a day, entries run in time order, and entries made at the same place
    /// within 30 minutes share one card (so a photo and its caption sit together).
    private var days: [(Date, [JournalGroup])] {
        Dictionary(grouping: filtered) { DayBoundary.shared.day(of: $0.date) }
            .sorted { $0.key > $1.key }
            .map { day, items in (day, JournalGroup.make(items.sorted { $0.date > $1.date }, visits: visits)) }
    }

    /// Preview "journal.page" 1-5: Journal layouts ("" = the current cards). Sample-only until one is picked.
    @AppStorage("journal.page") private var jPage = ""
    @State private var composing = false
    /// Search button style "journal.search": B (default) = one glass capsule holding search and +.
    /// A = its own glass circle next to +, C = a search field under the title (kept as preview options).
    @AppStorage("journal.search") private var searchStyle = "B"
    @AppStorage("journal.searchQuery") private var demoQuery = ""
    @State private var searching = false
    @State private var inlineQuery = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    TabTitle("Journal") { titleButtons }
                    if searchStyle == "C" {
                        JournalSearchField(query: $inlineQuery).padding(.bottom, 4)
                    }
                    if searchStyle == "C" && !inlineQuery.isEmpty {
                        SearchResultsList(query: inlineQuery, entries: entries, visits: visits, onPick: { inlineQuery = $0 })
                    } else {
                    if entries.isEmpty {
                        ContentUnavailableView("No journal yet", systemImage: "doc.text",
                                               description: Text("Tap + to write, add a photo or record a voice memo."))
                    }
                    if !jPage.isEmpty {
                        JournalPageSample(page: jPage, days: days) { editingGroup = $0 }
                    } else {
                    ForEach(days, id: \.0) { day, groups in
                        Text(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.subheadline.weight(.semibold)).helperText()
                            .padding(.leading, 4).padding(.top, 6)
                        ForEach(groups) { g in
                            Button { editingGroup = g } label: { JournalCard(group: g) }.buttonStyle(.plain)
                                .accessibilityIdentifier("journalCard")
                        }
                    }
                    }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(AppBackgroundView())
            .navigationTitle("Journal")
            .tabRoot()
            .navigationDestination(isPresented: $searching) { JournalSearchView(barAtBottom: false, query: demoQuery) }
            .onReceive(NotificationCenter.default.publisher(for: .showOnMap)) { _ in searching = false }
            .onAppear {
                guard !demoQuery.isEmpty else { return }
                if searchStyle == "C" { inlineQuery = demoQuery } else if !searchStyle.isEmpty { searching = true }
            }
            .sheet(isPresented: $composing) { NavigationStack { NewEntryView(onDone: { composing = false }) } }
            .sheet(item: $editingGroup) { g in NavigationStack { NewEntryView(onDone: { editingGroup = nil }, editing: g) } }
        }
    }
}

extension JournalView {
    private var plusButton: some View {
        Button { composing = true } label: {
            Image(systemName: "plus").font(.title3.weight(.medium)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
        .accessibilityLabel("New entry")
        .accessibilityIdentifier("newEntry")
    }
    private var searchButton: some View {
        Button { searching = true } label: {
            Image(systemName: "magnifyingglass").font(.title3.weight(.medium)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain).foregroundStyle(Theme.accent)
        .accessibilityLabel("Search")
        .accessibilityIdentifier("journalSearch")
    }
    @ViewBuilder var titleButtons: some View {
        switch searchStyle {
        case "A":
            HStack(spacing: 10) {
                searchButton.glassEffect(.regular.interactive(), in: .circle)
                plusButton.glassEffect(.regular.interactive(), in: .circle)
            }
        case "B":
            HStack(spacing: 0) { searchButton; plusButton }
                .padding(.horizontal, 4)
                .glassEffect(.regular.interactive(), in: .capsule)
        default:
            plusButton.glassEffect(.regular.interactive(), in: .circle)
        }
    }
}

struct JournalGroup: Identifiable {
    var entries: [JournalEntry]
    var place: String?
    var id: PersistentIdentifier { entries[0].persistentModelID }
    var date: Date { entries.map(\.date).min() ?? entries[0].date }
    var videos: Set<Int> { Set(entries.filter { $0.thumbnail != nil }.enumerated().compactMap { $0.element.videoFileName != nil ? $0.offset : nil }) }
    var photos: [Data] { entries.compactMap(\.thumbnail) }
    var text: String? { entries.first { !$0.text.isEmpty && $0.kind != .voice }?.text }
    var voice: JournalEntry? { entries.first { $0.kind == .voice } }
    var title: String? { entries.lazy.compactMap(\.title).first { !$0.isEmpty } }
    var kind: JournalKind { voice != nil ? .voice : (photos.isEmpty ? .text : .photo) }

    static func placeName(for entry: JournalEntry, visits: [Visit]) -> String? {
        if let saved = entry.placeName { return saved }
        if let v = visits.first(where: { $0.arrival <= entry.date && entry.date <= ($0.departure ?? .distantFuture) && $0.category != .home }) {
            return v.placeName
        }
        guard let c = entry.coordinate else { return nil }
        let here = CLLocation(latitude: c.latitude, longitude: c.longitude)
        let near = visits.filter { $0.category != .home }
            .min { here.distance(from: CLLocation(latitude: $0.latitude, longitude: $0.longitude)) < here.distance(from: CLLocation(latitude: $1.latitude, longitude: $1.longitude)) }
        guard let near, here.distance(from: CLLocation(latitude: near.latitude, longitude: near.longitude)) < 150 else { return nil }
        return near.placeName
    }

    static func make(_ sorted: [JournalEntry], visits: [Visit]) -> [JournalGroup] {
        var out: [JournalGroup] = []
        for e in sorted {
            let name = placeName(for: e, visits: visits)
            // Everything saved from one entry stays on one card, even if other entries fall in between.
            if let g = e.groupID, let i = out.firstIndex(where: { $0.entries.contains { $0.groupID == g } }) {
                out[i].entries.append(e)
            } else if var last = out.last, last.place == name, name != nil, e.groupID == nil,
               abs(e.date.timeIntervalSince(last.entries.last!.date)) < 1800, e.kind != .voice, last.voice == nil {
                last.entries.append(e); out[out.count - 1] = last
            } else {
                out.append(JournalGroup(entries: [e], place: name))
            }
        }
        return out
    }
}

/// One card in the Journal. Preview flag "journal.cardStyle" (David picks):
/// A = icon + title (place under it), photos, text, voice; B = photos on top like Apple Journal, then title, text, voice, place · time at the bottom;
/// C = no icon: title, place · time, then text, photos, voice.
struct JournalCard: View {
    let group: JournalGroup
    /// Photos inside the card with a white border, a big photo and a narrow one side by side.
    @AppStorage("journal.cardStyle") private var style = "inset"
    private var heading: String { group.title ?? group.place ?? (group.kind == .voice ? "Voice memo" : group.kind == .photo ? "Photo" : "Journal") }
    private var meta: String { [group.title != nil ? group.place : nil, group.date.shortTime].compactMap { $0 }.joined(separator: " · ") }

    var body: some View {
        switch style {
        case "A": styleA
        case "B": styleB
        case "C": styleC
        default: styleInset
        }
    }

    private var styleInset: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !group.photos.isEmpty {
                GeometryReader { g in
                    let images = group.photos.prefix(2).compactMap { UIImage(data: $0) }
                    let gap: CGFloat = 6
                    HStack(spacing: gap) {
                        ForEach(Array(images.enumerated()), id: \.offset) { i, image in
                            let w = images.count == 1 ? g.size.width : (i == 0 ? (g.size.width - gap) * 0.62 : (g.size.width - gap) * 0.38)
                            Color.clear.frame(width: w, height: g.size.height)
                                .overlay { Image(uiImage: image).resizable().scaledToFill() }
                                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                                .overlay {
                                    if group.videos.contains(i) {
                                        Image(systemName: "play.fill").font(.caption).foregroundStyle(.white)
                                            .frame(width: 30, height: 30).background(.black.opacity(0.35), in: .circle)
                                    }
                                }
                        }
                    }
                }
                .frame(height: 150)
                .padding([.horizontal, .top], 10)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(heading).font(.headline)
                textBlock
                voiceBlock
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var styleA: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: group.kind == .voice ? "mic" : group.kind == .photo ? "photo" : "pencil")
                        .font(.scaled(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 29, height: 29).background(Theme.accent, in: .rect(cornerRadius: 7, style: .continuous))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(heading).font(.subheadline.weight(.semibold))
                        if group.title != nil, let place = group.place { Text(place).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Text(group.date.shortTime).font(.caption).foregroundStyle(.secondary)
                }
                photoRow(size: 96)
                textBlock
                voiceBlock
            }
        }
    }

    private var styleB: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !group.photos.isEmpty {
                HStack(spacing: 2) {
                    ForEach(Array(group.photos.prefix(2).enumerated()), id: \.offset) { _, data in
                        if let image = UIImage(data: data) {
                            Color.clear.frame(maxWidth: .infinity).frame(height: 150)
                                .overlay { Image(uiImage: image).resizable().scaledToFill() }.clipped()
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text(heading).font(.headline)
                textBlock
                voiceBlock
                Text(meta).font(.caption).foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: Theme.cardRadius, style: .continuous))
        .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    private var styleC: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(heading).font(.headline)
                    Text(meta).font(.subheadline).foregroundStyle(.secondary)
                }
                textBlock
                photoRow(size: 72)
                voiceBlock
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func photoRow(size: CGFloat) -> some View {
        if !group.photos.isEmpty {
            HStack(spacing: 8) {
                ForEach(Array(group.photos.prefix(3).enumerated()), id: \.offset) { i, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFill()
                            .frame(width: size, height: size).clipShape(.rect(cornerRadius: 12, style: .continuous))
                            .overlay {
                                if group.videos.contains(i) {
                                    Image(systemName: "play.fill").font(.caption).foregroundStyle(.white)
                                        .frame(width: 30, height: 30).background(.black.opacity(0.35), in: .circle)
                                }
                            }
                    }
                }
            }
        }
    }

    @ViewBuilder private var textBlock: some View {
        if let text = group.text, !text.isEmpty { Text(text).font(.subheadline) }
    }

    @ViewBuilder private var voiceBlock: some View {
        if let voice = group.voice {
            VoiceBubble(seconds: voice.audioDuration, words: voice.text, transcribed: voice.isTranscribed,
                        seed: voice.audioFileName ?? "\(voice.date)",
                        audioURL: voice.audioFileName.map { VoiceNoteService.folder.appending(path: $0) })
        }
    }
}

/// A journal entry opened full screen: place and time, photos, words and the voice note.
struct JournalEntryView: View {
    let group: JournalGroup
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(group.date.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute()))
                    .font(.subheadline).foregroundStyle(.secondary)
                ForEach(Array(group.photos.enumerated()), id: \.offset) { _, data in
                    if let image = UIImage(data: data) {
                        Image(uiImage: image).resizable().scaledToFit()
                            .clipShape(.rect(cornerRadius: Theme.cardRadius, style: .continuous))
                    }
                }
                if let text = group.text { Text(text).font(.body) }
                if let voice = group.voice {
                    VoiceBubble(seconds: voice.audioDuration, words: voice.text, transcribed: voice.isTranscribed,
                                seed: voice.audioFileName ?? "\(voice.date)",
                                audioURL: voice.audioFileName.map { VoiceNoteService.folder.appending(path: $0) })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18).padding(.bottom, 30)
        }
        .background(AppBackgroundView())
        .navigationTitle(group.place ?? "Journal")
        .navigationBarTitleDisplayMode(.large)
        .backgroundNavBar()
        .toolbarVisibility(.hidden, for: .tabBar)
        .accessibilityIdentifier("journalEntry")
    }
}
