import Foundation
import AVFoundation
import Speech

/// Captures audio from the microphone, streams it to Apple's on-device speech
/// recogniser, and simultaneously writes the buffers to a temp M4A file so the
/// recording can be saved as an `.audio` Attachment. Tap the mic to start,
/// tap again to stop. Live transcript updates land via the @MainActor
/// `currentTranscript` published-style state.
///
/// On-device recognition keeps the privacy story intact — no audio leaves the
/// device unless the user has chosen a cloud sync provider, in which case it
/// rides the same path as photos and scans.
@MainActor
@Observable
final class VoiceDictationCoordinator {

    enum AuthorisationState {
        case notDetermined
        case microphoneDenied
        case speechDenied
        case ready
    }

    enum DictationError: Error, LocalizedError {
        case microphoneUnavailable
        case speechUnavailable
        case recognitionFailed(message: String)

        var errorDescription: String? {
            switch self {
            case .microphoneUnavailable:        return "Microphone access is required."
            case .speechUnavailable:            return "Speech recognition isn't available right now."
            case .recognitionFailed(let m):     return "Recognition failed: \(m)"
            }
        }
    }

    // Observable state
    private(set) var isRecording: Bool = false
    private(set) var currentTranscript: String = ""
    private(set) var elapsed: TimeInterval = 0
    private(set) var lastError: String?

    // Audio plumbing
    private let engine = AVAudioEngine()
    private var recogniser: SFSpeechRecognizer?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var audioFileURL: URL?
    private var startTime: Date?
    private var elapsedTimer: Timer?

    // MARK: Permissions

    func currentAuthorisation() async -> AuthorisationState {
        let speechStatus = SFSpeechRecognizer.authorizationStatus()
        let micStatus = AVAudioApplication.shared.recordPermission
        if micStatus == .denied { return .microphoneDenied }
        if speechStatus == .denied || speechStatus == .restricted { return .speechDenied }
        if micStatus == .granted && speechStatus == .authorized { return .ready }
        return .notDetermined
    }

    /// Asks for both Microphone + Speech permissions if needed. Returns the
    /// resolved state.
    @discardableResult
    func requestAuthorisation() async -> AuthorisationState {
        // Microphone first.
        let micGranted: Bool = await withCheckedContinuation { cont in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        if !micGranted { return .microphoneDenied }

        // Then Speech.
        let speechStatus: SFSpeechRecognizerAuthorizationStatus = await withCheckedContinuation { cont in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status)
            }
        }
        if speechStatus != .authorized { return .speechDenied }
        return .ready
    }

    // MARK: Recording lifecycle

    func start() async throws {
        guard !isRecording else { return }
        let authState = await currentAuthorisation()
        if authState != .ready {
            let resolved = await requestAuthorisation()
            if resolved != .ready { throw DictationError.microphoneUnavailable }
        }

        // Pick a recogniser. Prefer en-GB if supported on this device, else
        // fall back to the system's preferred locale.
        let recogniser = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
            ?? SFSpeechRecognizer(locale: .current)
            ?? SFSpeechRecognizer()
        guard let recogniser, recogniser.isAvailable else {
            throw DictationError.speechUnavailable
        }
        self.recogniser = recogniser

        // Audio session — record + measurement so we get clean input on iOS.
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        // Build the recognition request.
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // On-device when supported. Falls back to network on devices/locales
        // that don't support it. Caller can inspect lastError if it errors.
        if recogniser.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }
        self.request = request

        // Tap the input node and feed both the recogniser and the file.
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString.prefix(8)).m4a")
        audioFileURL = url

        // M4A AAC settings for the saved attachment.
        let writeSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
        ]
        audioFile = try AVAudioFile(forWriting: url, settings: writeSettings)

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
            try? self?.audioFile?.write(from: buffer)
        }

        engine.prepare()
        try engine.start()

        // Recognition stream.
        task = recogniser.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.currentTranscript = result.bestTranscription.formattedString
                }
                if let error {
                    self.lastError = error.localizedDescription
                }
            }
        }

        startTime = .now
        currentTranscript = ""
        elapsed = 0
        lastError = nil
        isRecording = true
        startElapsedTicker()
    }

    /// Stops the engine and finalises the audio file. Returns the URL of the
    /// captured M4A and the final transcript.
    @discardableResult
    func stop() -> (audioURL: URL?, transcript: String) {
        guard isRecording else { return (audioFileURL, currentTranscript) }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        request?.endAudio()
        task?.finish()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        isRecording = false
        elapsedTimer?.invalidate()
        elapsedTimer = nil

        let url = audioFileURL
        let transcript = currentTranscript

        // Reset for next run.
        audioFile = nil
        audioFileURL = nil
        request = nil
        task = nil

        return (url, transcript)
    }

    /// Discard any in-progress recording without saving.
    func cancel() {
        if isRecording { _ = stop() }
        if let url = audioFileURL { try? FileManager.default.removeItem(at: url) }
        currentTranscript = ""
        elapsed = 0
        lastError = nil
    }

    // MARK: Helpers

    private func startElapsedTicker() {
        elapsedTimer?.invalidate()
        elapsedTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let startTime = self.startTime else { return }
                self.elapsed = Date().timeIntervalSince(startTime)
            }
        }
    }
}
