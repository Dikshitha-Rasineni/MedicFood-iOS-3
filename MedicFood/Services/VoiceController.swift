import AVFoundation
import Observation

/// Records and plays back a spoken instruction ("take this with warm water").
///
/// Everything here is `@MainActor`, and the duration ticker is a `Task` that
/// inherits that isolation — there is no `Timer` closure reaching into
/// main-actor state from a nonisolated context.
@MainActor
@Observable
final class VoiceController {

    private(set) var isRecording = false
    private(set) var isPlaying = false
    private(set) var duration: TimeInterval = 0
    private(set) var fileName: String?
    private(set) var permissionDenied = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var player: AVAudioPlayer?
    @ObservationIgnored private var ticker: Task<Void, Never>?
    /// Files recorded in this session, so only those are ever deleted here.
    @ObservationIgnored private var sessionFiles: Set<String> = []

    var hasRecording: Bool { fileName != nil }

    static func format(_ time: TimeInterval) -> String {
        let total = max(0, Int(time.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Attach a recording that already exists on disk.
    func load(fileName: String?) {
        guard let fileName, MediaStore.exists(fileName) else { return }
        self.fileName = fileName
        duration = (try? AVAudioPlayer(contentsOf: MediaStore.url(for: fileName)))?.duration ?? 0
    }

    // MARK: Recording

    func startRecording() async {
        errorMessage = nil
        stopPlayback()

        let granted = await AVAudioApplication.requestRecordPermission()
        guard granted else {
            permissionDenied = true
            return
        }
        permissionDenied = false

        do {
            let session = AVAudioSession.sharedInstance()
            var options: AVAudioSession.CategoryOptions = [.defaultToSpeaker]
            if #available(iOS 18.0, *) {
                options.insert(.allowBluetoothHFP)
            } else {
                options.insert(.allowBluetooth)
            }
            try session.setCategory(.playAndRecord, mode: .default, options: options)
            try session.setActive(true)

            let name = "voice-\(UUID().uuidString).m4a"
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            let newRecorder = try AVAudioRecorder(url: MediaStore.url(for: name), settings: settings)
            guard newRecorder.record() else {
                errorMessage = "Unable to start recording."
                return
            }

            // Re-recording replaces the previous take from this session.
            if let previous = fileName, sessionFiles.contains(previous) {
                MediaStore.delete(previous)
                sessionFiles.remove(previous)
            }

            recorder = newRecorder
            sessionFiles.insert(name)
            fileName = name
            duration = 0
            isRecording = true
            startTicker()
        } catch {
            errorMessage = "Unable to start recording."
        }
    }

    func stopRecording() {
        guard isRecording else { return }
        duration = recorder?.currentTime ?? duration
        recorder?.stop()
        recorder = nil
        isRecording = false
    }

    func delete() {
        stopRecording()
        stopPlayback()
        if let fileName, sessionFiles.contains(fileName) {
            MediaStore.delete(fileName)
            sessionFiles.remove(fileName)
        }
        fileName = nil
        duration = 0
    }

    // MARK: Playback

    func togglePlayback() {
        isPlaying ? stopPlayback() : play()
    }

    func play() {
        guard let fileName, !isRecording else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            let newPlayer = try AVAudioPlayer(contentsOf: MediaStore.url(for: fileName))
            guard newPlayer.play() else { return }
            player = newPlayer
            isPlaying = true
            startTicker()
        } catch {
            errorMessage = "Unable to play the recording."
        }
    }

    func stopPlayback() {
        player?.stop()
        player = nil
        isPlaying = false
    }

    // MARK: Ticker

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(200))
                guard let self else { return }
                if self.isRecording {
                    self.duration = self.recorder?.currentTime ?? self.duration
                } else if self.isPlaying, self.player?.isPlaying != true {
                    self.isPlaying = false
                }
                if !self.isRecording && !self.isPlaying { return }
            }
        }
    }
}
