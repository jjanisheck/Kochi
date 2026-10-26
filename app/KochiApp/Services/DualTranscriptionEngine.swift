import Foundation
import Speech
import AVFoundation
import Combine

/// One transcript line attributed to a single speaker/source.
nonisolated struct TranscriptLine: Identifiable, Equatable, Sendable {
    let id = UUID()
    let speaker: String       // "Me" (mic) or "Them" (system audio)
    var text: String
    let timestamp: Date
    var elapsedTime: TimeInterval = 0

    nonisolated func replacingText(_ text: String) -> TranscriptLine {
        var updated = self
        updated.text = text
        return updated
    }
}

/// Recognition readiness is separate from the microphone's audio level.
nonisolated enum LiveTranscriptionStatus: Equatable, Sendable {
    case idle, preparing, downloading, listening
    case failed(String)

    var shortLabel: String {
        switch self {
        case .idle: return "ready"
        case .preparing: return "preparing"
        case .downloading: return "downloading"
        case .listening: return "listening"
        case .failed: return "unavailable"
        }
    }

    var message: String {
        switch self {
        case .idle: return "Ready to transcribe."
        case .preparing: return "Preparing on-device speech recognition…"
        case .downloading: return "Downloading the speech model… Audio recording continues."
        case .listening: return "Listening…"
        case .failed(let message): return message
        }
    }

    var isFailure: Bool { if case .failed = self { return true }; return false }
}

/// Audio is copied off the tap and converted only AFTER the analyzer's actual
/// format is known. Session IDs prevent old setup/results from leaking into a restart.
nonisolated final class SpeechChannel: @unchecked Sendable {
    let label: String
    private let locale: Locale
    private let stateLock = NSLock()
    private var sessionID: UUID?
    private var continuation: AsyncStream<AVAudioPCMBuffer>.Continuation?
    private var setupTask: Task<Void, Never>?
    private var analyzer: SpeechAnalyzer?
    private var status: LiveTranscriptionStatus = .idle

    var onUpdate: ((String, String, Bool) -> Void)?
    var onStatus: ((LiveTranscriptionStatus) -> Void)?

    init(label: String, locale: Locale = Locale(identifier: "en-US")) {
        self.label = label
        self.locale = locale
    }

    static func supportsOnDeviceRecognition(locale: Locale = Locale(identifier: "en-US")) async -> Bool {
        if SpeechTranscriber.isAvailable,
           await SpeechTranscriber.supportedLocale(equivalentTo: locale) != nil { return true }
        return await DictationTranscriber.supportedLocale(equivalentTo: locale) != nil
    }

    func start() {
        let id = UUID()
        let (stream, input) = AsyncStream<AVAudioPCMBuffer>.makeStream(bufferingPolicy: .bufferingNewest(512))
        stateLock.lock()
        guard sessionID == nil else { stateLock.unlock(); return }
        sessionID = id
        status = .preparing
        continuation = input
        stateLock.unlock()
        publish(.preparing, for: id)
        let task = Task { [weak self] in
            guard let self else { return }
            await self.run(stream: stream, id: id)
        }
        stateLock.lock()
        if sessionID == id { setupTask = task } else { task.cancel() }
        stateLock.unlock()
    }

    private enum Module: Sendable {
        case speech(SpeechTranscriber, Locale)
        case dictation(DictationTranscriber, Locale)

        var module: any SpeechModule {
            switch self {
            case .speech(let transcriber, _): return transcriber
            case .dictation(let transcriber, _): return transcriber
            }
        }
        var locale: Locale {
            switch self { case .speech(_, let locale), .dictation(_, let locale): return locale }
        }
        func collect(_ receive: @escaping @Sendable (String, Bool) -> Void) async throws {
            switch self {
            case .speech(let transcriber, _):
                for try await result in transcriber.results {
                    receive(String(result.text.characters), result.isFinal)
                }
            case .dictation(let transcriber, _):
                for try await result in transcriber.results {
                    receive(String(result.text.characters), result.isFinal)
                }
            }
        }
    }

    private func selectModule() async throws -> Module {
        if SpeechTranscriber.isAvailable,
           let supported = await SpeechTranscriber.supportedLocale(equivalentTo: locale) {
            return .speech(SpeechTranscriber(locale: supported, preset: .progressiveTranscription), supported)
        }
        if let supported = await DictationTranscriber.supportedLocale(equivalentTo: locale) {
            return .dictation(DictationTranscriber(locale: supported, preset: .progressiveLongDictation), supported)
        }
        #if targetEnvironment(simulator)
        throw ChannelError.unavailable("On-device transcription is unavailable in this simulator. Test speech recognition on a supported iPhone or Mac. Audio recording can still work.")
        #else
        throw ChannelError.unavailable("On-device speech recognition is unavailable for English on this device. Check the device's language and dictation settings.")
        #endif
    }

    private func run(stream: AsyncStream<AVAudioPCMBuffer>, id: UUID) async {
        var collector: Task<Void, Error>?
        var liveAnalyzer: SpeechAnalyzer?
        do {
            let selection = try await selectModule()
            try Task.checkCancellation()
            let modules = [selection.module]
            guard await AssetInventory.status(forModules: modules) != .unsupported else {
                throw ChannelError.unavailable("This device doesn't support the required on-device speech model.")
            }
            try await AssetInventory.reserve(locale: selection.locale)
            if let installation = try await AssetInventory.assetInstallationRequest(supporting: modules) {
                publish(.downloading, for: id)
                try await installation.downloadAndInstall()
            }
            try Task.checkCancellation()
            guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: modules) else {
                #if os(iOS)
                try await runLocalDictation(stream: stream, id: id)
                return
                #else
                throw ChannelError.unavailable("The on-device speech model has no compatible audio format.")
                #endif
            }
            let analyzer = SpeechAnalyzer(modules: modules)
            liveAnalyzer = analyzer
            guard store(analyzer: analyzer, for: id) else { return }
            publish(.preparing, for: id)
            try await analyzer.prepareToAnalyze(in: format)
            try Task.checkCancellation()
            let converter = AnalyzerInputConverter(analyzerFormat: format)
            let (inputs, converted) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(128))
            defer { converted.finish() }
            collector = Task { [weak self] in
                do {
                    try await selection.collect { [weak self] text, final in
                        guard let self, self.isCurrent(id) else { return }
                        self.onUpdate?(self.label, text, final)
                    }
                } catch {
                    self?.report(error, for: id)
                    throw error
                }
            }
            try await analyzer.start(inputSequence: inputs)
            publish(.listening, for: id)
            for await buffer in stream {
                try Task.checkCancellation()
                for input in try converter.convert(buffer, at: nil) {
                    if case .dropped = converted.yield(input) {
                        throw ChannelError.unavailable("Live transcription fell behind. Audio recording continues; the saved audio can be transcribed later.")
                    }
                }
            }
            for input in try converter.flush() { converted.yield(input) }
            converted.finish()
            try await analyzer.finalizeAndFinishThroughEndOfInput()
            try await collector?.value
        } catch is CancellationError {
            // A stopped/replaced session cannot publish late results or failures.
        } catch {
            report(error, for: id)
        }
        collector?.cancel()
        await liveAnalyzer?.cancelAndFinishNow()
    }

    private func store(analyzer: SpeechAnalyzer, for id: UUID) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard sessionID == id else { return false }
        self.analyzer = analyzer
        return true
    }

    #if os(iOS)
    /// Some simulators expose installed dictation assets but no SpeechAnalyzer
    /// audio formats. Use the same local assets via the compatible recognizer API.
    /// A server-backed request is never permitted.
    private func runLocalDictation(stream: AsyncStream<AVAudioPCMBuffer>, id: UUID) async throws {
        let recognizer = try LocalDictationSession(locale: locale) { [weak self] text, final in
            guard let self, self.isCurrent(id) else { return }
            self.onUpdate?(self.label, text, final)
        }
        defer { recognizer.stop() }
        publish(.listening, for: id)
        for await buffer in stream {
            try Task.checkCancellation()
            try recognizer.append(buffer)
        }
        try await recognizer.finish()
    }

    nonisolated private final class LocalDictationSession: @unchecked Sendable {
        private let recognizer: SFSpeechRecognizer
        private let queue = DispatchQueue(label: "kochi.local-dictation")
        private let receive: @Sendable (String, Bool) -> Void
        private var request: SFSpeechAudioBufferRecognitionRequest?
        private var task: SFSpeechRecognitionTask?
        private var inputEnded = false
        private var stopped = false
        private var failure: Error?
        private var requestID: UUID?
        private let completion: AsyncThrowingStream<Void, Error>
        private let continuation: AsyncThrowingStream<Void, Error>.Continuation

        init(locale: Locale, receive: @escaping @Sendable (String, Bool) -> Void) throws {
            guard let recognizer = SFSpeechRecognizer(locale: locale),
                  recognizer.isAvailable, recognizer.supportsOnDeviceRecognition else {
                throw ChannelError.unavailable("On-device speech recognition is unavailable in this simulator. Test transcription on a supported iPhone or Mac.")
            }
            self.recognizer = recognizer
            self.receive = receive
            (completion, continuation) = AsyncThrowingStream<Void, Error>.makeStream()
        }

        func append(_ buffer: AVAudioPCMBuffer) throws {
            try queue.sync {
                if let failure { throw failure }
                guard !stopped, !inputEnded else { return }
                if request == nil { startRequest() }
                request?.append(buffer)
            }
        }

        private func startRequest() {
            let id = UUID()
            requestID = id
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.requiresOnDeviceRecognition = true
            request.shouldReportPartialResults = true
            request.addsPunctuation = true
            self.request = request
            task = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self else { return }
                self.queue.async {
                    guard !self.stopped, self.requestID == id else { return }
                    if let result {
                        self.receive(result.bestTranscription.formattedString, result.isFinal)
                        if result.isFinal {
                            self.requestID = nil
                            self.request = nil
                            self.task = nil
                            if self.inputEnded { self.continuation.finish() }
                            return // Start a fresh utterance on the next buffer.
                        }
                    }
                    if let error {
                        self.requestID = nil
                        self.request = nil
                        self.task = nil
                        if (error as NSError).code == 1110 { // No speech in this utterance.
                            if self.inputEnded { self.continuation.finish() }
                        } else {
                            self.stopped = true
                            self.failure = error
                            self.continuation.finish(throwing: error)
                        }
                    }
                }
            }
        }

        func finish() async throws {
            queue.sync {
                inputEnded = true
                if let request { request.endAudio() } else { continuation.finish() }
            }
            for try await _ in completion {}
        }

        func stop() {
            queue.sync {
                stopped = true
                request?.endAudio()
                task?.cancel()
                request = nil
                task = nil
                continuation.finish()
            }
        }
    }
    #endif

    private func isCurrent(_ id: UUID) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        return sessionID == id
    }

    private func publish(_ status: LiveTranscriptionStatus, for id: UUID) {
        stateLock.lock()
        guard sessionID == id, !self.status.isFailure else { stateLock.unlock(); return }
        self.status = status
        stateLock.unlock()
        onStatus?(status)
    }

    private func report(_ error: Error, for id: UUID) {
        guard isCurrent(id), !Task.isCancelled else { return }
        var message = (error as? ChannelError)?.localizedDescription
            ?? "Speech recognition couldn't start: \(error.localizedDescription)"
        #if targetEnvironment(simulator)
        if (error as NSError).domain == "kLSRErrorDomain", (error as NSError).code == 300 {
            message = "This simulator's on-device speech engine cannot initialize. Use a physical iPhone or the Mac app for live transcription. Audio recording continues."
        }
        #endif
        print("Speech channel [\(label)] failed: \(error)")
        publish(.failed(message), for: id)
    }

    /// The tap's buffer storage can be reused as soon as this method returns.
    func append(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        let input = continuation
        stateLock.unlock()
        guard let input, buffer.frameLength > 0,
              let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else { return }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(buffer.mutableAudioBufferList)
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for (from, to) in zip(source, destination) {
            if let fromData = from.mData, let toData = to.mData {
                memcpy(toData, fromData, min(Int(from.mDataByteSize), Int(to.mDataByteSize)))
            }
        }
        input.yield(copy)
    }

    func stop() {
        stateLock.lock()
        sessionID = nil
        status = .idle
        let input = continuation; continuation = nil
        let task = setupTask; setupTask = nil
        let analyzer = self.analyzer; self.analyzer = nil
        stateLock.unlock()
        input?.finish()
        task?.cancel()
        Task { await analyzer?.cancelAndFinishNow() }
    }

    /// Ends a supplied audio sequence while allowing the final results to drain.
    func finishInput() {
        stateLock.lock()
        let input = continuation; continuation = nil
        stateLock.unlock()
        input?.finish()
    }

    private enum ChannelError: LocalizedError {
        case unavailable(String)
        var errorDescription: String? { if case .unavailable(let message) = self { return message }; return nil }
    }
}

/// Drives two on-device speech channels (mic = "Me", system audio = "Them") and
/// merges their output into a single speaker-labeled transcript.
final class DualTranscriptionEngine: ObservableObject, @unchecked Sendable {
    /// Flat, speaker-labeled transcript (what the existing UI binds to).
    @Published var transcriptionText: String = ""
    /// Structured lines, in finalization order, for richer display if desired.
    @Published var lines: [TranscriptLine] = []
    @Published var isRunning = false
    @Published private(set) var micStatus: LiveTranscriptionStatus = .idle
    @Published private(set) var systemStatus: LiveTranscriptionStatus = .idle
    nonisolated(unsafe) private var runID = UUID()

    nonisolated static let micLabel = "Me"
    nonisolated static let systemLabel = "Them"

    nonisolated private let micChannel = SpeechChannel(label: DualTranscriptionEngine.micLabel)
    nonisolated private let systemChannel = SpeechChannel(label: DualTranscriptionEngine.systemLabel)
    #if os(macOS)
    private let systemCapture = SystemAudioCapture()
    #endif

    /// Finalized lines per speaker, plus the current live partial per speaker.
    nonisolated(unsafe) private var finalized: [TranscriptLine] = []
    nonisolated(unsafe) private var partials: [String: TranscriptLine] = [:]
    nonisolated(unsafe) private var startedAt: TimeInterval = 0
    nonisolated private let lock = NSLock()
    nonisolated(unsafe) private var pendingDisplay: (lines: [TranscriptLine], text: String)?
    nonisolated(unsafe) private var publicationScheduled = false
    nonisolated(unsafe) private var updateRevision: UInt64 = 0

    private var captureSystemAudio: Bool = true

    /// Forwards each captured system-audio buffer (the "Them" stream) to an
    /// external consumer — used by AudioManager to mix it into the saved recording.
    nonisolated(unsafe) var onSystemAudioBuffer: (@Sendable (AVAudioPCMBuffer) -> Void)?

    /// - Parameter includeSystemAudio: capture the far side of a call (macOS only).
    func start(includeSystemAudio: Bool = true) {
        guard !isRunning else { return }
        let currentRun = UUID()
        lock.lock()
        runID = currentRun
        startedAt = ProcessInfo.processInfo.systemUptime
        finalized.removeAll()
        partials.removeAll()
        pendingDisplay = nil
        publicationScheduled = false
        updateRevision = 0
        lock.unlock()
        lines = []
        transcriptionText = ""
        isRunning = true
        captureSystemAudio = includeSystemAudio
        micStatus = .preparing
        micChannel.onUpdate = { @Sendable [weak self] label, text, final in
            self?.handleUpdate(label: label, text: text, isFinal: final, run: currentRun)
        }
        systemChannel.onUpdate = { @Sendable [weak self] label, text, final in
            self?.handleUpdate(label: label, text: text, isFinal: final, run: currentRun)
        }
        micChannel.onStatus = { @Sendable [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.runID == currentRun else { return }
                self.micStatus = status
            }
        }
        systemChannel.onStatus = { @Sendable [weak self] status in
            DispatchQueue.main.async {
                guard let self, self.runID == currentRun else { return }
                self.systemStatus = status
            }
        }
        micChannel.start()

        #if os(macOS)
        // System (far-side) audio capture is macOS-only (ScreenCaptureKit).
        // iOS is mic-only, so this whole branch is compiled out there.
        if includeSystemAudio {
            systemChannel.start()
            systemCapture.onBuffer = { @Sendable [weak self] buffer in
                self?.systemChannel.append(buffer)
                self?.onSystemAudioBuffer?(buffer)
            }
            systemCapture.start { success, error in
                if !success {
                    print("⚠️ System audio capture unavailable: \(error?.localizedDescription ?? "unknown") — falling back to mic-only.")
                }
            }
        }
        #endif
    }

    /// Feed a microphone buffer (from AudioManager's existing input tap).
    nonisolated func appendMicBuffer(_ buffer: AVAudioPCMBuffer) {
        micChannel.append(buffer)
    }

    func stop() {
        lock.lock()
        runID = UUID()
        pendingDisplay = nil
        publicationScheduled = false
        lock.unlock()
        micStatus = .idle
        systemStatus = .idle
        micChannel.stop()
        systemChannel.stop()
        #if os(macOS)
        systemCapture.stop()
        #endif
        isRunning = false
    }

    // MARK: - Merge

    nonisolated private func handleUpdate(label: String, text: String, isFinal: Bool, run: UUID) {
        lock.lock()
        guard runID == run else { lock.unlock(); return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let line = partials[label]?.replacingText(trimmed)
            ?? TranscriptLine(speaker: label, text: trimmed, timestamp: Date(),
                              elapsedTime: max(0, ProcessInfo.processInfo.systemUptime - startedAt))
        if isFinal {
            if !trimmed.isEmpty { finalized.append(line) }
            partials[label] = nil
        } else {
            partials[label] = trimmed.isEmpty ? nil : line
        }
        let snapshotFinal = finalized
        let snapshotPartials = partials
        updateRevision &+= 1
        let revision = updateRevision
        lock.unlock()

        let (display, flat) = Self.render(finalized: snapshotFinal, partials: snapshotPartials)
        lock.lock()
        guard runID == run, updateRevision == revision else { lock.unlock(); return }
        pendingDisplay = (display, flat)
        let shouldSchedule = !publicationScheduled
        publicationScheduled = true
        lock.unlock()
        guard shouldSchedule else { return }
        DispatchQueue.main.async {
            self.lock.lock()
            guard self.runID == run else { self.lock.unlock(); return }
            let pending = self.pendingDisplay
            self.pendingDisplay = nil
            self.publicationScheduled = false
            self.lock.unlock()
            guard let pending else { return }
            self.lines = pending.lines
            self.transcriptionText = pending.text
        }
    }

    /// Pure render of finalized lines + live partials into a speaker-labeled
    /// transcript. Extracted so it can be verified headlessly (no audio/TCC).
    nonisolated static func render(finalized: [TranscriptLine],
                       partials: [String: TranscriptLine]) -> ([TranscriptLine], String) {
        var display = finalized
        // Stable order for partials so output is deterministic (mic first).
        for speaker in [micLabel, systemLabel] {
            if let partial = partials[speaker],
               !partial.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                display.append(partial)
            }
        }
        let flat = display.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        return (display, flat)
    }
}
