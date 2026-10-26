# Live transcription

The audio meter measures captured microphone samples. It does not indicate
whether speech recognition is ready or producing text. The transcript header and
empty-state message report the recognizer's state separately: preparing,
downloading, listening, or unavailable.

`SpeechChannel` resolves the requested English locale through Apple's supported
locale API, reserves the locale, installs required assets, and prepares the
analyzer with its actual audio format. Setup errors are surfaced in the UI.
`DictationTranscriber` provides a local alternative when the newer model is not
supported. On iOS, if the analyzer cannot use the installed dictation assets,
the compatibility path uses `SFSpeechRecognizer` with
`requiresOnDeviceRecognition = true`. It never enables server recognition.

Tap buffers are copied before returning to the audio engine. Conversion runs
after format negotiation, rather than converting early buffers to an assumed
format. Startup buffering is bounded. Per-session identifiers reject late
results and failures after a recording is stopped or replaced.

The iOS Simulator may report dictation assets as installed and still fail to
initialize its local recognizer. In that case the app explains the limitation
and continues saving audio; live transcription must be tested on a supported
physical iPhone or Mac.

## Live text and long meetings

The home transcript displays elapsed meeting time, speaker, and text in aligned
columns with subtle row separators. Timestamps and speaker labels use the mono
font; speech uses Zilla Slab Medium at 13 points, matching the coach caption.
Default uses a very light surface with dark gray text; the other bundled themes
retain their textured surfaces and white speech text.
Each passage keeps its identity and elapsed time from its first nonempty live
result through corrections and finalization. These are recognition arrival times,
not word-level audio offsets. `Me` displays as `YOU`; `Them` retains its source
label. On iOS, microphone speech is one source, without speaker diarization.
There are no chat bubbles. The live panel displays up to the latest 100 passages
and 16,000 characters, and indicates when older text is outside that view.
The complete text stays in the meeting file and finished meeting history.
Saved-meeting transcript styling is independent.

There is no configured meeting duration or file-size cutoff. Audio is streamed to
mono 48 kHz AAC with a 64 kb/s target, so budget about **30 MB per hour** for audio
(roughly 60 MB for two hours), plus transcript/metadata. Actual AAC size varies
with content and encoder behavior. This is a storage estimate, not a certified
recording duration. A real multi-hour device run is still needed to establish
reliability with live recognition, coaching, battery, temperature, and phone locks.

The audio callback copies buffers into a bounded serial writer; encoding and disk
writes happen off the realtime thread. A writer overrun or disk failure stops
capture visibly rather than dropping unlimited audio or accumulating memory.
The far-side audio FIFO and analyzer input queues are bounded too. Speech results
coalesce before reaching the UI, and revisions prevent older rendering work from
replacing a newer update. Transcription failure does not itself stop audio saving.

Transcript checkpoints retain only the latest pending value and write an atomic
snapshot off the UI thread about once per second. This also preserves speech
corrections instead of appending suffixes to an earlier volatile result. Stop
flushes the final transcript and drains audio before closing its container. An
unexpected process exit can still lose the last checkpoint, and an unfinished
M4A file is not guaranteed recoverable after a crash or force quit.

On iOS, background audio mode supports continued capture when the screen locks.
The app observes system audio deactivation/resumption, route changes, audio
service resets, and missing buffers. It resumes only when iOS recommends it;
otherwise it stops with an explanation and retains saved files. Coaching work is
cancelled in the background. This does not make recording immune to phone calls,
resource pressure, force quitting, or system termination.

## Diagnosing a stopped recording

Each new meeting has a local `recording-diagnostics.jsonl` beside its audio. Every
ten seconds, and on relevant lifecycle events, it records elapsed time, audio
bytes, transcript character count, resident memory, thermal state, free storage,
and time since the last microphone buffer. It also records speech readiness,
interruptions, route changes, restarts, failures, and normal stop. It contains no
transcript text or audio. Log rotation keeps the most recent two approximately
1 MB parts per recording.

Open **info → About → Recording diagnostics → Share latest recording report**.
This exports the latest local report through the system share sheet. A persistent
marker flags an unfinished prior recording on relaunch; it does not prove a
crash, because installing an update or force quitting can leave the same marker.

For a confirmed app termination, also inspect the phone's Analytics Data or
Xcode's device crash reports. A memory termination (jetsam), watchdog termination,
audio interruption, and a recognizer failure have different evidence. The app's
diagnostic report helps correlate those events; it does not invent a crash cause
when the system has no matching report.

## Verification

Launch the built app's executable with `--selftest-speech-status` to inspect
supported and installed English models. `--selftest` waits for recognition to
be ready, synthesizes a known phrase, supplies the PCM samples, and verifies
recognized words. The synthesizer is retained until it has finished producing
audio. No microphone recording is used in this test.

`--selftest-merge` checks that live partials and finalized results keep the
correct `Me` and `Them` labels. An unavailable runtime is reported as unavailable,
not counted as a passing recognition test.

On Mac, `--selftest-recording` encodes **two hours of synthetic PCM audio at
accelerated speed**, verifies the finalized duration, samples memory growth,
checks audio-file sizes, flushes a large Unicode transcript with partial-result
corrections, and checks diagnostic export and unfinished-session recovery. It
does not capture the microphone or run recognition or coaching. Passing this
test is not equivalent to two elapsed hours of live recording on an iPhone.
