import SwiftUI

struct CoachingView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var goalManager: GoalManager
    @EnvironmentObject var themeManager: ThemeManager
    @StateObject private var llmManager = LLMManager()
    
    @State private var showModelSelector = false
    @State private var selectedGoal: Goal?
    @State private var isGeneratingCoaching = false
    
    var body: some View {
        NavigationStack {
            ZStack {
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(spacing: 20) {
                        // Model Status Card
                        ModelStatusCard(llmManager: llmManager)
                            .onTapGesture {
                                showModelSelector = true
                            }
                        
                        // Real-time Coaching Section
                        if audioManager.isRecording {
                            RealtimeCoachingCard(
                                transcription: audioManager.transcriptionText,
                                coaching: llmManager.streamingText,
                                isProcessing: llmManager.isProcessing
                            )
                        }
                        
                        // Goals Progress
                        GoalsProgressCard(
                            goals: goalManager.goals,
                            selectedGoal: $selectedGoal
                        )
                        
                        // Session Analysis
                        if !audioManager.transcriptionText.isEmpty {
                            SessionAnalysisCard(
                                onAnalyze: analyzeSession
                            )
                        }
                        
                        // Coaching History
                        CoachingHistoryCard()
                    }
                    .padding()
                }
                
                if llmManager.isProcessing {
                    ProcessingOverlay()
                }
            }
            .navigationTitle("AI Coaching")
            .inlineNavigationTitle()
            .sheet(isPresented: $showModelSelector) {
                ModelSelectorView(llmManager: llmManager)
            }
            .onReceive(audioManager.$transcriptionText) { text in
                if audioManager.isRecording && !text.isEmpty {
                    generateRealtimeCoaching(for: text)
                }
            }
        }
    }
    
    // MARK: - Actions
    private func generateRealtimeCoaching(for transcription: String) {
        guard !isGeneratingCoaching else { return }
        
        isGeneratingCoaching = true
        
        Task {
            do {
                try await llmManager.generateCoachingResponse(
                    for: transcription,
                    goals: goalManager.goals
                )
            } catch {
                print("Coaching generation error: \(error)")
            }
            
            isGeneratingCoaching = false
        }
    }
    
    private func analyzeSession() {
        Task {
            do {
                // Evaluate goals
                let evaluation = try await llmManager.evaluateGoals(
                    goalManager.goals,
                    with: audioManager.transcriptionText
                )
                
                // Update goal completion based on evaluation
                for (goalId, achieved) in evaluation.evaluations {
                    if let goal = goalManager.goals.first(where: { $0.id == goalId }) {
                        if achieved && !goal.isCompleted {
                            goalManager.toggleGoalCompletion(goal)
                        }
                    }
                }
                
                // Generate session notes
                let notes = try await llmManager.generateSessionNotes(
                    transcription: audioManager.transcriptionText,
                    goals: goalManager.goals
                )
                
                goalManager.updateNotes(notes)
                
            } catch {
                print("Session analysis error: \(error)")
            }
        }
    }
}

// MARK: - Model Status Card
struct ModelStatusCard: View {
    @ObservedObject var llmManager: LLMManager
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "cpu")
                    .font(.title2)
                    .foregroundColor(themeManager.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI Model")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)

                    Text("Apple Foundation Models")
                        .font(.caption)
                        .foregroundColor(themeManager.textColor.opacity(0.7))
                }

                Spacer()

                // Apple Foundation Models are always available on iOS 17+
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }

            // Apple Foundation Models info
            HStack {
                Image(systemName: "info.circle")
                    .foregroundColor(themeManager.accentColor.opacity(0.7))

                Text("Using on-device NaturalLanguage framework")
                    .font(.caption2)
                    .foregroundColor(themeManager.textColor.opacity(0.6))
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Realtime Coaching Card
struct RealtimeCoachingCard: View {
    let transcription: String
    let coaching: String
    let isProcessing: Bool
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "waveform")
                    .font(.title2)
                    .foregroundColor(themeManager.accentColor)
                
                Text("Live Coaching")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Spacer()
                
                if isProcessing {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
            
            if !coaching.isEmpty {
                Text(coaching)
                    .font(.body)
                    .foregroundColor(themeManager.textColor.opacity(0.9))
                    .padding()
                    .background(themeManager.backgroundColor)
                    .cornerRadius(8)
            } else {
                Text("Listening and analyzing...")
                    .font(.caption)
                    .foregroundColor(themeManager.textColor.opacity(0.6))
                    .italic()
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Goals Progress Card
struct GoalsProgressCard: View {
    let goals: [Goal]
    @Binding var selectedGoal: Goal?
    @EnvironmentObject var themeManager: ThemeManager
    
    var completionRate: Double {
        guard !goals.isEmpty else { return 0 }
        let completed = goals.filter { $0.isCompleted }.count
        return Double(completed) / Double(goals.count)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "target")
                    .font(.title2)
                    .foregroundColor(themeManager.accentColor)
                
                Text("Goals Progress")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Spacer()
                
                Text("\(Int(completionRate * 100))%")
                    .font(.headline)
                    .foregroundColor(themeManager.accentColor)
            }
            
            ProgressView(value: completionRate)
                .tint(themeManager.accentColor)
            
            ForEach(goals.prefix(3)) { goal in
                HStack {
                    Image(systemName: goal.isCompleted ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(goal.isCompleted ? .green : themeManager.textColor.opacity(0.4))
                    
                    Text(goal.text)
                        .font(.caption)
                        .foregroundColor(themeManager.textColor.opacity(0.8))
                        .lineLimit(1)
                    
                    Spacer()
                }
                .padding(.vertical, 2)
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Session Analysis Card
struct SessionAnalysisCard: View {
    let onAnalyze: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundColor(themeManager.accentColor)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Analysis")
                        .font(.headline)
                        .foregroundColor(themeManager.textColor)
                    
                    Text("Analyze your conversation and update goals")
                        .font(.caption)
                        .foregroundColor(themeManager.textColor.opacity(0.7))
                }
                
                Spacer()
            }
            
            Button(action: onAnalyze) {
                Text("Analyze Session")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(themeManager.accentColor)
                    .cornerRadius(10)
            }
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Coaching History Card
struct CoachingHistoryCard: View {
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundColor(themeManager.accentColor)
                
                Text("Recent Sessions")
                    .font(.headline)
                    .foregroundColor(themeManager.textColor)
                
                Spacer()
            }
            
            // Placeholder for session history
            Text("No previous sessions")
                .font(.caption)
                .foregroundColor(themeManager.textColor.opacity(0.6))
                .italic()
        }
        .padding()
        .background(themeManager.secondaryBackgroundColor)
        .cornerRadius(12)
    }
}

// MARK: - Processing Overlay
struct ProcessingOverlay: View {
    @EnvironmentObject var themeManager: ThemeManager
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: themeManager.accentColor))
                    .scaleEffect(1.5)
                
                Text("AI is thinking...")
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .padding(30)
            .background(themeManager.secondaryBackgroundColor)
            .cornerRadius(15)
            .shadow(radius: 10)
            .scaleEffect(isAnimating ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: isAnimating)
            .onAppear {
                isAnimating = true
            }
        }
    }
}

struct CoachingView_Previews: PreviewProvider {
    static var previews: some View {
        CoachingView()
            .environmentObject(AudioManager())
            .environmentObject(GoalManager())
            .environmentObject(ThemeManager())
    }
}