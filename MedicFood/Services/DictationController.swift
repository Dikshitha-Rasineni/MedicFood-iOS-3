import AVFoundation
import Observation
import Speech

/// Listens, and turns what is said into text as it is said.
///
/// This is the first half of "add a medicine by speaking". It only produces a
/// transcript — the person sees it appear, can correct it, and only then is it
/// turned into a medicine. Recognition is on-device when the phone supports it,
/// so for most phones nothing is sent anywhere at this step.
///
/// Kept deliberately thin. Everything in here is the platform's speech stack,
/// which does not run reliably in the Simulator, so the logic worth testing
/// lives in the view model that consumes the transcript instead.
@MainActor
@Observable
final class DictationController {

    enum State: Equatable {
        case idle
        case listening
        /// The user said no, or the phone cannot do it. Carries what to show.
        case blocked(String)
    }

    private(set) var state: State = .idle
    /// The words so far. Updated live while listening.
    private(set) var transcript = ""

    var isListening: Bool { state == .listening }

    /// Called once, with the final transcript, when listening ends.
    var onFinished: ((String) -> Void)?

    private let recognizer: SFSpeechRecognizer?
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTask: Task<Void, Never>?
    private var didFinish = false

    /// Stop on its own after this long with no new words, so a person who has
    /// finished speaking does not have to find the button again.
    private static let silenceTimeout: Duration = .seconds(3)

    init(locale: Locale = Locale(identifier: "en-IN")) {
        // Indian English first, since the names and shorthand this is built for
        // are Indian ones; the system default when it is not offered.
        recognizer = SFSpeechRecognizer(locale: locale) ?? SFSpeechRecognizer()
    }

    // MARK: - Control

    func toggle() async {
        if isListening { stop() } else { await start() }
    }

    func start() async {
        guard !isListening else { return }

        guard let recognizer, recognizer.isAvailable else {
            state = .blocked("Speech recognition is not available on this device right now.")
            return
        }
        guard await Self.speechAllowed() else {
            state = .blocked("Allow Speech Recognition for MedicFood in Settings to use your voice.")
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            state = .blocked("Allow Microphone access for MedicFood in Settings to use your voice.")
            return
        }

        do {
            try begin(with: recognizer)
        } catch {
            teardown()
            state = .blocked("Could not start listening. Check that no other app is using the microphone.")
        }
    }

    func stop() {
        guard isListening else { return }
        finish()
    }

    // MARK: - Internals

    private func begin(with recognizer: SFSpeechRecognizer) throws {
        transcript = ""
        didFinish = false

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        // Keep it on the phone whenever the phone can.
        if recognizer.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        // Medicine names are not everyday words; this nudges the recogniser
        // toward the vocabulary of a prescription.
        request.contextualStrings = ["milligrams", "tablet", "capsule", "twice a day", "after food",
                                     "before food", "at night", "once a week", "paracetamol",
                                     "metformin", "amoxicillin", "vitamin D"]
        self.request = request

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak request] buffer, _ in
            request?.append(buffer)
        }

        engine.prepare()
        try engine.start()

        task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            // The platform calls back off the main thread.
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor [weak self] in
                self?.handle(text: text, isFinal: isFinal, failed: failed)
            }
        }

        state = .listening
        armSilenceTimer()
    }

    private func handle(text: String?, isFinal: Bool, failed: Bool) {
        if let text, !text.isEmpty {
            transcript = text
            armSilenceTimer()
        }
        // An error after the user has stopped is the normal end of a task, not
        // a failure; either way the transcript so far is what they get.
        if isFinal || failed { finish() }
    }

    private func armSilenceTimer() {
        silenceTask?.cancel()
        silenceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.silenceTimeout)
            guard !Task.isCancelled else { return }
            self?.stop()
        }
    }

    private func finish() {
        guard !didFinish else { return }
        didFinish = true
        teardown()
        state = .idle
        onFinished?(transcript)
    }

    private func teardown() {
        silenceTask?.cancel()
        silenceTask = nil
        if engine.isRunning { engine.stop() }
        engine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        task?.cancel()
        request = nil
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private static func speechAllowed() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
}
