//
//  KochiApp_iOS.swift
//  KochiApp — iOS
//
//  The iPhone entry point. Only this file and `KochiApp.swift` differ between
//  the two app targets: the macOS one drives a fixed-width window plus a
//  menu-bar whistle, this one just fills the phone with the MC—1 layout.
//

import SwiftUI

@main
struct KochiPhoneApp: App {
    init() {
        // Register the bundled KŌCHI faces (Zilla Slab / JetBrains Mono /
        // Hanken Grotesk) so `Font.custom` resolves them.
        KFont.register()
    }

    @StateObject private var audioManager = AudioManager()
    @StateObject private var goalManager = GoalManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var llmManager = LLMManager()
    @StateObject private var cloudAnalysisManager = CloudAnalysisManager()
    @StateObject private var themeStore = ThemeStore.shared

    var body: some Scene {
        WindowGroup {
            KochiMC1View()
                .environmentObject(audioManager)
                .environmentObject(goalManager)
                .environmentObject(themeManager)
                .environmentObject(llmManager)
                .environmentObject(cloudAnalysisManager)
                .environmentObject(themeStore)
                .onAppear { setupApp() }
        }
    }

    private func setupApp() {
        // Deferred so the permission prompts and stored-state loads don't
        // publish changes from inside the first view update.
        DispatchQueue.main.async {
            audioManager.requestMicrophonePermission()
            goalManager.loadGoals()
            themeManager.loadTheme()
        }
    }
}
