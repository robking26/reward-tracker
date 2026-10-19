import AVFoundation
import Foundation
import Observation
import Speech

/// Speech to text for the coach (V1–V2). Uses on-device recognition when the device supports it, so nothing
/// you say leaves the phone; otherwise it says so and still works.
@MainActor
@Observable
final class Dictation {
    private(set) var isRecording = false
    private(set) var transcript = ""
    private(set) var errorMessage: String? = nil
    private(set) var isOnDevice = false

    @ObservationIgnored private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-GB"))
    @ObservationIgnored private var engine: AVAudioEngine? = nil
    @ObservationIgnored private var request: SFSpeechAudioBufferRecognitionRequest? = nil
    @ObservationIgnored private var task: SFSpeechRecognitionTask? = nil

    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        guard await Self.speechAuthorised() else {
            errorMessage = "Speech recognition isn't allowed. Turn it on in Settings › Vaultality."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access isn't allowed. Turn it on in Settings › Vaultality."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Dictation isn't available right now. You can type instead."
            return
        }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.record, mode: .measurement, options: .duckOthers)
            try session.setActive(true, options: .notifyOthersOnDeactivation)

            let engine = AVAudioEngine()
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            isOnDevice = recognizer.supportsOnDeviceRecognition
            if isOnDevice { request.requiresOnDeviceRecognition = true }

            Self.installTap(on: engine.inputNode, feeding: request)
            engine.prepare()
            try engine.start()

            transcript = ""
            self.engine = engine
            self.request = request
            isRecording = true
            task = Self.recognise(with: recognizer, request: request) { [weak self] text, finished in
                Task { @MainActor in
                    guard let self else { return }
                    if let text { self.transcript = text }
                    if finished { self.finish() }
                }
            }
        } catch {
            errorMessage = "Couldn't start the microphone. \(error.localizedDescription)"
            finish()
        }
    }

    /// Stops listening; the final words still arrive through the recognition callback.
    func stop() {
        request?.endAudio()
        engine?.stop()
        engine?.inputNode.removeTap(onBus: 0)
        engine = nil
        isRecording = false
    }

    private func finish() {
        stop()
        task = nil
        request = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // Audio and recognition callbacks run on background threads, so they're created outside the main actor.
    nonisolated private static func installTap(on input: AVAudioInputNode, feeding request: SFSpeechAudioBufferRecognitionRequest) {
        input.installTap(onBus: 0, bufferSize: 1_024, format: input.outputFormat(forBus: 0)) { buffer, _ in
            request.append(buffer)
        }
    }

    nonisolated private static func recognise(with recognizer: SFSpeechRecognizer, request: SFSpeechAudioBufferRecognitionRequest,
                                              update: @escaping @Sendable (String?, Bool) -> Void) -> SFSpeechRecognitionTask {
        recognizer.recognitionTask(with: request) { result, error in
            update(result?.bestTranscription.formattedString, error != nil || (result?.isFinal ?? false))
        }
    }

    nonisolated private static func speechAuthorised() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .denied, .restricted: return false
        default:
            return await withCheckedContinuation { continuation in
                SFSpeechRecognizer.requestAuthorization { status in
                    continuation.resume(returning: status == .authorized)
                }
            }
        }
    }
}
