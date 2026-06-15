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

## Coaching Video Assets

This directory contains video assets for the Army General coaching system.

## Video Files

47 video files totaling ~160MB:
- 11 video categories (idle, goal, timing, pause, listen, prompt, mute, focus, check, steady, wrap)
- 4 variations of each video
- MP4 format optimized for iOS

## How to Add Videos

### Option 1: Copy from Desktop App

```bash
# From project root
cp kochi-audio-transcribe/assets/video/general-*.mp4 ios/KochiApp/Resources/Videos/
```

Then run:
```bash
./ios/add-videos-to-xcode.sh
```

Follow the instructions to add videos to Xcode project.

### Option 2: Manual Download

Videos are sourced from the desktop application at:
`kochi-audio-transcribe/assets/video/`

Copy all files starting with `general-` to this directory.

### Option 3: Add in Xcode

1. Open `ios/Kochi.xcodeproj` in Xcode
2. Right-click on 'KochiApp' in project navigator
3. Select "Add Files to KochiApp..."
4. Navigate to this directory
5. Select all .mp4 files
6. Ensure "Copy items if needed" is checked
7. Click "Add"

## Video Categories

Each category has 4 variations (general-{category}-1.mp4 through general-{category}-4.mp4):

- **idle** - Breathing animation (loops continuously)
- **goal** - Celebration when goals achieved ✅
- **timing** - Time management reminders ⏰
- **pause** - Take a break ✋
- **listen** - Active listening prompts 👂
- **prompt** - Ask questions ❓
- **mute** - Stop over-talking 🤐
- **focus** - Concentration reminders 👀
- **check** - Progress check ⌚
- **steady** - Good pace maintenance 👍
- **wrap** - Wrap up meeting 🏁

## Note on Git

Videos are excluded from git (.gitignore) due to their size (160MB total).
Each developer/build should copy videos locally from the desktop app.

## Testing Without Videos

The app works perfectly without videos! It will show icon placeholders if videos are missing.
Videos enhance the experience but are not required for functionality.
