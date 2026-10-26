import AVFoundation
import Speech
import Combine
#if os(iOS)
import UIKit
#endif

class AudioManager: NSObject, ObservableObject, @unchecked Sendable {
    // MARK: - Published Properties
    @Published var isRecording = false
    /// True while the saved audio is being re-transcribed on-device for a higher-accuracy transcript.
    @Published var isRefiningTranscript = false
    @Published var audioLevel: Float = 0.0
    @Published var recordingTime: TimeInterval = 0
    @Published var transcriptionText = ""
    @Published var transcriptLines: [TranscriptLine] = []
    @Published private(set) var transcriptionStatus: LiveTranscriptionStatus = .idle
    @Published private(set) var recordingFailure: String?
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
    private let captureClock = RecordingCaptureClock()
    private var recordingStartedAt: TimeInterval = 0
    private var captureInterrupted = false
    
    // MARK: - Transcription
    // The active live path is the on-device DualTranscriptionEngine
    // (Apple Speech — fully on-device, no API key).
    @Published var dualEngine = DualTranscriptionEngine()
    /// Capture the far side of a call (system audio) in addition to the mic.
    /// macOS only — iOS is mic-only (no ScreenCaptureKit equivalent).
    #if os(macOS)
    @Published var captureSystemAudio = true
    #else
    @Published var captureSystemAudio = false
    #endif
    private var audioBufferDelegate: AudioBufferDelegate?
    private var audioTapInstalled = false

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
        setupCaptureNotifications()
    }
    
    // MARK: - Setup
    private func setupAudioSession() {
        #if os(iOS)
        // iOS requires an active audio session before AVAudioEngine can tap the mic.
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
            try session.setActive(true)
        } catch {
            print("⚠️ AVAudioSession setup failed: \(error)")
        }
        #endif
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
        dualEngine.$lines
            .sink { [weak self] lines in self?.transcriptLines = lines }
            .store(in: &cancellables)
        dualEngine.$micStatus
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.transcriptionStatus = status
                RecordingDiagnostics.shared.event("speech_status", ["status": status.message])
            }
            .store(in: &cancellables)
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
        guard hasPermission, !isRecording else { return }
        recordingFailure = nil
        captureInterrupted = false
        setupAudioSession()

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
        recorder.onFailure = { [weak self] message in
            DispatchQueue.main.async { self?.failRecording(message) }
        }
        do { try recorder.start(url: recordingURL) }
        catch {
            recordingFailure = "Recording couldn't start: \(error.localizedDescription)"
            return
        }
        mixedRecorder = recorder
        if let folder = meetingFileManager.currentMeetingURL {
            RecordingDiagnostics.shared.start(meetingFolder: folder, audioURL: recordingURL)
        }
        // Feed the captured far-side ("Them") audio into the mix.
        dualEngine.onSystemAudioBuffer = { [weak recorder] buffer in
            recorder?.appendSystem(buffer)
        }

        isRecording = true
        startMetering()
        startRecordingTimer()
        startSpeechRecognition()
    }
    
    func stopRecording() {
        guard isRecording else { return }
        let finalDuration = max(recordingTime, ProcessInfo.processInfo.systemUptime - recordingStartedAt)
        let finalTranscript = transcriptionText
        // Stop the producer first, then drain/finalize the serial audio writer.
        stopSpeechRecognition()
        mixedRecorder?.stop()
        mixedRecorder = nil
        isRecording = false
        stopMetering()

        stopRecordingTimer()

        // Finalize meeting folder with complete transcript
        meetingFileManager.endMeeting(finalTranscript: finalTranscript, duration: finalDuration)
        RecordingDiagnostics.shared.finish(seconds: finalDuration, reason: recordingFailure == nil ? "user_stopped" : "capture_error")

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
        recordingStartedAt = ProcessInfo.processInfo.systemUptime
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self else { return }
            let previous = Int(self.recordingTime) / 10
            self.recordingTime = ProcessInfo.processInfo.systemUptime - self.recordingStartedAt
            if Int(self.recordingTime) / 10 != previous {
                RecordingDiagnostics.shared.sample(seconds: self.recordingTime,
                    transcriptCharacters: self.transcriptionText.count, bufferGap: self.captureClock.gap)
                if let free = RecordingDiagnostics.availableDiskBytes(at: self.documentsPath), free < 32_000_000 {
                    self.failRecording("Recording stopped because device storage is almost full. The saved audio and transcript are kept.")
                }
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
        transcriptLines = []

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
            guard recordingFormat.sampleRate.isFinite, recordingFormat.sampleRate > 0,
                  recordingFormat.channelCount > 0 else {
                failRecording("The microphone has no available audio input. Check the microphone or Bluetooth connection.")
                return
            }
            RecordingDiagnostics.shared.event("microphone_started", ["inputSampleRate": "\(recordingFormat.sampleRate)", "inputChannels": "\(recordingFormat.channelCount)"])

            print("🎤 Audio format: \(recordingFormat)")
            print("🎤 Sample rate: \(recordingFormat.sampleRate)")
            print("🎤 Channel count: \(recordingFormat.channelCount)")

            // Only thread-safe capture components cross onto the realtime tap.
            // Capturing AudioManager here previously read UI-owned state from the
            // audio thread and could also inherit main-actor closure isolation.
            let speech = dualEngine
            let recorder = mixedRecorder
            let clock = captureClock
            let delegate = AudioBufferDelegate { buffer in
                clock.markBuffer()
                speech.appendMicBuffer(buffer)
                recorder?.appendMic(buffer)
            }
            audioBufferDelegate = delegate
            let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
                delegate.processBuffer(buffer)
            }
            inputNode.kochi_installTap(onBus: 0, bufferSize: 1024, format: recordingFormat, block: tap)
            audioTapInstalled = true

            audioEngine.prepare()
            try audioEngine.start()

            // Start watchdog timer to detect if audio tap stops
            captureClock.markBuffer()
            startAudioEngineMonitor()

            print("✅ Microphone capture started; speech readiness is reported separately")

        } catch {
            print("❌ Speech recognition error: \(error)")
            transcriptionStatus = .failed("Microphone capture couldn't start: \(error.localizedDescription)")
            failRecording("Microphone capture couldn't start: \(error.localizedDescription)")
        }
    }
    
    private func startAudioEngineMonitor() {
        audioEngineMonitor?.invalidate()
        audioEngineMonitor = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self, let audioEngine = self.audioEngine else { return }
            guard self.isRecording, !self.captureInterrupted else { return }

            DispatchQueue.main.async {
                let isRunning = audioEngine.isRunning
                let timeSinceLastBuffer = self.captureClock.gap
                if timeSinceLastBuffer > 15 {
                    self.failRecording("Microphone audio stopped arriving. The recording has been saved; check the audio connection before restarting.")
                    return
                }

                // Check if audio engine stopped or buffers stopped arriving
                if !isRunning {
                    RecordingDiagnostics.shared.event("audio_engine_stopped")
                    print("❌ AUDIO ENGINE STOPPED! Attempting restart...")
                    self.restartAudioEngine()
                } else if timeSinceLastBuffer > 3.0 {
                    RecordingDiagnostics.shared.event("audio_buffer_gap", ["seconds": "\(timeSinceLastBuffer)"])
                    print("⚠️ NO AUDIO BUFFERS for \(String(format: "%.1f", timeSinceLastBuffer))s - engine running: \(isRunning)")
                    // Engine is running but no buffers - something is wrong
                    print("🔧 Audio engine status: running=\(isRunning), tap installed")
                    self.restartAudioEngine()
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
            audioEngine.stop()
            // Remove old tap
            if audioTapInstalled { audioEngine.inputNode.removeTap(onBus: 0); audioTapInstalled = false }

            // Reinstall tap
            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            guard recordingFormat.sampleRate.isFinite, recordingFormat.sampleRate > 0,
                  recordingFormat.channelCount > 0 else {
                RecordingDiagnostics.shared.event("microphone_format_unavailable")
                return
            }

            let delegate = audioBufferDelegate
            let tap: @Sendable (AVAudioPCMBuffer, AVAudioTime) -> Void = { buffer, _ in
                delegate?.processBuffer(buffer)
            }
            inputNode.kochi_installTap(onBus: 0, bufferSize: 1024, format: recordingFormat, block: tap)
            audioTapInstalled = true

            // Restart engine
            audioEngine.prepare()
            try audioEngine.start()

            RecordingDiagnostics.shared.event("microphone_restarted")
            print("✅ Audio engine restarted successfully")
        } catch {
            print("❌ Failed to restart audio engine: \(error)")
            RecordingDiagnostics.shared.event("microphone_restart_failed", ["error": error.localizedDescription])
        }
    }

    private func stopSpeechRecognition() {
        stopAudioEngineMonitor()
        audioEngine?.stop()
        if audioTapInstalled { audioEngine?.inputNode.removeTap(onBus: 0); audioTapInstalled = false }
        dualEngine.stop()

        audioEngine = nil
        audioBufferDelegate = nil
    }

    private func failRecording(_ message: String) {
        guard isRecording else { return }
        recordingFailure = message
        RecordingDiagnostics.shared.event("recording_error", ["message": message])
        stopRecording()
    }

    private func setupCaptureNotifications() {
        #if os(iOS)
        NotificationCenter.default.publisher(for: AVAudioSession.didBecomeInactiveNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleAudioInterruption(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.resumptionRecommendationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in self?.handleAudioResumption(note) }
            .store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.routeChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] note in
                guard let self, self.isRecording else { return }
                let reason = (note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt) ?? 0
                RecordingDiagnostics.shared.event("audio_route_changed", ["reason": "\(reason)"])
                guard !self.captureInterrupted else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    guard let self, self.isRecording, !self.captureInterrupted else { return }
                    self.restartAudioEngine()
                }
            }.store(in: &cancellables)
        NotificationCenter.default.publisher(for: AVAudioSession.mediaServicesWereResetNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.failRecording("iOS audio services restarted. Your recording was saved; start a new recording to continue.") }
            .store(in: &cancellables)
        for (notification, event) in [(UIApplication.didEnterBackgroundNotification, "app_backgrounded"),
                                       (UIApplication.willEnterForegroundNotification, "app_foregrounded"),
                                       (UIApplication.didReceiveMemoryWarningNotification, "memory_warning")] {
            NotificationCenter.default.publisher(for: notification)
                .sink { _ in RecordingDiagnostics.shared.event(event) }
                .store(in: &cancellables)
        }
        #endif
    }

    #if os(iOS)
    private func handleAudioInterruption(_ note: Notification) {
        guard isRecording,
              let context = note.userInfo?[AVAudioSession.deactivationContextKey] as? AVAudioSession.DeactivationContext,
              context.source == .system else { return }
        captureInterrupted = true
        audioEngine?.pause()
        transcriptionStatus = .failed("Microphone interrupted by iOS. Waiting for audio to become available…")
        RecordingDiagnostics.shared.event("audio_interruption_began", ["source": "system"])
    }

    private func handleAudioResumption(_ note: Notification) {
        guard isRecording, captureInterrupted,
              let context = note.userInfo?[AVAudioSession.resumptionContextKey] as? AVAudioSession.ResumptionContext else { return }
        let canResume = context.recommendation == .shouldResume
        RecordingDiagnostics.shared.event("audio_interruption_ended", ["canResume": "\(canResume)"])
        captureInterrupted = false
        guard canResume else {
            failRecording("Another app interrupted the microphone. Your recording was saved; start a new recording to continue.")
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            restartAudioEngine()
            transcriptionStatus = dualEngine.micStatus
        } catch { failRecording("The microphone couldn't resume: \(error.localizedDescription)") }
    }
    #endif
    
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
nonisolated final class AudioBufferDelegate: @unchecked Sendable {
    private let processBuffer: @Sendable (AVAudioPCMBuffer) -> Void

    init(processBuffer: @escaping @Sendable (AVAudioPCMBuffer) -> Void) {
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
