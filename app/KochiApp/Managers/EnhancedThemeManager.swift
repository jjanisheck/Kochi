import SwiftUI
import Combine

/// Cross-platform haptic feedback style. Maps to `UIImpactFeedbackGenerator`
/// on iOS; a no-op on macOS (which has no equivalent for this interaction).
enum HapticStyle {
    case light, medium, heavy, soft, rigid
}

// MARK: - Enhanced Theme Manager
class EnhancedThemeManager: ObservableObject {
    @Published var currentTheme: EnhancedTheme = .ocean
    @Published var animationsEnabled = true
    @Published var hapticFeedbackEnabled = true
    @Published var customAccentColor: Color?
    @Published var fontSize: FontSize = .medium
    @Published var highContrast = false
    
    private let userDefaults = UserDefaults.standard
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Animation Properties
    @Published var pulseAnimation = false
    @Published var waveAnimation = false
    @Published var particleAnimation = false
    
    init() {
        loadSettings()
        setupAnimations()
    }
    
    // MARK: - Theme Properties
    var backgroundColor: Color {
        if highContrast {
            return currentTheme.highContrastBackground
        }
        return currentTheme.backgroundColor
    }
    
    var gradientBackground: LinearGradient {
        currentTheme.gradientBackground
    }
    
    var secondaryBackgroundColor: Color {
        currentTheme.secondaryBackgroundColor
    }
    
    var textColor: Color {
        if highContrast {
            return currentTheme.highContrastText
        }
        return currentTheme.textColor
    }
    
    var accentColor: Color {
        customAccentColor ?? currentTheme.accentColor
    }
    
    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }
    
    // MARK: - Font Sizing
    func scaledFont(_ style: Font.TextStyle) -> Font {
        switch fontSize {
        case .small:
            return Font.system(style).weight(.regular)
        case .medium:
            return Font.system(style)
        case .large:
            return Font.system(style).weight(.medium)
        case .extraLarge:
            return Font.system(style).weight(.semibold)
        }
    }
    
    // MARK: - Animations
    private func setupAnimations() {
        if animationsEnabled {
            Timer.publish(every: 3, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    withAnimation(.easeInOut(duration: 1)) {
                        self?.pulseAnimation.toggle()
                    }
                }
                .store(in: &cancellables)
            
            Timer.publish(every: 5, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in
                    withAnimation(.easeInOut(duration: 2)) {
                        self?.waveAnimation.toggle()
                    }
                }
                .store(in: &cancellables)
        }
    }
    
    // MARK: - Haptic Feedback
    func triggerHaptic(_ style: HapticStyle = .light) {
        guard hapticFeedbackEnabled else { return }
        // macOS: no tactile haptics for this interaction — no-op.
    }
    
    // MARK: - Settings Management
    func loadSettings() {
        if let themeRaw = userDefaults.string(forKey: "enhancedTheme"),
           let theme = EnhancedTheme(rawValue: themeRaw) {
            currentTheme = theme
        }
        
        animationsEnabled = userDefaults.bool(forKey: "animationsEnabled")
        hapticFeedbackEnabled = userDefaults.bool(forKey: "hapticFeedbackEnabled")
        highContrast = userDefaults.bool(forKey: "highContrast")
        
        if let fontSizeRaw = userDefaults.string(forKey: "fontSize"),
           let fontSize = FontSize(rawValue: fontSizeRaw) {
            self.fontSize = fontSize
        }
    }
    
    func saveSettings() {
        userDefaults.set(currentTheme.rawValue, forKey: "enhancedTheme")
        userDefaults.set(animationsEnabled, forKey: "animationsEnabled")
        userDefaults.set(hapticFeedbackEnabled, forKey: "hapticFeedbackEnabled")
        userDefaults.set(fontSize.rawValue, forKey: "fontSize")
        userDefaults.set(highContrast, forKey: "highContrast")
    }
    
    // MARK: - Theme Switching
    func setTheme(_ theme: EnhancedTheme, animated: Bool = true) {
        if animated {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                currentTheme = theme
            }
        } else {
            currentTheme = theme
        }
        saveSettings()
        triggerHaptic(.medium)
    }
}

// MARK: - Enhanced Theme Definition
enum EnhancedTheme: String, CaseIterable {
    case ocean = "Ocean"
    case forest = "Forest"
    case sunset = "Sunset"
    case midnight = "Midnight"
    case lavender = "Lavender"
    case classic = "Classic"
    case neon = "Neon"
    case earth = "Earth"
    
    var backgroundColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.05, green: 0.1, blue: 0.2)
        case .forest:
            return Color(red: 0.05, green: 0.15, blue: 0.05)
        case .sunset:
            return Color(red: 0.25, green: 0.1, blue: 0.05)
        case .midnight:
            return Color(red: 0.05, green: 0.05, blue: 0.15)
        case .lavender:
            return Color(red: 0.9, green: 0.9, blue: 0.95)
        case .classic:
            return Color(red: 0.95, green: 0.95, blue: 0.95)
        case .neon:
            return Color(red: 0.05, green: 0.05, blue: 0.1)
        case .earth:
            return Color(red: 0.15, green: 0.12, blue: 0.1)
        }
    }
    
    var gradientBackground: LinearGradient {
        switch self {
        case .ocean:
            return LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.1, blue: 0.2),
                    Color(red: 0.1, green: 0.2, blue: 0.3),
                    Color(red: 0.15, green: 0.3, blue: 0.4)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .sunset:
            return LinearGradient(
                colors: [
                    Color(red: 0.9, green: 0.4, blue: 0.2),
                    Color(red: 0.95, green: 0.6, blue: 0.3),
                    Color(red: 1.0, green: 0.8, blue: 0.4)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        case .neon:
            return LinearGradient(
                colors: [
                    Color(red: 0.1, green: 0.0, blue: 0.3),
                    Color(red: 0.3, green: 0.0, blue: 0.5),
                    Color(red: 0.5, green: 0.0, blue: 0.7)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        default:
            return LinearGradient(
                colors: [backgroundColor, secondaryBackgroundColor],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
    
    var secondaryBackgroundColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.1, green: 0.15, blue: 0.25)
        case .forest:
            return Color(red: 0.1, green: 0.2, blue: 0.1)
        case .sunset:
            return Color(red: 0.3, green: 0.15, blue: 0.1)
        case .midnight:
            return Color(red: 0.1, green: 0.1, blue: 0.2)
        case .lavender:
            return Color(red: 0.85, green: 0.85, blue: 0.9)
        case .classic:
            return Color(red: 0.9, green: 0.9, blue: 0.9)
        case .neon:
            return Color(red: 0.1, green: 0.1, blue: 0.2)
        case .earth:
            return Color(red: 0.2, green: 0.17, blue: 0.15)
        }
    }
    
    var textColor: Color {
        switch self {
        case .ocean, .forest, .sunset, .midnight, .neon, .earth:
            return .white
        case .lavender, .classic:
            return .black
        }
    }
    
    var accentColor: Color {
        switch self {
        case .ocean:
            return Color(red: 0.2, green: 0.6, blue: 0.9)
        case .forest:
            return Color(red: 0.3, green: 0.7, blue: 0.3)
        case .sunset:
            return Color(red: 0.9, green: 0.5, blue: 0.2)
        case .midnight:
            return Color(red: 0.4, green: 0.4, blue: 0.8)
        case .lavender:
            return Color(red: 0.6, green: 0.4, blue: 0.8)
        case .classic:
            return Color(red: 0.2, green: 0.4, blue: 0.8)
        case .neon:
            return Color(red: 0.0, green: 1.0, blue: 0.8)
        case .earth:
            return Color(red: 0.6, green: 0.4, blue: 0.2)
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .ocean, .forest, .sunset, .midnight, .neon, .earth:
            return .dark
        case .lavender, .classic:
            return .light
        }
    }
    
    var highContrastBackground: Color {
        switch colorScheme {
        case .dark:
            return .black
        case .light:
            return .white
        default:
            return backgroundColor
        }
    }
    
    var highContrastText: Color {
        switch colorScheme {
        case .dark:
            return .white
        case .light:
            return .black
        default:
            return textColor
        }
    }
    
    // MARK: - Animation Colors
    var animationColors: [Color] {
        switch self {
        case .ocean:
            return [.blue, .cyan, .teal]
        case .forest:
            return [.green, Color(red: 0.4, green: 0.6, blue: 0.2), .mint]
        case .sunset:
            return [.orange, .red, .yellow]
        case .midnight:
            return [.purple, .indigo, Color(red: 0.2, green: 0.2, blue: 0.4)]
        case .lavender:
            return [.purple.opacity(0.3), .pink.opacity(0.3), .blue.opacity(0.3)]
        case .classic:
            return [.gray.opacity(0.3), .blue.opacity(0.3), .green.opacity(0.3)]
        case .neon:
            return [.pink, .cyan, .green]
        case .earth:
            return [.brown, .orange.opacity(0.7), Color(red: 0.7, green: 0.5, blue: 0.3)]
        }
    }
}

// MARK: - Font Size
enum FontSize: String, CaseIterable {
    case small = "Small"
    case medium = "Medium"
    case large = "Large"
    case extraLarge = "Extra Large"
    
    var scaleFactor: CGFloat {
        switch self {
        case .small: return 0.85
        case .medium: return 1.0
        case .large: return 1.15
        case .extraLarge: return 1.3
        }
    }
}

// MARK: - Theme Preview
struct ThemePreview: View {
    let theme: EnhancedTheme
    
    var body: some View {
        ZStack {
            theme.gradientBackground
            
            VStack(spacing: 10) {
                Circle()
                    .fill(theme.accentColor)
                    .frame(width: 40, height: 40)
                
                Text(theme.rawValue)
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(theme.textColor)
            }
        }
        .frame(width: 80, height: 80)
        .cornerRadius(12)
    }
}