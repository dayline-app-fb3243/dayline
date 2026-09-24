import Foundation
import AVFoundation
import Speech
import SwiftData

/// Records voice journal notes and transcribes them on the device.
@MainActor
final class VoiceNoteService: NSObject, ObservableObject {
    static let shared = VoiceNoteService()

    @Published private(set) var isRecording = false
    @Published private(set) var level: Float = 0
    @Published private(set) var elapsed: TimeInterval = 0

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentFile: URL?

    static var folder: URL {
        let url = URL.documentsDirectory.appending(path: "Voice", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func start() async throws {
        guard await AVAudioApplication.requestRecordPermission() else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true)

        let file = Self.folder.appending(path: "\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let recorder = try AVAudioRecorder(url: file, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        currentFile = file
        isRecording = true
        elapsed = 0
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder else { return }
                recorder.updateMeters()
                self.level = max(0, (recorder.averagePower(forChannel: 0) + 50) / 50)
                self.elapsed = recorder.currentTime
            }
        }
    }

    /// Stops, saves the entry, then fills in the transcript when it's ready.
    func stop(context: ModelContext, coordinate: (Double, Double)?) async {
        guard let recorder, let file = currentFile else { return }
        let duration = recorder.currentTime
        recorder.stop()
        meterTimer?.invalidate()
        isRecording = false
        self.recorder = nil

        let entry = JournalEntry(date: .now, kind: .voice, text: "", audioFileName: file.lastPathComponent,
                                 audioDuration: duration, latitude: coordinate?.0, longitude: coordinate?.1)
        context.insert(entry)
        try? context.save()

        if let text = await Transcriber.transcribe(file) {
            entry.text = text
            entry.isTranscribed = true
            try? context.save()
        }
    }
}

enum Transcriber {
    /// On-device speech-to-text. Returns nil if speech recognition is not allowed or fails.
    static func transcribe(_ url: URL) async -> String? {
        let status = await withCheckedContinuation { c in
            SFSpeechRecognizer.requestAuthorization { c.resume(returning: $0) }
        }
        guard status == .authorized, let recognizer = SFSpeechRecognizer(), recognizer.isAvailable else { return nil }
        let request = SFSpeechURLRecognitionRequest(url: url)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        return await withCheckedContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if error != nil {
                    finished = true
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}
