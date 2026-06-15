import SwiftUI

// MARK: - Custom Transitions
struct SlideAndFadeTransition: ViewModifier {
    let isShowing: Bool
    let delay: Double
    
    func body(content: Content) -> some View {
        content
            .opacity(isShowing ? 1 : 0)
            .offset(y: isShowing ? 0 : 20)
            .animation(
                .spring(response: 0.6, dampingFraction: 0.8)
                .delay(delay),
                value: isShowing
            )
    }
}

struct ScaleAndRotateTransition: ViewModifier {
    let isShowing: Bool
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isShowing ? 1 : 0.8)
            .rotationEffect(.degrees(isShowing ? 0 : -5))
            .opacity(isShowing ? 1 : 0)
            .animation(
                .spring(response: 0.5, dampingFraction: 0.7),
                value: isShowing
            )
    }
}

// MARK: - View Extensions
extension View {
    func slideAndFade(isShowing: Bool, delay: Double = 0) -> some View {
        modifier(SlideAndFadeTransition(isShowing: isShowing, delay: delay))
    }
    
    func scaleAndRotate(isShowing: Bool) -> some View {
        modifier(ScaleAndRotateTransition(isShowing: isShowing))
    }
    
    func shimmer(isAnimating: Bool = true) -> some View {
        self.overlay(
            GeometryReader { geometry in
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.3),
                        Color.white.opacity(0)
                    ]),
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: geometry.size.width * 0.3)
                .offset(x: isAnimating ? geometry.size.width : -geometry.size.width)
                .animation(
                    Animation.linear(duration: 1.5)
                        .repeatForever(autoreverses: false),
                    value: isAnimating
                )
            }
            .clipped()
        )
    }
    
    func cardFlip(isFaceUp: Bool, axis: (x: CGFloat, y: CGFloat, z: CGFloat) = (0, 1, 0)) -> some View {
        rotation3DEffect(
            .degrees(isFaceUp ? 0 : 180),
            axis: axis
        )
        .animation(.spring(response: 0.6, dampingFraction: 0.8), value: isFaceUp)
    }
    
    func bounce(trigger: Bool) -> some View {
        self.scaleEffect(trigger ? 1.1 : 1.0)
            .animation(
                .spring(response: 0.3, dampingFraction: 0.3, blendDuration: 0),
                value: trigger
            )
    }
    
    func parallaxEffect(offset: CGFloat, multiplier: CGFloat = 1.0) -> some View {
        self.offset(y: offset * multiplier)
    }
}

// MARK: - Loading Animation Views
struct PulsingCircle: View {
    @State private var isAnimating = false
    let color: Color
    let size: CGFloat
    
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .scaleEffect(isAnimating ? 1.2 : 1.0)
            .opacity(isAnimating ? 0.3 : 0.8)
            .animation(
                Animation.easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true),
                value: isAnimating
            )
            .onAppear { isAnimating = true }
    }
}

struct WaveformAnimation: View {
    @State private var animationAmounts = [CGFloat](repeating: 0.5, count: 5)
    let color: Color
    let barWidth: CGFloat = 4
    let maxHeight: CGFloat = 40
    
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<5) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color)
                    .frame(width: barWidth, height: maxHeight * animationAmounts[index])
                    .animation(
                        Animation.easeInOut(duration: Double.random(in: 0.5...0.8))
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.1),
                        value: animationAmounts[index]
                    )
            }
        }
        .onAppear {
            for index in 0..<5 {
                animationAmounts[index] = CGFloat.random(in: 0.3...1.0)
            }
        }
    }
}

struct RecordingPulse: View {
    @State private var isAnimating = false
    let color: Color
    
    var body: some View {
        ZStack {
            ForEach(0..<3) { index in
                Circle()
                    .stroke(color.opacity(0.3 - Double(index) * 0.1), lineWidth: 2)
                    .scaleEffect(isAnimating ? 1 + CGFloat(index) * 0.3 : 1)
                    .opacity(isAnimating ? 0 : 1)
                    .animation(
                        Animation.easeOut(duration: 2)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.4),
                        value: isAnimating
                    )
            }
            
            Circle()
                .fill(color)
                .frame(width: 20, height: 20)
        }
        .frame(width: 100, height: 100)
        .onAppear { isAnimating = true }
    }
}

// MARK: - Custom Animation Timing
struct SpringAnimation {
    static let gentle = Animation.spring(response: 0.5, dampingFraction: 0.825)
    static let bouncy = Animation.spring(response: 0.5, dampingFraction: 0.5)
    static let smooth = Animation.spring(response: 0.6, dampingFraction: 0.8)
    static let quick = Animation.spring(response: 0.3, dampingFraction: 0.7)
}

// MARK: - Gesture Modifiers
struct DragToRevealModifier: ViewModifier {
    @State private var dragAmount = CGSize.zero
    @State private var isDragging = false
    let threshold: CGFloat = 100
    let onReveal: () -> Void
    
    func body(content: Content) -> some View {
        content
            .offset(x: dragAmount.width)
            .opacity(1 - abs(dragAmount.width) / 200)
            .gesture(
                DragGesture()
                    .onChanged { value in
                        isDragging = true
                        dragAmount = value.translation
                    }
                    .onEnded { value in
                        if abs(value.translation.width) > threshold {
                            withAnimation(.spring()) {
                                dragAmount.width = value.translation.width > 0 ? 500 : -500
                            }
                            onReveal()
                        } else {
                            withAnimation(.spring()) {
                                dragAmount = .zero
                            }
                        }
                        isDragging = false
                    }
            )
            .animation(.spring(), value: dragAmount)
    }
}

extension View {
    func dragToReveal(onReveal: @escaping () -> Void) -> some View {
        modifier(DragToRevealModifier(onReveal: onReveal))
    }
}

// MARK: - Animated Number Display
struct AnimatedNumber: View {
    let value: Double
    let format: String
    @State private var animatedValue: Double = 0
    
    var body: some View {
        Text(String(format: format, animatedValue))
            .onAppear {
                withAnimation(.easeOut(duration: 0.5)) {
                    animatedValue = value
                }
            }
            .onChange(of: value) { newValue in
                withAnimation(.easeOut(duration: 0.5)) {
                    animatedValue = newValue
                }
            }
    }
}

// MARK: - Morphing Shape
struct MorphingSymbol: View {
    let symbols: [String]
    @State private var currentIndex = 0
    @State private var timer: Timer?
    
    var body: some View {
        Image(systemName: symbols[currentIndex])
            .font(.largeTitle)
            .animation(.spring(), value: currentIndex)
            .onAppear {
                timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { _ in
                    currentIndex = (currentIndex + 1) % symbols.count
                }
            }
            .onDisappear {
                timer?.invalidate()
            }
    }
}

// MARK: - Particle Effects
struct ParticleEffect: View {
    @State private var particles: [Particle] = []
    let color: Color
    let particleCount: Int = 20
    
    var body: some View {
        ZStack {
            ForEach(particles) { particle in
                Circle()
                    .fill(color.opacity(particle.opacity))
                    .frame(width: particle.size, height: particle.size)
                    .offset(x: particle.x, y: particle.y)
                    .animation(
                        .linear(duration: particle.lifetime),
                        value: particle.y
                    )
            }
        }
        .onAppear {
            generateParticles()
        }
    }
    
    private func generateParticles() {
        particles = (0..<particleCount).map { _ in
            Particle(
                x: CGFloat.random(in: -100...100),
                y: CGFloat.random(in: -50...50),
                size: CGFloat.random(in: 2...8),
                opacity: Double.random(in: 0.3...0.8),
                lifetime: Double.random(in: 1...3)
            )
        }
        
        // Animate particles upward
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            particles = particles.map { particle in
                var p = particle
                p.y = -200
                p.opacity = 0
                return p
            }
        }
    }
}

struct Particle: Identifiable {
    let id = UUID()
    var x: CGFloat
    var y: CGFloat
    var size: CGFloat
    var opacity: Double
    var lifetime: Double
}