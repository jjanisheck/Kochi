import AVFoundation
import Speech
import Combine

class AudioManager: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var isRecording = false
    /// True while the saved audio is being re-transcribed on-device for a higher-accuracy transcript.
    @Published var isRefiningTranscript = false
    @Published var audioLevel: Float = 0.0
    @Published var recordingTime: TimeInterval = 0
    @Published var transcriptionText = ""
    @Published var coachingResponse = ""
    @Published var hasPermission = false
    
    // MARK: - Audio Properties
    private var audioEngine: AVAudioEngine?
    /// Records a mixed mic + system-audio AAC (.m4a) file for the meeting.
    private var mixedRecorder: MixedAudioRecorder?
    private var audioPlayer: AVAudioPlayer?
    private var levelTimer: Timer?
    private var recordingTimer: Timer?
    private var audioEngineMonitor: Timer?
    private var lastAudioBufferTime: Date?
    
    // MARK: - Transcription
    // The active live path is the on-device DualTranscriptionEngine
    // (Apple Speech — fully on-device, no API key).
    @Published var dualEngine = DualTranscriptionEngine()
    /// Capture the far side of a call (system audio) in addition to the mic.
    @Published var captureSystemAudio = true
    private var audioBufferDelegate: AudioBufferDelegate?

    // MARK: - File Management
    private let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    private var currentRecordingURL: URL?
    let meetingFileManager = MeetingFileManager()
    /// Folder name of the meeting currently/just recorded — links a MeetingSession to its audio.
    private(set) var activeMeetingFolderName: String?

    // MARK: - Combine
    private var cancellables = Set<AnyCancellable>()
    
    override init() {
        super.init()
        setupAudioSession()
        setupTranscriptionBinding()
    }
    
    // MARK: - Setup
    private func setupAudioSession() {
        // macOS: AVAudioEngine's input node works without an audio session.
    }

    func requestMicrophonePermission() {
        // AVCaptureDevice authorization is the on-device microphone permission path on macOS.
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                self?.hasPermission = granted
                if granted {
                    self?.requestSpeechRecognitionPermission()
                }
            }
        }
    }
    
    private func requestSpeechRecognitionPermission() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                self?.hasPermission = status == .authorized
            }
        }
    }
    
    private func setupTranscriptionBinding() {
        // Live transcript now comes from the on-device dual-channel engine.
        dualEngine.$transcriptionText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newText in
                guard let self = self else { return }
                self.transcriptionText = newText
                // Write to disk immediately as transcript updates (crash-safe, with timestamp)
                self.meetingFileManager.appendToTranscript(newText, currentTime: self.recordingTime)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Recording
    func startRecording() {
        guard hasPermission else { return }

        // Create meeting folder and get audio file URL
        guard meetingFileManager.startNewMeeting() != nil else {
            print("❌ Failed to create meeting folder")
            return
        }

        // Audio recording goes in the meeting folder (mixed mic + system audio, AAC .m4a).
        currentRecordingURL = meetingFileManager.getAudioFileURL()
        activeMeetingFolderName = meetingFileManager.currentMeetingURL?.lastPathComponent
        guard let recordingURL = currentRecordingURL else {
            print("❌ No audio file URL")
            return
        }

        let recorder = MixedAudioRecorder()
        recorder.start(url: recordingURL)
        mixedRecorder = recorder
        // Feed the captured far-side ("Them") audio into the mix.
        dualEngine.onSystemAudioBuffer = { [weak self] buffer in
            self?.mixedRecorder?.appendSystem(buffer)
        }

        isRecording = true
        startMetering()
        startRecordingTimer()
        startSpeechRecognition()
    }
    
    func stopRecording() {
        mixedRecorder?.stop()
        mixedRecorder = nil
        isRecording = false
        stopMetering()

        let finalDuration = recordingTime
        let finalTranscript = transcriptionText

        stopRecordingTimer()
        stopSpeechRecognition()

        // Finalize meeting folder with complete transcript
        meetingFileManager.endMeeting(finalTranscript: finalTranscript, duration: finalDuration)

        // NOTE: automatic post-recording refinement is intentionally disabled. It
        // re-transcribed the MIXED audio as a single stream, which collapsed the
        // Me/Them conversation into one paragraph. We keep the live, dual-channel
        // (speaker-separated) transcript so the two inputs stay distinct.

        // Save recording metadata (legacy)
        if let url = currentRecordingURL {
            saveRecordingMetadata(url: url)
        }

        // Post notification that recording stopped
        NotificationCenter.default.post(name: .recordingStopped, object: transcriptionText)

        print("🏁 Recording stopped. Transcript saved: \(finalTranscript.count) characters")
    }

    // Stop only audio recording, keep speech recognition running
    func stopRecordingOnly() {
        mixedRecorder?.stop()
        mixedRecorder = nil
        isRecording = false
        stopMetering()
        stopRecordingTimer()
        // NOTE: Speech recognition continues running to capture final transcription
    }

    // Stop speech recognition manually (called after capturing full transcript)
    func stopSpeechRecognitionManually() {
        stopSpeechRecognition()

        // Save recording metadata
        if let url = currentRecordingURL {
            saveRecordingMetadata(url: url)
        }

        // Post notification that recording stopped
        NotificationCenter.default.post(name: .recordingStopped, object: transcriptionText)
    }
    
    // MARK: - Metering
    private func startMetering() {
        levelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let level = self.mixedRecorder?.latestMicPowerDb ?? -160
            let normalizedLevel = self.normalizeLevel(level)

            DispatchQueue.main.async {
                self.audioLevel = normalizedLevel
            }
        }
    }
    
    private func stopMetering() {
        levelTimer?.invalidate()
        levelTimer = nil

        DispatchQueue.main.async {
            self.audioLevel = 0
        }
    }
    
    private func normalizeLevel(_ level: Float) -> Float {
        let minDb: Float = -60
        let maxDb: Float = 0
        
        if level < minDb {
            return 0
        } else if level > maxDb {
            return 1
        } else {
            return (level - minDb) / (maxDb - minDb)
        }
    }
    
    // MARK: - Timer
    private func startRecordingTimer() {
        recordingTime = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                self?.recordingTime += 1
            }
        }
    }
    
    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil

        DispatchQueue.main.async {
            self.recordingTime = 0
        }
    }
    
    // MARK: - Speech Recognition
    private func startSpeechRecognition() {
        print("🎤 Starting on-device dual-channel transcription...")

        // Reset transcription for new recording
        transcriptionText = ""

        // Start the on-device engine (mic = "Me", system audio = "Them").
        dualEngine.start(includeSystemAudio: captureSystemAudio)

        // Setup audio engine for real-time transcription
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ Failed to create audio engine")
            return
        }

        do {
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            print("🎤 Audio format: \(recordingFormat)")
            print("🎤 Sample rate: \(recordingFormat.sampleRate)")
            print("🎤 Channel count: \(recordingFormat.channelCount)")

            // Create buffer delegate for transcription
            var bufferCount = 0
            var lastBufferTime = Date()
            audioBufferDelegate = AudioBufferDelegate { [weak self] buffer in
                bufferCount += 1
                let now = Date()
                let timeSinceLastBuffer = now.timeIntervalSince(lastBufferTime)

                if bufferCount % 100 == 0 {
                    print("🎤 Processed \(bufferCount) audio buffers (gap: \(String(format: "%.2f", timeSinceLastBuffer))s)")
                }

                // Detect if buffers stopped arriving (gap > 1 second is abnormal)
                if timeSinceLastBuffer > 1.0 {
                    print("⚠️ LARGE BUFFER GAP: \(String(format: "%.2f", timeSinceLastBuffer))s - audio tap may have stopped!")
                }

                lastBufferTime = now

                guard let self = self else { return }

                // Track buffer arrival for watchdog
                DispatchQueue.main.async {
                    self.lastAudioBufferTime = Date()
                }

                // Feed the mic buffer to the on-device engine ("Me" channel)
                // and to the mixed recorder (master clock for the saved .m4a).
                self.dualEngine.appendMicBuffer(buffer)
                self.mixedRecorder?.appendMic(buffer)
            }

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.audioBufferDelegate?.processBuffer(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()

            // Start watchdog timer to detect if audio tap stops
            lastAudioBufferTime = Date()
            startAudioEngineMonitor()

            print("✅ Cloud transcription started successfully")

        } catch {
            print("❌ Speech recognition error: \(error)")
        }
    }
    
    private func startAudioEngineMonitor() {
        audioEngineMonitor?.invalidate()
        audioEngineMonitor = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, let audioEngine = self.audioEngine else { return }

            DispatchQueue.main.async {
                let isRunning = audioEngine.isRunning
                let timeSinceLastBuffer = Date().timeIntervalSince(self.lastAudioBufferTime ?? Date())

                // Check if audio engine stopped or buffers stopped arriving
                if !isRunning {
                    print("❌ AUDIO ENGINE STOPPED! Attempting restart...")
                    self.restartAudioEngine()
                } else if timeSinceLastBuffer > 3.0 {
                    print("⚠️ NO AUDIO BUFFERS for \(String(format: "%.1f", timeSinceLastBuffer))s - engine running: \(isRunning)")
                    // Engine is running but no buffers - something is wrong
                    print("🔧 Audio engine status: running=\(isRunning), tap installed")
                }
            }
        }
    }

    private func stopAudioEngineMonitor() {
        audioEngineMonitor?.invalidate()
        audioEngineMonitor = nil
    }

    private func restartAudioEngine() {
        guard let audioEngine = audioEngine else { return }
        print("🔄 Restarting audio engine...")

        do {
            // Remove old tap
            audioEngine.inputNode.removeTap(onBus: 0)

            // Reinstall tap
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.audioBufferDelegate?.processBuffer(buffer)
            }

            // Restart engine
            audioEngine.prepare()
            try audioEngine.start()

            lastAudioBufferTime = Date()
            print("✅ Audio engine restarted successfully")
        } catch {
            print("❌ Failed to restart audio engine: \(error)")
        }
    }

    private func stopSpeechRecognition() {
        stopAudioEngineMonitor()
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        dualEngine.stop()

        audioEngine = nil
        audioBufferDelegate = nil
        lastAudioBufferTime = nil
    }
    
    // MARK: - File Management
    private func saveRecordingMetadata(url: URL) {
        _ = RecordingMetadata(
            url: url,
            date: Date(),
            duration: recordingTime,
            transcription: transcriptionText
        )

        // Save to Core Data or UserDefaults
        // This will be implemented with Core Data integration
    }
    
    func getRecordings() -> [RecordingMetadata] {
        // Return saved recordings from Core Data
        return []
    }
    
    func playRecording(url: URL) {
        do {
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
        } catch {
            print("Failed to play recording: \(error)")
        }
    }
    
    func deleteRecording(url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            print("Failed to delete recording: \(error)")
        }
    }
}

// MARK: - Recording Metadata
struct RecordingMetadata: Identifiable, Codable {
    var id = UUID()
    let url: URL
    let date: Date
    let duration: TimeInterval
    let transcription: String
}

// MARK: - Audio Buffer Delegate
class AudioBufferDelegate {
    private let processBuffer: (AVAudioPCMBuffer) -> Void

    init(processBuffer: @escaping (AVAudioPCMBuffer) -> Void) {
        self.processBuffer = processBuffer
    }

    func processBuffer(_ buffer: AVAudioPCMBuffer) {
        processBuffer(buffer)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let recordingStopped = Notification.Name("recordingStopped")
}