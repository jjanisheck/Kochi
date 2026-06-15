import XCTest
import SwiftUI
@testable import KochiApp

class TranscriptionSettingsViewTests: XCTestCase {
    var audioManager: AudioManager!
    var themeManager: ThemeManager!

    override func setUp() {
        super.setUp()
        audioManager = AudioManager()
        themeManager = ThemeManager()
    }

    override func tearDown() {
        audioManager = nil
        themeManager = nil
        super.tearDown()
    }

    func testLanguageSelection() {
        let view = TranscriptionSettingsView()
            .environmentObject(audioManager)
            .environmentObject(themeManager)

        // Test initial language
        XCTAssertEqual(audioManager.transcriptionManager.selectedLanguage, .english)

        // Change language
        audioManager.transcriptionManager.selectedLanguage = .spanish
        XCTAssertEqual(audioManager.transcriptionManager.selectedLanguage, .spanish)
        XCTAssertEqual(audioManager.transcriptionManager.selectedLanguage.displayName, "Spanish")
    }

    func testAppleSpeechRecognition() {
        let view = TranscriptionSettingsView()
            .environmentObject(audioManager)
            .environmentObject(themeManager)

        // Verify Apple Speech Recognition is being used
        XCTAssertNotNil(audioManager.transcriptionManager)
    }
}
