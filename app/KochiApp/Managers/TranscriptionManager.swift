import Foundation
import Foundation
import AVFoundation
import Speech
import Combine

// MARK: - Transcription Protocol
protocol TranscriptionService {
    func startTranscription(audioURL: URL) async throws -> String
    func startRealtimeTranscription(audioBuffer: AVAudioPCMBuffer) async
    func stopTranscription()
    var transcriptionPublisher: AnyPublisher<String, Never> { get }
    var segmentsPublisher: AnyPublisher<[TimestampedSegment], Never> { get }
}


// MARK: - Timestamped Segment Model
struct TimestampedSegment: Codable {
    let text: String
    let timestamp: TimeInterval  // seconds from recording start
    let duration: TimeInterval
}

// MARK: - Transcription Manager
// Uses iOS native Speech framework for 100% on-device transcription
// Implements timestamped segments for time-based goal evaluation
class TranscriptionManager: ObservableObject {
    @Published var transcriptionText = ""
    @Published var isTranscribing = false
    @Published var selectedLanguage: TranscriptionLanguage = .english
    @Published var segments: [TimestampedSegment] = []

    private var speechService: AppleSpeechService
    private var cancellables = Set<AnyCancellable>()

    // Time tracking for segments
    private var recordingStartTime: Date?
    private var lastEvaluationTime: TimeInterval = 0

    // Track longest transcript to prevent loss due to speech recognition revisions
    private var longestTranscript = ""

    init() {
        self.speechService = AppleSpeechService()
        setupPublishers()
    }

    // MARK: - Time-based Segment Management

    /// Starts tracking time for a new recording session
    func startRecordingSession() {
        recordingStartTime = Date()
        lastEvaluationTime = 0
        segments = []
        longestTranscript = ""
        transcriptionText = ""
        speechService.resetAccumulatedTranscript()
        print("🎬 Recording session started")
    }

    /// Gets transcript text from segments since the last evaluation
    /// Returns only new speech, not the full transcript
    func getNewSegmentText() -> String {
        let newSegments = segments.filter { $0.timestamp >= lastEvaluationTime }
        let text = newSegments.map { $0.text }.joined(separator: " ")

        if !newSegments.isEmpty {
            // Update last evaluation time to the end of the newest segment
            if let lastSegment = newSegments.last {
                lastEvaluationTime = lastSegment.timestamp + lastSegment.duration
            }
            print("📝 New segments: \(newSegments.count) segments, \(text.count) chars (from \(lastEvaluationTime - (newSegments.last?.duration ?? 0))s to \(lastEvaluationTime)s)")
        }

        return text
    }

    /// Gets transcript text from a specific time range
    func getSegmentsInRange(from startTime: TimeInterval, to endTime: TimeInterval) -> String {
        let rangeSegments = segments.filter { segment in
            segment.timestamp >= startTime && segment.timestamp < endTime
        }
        return rangeSegments.map { $0.text }.joined(separator: " ")
    }

    /// Gets transcript text from the last N seconds
    func getSegmentsFromLast(seconds: TimeInterval) -> String {
        guard let startTime = recordingStartTime else { return "" }
        let currentTime = Date().timeIntervalSince(startTime)
        let cutoffTime = max(0, currentTime - seconds)

        let recentSegments = segments.filter { $0.timestamp >= cutoffTime }
        return recentSegments.map { $0.text }.joined(separator: " ")
    }

    /// Resets for a new recording (legacy compatibility)
    func resetChunkTracking() {
        startRecordingSession()
    }

    /// Returns true if there's new content to process since last evaluation
    var hasNewContent: Bool {
        return segments.contains { $0.timestamp >= lastEvaluationTime }
    }

    /// Current recording duration in seconds
    var currentRecordingTime: TimeInterval {
        guard let start = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Setup
    private func setupPublishers() {
        // Subscribe to transcription updates from Apple Speech
        // CRITICAL: Receive on main thread to ensure @Published updates work correctly
        speechService.transcriptionPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] text in
                guard let self = self else { return }

                // Apple Speech Recognition can revise and shorten the transcript
                // We preserve the longest version to never lose content
                if text.count > self.longestTranscript.count {
                    if text.count - self.longestTranscript.count > 50 || self.longestTranscript.count == 0 {
                        print("📝 Transcript grew: \(self.longestTranscript.count) → \(text.count) chars")
                    }
                    self.longestTranscript = text
                    self.transcriptionText = text
                } else if text.count < self.longestTranscript.count {
                    // This can happen legitimately when recognition restarts and accumulated text is being rebuilt
                    // Only warn if the difference is significant (more than just incremental rebuilding)
                    if self.longestTranscript.count - text.count > 100 {
                        print("⚠️ Significant transcript reduction: \(self.longestTranscript.count) → \(text.count) chars, preserving longer version")
                    }
                    // Keep the longer version
                    self.transcriptionText = self.longestTranscript
                } else {
                    // Same length, just update
                    self.transcriptionText = text
                }
            }
            .store(in: &cancellables)

        // Subscribe to timestamped segments
        // Preserve the longest segment list (similar to longestTranscript)
        speechService.segmentsPublisher
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newSegments in
                guard let self = self else { return }
                // Only update if we have more segments (recognition restarts can reduce count)
                if newSegments.count >= self.segments.count {
                    self.segments = newSegments
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Public Methods
    func startTranscription(audioURL: URL) async throws {
        isTranscribing = true

        do {
            let text = try await speechService.startTranscription(audioURL: audioURL)
            transcriptionText = text
        } catch {
            print("Transcription error: \(error)")
            throw error
        }

        isTranscribing = false
    }

    func startRealtimeTranscription(audioBuffer: AVAudioPCMBuffer) async {
        await speechService.startRealtimeTranscription(audioBuffer: audioBuffer)
    }

    func stopTranscription() {
        speechService.stopTranscription()
        isTranscribing = false
    }

    // MARK: - Permission
    func requestAuthorization() async -> Bool {
        return await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }
    
}

// MARK: - Apple Speech Service
// Uses iOS native Speech framework with on-device recognition
// Handles automatic restart when hitting ~1 minute recognition limit
class AppleSpeechService: NSObject, TranscriptionService {
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let transcriptionSubject = PassthroughSubject<String, Never>()
    private let segmentsSubject = PassthroughSubject<[TimestampedSegment], Never>()

    // Accumulated data across recognition restarts
    private var accumulatedTranscript = ""
    private var accumulatedSegments: [TimestampedSegment] = []
    private var timeOffsetForRestart: TimeInterval = 0  // Time offset when recognition restarts
    private var isRestarting = false

    // Track the longest text in current session (Apple's recognizer often revises to be shorter)
    private var longestCurrentText = ""
    private var longestCurrentSegments: [TimestampedSegment] = []

    var transcriptionPublisher: AnyPublisher<String, Never> {
        transcriptionSubject.eraseToAnyPublisher()
    }

    var segmentsPublisher: AnyPublisher<[TimestampedSegment], Never> {
        segmentsSubject.eraseToAnyPublisher()
    }

    func resetAccumulatedTranscript() {
        accumulatedTranscript = ""
        accumulatedSegments = []
        timeOffsetForRestart = 0
        isRestarting = false
        longestCurrentText = ""
        longestCurrentSegments = []
    }

    func startTranscription(audioURL: URL) async throws -> String {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            throw TranscriptionError.recognizerNotAvailable
        }

        let request = SFSpeechURLRecognitionRequest(url: audioURL)
        request.shouldReportPartialResults = true
        // Enable on-device recognition for privacy (iOS 13+)
        if #available(iOS 13.0, *) {
            request.requiresOnDeviceRecognition = true
        }

        return try await withCheckedThrowingContinuation { continuation in
            recognitionTask = recognizer.recognitionTask(with: request) { result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                if let result = result {
                    let text = result.bestTranscription.formattedString
                    self.transcriptionSubject.send(text)

                    if result.isFinal {
                        continuation.resume(returning: text)
                    }
                }
            }
        }
    }

    func startRealtimeTranscription(audioBuffer: AVAudioPCMBuffer) async {
        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            print("❌ Speech recognizer not available")
            return
        }

        if recognitionRequest == nil {
            print("🎤 Initializing speech recognition request...")
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            recognitionRequest?.shouldReportPartialResults = true
            // Enable on-device recognition for privacy
            if #available(iOS 13.0, *) {
                recognitionRequest?.requiresOnDeviceRecognition = true
            }

            // Reset longest trackers for new session
            longestCurrentText = ""
            longestCurrentSegments = []

            var resultCount = 0

            recognitionTask = recognizer.recognitionTask(with: recognitionRequest!) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    let nsError = error as NSError
                    // Check if this is the ~1 minute timeout (error code 216 or 1110)
                    // These indicate the recognition task ended, not a real error
                    if nsError.code == 216 || nsError.code == 1110 || nsError.domain == "kAFAssistantErrorDomain" {
                        print("⚠️ Recognition limit reached - accumulated: \(self.accumulatedTranscript.count) chars, \(self.accumulatedSegments.count) segments")
                        // Update time offset for next session based on accumulated segments
                        if let lastSegment = self.accumulatedSegments.last {
                            self.timeOffsetForRestart = lastSegment.timestamp + lastSegment.duration
                            print("📍 Time offset for restart: \(self.timeOffsetForRestart)s")
                        }
                        // The recognition will be restarted on next audio buffer
                        DispatchQueue.main.async {
                            self.recognitionRequest = nil
                            self.recognitionTask = nil
                        }
                    } else {
                        print("❌ Recognition error: \(error)")
                    }
                    return
                }

                if let result = result {
                    resultCount += 1
                    let currentText = result.bestTranscription.formattedString

                    // Extract timestamped segments from current recognition
                    let currentSegments = result.bestTranscription.segments.map { segment in
                        TimestampedSegment(
                            text: segment.substring,
                            timestamp: self.timeOffsetForRestart + segment.timestamp,
                            duration: segment.duration
                        )
                    }

                    // Combine accumulated transcript with current recognition
                    let fullText: String
                    let fullSegments: [TimestampedSegment]
                    if self.accumulatedTranscript.isEmpty {
                        fullText = currentText
                        fullSegments = currentSegments
                    } else {
                        fullText = self.accumulatedTranscript + " " + currentText
                        fullSegments = self.accumulatedSegments + currentSegments
                    }

                    if resultCount % 10 == 0 || result.isFinal {
                        print("📝 Recognition result #\(resultCount): \(currentText.count) chars, total: \(fullText.count), isFinal: \(result.isFinal)")
                    }

                    // Send the full accumulated text and segments
                    DispatchQueue.main.async {
                        self.transcriptionSubject.send(fullText)
                        self.segmentsSubject.send(fullSegments)
                    }

                    // CRITICAL FIX: Track the longest currentText during this session
                    // Apple's recognizer often revises text to be shorter, even down to 0 chars
                    if currentText.count > self.longestCurrentText.count {
                        self.longestCurrentText = currentText
                        self.longestCurrentSegments = currentSegments
                        print("📈 New longest: \(currentText.count) chars (previous: \(self.longestCurrentText.count))")
                    }

                    // When recognition finalizes (hits limit), save the LONGEST version we saw
                    if result.isFinal {
                        // Use the longest text we saw, not the current (possibly revised-down) text
                        let textToSave = self.longestCurrentText.isEmpty ? currentText : self.longestCurrentText
                        let segmentsToSave = self.longestCurrentSegments.isEmpty ? currentSegments : self.longestCurrentSegments

                        if !textToSave.isEmpty {
                            // Save longest recognition to accumulated
                            if self.accumulatedTranscript.isEmpty {
                                self.accumulatedTranscript = textToSave
                                self.accumulatedSegments = segmentsToSave
                            } else {
                                self.accumulatedTranscript = self.accumulatedTranscript + " " + textToSave
                                self.accumulatedSegments = self.accumulatedSegments + segmentsToSave
                            }

                            // Update time offset for next recognition session
                            if let lastSegment = segmentsToSave.last {
                                self.timeOffsetForRestart = lastSegment.timestamp + lastSegment.duration
                            }
                            print("💾 Recognition finalized: saved longest (\(textToSave.count) chars), total accumulated: \(self.accumulatedTranscript.count) chars, \(self.accumulatedSegments.count) segments")
                        } else {
                            print("⚠️ Empty final result AND no longest saved, preserving accumulated: \(self.accumulatedTranscript.count) chars")
                        }

                        // Reset longest trackers for next session
                        self.longestCurrentText = ""
                        self.longestCurrentSegments = []
                        // Clear request so it restarts on next buffer
                        DispatchQueue.main.async {
                            self.recognitionRequest = nil
                            self.recognitionTask = nil
                        }
                    }
                }
            }
            print("✅ Speech recognition task started (accumulated: \(accumulatedTranscript.count) chars, \(accumulatedSegments.count) segments, offset: \(timeOffsetForRestart)s)")
        }

        recognitionRequest?.append(audioBuffer)
    }

    func stopTranscription() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        // DO NOT reset accumulated data here - it's needed for final transcript capture
        // Reset only happens in resetAccumulatedTranscript() when starting a new recording
        isRestarting = false
        print("🛑 Transcription stopped (preserved: \(accumulatedTranscript.count) chars, \(accumulatedSegments.count) segments)")
    }
}

// MARK: - Supporting Types
enum TranscriptionLanguage: String, CaseIterable {
    case english = "en-US"
    case spanish = "es-ES"
    case french = "fr-FR"
    case german = "de-DE"
    case italian = "it-IT"
    case portuguese = "pt-BR"
    case russian = "ru-RU"
    case chinese = "zh-CN"
    case japanese = "ja-JP"
    case korean = "ko-KR"

    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Spanish"
        case .french: return "French"
        case .german: return "German"
        case .italian: return "Italian"
        case .portuguese: return "Portuguese"
        case .russian: return "Russian"
        case .chinese: return "Chinese"
        case .japanese: return "Japanese"
        case .korean: return "Korean"
        }
    }
}

enum TranscriptionError: LocalizedError {
    case recognizerNotAvailable
    case transcriptionFailed

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer is not available. Please check Settings > Privacy > Speech Recognition."
        case .transcriptionFailed:
            return "Transcription failed. Please try again."
        }
    }
}