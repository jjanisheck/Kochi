import SwiftUI

struct RecordingView: View {
    @EnvironmentObject var audioManager: AudioManager
    @EnvironmentObject var themeManager: ThemeManager
    @State private var showCoachingOverlay = false
    @State private var animationScale: CGFloat = 1.0
    
    var body: some View {
        ZStack {
            // Background
            themeManager.backgroundColor
                .ignoresSafeArea()
            
            VStack(spacing: 30) {
                // Audio Level Meter
                AudioLevelMeter(level: audioManager.audioLevel)
                    .frame(height: 60)
                    .padding(.horizontal)
                
                // Recording Timer
                Text(formatTime(audioManager.recordingTime))
                    .font(.system(size: 48, weight: .medium, design: .monospaced))
                    .foregroundColor(themeManager.textColor)
                    .opacity(audioManager.isRecording ? 1 : 0.5)
                
                // Film Reel Animation
                FilmReelAnimation(isAnimating: audioManager.isRecording)
                    .frame(width: 200, height: 200)
                
                // Record Button
                RecordButton(isRecording: audioManager.isRecording) {
                    if audioManager.isRecording {
                        audioManager.stopRecording()
                    } else {
                        audioManager.startRecording()
                    }
                }
                .scaleEffect(animationScale)
                .animation(.easeInOut(duration: 0.2), value: animationScale)
                
                // Transcription Text
                ScrollView {
                    Text(audioManager.transcriptionText.isEmpty ? "Start recording to see transcription..." : audioManager.transcriptionText)
                        .font(.body)
                        .foregroundColor(themeManager.textColor.opacity(0.8))
                        .multilineTextAlignment(.leading)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .background(themeManager.secondaryBackgroundColor)
                .cornerRadius(10)
                .padding(.horizontal)
                
                Spacer()
            }
            .padding(.top, 40)
            
            // Coaching Overlay
            if showCoachingOverlay && !audioManager.coachingResponse.isEmpty {
                CoachingOverlay(text: audioManager.coachingResponse)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(audioManager.$coachingResponse) { response in
            withAnimation {
                showCoachingOverlay = !response.isEmpty
            }
        }
    }
    
    private func formatTime(_ time: TimeInterval) -> String {
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

// MARK: - Audio Level Meter
struct AudioLevelMeter: View {
    let level: Float
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 2) {
                ForEach(0..<20) { index in
                    Rectangle()
                        .fill(barColor(for: index))
                        .frame(width: (geometry.size.width - 38) / 20)
                        .scaleEffect(y: barHeight(for: index), anchor: .bottom)
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
        }
    }
    
    private func barHeight(for index: Int) -> CGFloat {
        let threshold = Float(index) / 20.0
        return level > threshold ? 1.0 : 0.3
    }
    
    private func barColor(for index: Int) -> Color {
        if index < 12 {
            return themeManager.accentColor
        } else if index < 16 {
            return .yellow
        } else {
            return .red
        }
    }
}

// MARK: - Film Reel Animation
struct FilmReelAnimation: View {
    let isAnimating: Bool
    @State private var rotation: Double = 0
    
    var body: some View {
        Image(systemName: "film")
            .resizable()
            .aspectRatio(contentMode: .fit)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                if isAnimating {
                    startAnimation()
                }
            }
            .onChange(of: isAnimating) { _, newValue in
                if newValue {
                    startAnimation()
                } else {
                    stopAnimation()
                }
            }
    }
    
    private func startAnimation() {
        withAnimation(.linear(duration: 2).repeatForever(autoreverses: false)) {
            rotation = 360
        }
    }
    
    private func stopAnimation() {
        withAnimation(.linear(duration: 0.1)) {
            rotation = 0
        }
    }
}

// MARK: - Record Button
struct RecordButton: View {
    let isRecording: Bool
    let action: () -> Void
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isRecording ? Color.red : themeManager.accentColor)
                    .frame(width: 80, height: 80)
                
                Image(systemName: isRecording ? "stop.fill" : "mic.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
            }
        }
        .shadow(radius: isRecording ? 10 : 5)
    }
}

// MARK: - Coaching Overlay
struct CoachingOverlay: View {
    let text: String
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        VStack {
            Text(text)
                .font(.headline)
                .foregroundColor(.white)
                .padding()
                .background(themeManager.accentColor.opacity(0.9))
                .cornerRadius(10)
                .shadow(radius: 5)
                .padding(.top, 50)
            
            Spacer()
        }
    }
}

struct RecordingView_Previews: PreviewProvider {
    static var previews: some View {
        RecordingView()
            .environmentObject(AudioManager())
            .environmentObject(ThemeManager())
    }
}