import SwiftUI
import AVKit

// MARK: - Modern Content View (Matching iPhone-16-plus.png Design)
struct ContentView_Modern: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var llmManager: LLMManager
    @StateObject private var videoManager = VideoCoachingManager()
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with KŌCHI branding (orange)
            ModernHeader(showSettings: $showSettings)

            // Search bar placeholder
            SearchBar()
                .padding(.horizontal)
                .padding(.vertical, 8)

            // Video Coach Section (main focus)
            VideoCoachSection(videoManager: videoManager)
                .padding(.horizontal)

            // Goals Section (below video)
            GoalsChecklist()
                .padding(.horizontal)
                .padding(.vertical, 12)

            // Progress Indicator
            RecordingProgressView()
                .padding(.horizontal)

            Spacer()

            // Bottom Action Buttons
            BottomActionButtons()
                .padding(.horizontal)
                .padding(.bottom, 20)
        }
        .background(Color.systemGroupedBackground)
        .sheet(isPresented: $showSettings) {
            SettingsView(isPresented: $showSettings)
        }
    }
}

// MARK: - Modern Header
struct ModernHeader: View {
    @Binding var showSettings: Bool

    var body: some View {
        HStack {
            // KŌCHI logo in orange
            Text("KŌCHI")
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(Color(hex: "FF6B35")) // Orange/coral

            Spacer()

            // Settings button
            Button(action: { showSettings.toggle() }) {
                Image(systemName: "gearshape")
                    .font(.title2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color.systemBackground)
    }
}

// MARK: - Search Bar
struct SearchBar: View {
    @State private var searchText = ""

    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)

            TextField("Search", text: $searchText)
                .textFieldStyle(PlainTextFieldStyle())

            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(8)
        .background(Color.systemGray6)
        .cornerRadius(10)
    }
}

// MARK: - Video Coach Section (Like design mockup)
struct VideoCoachSection: View {
    @ObservedObject var videoManager: VideoCoachingManager
    @EnvironmentObject var llmManager: LLMManager

    var body: some View {
        VStack(spacing: 0) {
            // Video player area with coach
            ZStack {
                // Placeholder for actual video (grayscale coach character)
                Rectangle()
                    .fill(Color.systemGray4)
                    .aspectRatio(16/9, contentMode: .fit)
                    .overlay(
                        // Coach character placeholder
                        Image(systemName: "person.crop.square.filled.and.at.rectangle")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 120, height: 120)
                            .foregroundColor(.secondary)
                    )

                // Coaching message overlay at bottom
                VStack {
                    Spacer()

                    if !llmManager.coachingResponse.isEmpty {
                        HStack {
                            Image(systemName: "play.fill")
                                .foregroundColor(.white)
                                .font(.caption)

                            Text(llmManager.coachingResponse)
                                .font(.system(size: 14))
                                .foregroundColor(.white)
                                .lineLimit(2)
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                        .padding()
                    }
                }
            }
            .cornerRadius(12)
            .shadow(color: .black.opacity(0.1), radius: 5)
        }
    }
}

// MARK: - Goals Checklist (Matching design)
struct GoalsChecklist: View {
    @EnvironmentObject var goalManager: GoalManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("goals")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            ForEach(goalManager.goals.prefix(3)) { goal in
                GoalChecklistItem(goal: goal)
            }
        }
        .padding()
        .background(Color.systemBackground)
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 3)
    }
}

// MARK: - Goal Checklist Item
struct GoalChecklistItem: View {
    let goal: Goal
    @EnvironmentObject var goalManager: GoalManager

    var body: some View {
        Button(action: {
            goalManager.toggleGoalCompletion(goal)
        }) {
            HStack(spacing: 12) {
                // Checkbox
                Image(systemName: goal.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundColor(goal.isCompleted ? Color(hex: "FF6B35") : .secondary)

                // Goal text
                Text(goal.text)
                    .font(.system(size: 16))
                    .foregroundColor(.primary)
                    .strikethrough(goal.isCompleted)

                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Recording Progress View (Visual dots indicator)
struct RecordingProgressView: View {
    @EnvironmentObject var audioManager: AudioManager

    var body: some View {
        VStack(spacing: 8) {
            // Progress dots (like design mockup)
            HStack(spacing: 8) {
                ForEach(0..<11) { index in
                    Circle()
                        .fill(progressColor(for: index))
                        .frame(width: 28, height: 28)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func progressColor(for index: Int) -> Color {
        if audioManager.isRecording {
            let progress = Int(audioManager.recordingTime / 10) // Each segment = 10 seconds
            return index < progress ? Color(hex: "FF6B35") : Color.systemGray5
        } else {
            return Color.systemGray5
        }
    }
}

// MARK: - Bottom Action Buttons
struct BottomActionButtons: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var llmManager: LLMManager
    @State private var showInfo = false

    var body: some View {
        HStack(spacing: 16) {
            // Start button (orange)
            ActionButton(
                title: "start",
                icon: "play.fill",
                color: Color(hex: "FF6B35"),
                isActive: audioManager.isRecording
            ) {
                if !audioManager.isRecording {
                    audioManager.startRecording()
                }
            }

            // End button (gray)
            ActionButton(
                title: "end",
                icon: "stop.fill",
                color: Color.systemGray4,
                isActive: !audioManager.isRecording
            ) {
                if audioManager.isRecording {
                    audioManager.stopRecording()
                    // Evaluate goals on stop
                    Task {
                        try? await llmManager.evaluateGoals(
                            goalManager.goals,
                            with: audioManager.transcriptionText
                        )
                    }
                }
            }

            // Info button (light gray)
            ActionButton(
                title: "info",
                icon: "info.circle.fill",
                color: Color.systemGray5,
                isActive: true
            ) {
                showInfo.toggle()
            }
        }
        .sheet(isPresented: $showInfo) {
            SessionInfoView()
        }
    }
}

// MARK: - Action Button Component
struct ActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isActive ? .white : .secondary)

                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(isActive ? .white : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(isActive ? color : Color.systemGray6)
            .cornerRadius(12)
        }
    }
}

// MARK: - Session Info View
struct SessionInfoView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Session duration
                    InfoSection(title: "Session Duration") {
                        Text(formatTime(audioManager.recordingTime))
                            .font(.title)
                            .foregroundColor(Color(hex: "FF6B35"))
                    }

                    // Goals progress
                    InfoSection(title: "Goals Progress") {
                        let completed = goalManager.goals.filter { $0.isCompleted }.count
                        let total = goalManager.goals.count

                        ProgressView(value: Double(completed), total: Double(total))
                            .tint(Color(hex: "FF6B35"))

                        Text("\(completed) of \(total) completed")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    // Transcription
                    InfoSection(title: "Transcription") {
                        Text(audioManager.transcriptionText.isEmpty ? "No transcription yet" : audioManager.transcriptionText)
                            .font(.body)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Session Info")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Info Section Component
struct InfoSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            content
        }
        .padding()
        .background(Color.systemGray6)
        .cornerRadius(12)
    }
}

// MARK: - Color Extension (Hex Support)
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Previews
struct ContentView_Modern_Previews: PreviewProvider {
    static var previews: some View {
        ContentView_Modern()
            .environmentObject(AudioManager())
            .environmentObject(GoalManager())
            .environmentObject(ThemeManager())
            .environmentObject(LLMManager())
    }
}
