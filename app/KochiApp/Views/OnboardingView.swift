import SwiftUI
import AVFoundation
import Speech

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @StateObject private var enhancedThemeManager = EnhancedThemeManager()
    @State private var currentPage = 0
    @State private var hasCompletedOnboarding = false
    
    let pages: [OnboardingPage] = [
        OnboardingPage(
            title: "Welcome to Kochi",
            subtitle: "Your AI-powered presentation coach",
            systemImage: "waveform.circle.fill",
            description: "Transform your speaking skills with real-time AI coaching and personalized feedback.",
            primaryColor: .blue
        ),
        OnboardingPage(
            title: "Record & Transcribe",
            subtitle: "Capture every word",
            systemImage: "mic.fill",
            description: "Record your presentations and get instant transcriptions with advanced speech recognition.",
            primaryColor: .red
        ),
        OnboardingPage(
            title: "AI Coaching",
            subtitle: "Personalized feedback",
            systemImage: "brain",
            description: "Get real-time coaching on pace, clarity, filler words, and engagement techniques.",
            primaryColor: .purple
        ),
        OnboardingPage(
            title: "Track Progress",
            subtitle: "Achieve your goals",
            systemImage: "chart.line.uptrend.xyaxis",
            description: "Set speaking goals and track your improvement over time with detailed analytics.",
            primaryColor: .green
        ),
        OnboardingPage(
            title: "Get Started",
            subtitle: "Let's begin your journey",
            systemImage: "arrow.right.circle.fill",
            description: "Grant permissions and customize your experience to start improving today.",
            primaryColor: .indigo,
            isLastPage: true
        )
    ]
    
    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                gradient: Gradient(colors: [
                    pages[currentPage].primaryColor.opacity(0.1),
                    enhancedThemeManager.backgroundColor
                ]),
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            VStack {
                // Skip button
                HStack {
                    Spacer()
                    
                    if currentPage < pages.count - 1 {
                        Button("Skip") {
                            withAnimation(.spring()) {
                                currentPage = pages.count - 1
                            }
                        }
                        .foregroundColor(enhancedThemeManager.textColor.opacity(0.7))
                        .padding()
                    }
                }
                
                // Page content
                TabView(selection: $currentPage) {
                    ForEach(pages.indices, id: \.self) { index in
                        OnboardingPageView(page: pages[index]) {
                            if pages[index].isLastPage {
                                completeOnboarding()
                            } else {
                                withAnimation(.spring()) {
                                    currentPage = min(currentPage + 1, pages.count - 1)
                                }
                            }
                        }
                        .tag(index)
                    }
                }

                // Page indicators
                HStack(spacing: 8) {
                    ForEach(pages.indices, id: \.self) { index in
                        Circle()
                            .fill(currentPage == index ? pages[index].primaryColor : Color.gray.opacity(0.3))
                            .frame(width: 8, height: 8)
                            .scaleEffect(currentPage == index ? 1.2 : 1.0)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 30)
            }
        }
    }

    private func completeOnboarding() {
        // Request permissions
        requestPermissions { granted in
            if granted {
                // Save onboarding completion
                UserDefaults.standard.set(true, forKey: "HasCompletedOnboarding")
                hasCompletedOnboarding = true
                
                // Dismiss onboarding
                withAnimation(.spring()) {
                    isPresented = false
                }
            }
        }
    }
    
    private func requestPermissions(completion: @escaping (Bool) -> Void) {
        var allGranted = true
        let group = DispatchGroup()
        
        // Microphone permission (cross-platform: works on iOS and macOS)
        group.enter()
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            if !granted { allGranted = false }
            group.leave()
        }
        
        // Speech recognition permission
        group.enter()
        SFSpeechRecognizer.requestAuthorization { status in
            if status != .authorized { allGranted = false }
            group.leave()
        }
        
        
        group.notify(queue: .main) {
            completion(allGranted)
        }
    }
}

// MARK: - Onboarding Page Model
struct OnboardingPage {
    let title: String
    let subtitle: String
    let systemImage: String
    let description: String
    let primaryColor: Color
    var isLastPage: Bool = false
}

// MARK: - Onboarding Page View
struct OnboardingPageView: View {
    let page: OnboardingPage
    let action: () -> Void
    @StateObject private var enhancedThemeManager = EnhancedThemeManager()
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 30) {
            Spacer()
            
            // Icon with animation
            ZStack {
                // Background circles
                ForEach(0..<3) { index in
                    Circle()
                        .fill(page.primaryColor.opacity(0.1))
                        .frame(width: 150 + CGFloat(index * 30), height: 150 + CGFloat(index * 30))
                        .scaleEffect(isAnimating ? 1.1 : 1.0)
                        .animation(
                            Animation.easeInOut(duration: 2.0)
                                .repeatForever(autoreverses: true)
                                .delay(Double(index) * 0.2),
                            value: isAnimating
                        )
                }
                
                // Main icon
                Image(systemName: page.systemImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 100, height: 100)
                    .foregroundColor(page.primaryColor)
                    .scaleEffect(isAnimating ? 1.0 : 0.8)
                    .animation(
                        .spring(response: 0.6, dampingFraction: 0.8)
                        .delay(0.2),
                        value: isAnimating
                    )
            }
            .frame(height: 200)
            
            // Title and subtitle
            VStack(spacing: 10) {
                Text(page.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .foregroundColor(enhancedThemeManager.textColor)
                    .multilineTextAlignment(.center)
                    .slideAndFade(isShowing: isAnimating, delay: 0.3)
                
                Text(page.subtitle)
                    .font(.title3)
                    .foregroundColor(page.primaryColor)
                    .multilineTextAlignment(.center)
                    .slideAndFade(isShowing: isAnimating, delay: 0.4)
            }
            
            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(enhancedThemeManager.textColor.opacity(0.8))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .slideAndFade(isShowing: isAnimating, delay: 0.5)
            
            Spacer()
            
            // Action button
            Button(action: {
                enhancedThemeManager.triggerHaptic(.medium)
                action()
            }) {
                HStack {
                    Text(page.isLastPage ? "Get Started" : "Continue")
                        .fontWeight(.semibold)
                    
                    if !page.isLastPage {
                        Image(systemName: "arrow.right")
                    }
                }
                .foregroundColor(.white)
                .padding(.horizontal, 40)
                .padding(.vertical, 15)
                .background(page.primaryColor)
                .cornerRadius(25)
                .shadow(color: page.primaryColor.opacity(0.3), radius: 10, y: 5)
            }
            .scaleEffect(isAnimating ? 1.0 : 0.9)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.8)
                .delay(0.6),
                value: isAnimating
            )
            
            Spacer(minLength: 50)
        }
        .onAppear {
            withAnimation {
                isAnimating = true
            }
        }
    }
}

// MARK: - Tutorial Overlay
struct TutorialOverlay: View {
    @Binding var showTutorial: Bool
    let feature: TutorialFeature
    
    var body: some View {
        ZStack {
            // Dimmed background
            Color.black.opacity(0.7)
                .ignoresSafeArea()
                .onTapGesture {
                    showTutorial = false
                }
            
            // Spotlight effect
            GeometryReader { geometry in
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: geometry.size))
                    
                    // Cut out spotlight area
                    path.addRoundedRect(
                        in: feature.highlightFrame,
                        cornerSize: CGSize(width: 10, height: 10)
                    )
                }
                .fill(style: FillStyle(eoFill: true))
                .foregroundColor(.black.opacity(0.7))
            }
            
            // Tutorial content
            VStack(alignment: .leading, spacing: 15) {
                Text(feature.title)
                    .font(.headline)
                    .foregroundColor(.white)
                
                Text(feature.description)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                
                HStack {
                    if feature.showSkip {
                        Button("Skip Tutorial") {
                            UserDefaults.standard.set(true, forKey: "HasSeenTutorial")
                            showTutorial = false
                        }
                        .foregroundColor(.white.opacity(0.7))
                    }
                    
                    Spacer()
                    
                    Button("Got it!") {
                        showTutorial = false
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(20)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 15)
                    .fill(Color.black.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15)
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
            )
            .padding()
            .offset(y: feature.highlightFrame.maxY + 20 < platformScreenHeight / 2 ?
                    feature.highlightFrame.maxY + 20 :
                    feature.highlightFrame.minY - 200)
        }
        .transition(.opacity)
    }
}

// MARK: - Screen height
private var platformScreenHeight: CGFloat {
    return NSScreen.main?.frame.height ?? 800
}

// MARK: - Tutorial Feature Model
struct TutorialFeature {
    let title: String
    let description: String
    let highlightFrame: CGRect
    let showSkip: Bool
}

// MARK: - Quick Tips
struct QuickTip: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let icon: String
    let color: Color
}

struct QuickTipView: View {
    let tip: QuickTip
    @Binding var isShowing: Bool
    @State private var offset: CGFloat = -100
    @State private var opacity: Double = 0
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: tip.icon)
                .font(.title2)
                .foregroundColor(tip.color)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(tip.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(tip.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation(.spring()) {
                    opacity = 0
                    offset = -100
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    isShowing = false
                }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.systemBackground)
                .shadow(color: tip.color.opacity(0.2), radius: 10, y: 5)
        )
        .padding(.horizontal)
        .offset(y: offset)
        .opacity(opacity)
        .onAppear {
            withAnimation(.spring()) {
                offset = 0
                opacity = 1
            }
            
            // Auto-dismiss after 5 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                if isShowing {
                    withAnimation(.spring()) {
                        opacity = 0
                        offset = -100
                    }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        isShowing = false
                    }
                }
            }
        }
    }
}

// MARK: - Preview
struct OnboardingView_Previews: PreviewProvider {
    static var previews: some View {
        OnboardingView(isPresented: .constant(true))
    }
}