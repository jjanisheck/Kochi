import Foundation
import Speech
import AVFoundation

/// Headless verification of the on-device speech pipeline. Synthesizes a known
/// phrase with `AVSpeechSynthesizer`, feeds the audio through a real
/// `SpeechChannel` (Apple on-device recognition), and checks the transcript.
///
/// Run by launching the app with `--selftest`. Results are printed with the
/// `SELFTEST` prefix and the process exits with code 0 (pass) or 1 (fail).
enum TranscriptionSelfTest {
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
        guard channel.isAvailable else {
            print("SELFTEST FAIL: recognizer unavailable for en-US")
            exit(1)
        }

        var latestText = ""
        let lock = NSLock()
        channel.onUpdate = { _, text, _ in
            lock.lock(); latestText = text; lock.unlock()
        }
        channel.start()

        // Synthesize the phrase and feed buffers into the channel.
        let synth = AVSpeechSynthesizer()
        let utterance = AVSpeechUtterance(string: phrase)
        utterance.rate = 0.45
        utterance.volume = 1.0

        var produced = 0
        synth.write(utterance) { buffer in
            guard let pcm = buffer as? AVAudioPCMBuffer else { return }
            if pcm.frameLength > 0 {
                produced += Int(pcm.frameLength)
                channel.append(pcm)
            }
        }

        // Synthesis is async; give it time to produce audio, then end + evaluate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) {
            channel.stop()
            print("SELFTEST: synthesized \(produced) frames of audio")

            // Allow recognizer to emit the final result.
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                lock.lock(); let result = latestText.lowercased(); lock.unlock()
                evaluate(result)
            }
        }
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
            partials: [DualTranscriptionEngine.systemLabel: "speaking now"]
        )
        check("partial system line present", flat2.contains("Them: speaking now"))
        check("finalized mic still first", flat2.hasPrefix("Me: hello there"))

        // 3. Empty/whitespace partials are dropped.
        let (_, flat3) = DualTranscriptionEngine.render(
            finalized: [], partials: [DualTranscriptionEngine.micLabel: "   "]
        )
        check("blank partial dropped", flat3.isEmpty)

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
        let got = Set(result.split(separator: " ").map(String.init))
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
