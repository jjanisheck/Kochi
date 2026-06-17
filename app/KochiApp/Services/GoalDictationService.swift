import Foundation
import AVFoundation

/// A small mic-only dictation helper for the "Speak new goals" flow. Reuses the
/// on-device `SpeechChannel` (macOS 26+ `SpeechAnalyzer`/`SpeechTranscriber`) with
/// its own `AVAudioEngine` tap, independent of the meeting-recording pipeline.
@MainActor
final class GoalDictationService: ObservableObject {
    /// True while the mic is live and capturing.
    @Published private(set) var isListening = false
    /// Live transcript (finalized text plus the current partial) for on-screen feedback.
    @Published private(set) var transcript = ""

    private let channel = SpeechChannel(label: "Goals")
    private var engine: AVAudioEngine?
    private var finalText = ""
    private var partial = ""

    init() {
        channel.onUpdate = { [weak self] _, text, isFinal in
            // SpeechChannel calls back off the main actor; hop on to mutate state.
            Task { @MainActor [weak self] in
                guard let self else { return }
                if isFinal {
                    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !t.isEmpty { self.finalText += (self.finalText.isEmpty ? "" : " ") + t }
                    self.partial = ""
                } else {
                    self.partial = text
                }
                self.transcript = (self.finalText + " " + self.partial)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    /// Begins capturing from the microphone. No-op if already listening.
    func start() {
        guard !isListening else { return }
        finalText = ""
        partial = ""
        transcript = ""
        channel.start()

        let engine = AVAudioEngine()
        self.engine = engine
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.kochi_installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.channel.append(buffer)
        }
        engine.prepare()
        do {
            try engine.start()
            isListening = true
        } catch {
            print("❌ GoalDictationService engine start: \(error)")
            channel.stop()
            self.engine = nil
        }
    }

    /// Stops capture and returns the dictated text, briefly waiting for the
    /// analyzer to flush its final segment.
    func stop() async -> String {
        guard isListening else { return transcript }
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop()
        engine = nil
        channel.stop()
        isListening = false
        // Give the on-device analyzer a moment to emit its final result.
        try? await Task.sleep(nanoseconds: 700_000_000)
        let result = finalText.isEmpty ? partial : finalText
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
