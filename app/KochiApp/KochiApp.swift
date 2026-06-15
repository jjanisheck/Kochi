import SwiftUI

@main
struct KochiApp: App {
    /// Identifier shared by the macOS `WindowGroup` and the whistle's
    /// `openWindow(id:)` call, so reopening targets the same scene.
    static let mainWindowID = "kochi-main"

    init() {
        // Register the bundled KŌCHI fonts (Zilla Slab / JetBrains Mono /
        // Hanken Grotesk) so Font.custom resolves them.
        KFont.register()

        // Headless verification: `KochiApp --selftest` runs the on-device
        // transcription self-test and exits (never builds the UI).
        if CommandLine.arguments.contains("--selftest-merge") {
            TranscriptionSelfTest.runMerge()
        }
        if CommandLine.arguments.contains("--selftest") {
            TranscriptionSelfTest.run()
        }
        if CommandLine.arguments.contains("--selftest-llm") {
            if #available(macOS 27, *) { TranscriptionSelfTest.runLLM() }
            else { print("⚠️ --selftest-llm requires macOS 27"); exit(0) }
        }
        if CommandLine.arguments.contains("--selftest-refine") {
            TranscriptionSelfTest.runRefine()
        }
    }

    // A regular windowed app (Dock icon + normal window level). The menu-bar
    // icon is kept as a quick way to summon the window.
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var audioManager = AudioManager()
    @StateObject private var goalManager = GoalManager()
    @StateObject private var themeManager = ThemeManager()
    @StateObject private var llmManager = LLMManager()
    @StateObject private var enhancedThemeManager = EnhancedThemeManager()
    @StateObject private var performanceMonitor = PerformanceMonitor.shared
    @StateObject private var appStoreHelper = AppStoreHelper.shared

    var body: some Scene {
        WindowGroup(id: KochiApp.mainWindowID) {
            ContentView()
                .environmentObject(audioManager)
                .environmentObject(goalManager)
                .environmentObject(themeManager)
                .environmentObject(llmManager)
                .onAppear { setupApp() }
                // Fixed device-card width. The card fills to the very top;
                // the header rows inset their content past the traffic lights so
                // the READY bar snugs right up under the system dot bar.
                .frame(width: 436)
                // Hand SwiftUI's `openWindow` action to the AppKit delegate so the
                // menu-bar icon can spawn a fresh window once the last one is closed.
                .background(WindowOpenerBridge())
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }

    private func setupApp() {
        // Defer state changes to avoid "Publishing changes from within view updates" warning
        DispatchQueue.main.async {
            audioManager.requestMicrophonePermission()
            goalManager.loadGoals()
            themeManager.loadTheme()
            appStoreHelper.requestReviewIfAppropriate()
            performanceMonitor.startMonitoring()
        }
    }
}

import AppKit

/// Keeps the menu-bar icon. The app is a regular windowed app (Dock icon,
/// normal window level), so the icon just brings the app and its window to
/// the front.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    /// SwiftUI's `openWindow` action, captured by `WindowOpenerBridge` once the
    /// scene is alive. Lets the whistle build a brand-new window after the user
    /// has closed the last one.
    static var openMainWindow: (() -> Void)?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Guarantee a Dock icon + a normal foreground window, regardless of how
        // the bundle was launched. Without this the process can come up in
        // accessory mode (no Dock tile, window won't take focus).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        setupStatusItem()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            // Heroicons "clipboard-document-check" (MIT), shipped as a
            // vector imageset with template rendering so it tints to match
            // the menu bar automatically.
            let icon = NSImage(named: "ClipboardDocumentCheck")
            icon?.isTemplate = true
            icon?.size = NSSize(width: 18, height: 18)
            button.image = icon
            button.action = #selector(summonWindow)
            button.target = self
        }
        statusItem = item
    }

    /// Bring Kōchi forward: reuse the existing window if one is open (e.g. an
    /// in-progress recording session), otherwise spin up a fresh window.
    @objc private func summonWindow() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = AppDelegate.contentWindow {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            // Every window was closed while the app kept running in the menu
            // bar — ask SwiftUI to build a new one.
            AppDelegate.openMainWindow?()
        }
    }

    /// Reopen the window when the Dock icon is clicked and none are visible.
    /// We handle creation ourselves and return false so AppKit doesn't also
    /// spawn a duplicate window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { summonWindow() }
        return false
    }

    /// Keep running (and recording) after the last window closes, so the
    /// whistle stays available to bring the app back.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// The app's content window (the device card), if one currently exists.
    /// Excludes the status-bar button window, which can't become main.
    private static var contentWindow: NSWindow? {
        NSApp.windows.first { $0.canBecomeMain }
    }

}

/// Zero-size helper that captures SwiftUI's `openWindow` action and stores it on
/// `AppDelegate`, so the AppKit whistle can open a new window when none remain.
private struct WindowOpenerBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear {
                AppDelegate.openMainWindow = { openWindow(id: KochiApp.mainWindowID) }
            }
    }
}
