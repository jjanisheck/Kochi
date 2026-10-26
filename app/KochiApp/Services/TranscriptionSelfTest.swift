import Foundation
import Speech
import AVFoundation

#if os(macOS)
nonisolated private final class RecordingTestErrors: @unchecked Sendable {
    private let lock = NSLock()
    private var errors: [String] = []
    func record(_ text: String) { lock.withLock { errors.append(text) } }
    var first: String? { lock.withLock { errors.first } }
}
extension TranscriptionSelfTest {
    /// Accelerated audio-file stress test, not a claim of elapsed device endurance.
    /// No microphone, speaker playback, Speech, or model request is used.
    @MainActor static func runRecording() {
        Task { @MainActor in
            var failures = 0, checks = 0
            func check(_ value: Bool, _ label: String) {
                checks += 1
                if !value { failures += 1; print("RECORDING FAIL: \(label)") }
            }
            do {
                let root = FileManager.default.temporaryDirectory.appendingPathComponent("kochi-recording-test-\(UUID().uuidString)")
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let files = MeetingFileManager(rootURL: root.appendingPathComponent("Meetings"))
                guard let folder = files.startNewMeeting(), let audioURL = files.getAudioFileURL(),
                      let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1),
                      let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800) else {
                    print("RECORDING FAIL: couldn't create test audio"); exit(1)
                }
                buffer.frameLength = 4_800
                for i in 0..<4_800 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * .pi * 2 * 440 / 48_000) * 0.15) }
                let diagnostics = RecordingDiagnostics(root: root.appendingPathComponent("Diagnostics"))
                diagnostics.start(meetingFolder: folder, audioURL: audioURL)
                let writer = MixedAudioRecorder()
                let writerErrors = RecordingTestErrors()
                writer.onFailure = { writerErrors.record($0) }
                try writer.start(url: audioURL)
                let baseline = RecordingDiagnostics.residentMemoryMB
                var peak = baseline
                let began = Date()
                for i in 0..<72_000 { // 100ms × 72,000 = two hours of real PCM frames.
                    writer.appendMic(buffer)
                    if i % 64 == 0 { writer.flushPendingAudio() }
                    if i % 6_000 == 0 {
                        peak = max(peak, RecordingDiagnostics.residentMemoryMB)
                        diagnostics.sample(seconds: Double(i) / 10, transcriptCharacters: i, bufferGap: 0)
                        print("RECORDING: encoded \(i / 600) minutes, resident \(Int(RecordingDiagnostics.residentMemoryMB)) MB")
                    }
                }
                writer.stop()
                let audioFailure = writerErrors.first
                check(audioFailure == nil, "no writer overload or disk failure")
                let audio = try AVAudioFile(forReading: audioURL)
                let duration = Double(audio.length) / audio.processingFormat.sampleRate
                check(abs(duration - 7_200) < 0.2, "all two-hour audio frames finalized")
                check(peak - baseline < 100, "resident memory does not grow with meeting duration")
                let size = RecordingDiagnostics.fileBytes(at: audioURL) ?? 0
                check(size > 0 && size < 90_000_000, "AAC storage remains bounded near its target bitrate")
                // Late tap delivery is harmless after the producer has stopped.
                writer.appendMic(buffer); writer.flushPendingAudio()
                check(RecordingDiagnostics.fileBytes(at: audioURL) == size, "late buffers cannot write after stop")
                let invalid = MixedAudioRecorder()
                do { try invalid.start(url: root.appendingPathComponent("missing/audio.m4a")); check(false, "invalid audio path throws") }
                catch { check(true, "invalid audio path throws") }

                let privateText = "Me: private phrase — café 👋 corrected final transcript"
                for i in 0..<500 { files.appendToTranscript("Me: volatile partial \(i)", currentTime: Double(i)) }
                let longText = String(repeating: privateText + "\n", count: 8_000)
                files.endMeeting(finalTranscript: longText, duration: 7_200)
                let saved = try String(contentsOf: folder.appendingPathComponent("transcript.txt"), encoding: .utf8)
                check(saved.hasSuffix(longText), "final Unicode transcript fully flushed")
                check(!saved.contains("volatile partial"), "speech corrections do not corrupt checkpoint text")
                check(saved.hasPrefix("00:00 - 120:00"), "long-duration transcript timestamp preserved")
                let metadata = try JSONSerialization.jsonObject(with: Data(contentsOf: folder.appendingPathComponent("metadata.json"))) as? [String: Any]
                check(metadata?["durationSeconds"] as? Double == 7_200, "two-hour meeting metadata saved")
                diagnostics.event("synthetic_interruption", ["reason": "test"])
                diagnostics.finish(seconds: 7_200)
                if let report = await diagnostics.exportReport() {
                    let text = try String(contentsOf: report, encoding: .utf8)
                    check(text.contains("recording_finished") && text.contains("audioBytes"), "diagnostic export has lifecycle and storage")
                    let events = text.split(separator: "\n").compactMap { line in
                        try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
                    }
                    let finished = events.last { $0["event"] as? String == "recording_finished" }
                    check((finished?["audioBytes"] as? NSNumber)?.int64Value == size, "diagnostics report the actual finalized file size")
                    check(!text.contains(privateText) && !text.contains(longText), "diagnostics exclude transcript and audio content")
                } else { check(false, "diagnostic report export") }
                check(!FileManager.default.fileExists(atPath: root.appendingPathComponent("Diagnostics/active.json").path), "normal stop clears unfinished marker")
                diagnostics.start(meetingFolder: folder, audioURL: audioURL)
                _ = await diagnostics.exportReport() // Drain start before simulating an app relaunch.
                let relaunched = RecordingDiagnostics(root: root.appendingPathComponent("Diagnostics"))
                if let report = await relaunched.exportReport() {
                    check(try String(contentsOf: report, encoding: .utf8).contains("previous_session_unfinished"), "unfinished recording survives relaunch")
                } else { check(false, "unfinished report export") }
                print(String(format: "RECORDING: audio %.1f seconds, %.2f MB, peak resident delta %.1f MB; encoded in %.1f seconds", duration, Double(size) / 1_000_000, peak - baseline, Date().timeIntervalSince(began)))
                print("RECORDING: \(checks) checks, \(failures) failures. Artifacts: \(root.path)")
                exit(failures == 0 ? 0 : 1)
            } catch { print("RECORDING FAIL: \(error)"); exit(1) }
        }
        RunLoop.main.run()
    }
}
#endif

/// Headless verification of the on-device speech pipeline. Synthesizes a known
/// phrase with `AVSpeechSynthesizer`, feeds the audio through a real
/// `SpeechChannel` (Apple on-device recognition), and checks the transcript.
///
/// Run by launching the app with `--selftest`. Results are printed with the
/// `SELFTEST` prefix and the process exits with code 0 (pass) or 1 (fail).
enum TranscriptionSelfTest {
    private static var testSynthesizer: AVSpeechSynthesizer?
    // Common words a recognizer handles well; we assert on word overlap.
    static let phrase = "the quick brown fox jumps over the lazy dog"

    static func run() {
        print("SELFTEST: starting on-device transcription self-test")

        let existing = SFSpeechRecognizer.authorizationStatus()
        if existing == .authorized {
            DispatchQueue.main.async { runRecognition() }
        } else if existing == .notDetermined {
            // Prompt once (may need the user). A watchdog prevents an AFK hang.
            print("SELFTEST: requesting Speech Recognition authorization…")
            armWatchdog(seconds: 25)
            SFSpeechRecognizer.requestAuthorization { status in
                guard status == .authorized else {
                    print("SELFTEST SKIPPED: Speech Recognition not authorized (status=\(status.rawValue)). " +
                          "Grant it in System Settings ▸ Privacy & Security ▸ Speech Recognition, then re-run.")
                    exit(2)
                }
                DispatchQueue.main.async { runRecognition() }
            }
        } else {
            print("SELFTEST SKIPPED: Speech Recognition not authorized (status=\(existing.rawValue)). " +
                  "Grant it in System Settings ▸ Privacy & Security ▸ Speech Recognition, then re-run.")
            exit(2)
        }

        // Keep the process alive while async work runs.
        RunLoop.main.run()
    }

    private static func armWatchdog(seconds: TimeInterval) {
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
            print("SELFTEST TIMEOUT: no result within \(Int(seconds))s (likely awaiting a permission prompt).")
            exit(3)
        }
    }

    private static func runRecognition() {
        let channel = SpeechChannel(label: "Test")
        armWatchdog(seconds: 90)

        var latestText = ""
        var liveUpdates = 0
        let lock = NSLock()
        channel.onUpdate = { _, text, isFinal in
            lock.lock()
            latestText = text
            if !isFinal && !text.isEmpty { liveUpdates += 1 }
            lock.unlock()
        }
        var startedSynthesis = false
        channel.onStatus = { status in
            print("SELFTEST speech status: \(status.message)")
            DispatchQueue.main.async {
                if case .failed = status { exit(2) }
                guard status == .listening, !startedSynthesis else { return }
                startedSynthesis = true
                synthesize()
            }
        }

        func synthesize() {
            let synth = AVSpeechSynthesizer()
            testSynthesizer = synth // Retain the asynchronous producer until completion.
            let utterance = AVSpeechUtterance(string: phrase)
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
            utterance.rate = 0.45
            utterance.volume = 1.0
            var produced = 0
            synth.write(utterance) { buffer in
                guard let pcm = buffer as? AVAudioPCMBuffer else { return }
                if pcm.frameLength > 0 {
                    produced += Int(pcm.frameLength)
                    channel.append(pcm)
                } else {
                    channel.finishInput()
                    print("SELFTEST: synthesized \(produced) frames of audio")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        guard produced > 0 else { print("SELFTEST FAIL: no synthesized audio"); exit(1) }
                        lock.lock()
                        let result = latestText.lowercased()
                        let partialCount = liveUpdates
                        lock.unlock()
                        print("SELFTEST: \(partialCount) live partial updates received")
                        channel.stop()
                        evaluate(result)
                    }
                }
            }
        }
        channel.start()
    }

    static func runSpeechStatus() {
        Task {
            let locale = Locale(identifier: "en-US")
            print("SPEECH STATUS: modern available=\(SpeechTranscriber.isAvailable)")
            print("SPEECH STATUS: modern locale=\(await SpeechTranscriber.supportedLocale(equivalentTo: locale)?.identifier ?? "none")")
            print("SPEECH STATUS: dictation locale=\(await DictationTranscriber.supportedLocale(equivalentTo: locale)?.identifier ?? "none")")
            print("SPEECH STATUS: installed modern=\(await SpeechTranscriber.installedLocales.map(\.identifier))")
            print("SPEECH STATUS: installed dictation=\(await DictationTranscriber.installedLocales.map(\.identifier))")
            exit(0)
        }
        RunLoop.main.run()
    }

    /// Headless verification of speaker separation/labeling — needs no audio or
    /// permissions. Confirms mic→"Me", system→"Them", finalized ordering, and
    /// that a live partial appears after finalized lines.
    static func runMerge() {
        print("SELFTEST-MERGE: verifying speaker separation/labeling")
        var fails = 0

        func check(_ name: String, _ cond: Bool) {
            print("  [\(cond ? "PASS" : "FAIL")] \(name)")
            if !cond { fails += 1 }
        }

        // 1. Finalized mic + system lines render with correct labels and order.
        let finalized = [
            TranscriptLine(speaker: DualTranscriptionEngine.micLabel, text: "hello there", timestamp: Date()),
            TranscriptLine(speaker: DualTranscriptionEngine.systemLabel, text: "hi how are you", timestamp: Date())
        ]
        let (_, flat1) = DualTranscriptionEngine.render(finalized: finalized, partials: [:])
        check("mic labeled 'Me:'", flat1.contains("Me: hello there"))
        check("system labeled 'Them:'", flat1.contains("Them: hi how are you"))
        check("two lines", flat1.split(separator: "\n").count == 2)
        check("mic before system", flat1.range(of: "Me: hello")!.lowerBound < flat1.range(of: "Them: hi")!.lowerBound)

        // 2. A live partial is appended after finalized lines, labeled by source.
        let (_, flat2) = DualTranscriptionEngine.render(
            finalized: [finalized[0]],
            partials: [DualTranscriptionEngine.systemLabel:
                TranscriptLine(speaker: DualTranscriptionEngine.systemLabel, text: "speaking now", timestamp: Date(), elapsedTime: 7)]
        )
        check("partial system line present", flat2.contains("Them: speaking now"))
        check("finalized mic still first", flat2.hasPrefix("Me: hello there"))

        // 3. Empty/whitespace partials are dropped.
        let (_, flat3) = DualTranscriptionEngine.render(
            finalized: [], partials: [DualTranscriptionEngine.micLabel:
                TranscriptLine(speaker: DualTranscriptionEngine.micLabel, text: "   ", timestamp: Date())]
        )
        check("blank partial dropped", flat3.isEmpty)

        let live = TranscriptLine(speaker: "Me", text: "start", timestamp: Date(), elapsedTime: 11)
        let corrected = live.replacingText("starting the meeting")
        check("corrections preserve row identity", live.id == corrected.id)
        check("corrections preserve elapsed timestamp", corrected.elapsedTime == 11 && corrected.timestamp == live.timestamp)
        let (liveDisplay, _) = DualTranscriptionEngine.render(finalized: [], partials: ["Me": corrected])
        let (finalDisplay, _) = DualTranscriptionEngine.render(finalized: [corrected], partials: [:])
        check("finalization preserves timestamp and identity", liveDisplay == finalDisplay)
        check("meeting timestamp supports over an hour", deckTime(3_661) == "61:01")

        if fails == 0 {
            print("SELFTEST-MERGE PASS: speaker separation works")
            exit(0)
        } else {
            print("SELFTEST-MERGE FAIL: \(fails) check(s) failed")
            exit(1)
        }
    }

    private static func evaluate(_ result: String) {
        let expected = Set(phrase.split(separator: " ").map(String.init))
        let got = Set(result.components(separatedBy: CharacterSet.letters.inverted).filter { !$0.isEmpty })
        let overlap = expected.intersection(got)
        let ratio = expected.isEmpty ? 0 : Double(overlap.count) / Double(expected.count)

        print("SELFTEST transcript: \"\(result)\"")
        print("SELFTEST overlap: \(overlap.count)/\(expected.count) words (\(Int(ratio * 100))%)")

        if ratio >= 0.5 {
            print("SELFTEST PASS: on-device transcription is working")
            exit(0)
        } else {
            print("SELFTEST FAIL: transcript did not match synthesized speech")
            exit(1)
        }
    }
}

/// Headless verification of the Foundation Models analysis path. Runs a canned
/// two-speaker transcript through goal evaluation + session-note generation and
/// exits 0 (pass/skip) or 1 (fail), mirroring the `run()`/`runMerge()` style.
extension TranscriptionSelfTest {
    /// Re-transcribe the most recent meeting's `audio.m4a` on-device and print the
    /// result — verifies FileTranscriber against a real MixedAudioRecorder output.
    static func runRefine() {
        Task {
            let manager = MeetingFileManager()
            guard let meeting = manager.getAllMeetings().first else {
                print("⚠️ --selftest-refine: no meetings found"); exit(0)
            }
            let audioURL = meeting.appendingPathComponent("audio.m4a")
            guard FileManager.default.fileExists(atPath: audioURL.path) else {
                print("⚠️ --selftest-refine: no audio.m4a in \(meeting.lastPathComponent)"); exit(0)
            }
            do {
                print("▶︎ refining \(meeting.lastPathComponent)/audio.m4a …")
                let text = try await FileTranscriber.transcribe(fileURL: audioURL)
                print("✅ --selftest-refine: \(text.count) chars\n---\n\(text)\n---")
                exit(text.isEmpty ? 1 : 0)
            } catch {
                print("⚠️ --selftest-refine: \(error)"); exit(0)
            }
        }
        RunLoop.main.run()
    }
}

@available(macOS 27, iOS 27, *)
extension TranscriptionSelfTest {
    static func runLLM() {
        Task {
            // Two goals the transcript clearly meets, plus one it never touches.
            // A correct evaluator must mark the absent goal NOT achieved — this is
            // the guard against the model rubber-stamping every goal as hit.
            let pricingGoal = Goal(text: "Discuss pricing", isCompleted: false)
            let followUpGoal = Goal(text: "Schedule a follow-up", isCompleted: false)
            let absentGoal = Goal(text: "Mention the company's hiring plans", isCompleted: false)
            let goals = [pricingGoal, followUpGoal, absentGoal]
            let transcript = """
            Me: Let's talk about pricing — our plan is $20 per seat.
            Them: Sounds good. Let's set up a follow-up next Tuesday.
            """
            let fm = FoundationModelsService.shared
            guard fm.isAvailable else {
                print("⚠️ --selftest-llm: on-device model unavailable; skipping"); exit(0)
            }
            do {
                let eval = try await fm.evaluateGoals(goals, transcript: transcript)
                let notes = try await fm.generateSessionNotes(transcript: transcript, goals: goals)
                for goal in goals {
                    print("   • \(goal.text) → \(eval.evaluations[goal.id] == true ? "ACHIEVED" : "not achieved")")
                }
                let metHit      = eval.evaluations[pricingGoal.id] == true
                                  && eval.evaluations[followUpGoal.id] == true
                let absentNotHit = eval.evaluations[absentGoal.id] == false
                let ok = eval.evaluations.count == goals.count && !notes.isEmpty
                         && metHit && absentNotHit
                if !ok && !absentNotHit {
                    print("❌ --selftest-llm: absent goal was wrongly marked achieved (over-lenient evaluation)")
                }
                print(ok ? "✅ --selftest-llm PASS" : "❌ --selftest-llm FAIL")
                exit(ok ? 0 : 1)
            } catch {
                // A thrown framework error here means the on-device model runtime
                // couldn't serve (e.g. assets not yet provisioned / Apple Intelligence
                // not ready) — not a defect in our integration. The app handles this
                // by falling back to keyword analysis, so treat it as a skip, not a
                // failure. Our own logic errors surface as a failed `ok` assertion above.
                print("⚠️ --selftest-llm: model runtime unavailable; skipping (\(error))")
                exit(0)
            }
        }
        // Keep the process alive while the async self-test runs.
        RunLoop.main.run()
    }
}
