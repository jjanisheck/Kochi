//
//  TemporaryStubs.swift
//  KochiApp
//
//  TEMPORARY FILE - Remove after adding all files to Xcode project
//

import SwiftUI
import Combine
import AVFoundation

// LLMManager stub removed - actual implementation exists in Managers/LLMManager.swift

// EnhancedThemeManager stub removed - actual implementation exists in Managers/EnhancedThemeManager.swift

// Temporary stub for PerformanceMonitor
class PerformanceMonitor: ObservableObject {
    static let shared = PerformanceMonitor()
    
    @Published var cpuUsage: Double = 0
    @Published var memoryUsage: Double = 0
    
    func startMonitoring() {
        // Stub
    }
}

// Temporary stub for AppStoreHelper
class AppStoreHelper: ObservableObject {
    static let shared = AppStoreHelper()
    
    func requestReviewIfAppropriate() {
        // Stub
    }
}

// Temporary stub views removed - actual implementations now in Xcode project:
// - CoachingView.swift
// - MultimodalView.swift

// Extension to temporarily fix View modifier
extension View {
    func slideAndFade(isShowing: Bool, delay: Double = 0) -> some View {
        self.opacity(isShowing ? 1 : 0)
    }
}

// TranscriptionSettingsView removed - actual implementation exists in Views/TranscriptionSettingsView.swift

// GoalEvaluation stub removed - check if actual implementation exists or needs to be created

// TranscriptionManager stub removed - actual implementation exists in Managers/TranscriptionManager.swift

