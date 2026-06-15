import Foundation
import Speech
import AVFoundation

/// One-shot, on-device transcription of a finished audio file using the modern
/// `SpeechAnalyzer` / `SpeechTranscriber` framework (macOS 26+). Because it
/// processes the whole file at once — full context, no real-time deadline — it is
/// typically more accurate than the live, streaming transcript. Fully local: no
/// network, no API key, no cost.
enum FileTranscriber {
    /// Transcribe `fileURL` (e.g. the meeting's mixed `audio.m4a`) into plain text.
    /// Returns the concatenated finalized segments, or throws if the model/file fail.
    static func transcribe(fileURL: URL,
                           locale: Locale = Locale(identifier: "en-US")) async throws -> String {
        let transcriber = SpeechTranscriber(locale: locale, preset: .progressiveTranscription)
        // Ensure the on-device model for this locale is installed (no-op if present).
        if let request = try? await AssetInventory.assetInstallationRequest(supporting: [transcriber]) {
            try? await request.downloadAndInstall()
        }
        let analyzer = SpeechAnalyzer(modules: [transcriber])
        let file = try AVAudioFile(forReading: fileURL)

        // Collect finalized segments in order (no shared mutable state — the task
        // owns its array and returns it).
        let collector = Task { () -> [String] in
            var segments: [String] = []
            do {
                for try await result in transcriber.results where result.isFinal {
                    segments.append(String(result.text.characters))
                }
            } catch { /* stream ended */ }
            return segments
        }

        _ = try await analyzer.analyzeSequence(from: file)
        try await analyzer.finalizeAndFinishThroughEndOfInput()

        let segments = await collector.value
        return segments.joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
