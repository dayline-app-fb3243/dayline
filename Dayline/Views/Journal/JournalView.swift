import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation

struct JournalView: View {
    @Query(sort: \JournalEntry.date, order: .reverse) private var entries: [JournalEntry]
    @Query private var visits: [Visit]
    @State private var search = ""

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

    @State private var composing = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    if entries.isEmpty {
                        ContentUnavailableView("No journal yet", systemImage: "doc.text",
                                               description: Text("Tap + to add a note, photo or voice memo."))
                    }
                    ForEach(days, id: \.0) { day, groups in
                        Text(Calendar.current.isDateInToday(day) ? "Today" : day.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                            .font(.footnote).helperText().textCase(.uppercase)
                            .padding(.leading, 4).padding(.top, 6)
                        ForEach(groups) { g in
                            NavigationLink { JournalEntryView(group: g) } label: { JournalCard(group: g) }.buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 18).padding(.bottom, 30)
            }
            .background(AppBackgroundView())
            .navigationTitle("Journal")
            .navigationBarTitleDisplayMode(.large)
            .backgroundNavBar()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New entry", systemImage: "plus") { composing = true }
                        .accessibilityIdentifier("newEntry")
                }
            }
            .sheet(isPresented: $composing) { NavigationStack { NewEntryView(onDone: { composing = false }) } }
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
            if var last = out.last, let g = e.groupID, last.entries.contains(where: { $0.groupID == g }) {
                last.entries.append(e); out[out.count - 1] = last
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

/// One card in the Journal, laid out like the design: icon, place, time; photos; then the words.
struct JournalCard: View {
    let group: JournalGroup
    var body: some View {
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: group.kind == .voice ? "mic" : group.kind == .photo ? "photo" : "pencil")
                        .font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 29, height: 29).background(Theme.accent.gradient, in: .rect(cornerRadius: 7, style: .continuous))
                    Text(group.place ?? (group.kind == .voice ? "Voice note" : group.kind == .photo ? "Photo" : "Note"))
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(group.date.shortTime).font(.caption).foregroundStyle(.secondary)
                }
                if !group.photos.isEmpty {
                    HStack(spacing: 8) {
                        ForEach(Array(group.photos.prefix(3).enumerated()), id: \.offset) { i, data in
                            if let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFill()
                                    .frame(width: 96, height: 96).clipShape(.rect(cornerRadius: 14))
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
                if group.voice != nil, let text = group.text {
                    Text(text).font(.subheadline)
                }
                if let voice = group.voice {
                    VoiceBubble(seconds: voice.audioDuration, words: voice.text, transcribed: voice.isTranscribed,
                                seed: voice.audioFileName ?? "\(voice.date)",
                                audioURL: voice.audioFileName.map { VoiceNoteService.folder.appending(path: $0) })
                } else if let text = group.text {
                    Text(text).font(.subheadline)
                }
            }
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
