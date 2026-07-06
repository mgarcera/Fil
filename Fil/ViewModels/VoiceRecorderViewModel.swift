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

        // Keep transcription on-device whenever the recognizer supports it, so voice audio
        // never leaves the phone — matching Fil's local-first privacy promise.
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let resumeGuard = TranscriptionResumeGuard()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                // Store the continuation (and arm the timeout) before starting the task, so a
                // fast callback can never race ahead of the guard.
                resumeGuard.store(continuation: continuation, timeout: 60)
                let task = recognizer.recognitionTask(with: request) { result, error in
                    if let error {
                        resumeGuard.finish(.failure(error))
                        return
                    }
                    if let result, result.isFinal {
                        resumeGuard.finish(.success(result.bestTranscription.formattedString))
                    }
                }
                resumeGuard.attach(task: task)
            }
        } onCancel: {
            resumeGuard.cancel()
        }
    }

    enum PermissionStatus {
        case authorized
        case notDetermined
        case denied
    }

    /// The combined microphone + speech authorization state, read *without* prompting — so the UI
    /// can show a priming screen before the first system dialog and route to Settings after a
    /// denial. Denied if either is denied; not-determined if either is still undecided.
    var permissionStatus: PermissionStatus {
        #if os(iOS)
        let micStatus: PermissionStatus
        switch AVAudioApplication.shared.recordPermission {
        case .granted: micStatus = .authorized
        case .denied: micStatus = .denied
        default: micStatus = .notDetermined
        }
        #else
        let micStatus: PermissionStatus = .authorized
        #endif

        let speechStatus: PermissionStatus
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: speechStatus = .authorized
        case .denied, .restricted: speechStatus = .denied
        default: speechStatus = .notDetermined
        }

        if micStatus == .denied || speechStatus == .denied { return .denied }
        if micStatus == .notDetermined || speechStatus == .notDetermined { return .notDetermined }
        return .authorized
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
    case timedOut

    var errorDescription: String? {
        switch self {
        case .unavailable: "Speech recognition is not available"
        case .timedOut: "Transcription took too long"
        }
    }
}

/// Guarantees a speech-recognition continuation is resumed exactly once — on the first of
/// success, error, a safety timeout, or task cancellation — and stops the underlying recognition
/// task afterward. Without this, a recognition that never reports `isFinal` (a stall, an abnormal
/// termination) leaks the continuation and hangs fil creation in the "creating…" state forever.
private nonisolated final class TranscriptionResumeGuard: @unchecked Sendable {
    private let lock = NSLock()
    private var resumed = false
    private var continuation: CheckedContinuation<String, Error>?
    private var task: SFSpeechRecognitionTask?
    private var timeoutTask: Task<Void, Never>?

    func store(continuation: CheckedContinuation<String, Error>, timeout seconds: TimeInterval) {
        lock.lock()
        self.continuation = continuation
        lock.unlock()
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            self?.finish(.failure(TranscriptionError.timedOut))
        }
    }

    func attach(task: SFSpeechRecognitionTask) {
        lock.lock()
        self.task = task
        let alreadyResumed = resumed
        lock.unlock()
        // If we already finished (e.g. an immediate timeout) before the task was attached,
        // make sure the recognition doesn't keep running.
        if alreadyResumed { task.cancel() }
    }

    func finish(_ result: Result<String, Error>) {
        lock.lock()
        if resumed {
            lock.unlock()
            return
        }
        resumed = true
        let continuation = self.continuation
        let task = self.task
        let timeoutTask = self.timeoutTask
        self.continuation = nil
        lock.unlock()

        timeoutTask?.cancel()
        task?.cancel()
        continuation?.resume(with: result)
    }

    func cancel() {
        finish(.failure(CancellationError()))
    }
}
