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
    /// Non-nil when a recording could not start, or died on its way up. The UI
    /// shows this instead of a session that looks live but is deaf. Cleared at
    /// the top of the next start.
    @Published var recordingFailure: String?
    
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
    /// Configure and activate the iOS audio session, then call back on the main
    /// queue with whether the session came up. On macOS `AVAudioEngine`'s input
    /// node works without a session, so this reports success immediately.
    ///
    /// Called from `init` and again immediately before each recording, and the
    /// second call is the one that matters: iOS only wires up a real input route
    /// when the session is active and record-capable at the moment
    /// `AVAudioEngine.inputNode` is first touched. The session opened at `init`
    /// predates the microphone permission prompt (the app is constructed before
    /// the first view appears) and predates any coach-video playback, either of
    /// which leaves the engine with a 0 Hz input format and a tap that never
    /// fires — the app looks like it is recording but hears nothing.
    ///
    /// Nothing here touches the session on the caller's thread. `setCategory` is
    /// a hang risk once the session is active, and the synchronous
    /// `setActive(_:options:)` is a hang risk always — both trip the runtime's
    /// "AVAudioSession Hang Risk" check when the record button calls them on the
    /// main thread. So the configuration runs on this serial queue and activation
    /// uses the asynchronous API, with the result handed back on the main queue.
    /// Everything that depends on a live input route runs in the completion, not
    /// after the call returns.
    private static let sessionQueue = DispatchQueue(label: "com.janisheck.kochi.audio-session")

    private func setupAudioSession(completion: ((Bool) -> Void)? = nil) {
        #if os(iOS)
        Self.sessionQueue.async {
            let session = AVAudioSession.sharedInstance()
            do {
                // `.default`, not `.spokenAudio`: the SDK documents spokenAudio
                // purely as a playback mode for podcast/audiobook apps that want to
                // be paused rather than ducked. It says nothing about input, and
                // setting it on a record path leaves the session without a usable
                // input route — the engine then reports a 2 ch / 0 Hz format and
                // AURemoteIO fails -10851.
                try session.setCategory(.playAndRecord,
                                        mode: .default,
                                        options: [.defaultToSpeaker, .allowBluetoothHFP])
            } catch {
                print("⚠️ Audio session category failed: \(error.localizedDescription)")
                DispatchQueue.main.async { completion?(false) }
                return
            }
            session.activate(options: []) { activated, error in
                if let error = error {
                    print("⚠️ Audio session activation failed: \(error.localizedDescription)")
                }
                let inputs = session.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ", ")
                print("🔊 Session active=\(activated) inputAvailable=\(session.isInputAvailable) "
                      + "rate=\(session.sampleRate) inputs=[\(inputs.isEmpty ? "none" : inputs)]")
                // An active session with no input route still yields a 0 Hz engine,
                // so treat "no input" as a failure rather than letting the caller
                // find out downstream.
                let usable = activated && session.isInputAvailable
                if activated && !session.isInputAvailable {
                    print("❌ Audio session active but no input route. On the Simulator, "
                          + "enable I/O ▸ Audio Input and grant Simulator mic access in "
                          + "System Settings ▸ Privacy & Security ▸ Microphone.")
                }
                DispatchQueue.main.async { completion?(usable) }
            }
        }
        #else
        completion?(true)
        #endif
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
        recordingFailure = nil

        // `hasPermission` needs BOTH the mic and speech-recognition grants, so a
        // silent no-op here is otherwise indistinguishable from a broken button.
        guard hasPermission else {
            print("❌ Recording blocked — mic: \(AVCaptureDevice.authorizationStatus(for: .audio).rawValue), "
                  + "speech: \(SFSpeechRecognizer.authorizationStatus().rawValue) (1 = granted for both)")
            recordingFailure = "Kochi needs both microphone and speech-recognition access. "
                             + "Grant them in Settings, then try again."
            return
        }

        // Create meeting folder and get audio file URL
        guard meetingFileManager.startNewMeeting() != nil else {
            print("❌ Failed to create meeting folder")
            recordingFailure = "Couldn't create the meeting folder on disk."
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
    
    /// Roll a failed start all the way back.
    ///
    /// `startRecording` opens a meeting folder, an output file, a timer and a
    /// level meter before the audio engine is known to work — and on iOS the
    /// engine now comes up asynchronously, well after those. Without this, a
    /// failure past that point left the app metering silence into an empty
    /// meeting: recording forever, as far as the user could tell, and saving a
    /// 0-character transcript at the end.
    private func abortRecording(_ reason: String) {
        DispatchQueue.main.async {
            guard self.isRecording else { return }
            print("❌ Recording aborted: \(reason)")

            self.mixedRecorder?.stop()
            self.mixedRecorder = nil
            self.stopMetering()
            self.stopRecordingTimer()
            self.stopSpeechRecognition()

            // Discard the folder — a start that captured nothing should not
            // leave an empty meeting behind for the user to find and delete.
            if let url = self.meetingFileManager.currentMeetingURL {
                self.meetingFileManager.deleteMeeting(at: url)
                self.meetingFileManager.currentMeetingURL = nil
            }
            self.currentRecordingURL = nil
            self.activeMeetingFolderName = nil

            self.isRecording = false
            self.recordingFailure = reason
        }
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

        // The engine is built inside the completion, not after this call: on iOS
        // the input node only gets a real route once activation lands, and
        // activation cannot be waited on from the main thread. See setupAudioSession().
        setupAudioSession { [weak self] activated in
            guard let self = self else { return }
            // Activation is slow enough that the user can stop before it lands;
            // without this the engine would come up after the recording ended.
            guard self.isRecording else {
                print("⏹ Recording stopped before the audio session activated.")
                return
            }
            guard activated else {
                self.abortRecording("The audio session couldn't start, so there was no microphone to record from.")
                return
            }
            self.startAudioEngine()
        }
    }

    /// Build the engine, tap the microphone, and start it. Must run only once the
    /// audio session is active (iOS) — see `startSpeechRecognition()`.
    private func startAudioEngine() {
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ Failed to create audio engine")
            return
        }

        do {
            let inputNode = audioEngine.inputNode
            // The graph-side format is what the tap must use, but log the hardware
            // side too: when they disagree the IO unit failed to configure.
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            print("🎚 inputNode hardware=\(inputNode.inputFormat(forBus: 0)) graph=\(recordingFormat)")

            // A zero format means AURemoteIO never came up. Installing a tap with
            // it throws an uncatchable Objective-C exception, so bail loudly.
            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                #if targetEnvironment(simulator)
                print("❌ AVAudioEngine could not enable microphone input (format: "
                      + "\(recordingFormat)). The audio session is fine — this is the "
                      + "Simulator's AURemoteIO input limitation (-10851). Run on a "
                      + "physical iPhone to record.")
                self.audioEngine = nil
                abortRecording("The Simulator can't capture microphone input. Run on a device to record.")
                #else
                print("❌ AVAudioEngine could not enable microphone input (format: "
                      + "\(recordingFormat)) despite an active session with an input route.")
                self.audioEngine = nil
                abortRecording("Couldn't open the microphone. Check that no other app is using it.")
                #endif
                return
            }

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

            inputNode.kochi_installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
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
            // `self.`, not bare: the `guard let audioEngine = audioEngine` above
            // shadows the property with a local constant for the rest of the body.
            self.audioEngine = nil
            abortRecording("The audio engine failed to start: \(error.localizedDescription)")
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

        audioEngine.inputNode.removeTap(onBus: 0)

        // The usual reason the engine dies on iOS is that the session lost its
        // input route (interruption, route change, backgrounding), so bring the
        // session back — asynchronously — before asking for the format again.
        setupAudioSession { [weak self] activated in
            guard let self = self, let audioEngine = self.audioEngine else { return }
            guard activated else {
                self.abortRecording("Lost the audio session mid-recording and couldn't get it back. "
                                    + "Whatever was captured up to now has been discarded.")
                return
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)

            guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
                print("❌ Restart aborted — input node still reports \(recordingFormat).")
                self.abortRecording("Lost the microphone mid-recording. Another app may have taken it.")
                return
            }

            inputNode.kochi_installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
                self?.audioBufferDelegate?.processBuffer(buffer)
            }

            do {
                audioEngine.prepare()
                try audioEngine.start()
                self.lastAudioBufferTime = Date()
                print("✅ Audio engine restarted successfully")
            } catch {
                print("❌ Failed to restart audio engine: \(error)")
                self.abortRecording("The audio engine stopped and couldn't be restarted: "
                                    + error.localizedDescription)
            }
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