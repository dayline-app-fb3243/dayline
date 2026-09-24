import SwiftUI
import SwiftData
import PhotosUI
import Photos

enum CaptureMode: String, Identifiable { case photo, voice, text; var id: String { rawValue } }

struct CaptureSheet: View {
    let mode: CaptureMode
    var body: some View {
        switch mode {
        case .photo: PhotoCaptureSheet()
        case .voice: VoiceCaptureSheet()
        case .text: TextCaptureSheet()
        }
    }
}

private struct PhotoCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var selection: [PhotosPickerItem] = []
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                PhotosPicker(selection: $selection, maxSelectionCount: 10, matching: .images, photoLibrary: .shared()) {
                    Label("Choose photos", systemImage: "photo.stack").frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large)
                if saving { ProgressView() }
                Text("Photos go on your timeline at the place they were taken.")
                    .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding(24)
            .navigationTitle("Add photos").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
            .onChange(of: selection) { _, items in Task { await save(items) } }
        }
        .presentationDetents([.medium])
    }

    private func save(_ items: [PhotosPickerItem]) async {
        saving = true
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else { continue }
            var date = Date.now, lat: Double?, lon: Double?
            if let id = item.itemIdentifier, let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject {
                date = asset.creationDate ?? .now
                lat = asset.location?.coordinate.latitude; lon = asset.location?.coordinate.longitude
            }
            let thumb = image.preparingThumbnail(of: CGSize(width: 600, height: 600 * image.size.height / max(image.size.width, 1)))
            context.insert(JournalEntry(date: date, kind: .photo, photoAssetID: item.itemIdentifier,
                                        thumbnail: thumb?.jpegData(compressionQuality: 0.7), latitude: lat, longitude: lon))
        }
        try? context.save()
        dismiss()
    }
}

private struct VoiceCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @StateObject private var voice = VoiceNoteService.shared
    @State private var saving = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()
                Text(Duration.seconds(voice.elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 48, weight: .semibold)).monospacedDigit()
                Circle()
                    .fill(Theme.accent.opacity(0.15))
                    .frame(width: 120 + CGFloat(voice.level) * 60, height: 120 + CGFloat(voice.level) * 60)
                    .overlay { Image(systemName: "mic.fill").font(.system(size: 40)).foregroundStyle(Theme.accent) }
                    .animation(.easeOut(duration: 0.1), value: voice.level)
                Button {
                    Task {
                        if voice.isRecording {
                            saving = true
                            await voice.stop(context: context, coordinate: nil)
                            dismiss()
                        } else {
                            try? await voice.start()
                        }
                    }
                } label: {
                    Label(voice.isRecording ? "Stop and save" : "Start recording",
                          systemImage: voice.isRecording ? "stop.fill" : "record.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent).controlSize(.large).tint(Theme.accent)
                if saving { Label("Transcribing…", systemImage: "text.bubble").foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Voice note").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } } }
        }
    }
}

private struct TextCaptureSheet: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).padding()
                .navigationTitle("Note").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", systemImage: "checkmark") {
                            context.insert(JournalEntry(date: .now, kind: .text, text: text)); dismiss()
                        }.disabled(text.isEmpty)
                    }
                }
        }
    }
}
