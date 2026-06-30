import AVFoundation
import Speech
import SwiftUI

@Observable
final class VoiceRecorderViewModel {
    var isRecording = false
    var recordingDuration: TimeInterval = 0
    var isProcessing = false
    var errorMessage: String?

    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    private var currentRecordingURL: URL?

    @MainActor
    func startRecording() async {
        guard await AudioSessionCoordinator.configurePlayAndRecord() else {
            errorMessage = "Failed to set up audio session"
            return
        }

        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("\(UUID().uuidString).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.record()
            currentRecordingURL = url
            isRecording = true
            recordingDuration = 0
            startTimer()
        } catch {
            errorMessage = "Failed to start recording"
        }
    }

    func stopRecording() -> (url: URL, duration: TimeInterval)? {
        audioRecorder?.stop()
        let duration = recordingDuration
        isRecording = false
        stopTimer()
        guard let url = currentRecordingURL else { return nil }
        return (url, duration)
    }

    func transcribe(url: URL) async throws -> String {
        let recognizer = SFSpeechRecognizer()
        guard let recognizer, recognizer.isAvailable else {
            throw TranscriptionError.unavailable
        }

        let request = SFSpeechURLRecognitionRequest(url: url)
        request.shouldReportPartialResults = false

        return try await withCheckedThrowingContinuation { continuation in
            recognizer.recognitionTask(with: request) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if let result, result.isFinal {
                    continuation.resume(returning: result.bestTranscription.formattedString)
                }
            }
        }
    }

    func requestPermissions() async -> Bool {
        #if os(iOS)
        let audioGranted = await withCheckedContinuation { continuation in
            if #available(iOS 17, *) {
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            } else {
                AVAudioSession.sharedInstance().requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        #else
        let audioGranted = await AVCaptureDevice.requestAccess(for: .audio)
        #endif

        let speechGranted = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }

        return audioGranted && speechGranted
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

enum TranscriptionError: LocalizedError {
    case unavailable

    var errorDescription: String? {
        switch self {
        case .unavailable: "Speech recognition is not available"
        }
    }
}
