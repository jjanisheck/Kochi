import Foundation
import Speech
import AVFoundation
import Combine

/// One transcript line attributed to a single speaker/source.
struct TranscriptLine: Identifiable, Equatable {
    let id = UUID()
    let speaker: String       // "Me" (mic) or "Them" (system audio)
    var text: String
    let timestamp: Date
}

/// On-device speech recognition for a single audio source (one mic OR one
/// system-audio stream). Uses the modern macOS 26+ `SpeechAnalyzer` /
/// `SpeechTranscriber` framework — no API key, free, runs locally. (The legacy
/// `SFSpeechRecognizer` flow is non-functional on macOS 26+.)
final class SpeechChannel {
    let label: String
    private let locale: Locale

    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var continuation: AsyncStream<AnalyzerInput>.Continuation?
    private var resultsTask: Task<Void, Never>?
    private var setupTask: Task<Void, Never>?
    private var analyzerFormat: AVAudioFormat?
    private var running = false
    private let stateLock = NSLock()

    // The analyzer consumes 16 kHz mono Int16 (confirmed via bestAvailableAudioFormat).
    // Used as the conversion target until the live analyzer format is resolved.
    private let defaultFormat = AVAudioFormat(commonFormat: .pcmFormatInt16,
                                              sampleRate: 16000, channels: 1, interleaved: false)!
    private var converter: AVAudioConverter?
    private var converterInputFormat: AVAudioFormat?

    /// (label, text, isFinal) — volatile results (isFinal=false) are the live tail;
    /// final results (isFinal=true) commit a finalized segment.
    var onUpdate: ((String, String, Bool) -> Void)?

    init(label: String, locale: Locale = Locale(identifier: "en-US")) {
        self.label = label
        self.locale = locale
    }

    /// Kept for source compatibility; the modern analyzer manages its own readiness.
    var isAvailable: Bool { true }

    func start() {
        stateLock.lock()
        guard !running else { stateLock.unlock(); return }
        running = true
        // Create the input stream synchronously so buffers fed before the analyzer
        // finishes async setup are queued (unbounded) rather than dropped.
        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream()
        continuation = cont
        stateLock.unlock()
        setupTask = Task { [weak self] in await self?.setup(inputStream: stream) }
    }

    private func setup(inputStream: AsyncStream<AnalyzerInput>) async {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // Ensure the on-device model for this locale is installed (no-op if present).
        if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await request.downloadAndInstall()
        }
        let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [transcriber])
        let analyzer = SpeechAnalyzer(modules: [transcriber])

        guard commitSetup(transcriber: transcriber, analyzer: analyzer, format: format) else { return }

        // Drain results -> onUpdate on a detached task.
        resultsTask = Task { [weak self] in
            guard let self = self else { return }
            do {
                for try await result in transcriber.results {
                    self.onUpdate?(self.label, String(result.text.characters), result.isFinal)
                }
            } catch {
                print("⚠️ [\(self.label)] results stream ended: \(error)")
            }
        }

        do {
            try await analyzer.start(inputSequence: inputStream)
        } catch {
            print("⚠️ [\(label)] analyzer start failed: \(error)")
        }
    }

    /// Commit analyzer state under the lock (synchronous — no `await` inside, so the
    /// lock is never held across a suspension point). Returns false if stopped meanwhile.
    private func commitSetup(transcriber: SpeechTranscriber, analyzer: SpeechAnalyzer,
                             format: AVAudioFormat?) -> Bool {
        stateLock.lock(); defer { stateLock.unlock() }
        guard running else { return false }
        self.transcriber = transcriber
        self.analyzer = analyzer
        self.analyzerFormat = format
        return true
    }

    /// Feed an audio buffer from this channel's source. Safe to call from the audio thread.
    func append(_ buffer: AVAudioPCMBuffer) {
        stateLock.lock()
        guard running, let cont = continuation else { stateLock.unlock(); return }
        let target = analyzerFormat ?? defaultFormat
        stateLock.unlock()

        guard let converted = convert(buffer, to: target) else { return }
        cont.yield(AnalyzerInput(buffer: converted))
    }

    func stop() {
        stateLock.lock()
        running = false
        let cont = continuation; continuation = nil
        let analyzer = self.analyzer
        stateLock.unlock()

        cont?.finish()
        resultsTask?.cancel()
        Task { try? await analyzer?.finalizeAndFinishThroughEndOfInput() }
    }

    /// Resample/convert an input buffer to the analyzer's expected format.
    private func convert(_ buffer: AVAudioPCMBuffer, to outFormat: AVAudioFormat) -> AVAudioPCMBuffer? {
        let inFormat = buffer.format
        if inFormat == outFormat { return buffer }
        if converter == nil || converterInputFormat == nil || !inFormat.isEqual(converterInputFormat!) {
            converter = AVAudioConverter(from: inFormat, to: outFormat)
            converterInputFormat = inFormat
        }
        guard let converter = converter, buffer.frameLength > 0 else { return nil }

        let ratio = outFormat.sampleRate / inFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return nil }

        var fed = false
        var err: NSError?
        let status = converter.convert(to: out, error: &err) { _, inStatus in
            if fed { inStatus.pointee = .noDataNow; return nil }
            fed = true
            inStatus.pointee = .haveData
            return buffer
        }
        if status == .error || err != nil { return nil }
        return out.frameLength > 0 ? out : nil
    }
}

/// Drives two on-device speech channels (mic = "Me", system audio = "Them") and
/// merges their output into a single speaker-labeled transcript.
final class DualTranscriptionEngine: ObservableObject {
    /// Flat, speaker-labeled transcript (what the existing UI binds to).
    @Published var transcriptionText: String = ""
    /// Structured lines, in finalization order, for richer display if desired.
    @Published var lines: [TranscriptLine] = []
    @Published var isRunning = false

    static let micLabel = "Me"
    static let systemLabel = "Them"

    private let micChannel = SpeechChannel(label: DualTranscriptionEngine.micLabel)
    private let systemChannel = SpeechChannel(label: DualTranscriptionEngine.systemLabel)
    private let systemCapture = SystemAudioCapture()

    /// Finalized lines per speaker, plus the current live partial per speaker.
    private var finalized: [TranscriptLine] = []
    private var partials: [String: String] = [:]
    private let lock = NSLock()

    private var captureSystemAudio: Bool = true

    /// Forwards each captured system-audio buffer (the "Them" stream) to an
    /// external consumer — used by AudioManager to mix it into the saved recording.
    var onSystemAudioBuffer: ((AVAudioPCMBuffer) -> Void)?

    init() {
        micChannel.onUpdate = { [weak self] label, text, isFinal in
            self?.handleUpdate(label: label, text: text, isFinal: isFinal)
        }
        systemChannel.onUpdate = { [weak self] label, text, isFinal in
            self?.handleUpdate(label: label, text: text, isFinal: isFinal)
        }
    }

    /// - Parameter includeSystemAudio: capture the far side of a call (macOS only).
    func start(includeSystemAudio: Bool = true) {
        finalized.removeAll()
        partials.removeAll()
        DispatchQueue.main.async {
            self.lines = []
            self.transcriptionText = ""
            self.isRunning = true
        }
        captureSystemAudio = includeSystemAudio

        micChannel.start()

        if includeSystemAudio {
            systemChannel.start()
            systemCapture.onBuffer = { [weak self] buffer in
                self?.systemChannel.append(buffer)
                self?.onSystemAudioBuffer?(buffer)
            }
            systemCapture.start { success, error in
                if !success {
                    print("⚠️ System audio capture unavailable: \(error?.localizedDescription ?? "unknown") — falling back to mic-only.")
                }
            }
        }
    }

    /// Feed a microphone buffer (from AudioManager's existing input tap).
    func appendMicBuffer(_ buffer: AVAudioPCMBuffer) {
        micChannel.append(buffer)
    }

    func stop() {
        micChannel.stop()
        systemChannel.stop()
        systemCapture.stop()
        DispatchQueue.main.async { self.isRunning = false }
    }

    // MARK: - Merge

    private func handleUpdate(label: String, text: String, isFinal: Bool) {
        lock.lock()
        if isFinal {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                finalized.append(TranscriptLine(speaker: label, text: trimmed, timestamp: Date()))
            }
            partials[label] = nil
        } else {
            partials[label] = text
        }
        let snapshotFinal = finalized
        let snapshotPartials = partials
        lock.unlock()

        let (display, flat) = Self.render(finalized: snapshotFinal, partials: snapshotPartials)
        DispatchQueue.main.async {
            self.lines = display
            self.transcriptionText = flat
        }
    }

    /// Pure render of finalized lines + live partials into a speaker-labeled
    /// transcript. Extracted so it can be verified headlessly (no audio/TCC).
    static func render(finalized: [TranscriptLine],
                       partials: [String: String]) -> ([TranscriptLine], String) {
        var display = finalized
        // Stable order for partials so output is deterministic (mic first).
        for speaker in [micLabel, systemLabel] {
            if let partial = partials[speaker]?.trimmingCharacters(in: .whitespacesAndNewlines),
               !partial.isEmpty {
                display.append(TranscriptLine(speaker: speaker, text: partial, timestamp: Date()))
            }
        }
        let flat = display.map { "\($0.speaker): \($0.text)" }.joined(separator: "\n")
        return (display, flat)
    }
}
