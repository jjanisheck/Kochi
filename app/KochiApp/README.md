# KochiApp - iOS Meeting Coach

AI-powered meeting coach with on-device speech-to-text and goal analysis.

## Features

- **On-Device Transcription**: Whisper.cpp for private, offline speech-to-text
- **Local AI Analysis**: LFM 2.5 Thinking model for goal evaluation
- **Cloud Fallback**: OpenAI Whisper/GPT when local models unavailable
- **Real-time Coaching**: Live feedback during meetings
- **Goal Tracking**: Set and monitor meeting objectives

---

## Testing

### Test Suite Overview

The app includes a comprehensive test suite for verifying the speech-to-text and goal analysis flow.

| Test Class | Tests | Purpose |
|------------|-------|---------|
| `LocalTranscriptionServiceTests` | 6 | Transcription service, audio/file handling, error cases |
| `LocalLLMServiceTests` | 10 | Goal evaluation, scoring, feedback generation |
| `SpeechToTextGoalAnalysisIntegrationTests` | 11 | Full pipeline: Audio → Transcription → Analysis |
| `AnalysisModeSwitchingTests` | 4 | Local/cloud mode switching for analysis |
| `TranscriptionModeSwitchingTests` | 2 | Local/cloud mode switching for transcription |
| `WhisperModelTests` | 6 | Whisper model definitions and mappings |
| `LLMModelAnalysisTests` | 6 | LLM model categories and properties |
| `SpeechToTextAnalysisPerformanceTests` | 3 | Performance benchmarks |

**Total: 48 tests**

### Test Files Location

```
ios/KochiApp/Tests/
├── SpeechToTextAnalysisTests.swift  # Main integration tests
├── LLMManagerTests.swift            # LLM service tests
├── TranscriptionManagerTests.swift  # Transcription tests
├── UnitTests.swift                  # General unit tests
└── ViewTests.swift                  # UI tests
```

### Running Tests

#### Option 1: Xcode (Recommended)

1. Open `Kochi.xcodeproj` in Xcode
2. Add test target if not exists:
   - File → New → Target → iOS Unit Testing Bundle
   - Name: `KochiAppTests`
   - Target to Test: `KochiApp`
3. Add test files to target:
   - Drag files from `KochiApp/Tests/` to the test target
4. Run tests: `Cmd+U`

#### Option 2: Command Line

```bash
xcodebuild test \
  -project Kochi.xcodeproj \
  -scheme KochiApp \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Mock Services

Tests use mock services to run without real AI models:

- `MockLocalTranscriptionService` - Simulates Whisper.cpp transcription
- `MockLocalLLMService` - Simulates LFM 2.5 goal analysis

This allows fast, reliable testing without model downloads or API keys.

### Key Test Scenarios

**Full Pipeline Test:**
```
Audio Data → Transcription → Goal Matching → Score Calculation
     ↓              ↓               ↓               ↓
  [bytes]     "discussed      [budget: ✅]      66% (2/3)
              budget and      [timeline: ✅]
              timeline"       [licensing: ❌]
```

**Incremental Transcription:**
- Tests real-time segment processing
- Verifies progressive goal achievement
- Validates rolling transcript accumulation

**Edge Cases:**
- Empty transcriptions
- Long transcriptions (simulated meetings)
- Special characters and emojis
- Case-insensitive matching

---

## Coach rendering

The transcript and reel transport are separate, evenly spaced panels. The transport
uses two independently spinning reels with a center timer and sound meter. The
coach and transcript panels share the remaining height equally. On iPhone, the
theme background fills the entire screen,
including behind the status bar and Dynamic Island; controls respect safe areas.
The Mac app uses the same 402 × 874-point iPhone 17 Pro canvas, including 62-point
top and 34-point bottom safe-area spacing. Both platforms share panel sizing,
background scaling, fonts, and the five info tabs. Drag the Mac window by its
background; use the File menu or Command-W to close it.

On Mac, launch with `--character-workshop` to preview the installed mannequin and rehearse ten
coaching responses without starting a meeting. Edit geometry and motion in the
browser workshop. See
[Character Workshop](../../docs/character-workshop.md).

The Default theme uses the local mannequin, driven by structured on-device
coaching decisions. Its 35 authored clips run in a bundled offline renderer with
a fixed bust camera, pixel treatment, breathing idle, and contextual reactions.
See [Animated coach](../../docs/animated-coach.md) for the architecture and render checks.

## Coaching Video Assets

Bricks, Hero, Noir, and Zen use video coaching. Each theme loads its own video set
under `Resources/Themes/<theme-id>/videos/`, named `<label>-<variation>.mp4`
(e.g. `idle-1.mp4`). There are 11 labels — idle, goal, timing, pause, listen,
prompt, mute, focus, check, steady, wrap — with up to 4 variations each.
Bricks has the full reaction set; Hero, Noir, and Zen currently contain idle
clips and fall back to those when a reaction clip is unavailable.

To author or add clips for a theme, see
[`docs/creating-coach-videos.md`](../../docs/creating-coach-videos.md), which
covers the naming convention, clip specs, and generation prompts.

The app works without videos — it falls back to the `idle` clip, and shows a
placeholder if that's missing too.
