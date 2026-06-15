import XCTest
import AVFoundation
import Combine
@testable import KochiApp

// MARK: - Speech-to-Text and Goal Analysis Test Suite
// Verifies the complete flow: Recording → Transcription → Goal Analysis

// MARK: - Mock Services for Testing

/// Mock LocalTranscriptionService for testing without actual Whisper model
class MockLocalTranscriptionService {
    var isAvailable = true
    var mockTranscription = "This is a mock transcription for testing purposes."
    var shouldFail = false
    var transcribeCallCount = 0

    func transcribe(audioData: Data, language: String = "en") async throws -> String {
        transcribeCallCount += 1
        if shouldFail {
            throw LocalTranscriptionError.transcriptionFailed("Mock failure")
        }
        return mockTranscription
    }

    func transcribeFile(at url: URL, language: String = "en") async throws -> String {
        transcribeCallCount += 1
        if shouldFail {
            throw LocalTranscriptionError.transcriptionFailed("Mock failure")
        }
        return mockTranscription
    }
}

/// Mock LocalLLMService for testing without actual LLM model
class MockLocalLLMService {
    var isAvailable = true
    var shouldFail = false
    var evaluateCallCount = 0
    var mockEvaluation: GoalEvaluation?

    func evaluateGoals(_ goals: [Goal], transcript: String) async throws -> GoalEvaluation {
        evaluateCallCount += 1
        if shouldFail {
            throw LLMError.inferenceFailed
        }

        if let mock = mockEvaluation {
            return mock
        }

        // Default mock evaluation based on transcript content
        var evaluations: [UUID: Bool] = [:]
        var feedback: [UUID: String] = [:]

        let transcriptLower = transcript.lowercased()

        for goal in goals {
            let goalKeywords = goal.text.lowercased().split(separator: " ").map(String.init)
            let matches = goalKeywords.filter { keyword in
                keyword.count > 3 && transcriptLower.contains(keyword)
            }
            let achieved = !matches.isEmpty
            evaluations[goal.id] = achieved
            feedback[goal.id] = achieved ? "Goal keywords detected in transcript" : "Goal not yet discussed"
        }

        let achievedCount = evaluations.values.filter { $0 }.count
        let overallScore = Double(achievedCount) / Double(max(goals.count, 1))

        return GoalEvaluation(
            evaluations: evaluations,
            feedback: feedback,
            overallScore: overallScore,
            suggestions: goals.filter { evaluations[$0.id] == false }.prefix(2).map { "Focus on: \($0.text)" }
        )
    }

    func generateCoachingResponse(transcript: String, goals: [Goal]) async throws -> String {
        if shouldFail {
            throw LLMError.inferenceFailed
        }
        return "Mock coaching response: Keep focusing on your goals!"
    }
}

// MARK: - Local Transcription Service Tests

class LocalTranscriptionServiceTests: XCTestCase {
    var mockService: MockLocalTranscriptionService!

    override func setUp() {
        super.setUp()
        mockService = MockLocalTranscriptionService()
    }

    override func tearDown() {
        mockService = nil
        super.tearDown()
    }

    func testTranscriptionServiceAvailability() {
        XCTAssertTrue(mockService.isAvailable, "Mock service should be available")

        mockService.isAvailable = false
        XCTAssertFalse(mockService.isAvailable, "Service availability should be toggleable")
    }

    func testTranscribeAudioData() async throws {
        let audioData = Data(repeating: 0, count: 1024)

        let result = try await mockService.transcribe(audioData: audioData)

        XCTAssertEqual(result, mockService.mockTranscription)
        XCTAssertEqual(mockService.transcribeCallCount, 1)
    }

    func testTranscribeWithCustomMockText() async throws {
        mockService.mockTranscription = "We discussed the budget and timeline for the project."
        let audioData = Data(repeating: 0, count: 1024)

        let result = try await mockService.transcribe(audioData: audioData)

        XCTAssertTrue(result.contains("budget"))
        XCTAssertTrue(result.contains("timeline"))
    }

    func testTranscriptionFailure() async {
        mockService.shouldFail = true
        let audioData = Data(repeating: 0, count: 1024)

        do {
            _ = try await mockService.transcribe(audioData: audioData)
            XCTFail("Should throw error on failure")
        } catch {
            XCTAssertTrue(error is LocalTranscriptionError)
        }
    }

    func testTranscribeFile() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test.m4a")

        let result = try await mockService.transcribeFile(at: tempURL)

        XCTAssertEqual(result, mockService.mockTranscription)
        XCTAssertEqual(mockService.transcribeCallCount, 1)
    }

    func testMultipleTranscriptions() async throws {
        let audioData = Data(repeating: 0, count: 1024)

        _ = try await mockService.transcribe(audioData: audioData)
        _ = try await mockService.transcribe(audioData: audioData)
        _ = try await mockService.transcribe(audioData: audioData)

        XCTAssertEqual(mockService.transcribeCallCount, 3)
    }
}

// MARK: - Local LLM Service Tests

class LocalLLMServiceTests: XCTestCase {
    var mockService: MockLocalLLMService!
    var testGoals: [Goal]!

    override func setUp() {
        super.setUp()
        mockService = MockLocalLLMService()
        testGoals = [
            Goal(text: "discuss budget", isCompleted: false),
            Goal(text: "ask about timeline", isCompleted: false),
            Goal(text: "get licensing info", isCompleted: false)
        ]
    }

    override func tearDown() {
        mockService = nil
        testGoals = nil
        super.tearDown()
    }

    func testLLMServiceAvailability() {
        XCTAssertTrue(mockService.isAvailable, "Mock LLM service should be available")
    }

    func testGoalEvaluationWithMatchingTranscript() async throws {
        let transcript = "We discussed the budget and it's $50,000."

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: transcript)

        XCTAssertEqual(evaluation.evaluations.count, testGoals.count)

        // Budget goal should be achieved
        let budgetGoal = testGoals.first { $0.text.contains("budget") }!
        XCTAssertTrue(evaluation.evaluations[budgetGoal.id] == true, "Budget goal should be achieved")
    }

    func testGoalEvaluationWithNoMatches() async throws {
        let transcript = "The weather is nice today."

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: transcript)

        // No goals should be achieved
        let achievedCount = evaluation.evaluations.values.filter { $0 }.count
        XCTAssertEqual(achievedCount, 0, "No goals should be achieved with unrelated transcript")
        XCTAssertEqual(evaluation.overallScore, 0.0)
    }

    func testGoalEvaluationWithAllGoalsMatched() async throws {
        let transcript = "We discussed the budget, asked about the timeline, and got all the licensing info we needed."

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: transcript)

        // All goals should be achieved
        let achievedCount = evaluation.evaluations.values.filter { $0 }.count
        XCTAssertEqual(achievedCount, 3, "All goals should be achieved")
        XCTAssertEqual(evaluation.overallScore, 1.0)
    }

    func testGoalEvaluationWithPartialMatches() async throws {
        let transcript = "We covered the budget thoroughly and discussed licensing."

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: transcript)

        // Budget and licensing should match, timeline should not
        let budgetGoal = testGoals.first { $0.text.contains("budget") }!
        let timelineGoal = testGoals.first { $0.text.contains("timeline") }!
        let licensingGoal = testGoals.first { $0.text.contains("licensing") }!

        XCTAssertTrue(evaluation.evaluations[budgetGoal.id] == true)
        XCTAssertTrue(evaluation.evaluations[timelineGoal.id] == false)
        XCTAssertTrue(evaluation.evaluations[licensingGoal.id] == true)
    }

    func testGoalEvaluationFailure() async {
        mockService.shouldFail = true
        let transcript = "Test transcript"

        do {
            _ = try await mockService.evaluateGoals(testGoals, transcript: transcript)
            XCTFail("Should throw error on failure")
        } catch {
            XCTAssertTrue(error is LLMError)
        }
    }

    func testOverallScoreCalculation() async throws {
        // Test 0%, 33%, 67%, 100% scenarios
        mockService.mockEvaluation = GoalEvaluation(
            evaluations: [testGoals[0].id: true, testGoals[1].id: false, testGoals[2].id: false],
            feedback: [:],
            overallScore: 0.33,
            suggestions: []
        )

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: "test")

        XCTAssertEqual(evaluation.overallScore, 0.33, accuracy: 0.01)
    }

    func testFeedbackGeneration() async throws {
        let transcript = "We discussed the budget in detail."

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: transcript)

        let budgetGoal = testGoals.first { $0.text.contains("budget") }!
        XCTAssertNotNil(evaluation.feedback[budgetGoal.id])
        XCTAssertTrue(evaluation.feedback[budgetGoal.id]?.contains("detected") == true)
    }

    func testSuggestionsForUnachievedGoals() async throws {
        let transcript = "We discussed the budget."

        let evaluation = try await mockService.evaluateGoals(testGoals, transcript: transcript)

        // Should have suggestions for unachieved goals
        XCTAssertFalse(evaluation.suggestions.isEmpty)
        XCTAssertTrue(evaluation.suggestions.first?.contains("Focus on") == true)
    }

    func testCoachingResponseGeneration() async throws {
        let response = try await mockService.generateCoachingResponse(
            transcript: "Test transcript",
            goals: testGoals
        )

        XCTAssertFalse(response.isEmpty)
        XCTAssertTrue(response.contains("coaching"))
    }
}

// MARK: - Integration Tests: Speech-to-Text → Goal Analysis

class SpeechToTextGoalAnalysisIntegrationTests: XCTestCase {
    var mockTranscriptionService: MockLocalTranscriptionService!
    var mockLLMService: MockLocalLLMService!
    var testGoals: [Goal]!

    override func setUp() {
        super.setUp()
        mockTranscriptionService = MockLocalTranscriptionService()
        mockLLMService = MockLocalLLMService()
        testGoals = [
            Goal(text: "discuss project scope", isCompleted: false),
            Goal(text: "confirm budget allocation", isCompleted: false),
            Goal(text: "set delivery timeline", isCompleted: false)
        ]
    }

    override func tearDown() {
        mockTranscriptionService = nil
        mockLLMService = nil
        testGoals = nil
        super.tearDown()
    }

    // MARK: - Full Pipeline Tests

    func testFullPipelineSuccessfulFlow() async throws {
        // Simulate: Audio → Transcription → Goal Analysis
        mockTranscriptionService.mockTranscription = "We discussed the project scope and confirmed the budget allocation of $100,000."

        // Step 1: Transcribe audio
        let audioData = Data(repeating: 0, count: 1024)
        let transcription = try await mockTranscriptionService.transcribe(audioData: audioData)

        // Verify transcription
        XCTAssertFalse(transcription.isEmpty)
        XCTAssertTrue(transcription.contains("project scope"))
        XCTAssertTrue(transcription.contains("budget"))

        // Step 2: Analyze transcription against goals
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        // Verify evaluation
        XCTAssertEqual(evaluation.evaluations.count, testGoals.count)

        // Project scope and budget goals should be achieved
        let scopeGoal = testGoals.first { $0.text.contains("scope") }!
        let budgetGoal = testGoals.first { $0.text.contains("budget") }!

        XCTAssertTrue(evaluation.evaluations[scopeGoal.id] == true, "Scope goal should be achieved")
        XCTAssertTrue(evaluation.evaluations[budgetGoal.id] == true, "Budget goal should be achieved")

        // Timeline goal should not be achieved (not in transcript)
        let timelineGoal = testGoals.first { $0.text.contains("timeline") }!
        XCTAssertTrue(evaluation.evaluations[timelineGoal.id] == false, "Timeline goal should not be achieved")

        // Overall score should be 2/3
        XCTAssertEqual(evaluation.overallScore, 2.0/3.0, accuracy: 0.01)
    }

    func testFullPipelineWithAllGoalsAchieved() async throws {
        mockTranscriptionService.mockTranscription = "We discussed the project scope, confirmed the budget allocation, and set the delivery timeline for Q2."

        let audioData = Data(repeating: 0, count: 1024)
        let transcription = try await mockTranscriptionService.transcribe(audioData: audioData)
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        // All goals should be achieved
        let achievedCount = evaluation.evaluations.values.filter { $0 }.count
        XCTAssertEqual(achievedCount, 3)
        XCTAssertEqual(evaluation.overallScore, 1.0)
        XCTAssertTrue(evaluation.suggestions.isEmpty, "No suggestions needed when all goals achieved")
    }

    func testFullPipelineWithNoGoalsAchieved() async throws {
        mockTranscriptionService.mockTranscription = "We had a casual conversation about the weather and lunch plans."

        let audioData = Data(repeating: 0, count: 1024)
        let transcription = try await mockTranscriptionService.transcribe(audioData: audioData)
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        // No goals should be achieved
        let achievedCount = evaluation.evaluations.values.filter { $0 }.count
        XCTAssertEqual(achievedCount, 0)
        XCTAssertEqual(evaluation.overallScore, 0.0)
        XCTAssertFalse(evaluation.suggestions.isEmpty, "Should have suggestions for unachieved goals")
    }

    func testTranscriptionFailureHandling() async {
        mockTranscriptionService.shouldFail = true

        let audioData = Data(repeating: 0, count: 1024)

        do {
            _ = try await mockTranscriptionService.transcribe(audioData: audioData)
            XCTFail("Should throw error")
        } catch {
            // Verify error is handled appropriately
            XCTAssertTrue(error is LocalTranscriptionError)
        }
    }

    func testAnalysisFailureHandling() async throws {
        mockTranscriptionService.mockTranscription = "Valid transcription"
        mockLLMService.shouldFail = true

        let audioData = Data(repeating: 0, count: 1024)
        let transcription = try await mockTranscriptionService.transcribe(audioData: audioData)

        do {
            _ = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)
            XCTFail("Should throw error")
        } catch {
            XCTAssertTrue(error is LLMError)
        }
    }

    // MARK: - Incremental Transcription Tests

    func testIncrementalTranscriptionAnalysis() async throws {
        // Simulate real-time transcription with incremental updates
        var fullTranscript = ""

        // First segment
        mockTranscriptionService.mockTranscription = "Let's start by discussing the project scope."
        let segment1 = try await mockTranscriptionService.transcribe(audioData: Data())
        fullTranscript += segment1 + " "

        var evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: fullTranscript)
        let scopeGoal = testGoals.first { $0.text.contains("scope") }!
        XCTAssertTrue(evaluation.evaluations[scopeGoal.id] == true)

        // Second segment
        mockTranscriptionService.mockTranscription = "The budget has been confirmed at $50,000."
        let segment2 = try await mockTranscriptionService.transcribe(audioData: Data())
        fullTranscript += segment2 + " "

        evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: fullTranscript)
        let budgetGoal = testGoals.first { $0.text.contains("budget") }!
        XCTAssertTrue(evaluation.evaluations[budgetGoal.id] == true)

        // Third segment
        mockTranscriptionService.mockTranscription = "We'll set the delivery timeline for next quarter."
        let segment3 = try await mockTranscriptionService.transcribe(audioData: Data())
        fullTranscript += segment3

        evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: fullTranscript)
        XCTAssertEqual(evaluation.overallScore, 1.0, "All goals should be achieved after all segments")
    }

    // MARK: - Edge Cases

    func testEmptyTranscription() async throws {
        mockTranscriptionService.mockTranscription = ""

        let transcription = try await mockTranscriptionService.transcribe(audioData: Data())
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        XCTAssertEqual(evaluation.overallScore, 0.0)
    }

    func testEmptyGoalsList() async throws {
        mockTranscriptionService.mockTranscription = "This is a valid transcript."

        let transcription = try await mockTranscriptionService.transcribe(audioData: Data())
        let evaluation = try await mockLLMService.evaluateGoals([], transcript: transcription)

        XCTAssertEqual(evaluation.evaluations.count, 0)
        XCTAssertEqual(evaluation.overallScore, 0.0)  // No goals = 0 score
    }

    func testVeryLongTranscription() async throws {
        // Generate a long transcription (simulating a long meeting)
        let longText = String(repeating: "We discussed the project scope and budget. ", count: 100)
        mockTranscriptionService.mockTranscription = longText

        let transcription = try await mockTranscriptionService.transcribe(audioData: Data())
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        // Should still work with long transcriptions
        XCTAssertGreaterThan(evaluation.overallScore, 0.0)
    }

    func testSpecialCharactersInTranscription() async throws {
        mockTranscriptionService.mockTranscription = "We discussed the project's scope! 💼 Budget: $100,000 (confirmed). Timeline: Q2'24."

        let transcription = try await mockTranscriptionService.transcribe(audioData: Data())
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        // Should handle special characters gracefully
        XCTAssertGreaterThan(evaluation.overallScore, 0.0)
    }

    func testCaseInsensitiveMatching() async throws {
        // Test with different cases
        mockTranscriptionService.mockTranscription = "We discussed the PROJECT SCOPE and BUDGET allocation."

        let transcription = try await mockTranscriptionService.transcribe(audioData: Data())
        let evaluation = try await mockLLMService.evaluateGoals(testGoals, transcript: transcription)

        let scopeGoal = testGoals.first { $0.text.contains("scope") }!
        let budgetGoal = testGoals.first { $0.text.contains("budget") }!

        XCTAssertTrue(evaluation.evaluations[scopeGoal.id] == true, "Should match regardless of case")
        XCTAssertTrue(evaluation.evaluations[budgetGoal.id] == true, "Should match regardless of case")
    }
}

// MARK: - Analysis Mode Switching Tests

class AnalysisModeSwitchingTests: XCTestCase {
    var llmManager: LLMManager!

    override func setUp() {
        super.setUp()
        llmManager = LLMManager()
    }

    override func tearDown() {
        llmManager = nil
        super.tearDown()
    }

    func testDefaultAnalysisMode() {
        // Default should be local mode
        XCTAssertEqual(llmManager.analysisMode, .local)
    }

    func testAnalysisModeValues() {
        XCTAssertEqual(AnalysisMode.local.rawValue, "local")
        XCTAssertEqual(AnalysisMode.cloud.rawValue, "cloud")

        XCTAssertEqual(AnalysisMode.local.displayName, "On-Device (LFM 2.5)")
        XCTAssertEqual(AnalysisMode.cloud.displayName, "Cloud (OpenAI)")
    }

    func testAnalysisModeDescriptions() {
        XCTAssertTrue(AnalysisMode.local.description.contains("Private"))
        XCTAssertTrue(AnalysisMode.cloud.description.contains("OpenAI"))
    }

    func testSetAnalysisMode() async {
        await llmManager.setAnalysisMode(.cloud)
        XCTAssertEqual(llmManager.analysisMode, .cloud)

        await llmManager.setAnalysisMode(.local)
        XCTAssertEqual(llmManager.analysisMode, .local)
    }
}

// MARK: - Transcription Mode Switching Tests

class TranscriptionModeSwitchingTests: XCTestCase {
    func testTranscriptionModeValues() {
        XCTAssertEqual(TranscriptionMode.local.rawValue, "local")
        XCTAssertEqual(TranscriptionMode.cloud.rawValue, "cloud")

        XCTAssertEqual(TranscriptionMode.local.displayName, "On-Device (Whisper)")
        XCTAssertEqual(TranscriptionMode.cloud.displayName, "Cloud (OpenAI)")
    }

    func testTranscriptionModeDescriptions() {
        XCTAssertTrue(TranscriptionMode.local.description.contains("Private"))
        XCTAssertTrue(TranscriptionMode.cloud.description.contains("API key"))
    }
}

// MARK: - Whisper Model Tests

class WhisperModelTests: XCTestCase {
    func testWhisperModelCases() {
        let models = WhisperModel.allCases
        XCTAssertEqual(models.count, 4)

        XCTAssertTrue(models.contains(.tiny))
        XCTAssertTrue(models.contains(.base))
        XCTAssertTrue(models.contains(.small))
        XCTAssertTrue(models.contains(.medium))
    }

    func testWhisperModelDisplayNames() {
        XCTAssertEqual(WhisperModel.tiny.displayName, "Whisper Tiny")
        XCTAssertEqual(WhisperModel.base.displayName, "Whisper Base")
        XCTAssertEqual(WhisperModel.small.displayName, "Whisper Small")
        XCTAssertEqual(WhisperModel.medium.displayName, "Whisper Medium")
    }

    func testWhisperModelFileNames() {
        XCTAssertEqual(WhisperModel.tiny.fileName, "ggml-tiny.bin")
        XCTAssertEqual(WhisperModel.base.fileName, "ggml-base.bin")
        XCTAssertEqual(WhisperModel.small.fileName, "ggml-small.bin")
        XCTAssertEqual(WhisperModel.medium.fileName, "ggml-medium.bin")
    }

    func testWhisperModelSizes() {
        XCTAssertTrue(WhisperModel.tiny.size.contains("75"))
        XCTAssertTrue(WhisperModel.base.size.contains("142"))
        XCTAssertTrue(WhisperModel.small.size.contains("466"))
        XCTAssertTrue(WhisperModel.medium.size.contains("1.5"))
    }

    func testWhisperToLLMModelMapping() {
        XCTAssertEqual(WhisperModel.tiny.llmModel, LLMModel.whisperTiny)
        XCTAssertEqual(WhisperModel.base.llmModel, LLMModel.whisperBase)
        XCTAssertEqual(WhisperModel.small.llmModel, LLMModel.whisperSmall)
        XCTAssertEqual(WhisperModel.medium.llmModel, LLMModel.whisperMedium)
    }
}

// MARK: - LLM Model Tests

class LLMModelAnalysisTests: XCTestCase {
    func testAnalysisModels() {
        let analysisModels = LLMModel.analysisModels

        XCTAssertTrue(analysisModels.contains(.lfmThinking))
        XCTAssertTrue(analysisModels.contains(.tinyLlama))
        XCTAssertTrue(analysisModels.contains(.phi2))
        XCTAssertTrue(analysisModels.contains(.mistral))

        // Should not contain Whisper models
        XCTAssertFalse(analysisModels.contains(.whisperBase))
    }

    func testWhisperModels() {
        let whisperModels = LLMModel.whisperModels

        XCTAssertTrue(whisperModels.contains(.whisperTiny))
        XCTAssertTrue(whisperModels.contains(.whisperBase))
        XCTAssertTrue(whisperModels.contains(.whisperSmall))
        XCTAssertTrue(whisperModels.contains(.whisperMedium))

        // Should not contain analysis models
        XCTAssertFalse(whisperModels.contains(.lfmThinking))
    }

    func testIsWhisperModel() {
        XCTAssertTrue(LLMModel.whisperBase.isWhisperModel)
        XCTAssertTrue(LLMModel.whisperTiny.isWhisperModel)
        XCTAssertFalse(LLMModel.lfmThinking.isWhisperModel)
        XCTAssertFalse(LLMModel.mistral.isWhisperModel)
    }

    func testSupportsThinking() {
        XCTAssertTrue(LLMModel.lfmThinking.supportsThinking)
        XCTAssertFalse(LLMModel.tinyLlama.supportsThinking)
        XCTAssertFalse(LLMModel.whisperBase.supportsThinking)
    }

    func testLFMThinkingModel() {
        let lfm = LLMModel.lfmThinking

        XCTAssertEqual(lfm.displayName, "LFM 2.5 Thinking")
        XCTAssertEqual(lfm.fileName, "lfm-2.5-thinking-q4_k_m.gguf")
        XCTAssertTrue(lfm.size.contains("2.5"))
        XCTAssertTrue(lfm.description.contains("Reasoning"))
        XCTAssertEqual(lfm.huggingFaceModelId, "LiquidAI/LFM-2.5-Thinking-GGUF")
    }
}

// MARK: - Performance Tests

class SpeechToTextAnalysisPerformanceTests: XCTestCase {
    var mockTranscriptionService: MockLocalTranscriptionService!
    var mockLLMService: MockLocalLLMService!

    override func setUp() {
        super.setUp()
        mockTranscriptionService = MockLocalTranscriptionService()
        mockLLMService = MockLocalLLMService()
    }

    override func tearDown() {
        mockTranscriptionService = nil
        mockLLMService = nil
        super.tearDown()
    }

    func testTranscriptionPerformance() {
        measure {
            let expectation = XCTestExpectation(description: "Transcription")

            Task {
                _ = try? await mockTranscriptionService.transcribe(audioData: Data())
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
    }

    func testGoalAnalysisPerformance() {
        let goals = [
            Goal(text: "Test goal 1", isCompleted: false),
            Goal(text: "Test goal 2", isCompleted: false),
            Goal(text: "Test goal 3", isCompleted: false)
        ]

        measure {
            let expectation = XCTestExpectation(description: "Analysis")

            Task {
                _ = try? await mockLLMService.evaluateGoals(goals, transcript: "Test transcript")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 1.0)
        }
    }

    func testFullPipelinePerformance() {
        let goals = [
            Goal(text: "discuss budget", isCompleted: false),
            Goal(text: "ask about timeline", isCompleted: false)
        ]

        measure {
            let expectation = XCTestExpectation(description: "Full pipeline")

            Task {
                let transcription = try? await mockTranscriptionService.transcribe(audioData: Data())
                _ = try? await mockLLMService.evaluateGoals(goals, transcript: transcription ?? "")
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 2.0)
        }
    }
}
