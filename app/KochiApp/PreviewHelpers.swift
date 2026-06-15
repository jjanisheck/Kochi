import SwiftUI

// MARK: - Preview Helpers for Faster Iteration
// Use these to test UI changes in Xcode canvas WITHOUT running simulator

// MARK: - Mock Data for Previews
extension AudioManager {
    static var preview: AudioManager {
        let manager = AudioManager()
        manager.transcriptionText = "Sample transcription text for preview. This is what the user is saying during the recording session."
        manager.isRecording = true
        manager.recordingTime = 125.0 // 2:05
        manager.audioLevel = 0.7
        return manager
    }

    static var previewIdle: AudioManager {
        let manager = AudioManager()
        return manager
    }
}

extension GoalManager {
    static var preview: GoalManager {
        let manager = GoalManager()
        manager.goals = [
            Goal(id: UUID(), text: "do they have budget?", isCompleted: true),
            Goal(id: UUID(), text: "ask about license", isCompleted: false),
            Goal(id: UUID(), text: "get timeline for buy", isCompleted: false)
        ]
        return manager
    }
}

extension LLMManager {
    static var preview: LLMManager {
        let manager = LLMManager()
        manager.coachingResponse = "things are going well. need to be friendlier on this call. you got this."
        return manager
    }

    static var previewIdle: LLMManager {
        return LLMManager()
    }
}

extension ThemeManager {
    static var preview: ThemeManager {
        return ThemeManager()
    }
}

// MARK: - Preview Wrapper for Environment Objects
struct PreviewWrapper<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .environmentObject(AudioManager.preview)
            .environmentObject(GoalManager.preview)
            .environmentObject(LLMManager.preview)
            .environmentObject(ThemeManager.preview)
    }
}

// MARK: - Individual Component Previews
// These allow you to iterate on specific UI components quickly

#Preview("Modern Content View - Recording") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.preview)
    }
}

#Preview("Modern Content View - Idle") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.previewIdle)
            .environmentObject(LLMManager.previewIdle)
    }
}

#Preview("Video Coach Section") {
    PreviewWrapper {
        VideoCoachSection(videoManager: VideoCoachingManager())
            .padding()
            .environmentObject(LLMManager.preview)
    }
}

#Preview("Goals Checklist") {
    PreviewWrapper {
        GoalsChecklist()
            .padding()
            .environmentObject(GoalManager.preview)
    }
}

#Preview("Bottom Action Buttons") {
    PreviewWrapper {
        BottomActionButtons()
            .padding()
            .environmentObject(AudioManager.preview)
            .environmentObject(GoalManager.preview)
            .environmentObject(LLMManager.preview)
    }
}

#Preview("Recording Progress - Active") {
    PreviewWrapper {
        RecordingProgressView()
            .padding()
            .environmentObject(AudioManager.preview)
    }
}

#Preview("Recording Progress - Idle") {
    PreviewWrapper {
        RecordingProgressView()
            .padding()
            .environmentObject(AudioManager.previewIdle)
    }
}

#Preview("Session Info View") {
    PreviewWrapper {
        SessionInfoView()
            .environmentObject(AudioManager.preview)
            .environmentObject(GoalManager.preview)
    }
}

// MARK: - Dark Mode Previews
#Preview("Modern Content View - Dark Mode") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.preview)
    }
    .preferredColorScheme(.dark)
}

#Preview("Modern Content View - Light Mode") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.preview)
    }
    .preferredColorScheme(.light)
}

// MARK: - Size Variant Previews
#Preview("iPhone 16 Pro Max") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.preview)
    }
    .previewDevice("iPhone 16 Pro Max")
}

#Preview("iPhone SE") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.preview)
    }
    .previewDevice("iPhone SE (3rd generation)")
}

#Preview("iPad Pro") {
    PreviewWrapper {
        ContentView_Modern()
            .environmentObject(AudioManager.preview)
    }
    .previewDevice("iPad Pro (12.9-inch) (6th generation)")
}
