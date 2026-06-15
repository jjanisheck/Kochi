import XCTest
import AVFoundation
import Combine
@testable import KochiApp

class TranscriptionManagerTests: XCTestCase {
    var transcriptionManager: TranscriptionManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        transcriptionManager = TranscriptionManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        transcriptionManager = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertEqual(transcriptionManager.transcriptionText, "")
        XCTAssertFalse(transcriptionManager.isTranscribing)
        XCTAssertEqual(transcriptionManager.selectedLanguage, .english)
    }

    func testLanguageSelection() {
        transcriptionManager.selectedLanguage = .spanish
        XCTAssertEqual(transcriptionManager.selectedLanguage, .spanish)
        XCTAssertEqual(transcriptionManager.selectedLanguage.displayName, "Spanish")
    }

    func testTranscriptionTextBinding() {
        let expectation = XCTestExpectation(description: "Transcription text update")

        transcriptionManager.$transcriptionText
            .dropFirst()
            .sink { text in
                if text == "Test transcription" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        // Simulate transcription update
        transcriptionManager.transcriptionText = "Test transcription"

        wait(for: [expectation], timeout: 1.0)
    }

    func testTranscriptionLanguages() {
        let languages = TranscriptionLanguage.allCases
        XCTAssertEqual(languages.count, 10)

        XCTAssertEqual(TranscriptionLanguage.english.rawValue, "en-US")
        XCTAssertEqual(TranscriptionLanguage.spanish.rawValue, "es-ES")
        XCTAssertEqual(TranscriptionLanguage.chinese.rawValue, "zh-CN")

        for language in languages {
            XCTAssertFalse(language.displayName.isEmpty)
        }
    }

    func testTranscriptionError() {
        let error = TranscriptionError.recognizerNotAvailable
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not available"))

        let error2 = TranscriptionError.transcriptionFailed
        XCTAssertTrue(error2.errorDescription!.contains("failed"))
    }
}

class AudioManagerTests: XCTestCase {
    var audioManager: AudioManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        audioManager = AudioManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        audioManager = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertFalse(audioManager.isRecording)
        XCTAssertEqual(audioManager.audioLevel, 0.0)
        XCTAssertEqual(audioManager.recordingTime, 0)
        XCTAssertEqual(audioManager.transcriptionText, "")
    }

    func testTranscriptionManagerIntegration() {
        XCTAssertNotNil(audioManager.transcriptionManager)

        // Test transcription text binding
        let expectation = XCTestExpectation(description: "Transcription binding")

        audioManager.$transcriptionText
            .dropFirst()
            .sink { text in
                if text == "Test from manager" {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        audioManager.transcriptionManager.transcriptionText = "Test from manager"

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(audioManager.transcriptionText, "Test from manager")
    }
}

class CoreDataModelsTests: XCTestCase {
    func testGoalCreation() {
        let goal = Goal(text: "Test Goal", isCompleted: false)
        XCTAssertNotNil(goal.id)
        XCTAssertEqual(goal.text, "Test Goal")
        XCTAssertFalse(goal.isCompleted)
    }

    func testRecordingMetadata() {
        let url = URL(fileURLWithPath: "/test/path/recording.wav")
        let metadata = RecordingMetadata(
            url: url,
            date: Date(),
            duration: 120.0,
            transcription: "Test transcription"
        )

        XCTAssertNotNil(metadata.id)
        XCTAssertEqual(metadata.url, url)
        XCTAssertEqual(metadata.duration, 120.0)
        XCTAssertEqual(metadata.transcription, "Test transcription")
    }
}
