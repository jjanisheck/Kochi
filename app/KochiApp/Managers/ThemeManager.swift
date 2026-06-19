import SwiftUI
import Combine

class ThemeManager: ObservableObject {
    @Published var currentTheme: LegacyTheme = .ocean {
        didSet {
            saveTheme()
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let themeKey = "selectedTheme"
    
    init() {
        // Defer loading to avoid "Publishing changes from within view updates" warning
        Task { @MainActor [weak self] in
            self?.loadTheme()
        }
    }
    
    // MARK: - Theme Properties
    var backgroundColor: Color {
        currentTheme.backgroundColor
    }
    
    var secondaryBackgroundColor: Color {
        currentTheme.secondaryBackgroundColor
    }
    
    var textColor: Color {
        currentTheme.textColor
    }
    
    var accentColor: Color {
        currentTheme.accentColor
    }
    
    var colorScheme: ColorScheme? {
        currentTheme.colorScheme
    }
    
    // MARK: - Theme Management
    func loadTheme() {
        if let themeRawValue = userDefaults.string(forKey: themeKey),
           let theme = LegacyTheme(rawValue: themeRawValue) {
            currentTheme = theme
        }
    }
    
    func saveTheme() {
        userDefaults.set(currentTheme.rawValue, forKey: themeKey)
    }
    
    func setTheme(_ theme: LegacyTheme) {
        withAnimation(.easeInOut(duration: 0.3)) {
            currentTheme = theme
        }
    }
}

// MARK: - Theme Definition
enum LegacyTheme: String, CaseIterable {
    case ocean = "Ocean"
    case forest = "Forest"
    case sunset = "Sunset"
    case midnight = "Midnight"
    case lavender = "Lavender"
    case classic = "Classic"
    
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
        }
    }
    
    var textColor: Color {
        switch self {
        case .ocean, .forest, .sunset, .midnight:
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
        }
    }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .ocean, .forest, .sunset, .midnight:
            return .dark
        case .lavender, .classic:
            return .light
        }
    }
    
    var previewGradient: LinearGradient {
        LinearGradient(
            colors: [backgroundColor, secondaryBackgroundColor, accentColor],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}