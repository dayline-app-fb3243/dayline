import SwiftUI
import SwiftData
import PhotosUI
import CoreLocation
import UIKit
import AVFoundation
import UniformTypeIdentifiers

/// One piece of media in an entry: a photo, or a video with its poster frame.
struct EntryMedia: Identifiable {
    let id = UUID()
    var image: UIImage
    var videoURL: URL? = nil
    var duration: Double = 0
}

/// The entry is a list of blocks, like a note: text, a row of media, a voice note, more text.
struct EntryBlock: Identifiable {
    enum Kind { case text, media, voice }
    let id = UUID()
    var kind: Kind
    var text = ""
    var media: [EntryMedia] = []
    var seconds: Double = 0
    var voiceFileName: String? = nil
}

/// Movie picked from the library, copied into Documents/Video.
struct PickedMovie: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { SentTransferredFile($0.url) } importing: { received in
            let dest = try VideoStore.newURL(ext: received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension)
            try FileManager.default.copyItem(at: received.file, to: dest)
            return PickedMovie(url: dest)
        }
    }
}

enum VideoStore {
    static func folder() throws -> URL {
        let dir = URL.documentsDirectory.appending(path: "Video", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func newURL(ext: String = "mov") throws -> URL { try folder().appending(path: "\(UUID().uuidString).\(ext)") }
    static func url(for name: String) -> URL? { try? folder().appending(path: name) }
    /// Poster frame and length of a video file.
    static func poster(_ url: URL) async -> (UIImage, Double)? {
        let asset = AVURLAsset(url: url)
        let gen = AVAssetImageGenerator(asset: asset)
        gen.appliesPreferredTrackTransform = true
        gen.maximumSize = CGSize(width: 800, height: 800)
        guard let cg = try? await gen.image(at: .zero).image else { return nil }
        let d = (try? await asset.load(.duration)).map(CMTimeGetSeconds) ?? 0
        return (UIImage(cgImage: cg), d)
    }
}

/// New entry, Notes-style: title, text, photos and videos inline, voice notes,
/// with a camera / video / library / voice bar above the keyboard.
struct NewEntryView: View {
    var onDone: () -> Void = {}
    /// When set, the editor opens this saved entry so it can be changed or deleted.
    var editing: JournalGroup? = nil
    @Environment(\.modelContext) private var context
    @Query(sort: \Visit.arrival, order: .reverse) private var visits: [Visit]
    @Query(sort: \JournalEntry.date, order: .reverse) private var voiceEntries: [JournalEntry]
    @StateObject private var voice = VoiceNoteService.shared
    @State private var title = ""
    @State private var blocks: [EntryBlock] = [EntryBlock(kind: .text)]
    @State private var picks: [PhotosPickerItem] = []
    @State private var showLibrary = false
    @State private var showMediaChoices = false
    @State private var camera: CameraMode?
    @FocusState private var focus: UUID?
    @FocusState private var titleFocused: Bool
    @State private var startedAt = Date.now
    private let openedAt = Date.now
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var groupID = UUID().uuidString
    @State private var confirmDiscard = false

    enum CameraMode: Identifiable { case photo, video; var id: Self { self } }

    private var here: CLLocation? { LocationService.shared.lastLocation }
    private var placeName: String {
        if let saved = editing?.place { return saved }
        if let open = visits.first(where: { $0.departure == nil && $0.category != .home }) { return open.placeName }
        if let here, let near = visits.prefix(50).min(by: {
            CLLocation(latitude: $0.latitude, longitude: $0.longitude).distance(from: here) <
            CLLocation(latitude: $1.latitude, longitude: $1.longitude).distance(from: here)
        }), CLLocation(latitude: near.latitude, longitude: near.longitude).distance(from: here) < 150 {
            return near.placeName
        }
        return here == nil ? "Current location" : "Here"
    }
    private var allMedia: [EntryMedia] { blocks.flatMap(\.media) }
    private var bodyText: String {
        blocks.filter { $0.kind == .text }.map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }
    private var hasVoice: Bool { blocks.contains { $0.kind == .voice } }
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty || !bodyText.isEmpty || !allMedia.isEmpty || hasVoice
    }

    var body: some View {
        GeometryReader { editor in
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(startedAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())) · \(startedAt.shortTime) · \(placeName)")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
                TextField("Title", text: $title, axis: .vertical)
                    .font(.title2.bold()).focused($titleFocused)
                    .submitLabel(.next).onSubmit { focus = blocks.first?.id }
                    .accessibilityIdentifier("entryTitle")
                ForEach($blocks) { $block in
                    switch block.kind {
                    case .text:
                        TextField(block.id == blocks.first?.id ? "Write anything…" : "", text: $block.text, axis: .vertical)
                            .font(.body).focused($focus, equals: block.id)
                            .frame(minHeight: blocks.count == 1 ? max(44, editor.size.height - 110) : 44, alignment: .topLeading)
                            .accessibilityIdentifier("entryBody")
                    case .media:
                        mediaGrid(block)
                    case .voice:
                        let recorded = voiceEntries.first { $0.kind == .voice && $0.audioFileName == block.voiceFileName }
                        VoiceBubble(seconds: block.seconds, words: recorded?.text ?? "",
                                    transcribed: recorded?.isTranscribed ?? false,
                                    failed: recorded?.transcriptionFailed ?? false,
                                    seed: block.voiceFileName ?? block.id.uuidString,
                                    audioURL: block.voiceFileName.map { VoiceNoteService.folder.appending(path: $0) })
                            .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { remove(block.id) } }
                    }
                }
            }
            .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 30)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppBackgroundView())
        .navigationTitle(editing == nil ? "New entry" : "Edit entry")
        .onAppear(perform: loadEditing)
        .backgroundNavBar()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") {
                    if canSave || voice.isActive { confirmDiscard = true } else { onDone() }
                }
                .confirmationDialog("Discard this entry?", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("Discard Entry", role: .destructive) { Task { await discard() } }
                    Button("Keep Editing", role: .cancel) {}
                }
            }
            if editing != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Delete", systemImage: "trash", role: .destructive) { confirmDelete = true }
                        .accessibilityIdentifier("deleteEntry")
                        .confirmationDialog("Delete this entry?", isPresented: $confirmDelete, titleVisibility: .visible) {
                            Button("Delete Entry", role: .destructive) { deleteEditing() }
                            Button("Cancel", role: .cancel) {}
                        } message: { Text("This can't be undone.") }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", systemImage: "checkmark") { Task { await saveTapped() } }
                    .buttonStyle(.glassProminent).tint(Theme.accent).disabled(!canSave)
                    .accessibilityIdentifier("saveEntry")
            }
        }
        .safeAreaInset(edge: .bottom) {
            VoiceRecorderBar(voice: voice, onSend: { await stopVoice() }, leading: { addMediaButton }) { Color.clear }
        }
        .confirmationDialog("Add photo or video", isPresented: $showMediaChoices, titleVisibility: .visible) {
            Button("Photo and Video Library", systemImage: "photo.fill") { showLibrary = true }
            if cameraOK { Button("Take Photo", systemImage: "camera.fill") { camera = .photo } }
            Button("Cancel", role: .cancel) {}
        }
        .photosPicker(isPresented: $showLibrary, selection: $picks, maxSelectionCount: 10,
                      matching: .any(of: [.images, .videos]))
        .onChange(of: picks) { _, items in
            guard !items.isEmpty else { return }
            Task {
                var found: [EntryMedia] = []
                for item in items {
                    if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }),
                       let movie = try? await item.loadTransferable(type: PickedMovie.self),
                       let p = await VideoStore.poster(movie.url) {
                        found.append(EntryMedia(image: p.0, videoURL: movie.url, duration: p.1))
                    } else if let data = try? await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
                        found.append(EntryMedia(image: img))
                    }
                }
                picks = []
                insertMedia(found)
            }
        }
        .fullScreenCover(item: $camera) { mode in
            CameraPicker(video: mode == .video) { image, url in
                Task {
                    if let url, let p = await VideoStore.poster(url) {
                        insertMedia([EntryMedia(image: p.0, videoURL: url, duration: p.1)])
                    } else if let image {
                        insertMedia([EntryMedia(image: image)])
                    }
                }
            }
            .ignoresSafeArea()
        }
        .onAppear { titleFocused = true }
    }

    // MARK: pieces

    /// Messages-like plus button and one full-width recording field. Camera and library stay in the plus menu.
    private var cameraOK: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) || ProcessInfo.processInfo.arguments.contains("-demo") }

    private var addMediaButton: some View {
        Button { focus = nil; titleFocused = false; showMediaChoices = true } label: {
            Image(systemName: "plus").font(.title2.weight(.medium)).foregroundStyle(.primary)
                .frame(width: 48, height: 48)
                .glassEffect(.regular.interactive(), in: .circle)
        }
        .accessibilityLabel("Add photo or video")
        .accessibilityIdentifier("entryAddMedia")
    }

    @ViewBuilder private var cameraMenu: some View {
        Button("Take Photo", systemImage: "camera") { camera = .photo }
        Button("Record Video", systemImage: "video") { camera = .video }
    }

    private func circleButton(_ symbol: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.scaled(size: 19, weight: .regular)).foregroundStyle(.primary)
                .frame(width: 48, height: 48).contentShape(.circle)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(label)
    }

    private func mediaGrid(_ block: EntryBlock) -> some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)], spacing: 6) {
            ForEach(block.media) { m in
                Color.clear.frame(height: 130)
                    .overlay { Image(uiImage: m.image).resizable().scaledToFill() }
                    .clipShape(.rect(cornerRadius: 16, style: .continuous))
                    .overlay {
                        if m.videoURL != nil {
                            Image(systemName: "play.fill").font(.title3).foregroundStyle(.white)
                                .frame(width: 40, height: 40).background(.black.opacity(0.35), in: .circle)
                        }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if m.videoURL != nil {
                            Text(Duration.seconds(m.duration).formatted(.time(pattern: .minuteSecond)))
                                .font(.caption2.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.black.opacity(0.45), in: .capsule).padding(6)
                        }
                    }
                    .contextMenu { Button("Remove", systemImage: "trash", role: .destructive) { removeMedia(m.id) } }
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: editing

    /// Media goes where you are writing; a fresh text line follows so you can keep typing.
    private func insertMedia(_ items: [EntryMedia]) {
        guard !items.isEmpty else { return }
        let at = focusedIndex()
        if at < blocks.count, blocks[at].kind == .text, blocks[at].text.isEmpty, at > 0, blocks[at - 1].kind == .media {
            blocks[at - 1].media += items; return
        }
        let next = EntryBlock(kind: .text)
        blocks.insert(contentsOf: [EntryBlock(kind: .media, media: items), next], at: min(at + 1, blocks.count))
        focus = next.id
    }
    private func focusedIndex() -> Int {
        if let f = focus, let i = blocks.firstIndex(where: { $0.id == f }) { return i }
        return blocks.count - 1
    }
    private func removeMedia(_ id: UUID) {
        for i in blocks.indices { blocks[i].media.removeAll { $0.id == id } }
        blocks.removeAll { $0.kind == .media && $0.media.isEmpty }
    }
    private func remove(_ id: UUID) { blocks.removeAll { $0.id == id } }

    private var coordinate: (Double, Double)? { here.map { ($0.coordinate.latitude, $0.coordinate.longitude) } }

    private func stopVoice() async {
        let secs = voice.elapsed
        let at = focusedIndex()
        let savedVoice = await voice.stop(context: context, coordinate: coordinate)
        guard let savedVoice else { return }
        let next = EntryBlock(kind: .text)
        blocks.insert(contentsOf: [EntryBlock(kind: .voice, seconds: secs, voiceFileName: savedVoice.audioFileName), next], at: min(at + 1, blocks.count))
        focus = next.id
    }

    /// Throws away everything added in this entry, including voice notes saved while recording.
    /// Fill the editor from a saved entry (title = first line, the rest as text, photos/videos, voice notes).
    private func loadEditing() {
        guard let g = editing, !loaded else { return }
        loaded = true
        startedAt = g.date
        if let gid = g.entries.first(where: { $0.groupID != nil })?.groupID { groupID = gid }
        var list: [EntryBlock]
        if let t = g.title {
            title = t
            list = [EntryBlock(kind: .text, text: g.text ?? "")]
        } else {
            // Older entries kept the title as the first line of the text.
            let lines = (g.text ?? "").components(separatedBy: "\n")
            title = lines.count > 1 ? lines[0] : ""
            list = [EntryBlock(kind: .text, text: lines.count > 1 ? lines.dropFirst().joined(separator: "\n") : (lines.first ?? ""))]
        }
        let media: [EntryMedia] = g.entries.compactMap { e in
            guard let d = e.thumbnail, let img = UIImage(data: d) else { return nil }
            return EntryMedia(image: img, videoURL: e.videoFileName.flatMap { VideoStore.url(for: $0) }, duration: e.videoDuration)
        }
        if !media.isEmpty { list.append(EntryBlock(kind: .media, media: media)) }
        for v in g.entries where v.kind == .voice { list.append(EntryBlock(kind: .voice, seconds: v.audioDuration, voiceFileName: v.audioFileName)) }
        blocks = list
    }

    private func deleteEditing() {
        guard let g = editing else { return }
        for e in g.entries { context.delete(e) }
        try? context.save()
        onDone()
    }

    private func discard() async {
        if voice.isActive { voice.cancel() }
        let start = openedAt
        if let voices = try? context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date >= start })) {
            for v in voices where v.kind == .voice && v.groupID == nil { context.delete(v) }
            try? context.save()
        }
        onDone()
    }

    /// Save also finishes a voice note that's still recording or under review, so it lands in this entry.
    private func saveTapped() async {
        if voice.isActive { await stopVoice() }
        save()
    }

    private func save() {
        let lat = coordinate?.0, lon = coordinate?.1
        let head = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = bodyText
        let media = allMedia
        let place = placeName
        var saved: [JournalEntry] = []
        // Editing: replace the saved text/photos with what's in the editor; voice notes stay.
        if let g = editing { for e in g.entries where e.kind != .voice { context.delete(e) } }
        if media.isEmpty, !text.isEmpty {
            saved.append(JournalEntry(date: startedAt, kind: .text, text: text, latitude: lat, longitude: lon))
        }
        for (i, m) in media.enumerated() {
            let img = m.image
            let thumb = img.preparingThumbnail(of: CGSize(width: 600, height: 600 * img.size.height / max(img.size.width, 1)))
            let entry = JournalEntry(date: startedAt.addingTimeInterval(Double(i)), kind: .photo,
                                     text: i == 0 ? text : "",
                                     thumbnail: thumb?.jpegData(compressionQuality: 0.7), latitude: lat, longitude: lon)
            if let url = m.videoURL { entry.videoFileName = url.lastPathComponent; entry.videoDuration = m.duration }
            saved.append(entry)
        }
        if saved.isEmpty, !head.isEmpty, hasVoice {
            // Title + voice only: keep the title on a text entry so the card shows it.
            saved.append(JournalEntry(date: startedAt, kind: .text, text: "", latitude: lat, longitude: lon))
        }
        if saved.isEmpty, !head.isEmpty, !hasVoice {
            saved.append(JournalEntry(date: startedAt, kind: .text, text: "", latitude: lat, longitude: lon))
        }
        for e in saved { e.placeName = place; e.groupID = groupID; context.insert(e) }
        saved.first?.title = head.isEmpty ? nil : head
        // Voice notes recorded in this entry were saved when recording stopped; link them to this entry.
        let start = editing == nil ? startedAt : openedAt
        if let g = editing { for v in g.entries where v.kind == .voice { v.groupID = groupID } }
        if hasVoice, let voices = try? context.fetch(FetchDescriptor<JournalEntry>(predicate: #Predicate { $0.date >= start })) {
            for v in voices where v.kind == .voice && v.groupID == nil {
                v.groupID = groupID; v.placeName = place
                v.date = startedAt.addingTimeInterval(-1)
            }
        }
        try? context.save()
        onDone()
    }
}

/// Camera capture via UIKit: a photo, or a video when `video` is set.
struct CameraPicker: UIViewControllerRepresentable {
    var video = false
    var done: (UIImage?, URL?) -> Void
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        let movie = UTType.movie.identifier
        let cameraTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
        // Simulator (or no camera / restricted): fall back to the photo library instead of crashing.
        let useCamera = UIImagePickerController.isSourceTypeAvailable(.camera) && (!video || cameraTypes.contains(movie))
        picker.sourceType = useCamera ? .camera : .photoLibrary
        if video {
            let available = UIImagePickerController.availableMediaTypes(for: picker.sourceType) ?? []
            if available.contains(movie) { picker.mediaTypes = [movie] }
            if useCamera {
                picker.cameraCaptureMode = .video
                picker.videoQuality = .typeHigh
            }
        }
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let done: (UIImage?, URL?) -> Void
        init(done: @escaping (UIImage?, URL?) -> Void) { self.done = done }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let tmp = info[.mediaURL] as? URL, let dest = try? VideoStore.newURL(ext: tmp.pathExtension.isEmpty ? "mov" : tmp.pathExtension),
               (try? FileManager.default.copyItem(at: tmp, to: dest)) != nil {
                done(nil, dest)
            } else {
                done(info[.originalImage] as? UIImage, nil)
            }
            picker.dismiss(animated: true)
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            done(nil, nil)
            picker.dismiss(animated: true)
        }
    }
}
