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
    /// Recent loudness, newest last, for the live bars.
    @Published private(set) var levels: [Float] = []
    var isActive: Bool { currentFile != nil }

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private var currentFile: URL?
    var currentURL: URL? { currentFile }

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
        levels = []
        startMeter()
    }

    private func startMeter() {
        meterTimer?.invalidate()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let recorder = self.recorder, recorder.isRecording else { return }
                recorder.updateMeters()
                var l = max(0, (recorder.averagePower(forChannel: 0) + 50) / 50)
                if DemoData.isDemo { l = Float.random(in: 0.25...1) }   // simulator mic is silent
                self.level = l
                self.levels.append(l)
                if self.levels.count > 80 { self.levels.removeFirst(self.levels.count - 80) }
                self.elapsed = recorder.currentTime
            }
        }
    }

    /// Sliding away discards the recording.
    func cancel() {
        recorder?.stop()
        recorder?.deleteRecording()
        meterTimer?.invalidate()
        recorder = nil
        currentFile = nil
        isRecording = false
        levels = []
        elapsed = 0
    }

    /// Finish capture for review without discarding the file or its waveform.
    func finishForReview() {
        guard isRecording else { return }
        recorder?.stop()
        meterTimer?.invalidate()
        isRecording = false
    }

    /// Stops, saves the entry, then fills in the transcript when it's ready.
    func stop(context: ModelContext, coordinate: (Double, Double)?) async -> JournalEntry? {
        guard let recorder, let file = currentFile else { return nil }
        let duration = max(recorder.currentTime, elapsed)
        if duration < 1.0 { cancel(); return nil }
        recorder.stop()
        meterTimer?.invalidate()
        isRecording = false
        levels = []
        self.recorder = nil
        currentFile = nil

        let entry = JournalEntry(date: .now, kind: .voice, text: "", audioFileName: file.lastPathComponent,
                                 audioDuration: duration, latitude: coordinate?.0, longitude: coordinate?.1)
        context.insert(entry)
        try? context.save()

        // Transcribe in the background so the note shows up in the entry right away
        // (and Save links it), instead of waiting for speech-to-text to finish.
        Task { @MainActor in
            if let text = await Transcriber.transcribe(file), !text.isEmpty {
                entry.text = text
                entry.isTranscribed = true
            } else {
                entry.transcriptionFailed = true
            }
            try? context.save()
        }
        return entry
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
        // Apple's on-device engine when available; use Apple's Speech service otherwise.
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.shouldReportPartialResults = true
        return await withCheckedContinuation { continuation in
            var resolved = false
            var best = ""
            var recognition: SFSpeechRecognitionTask?
            func finish(_ text: String?) {
                guard !resolved else { return }
                resolved = true
                recognition?.cancel()
                continuation.resume(returning: text?.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            recognition = recognizer.recognitionTask(with: request) { result, error in
                DispatchQueue.main.async {
                    if let result { best = result.bestTranscription.formattedString }
                    if result?.isFinal == true || error != nil { finish(best.isEmpty ? nil : best) }
                }
            }
            // Some recognizer versions return partial words without an isFinal callback.
            // Conclude with those words rather than leaving the journal stuck forever.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                finish(best.isEmpty ? nil : best)
            }
        }
    }
}
