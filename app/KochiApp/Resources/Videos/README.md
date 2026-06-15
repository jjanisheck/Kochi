# Coaching Video Assets

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
