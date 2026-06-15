import XCTest
import Combine
@testable import KochiApp

class LLMManagerTests: XCTestCase {
    var llmManager: LLMManager!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        llmManager = LLMManager()
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables = nil
        llmManager = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertFalse(llmManager.isProcessing)
        XCTAssertEqual(llmManager.coachingResponse, "")
        XCTAssertEqual(llmManager.streamingText, "")
        XCTAssertEqual(llmManager.runningSummary, "")
    }

    func testAvailabilityDependsOnAPIKey() {
        // Availability depends on whether OpenAI API key is configured
        let isConfigured = OpenAIConfig.shared.isConfigured
        XCTAssertEqual(llmManager.isAvailable, isConfigured)
    }

    func testSessionReset() {
        llmManager.runningSummary = "Test summary"
        llmManager.resetSession()

        XCTAssertEqual(llmManager.runningSummary, "")
        XCTAssertEqual(llmManager.sessionTokenCount, 0)
    }

    func testSessionResetPreserveSummary() {
        llmManager.runningSummary = "Test summary"
        llmManager.resetSession(preserveSummary: true)

        XCTAssertEqual(llmManager.runningSummary, "Test summary")
    }

    func testTokenCalculation() {
        let goals = [
            Goal(text: "Test goal one", isCompleted: false),
            Goal(text: "Test goal two", isCompleted: false)
        ]
        let chunk = "This is a test chunk of text for token calculation."

        let available = llmManager.calculateAvailableTokens(goals: goals, chunk: chunk)

        XCTAssertGreaterThan(available, 0)
        XCTAssertLessThan(available, 100000)  // Should be less than max
    }

    func testGoalEvaluationWithoutAPIKey() async throws {
        // If no API key, should return suggestions about configuring it
        guard !OpenAIConfig.shared.isConfigured else {
            // Skip test if API key is configured (would make real API call)
            return
        }

        let goals = [Goal(text: "Test goal", isCompleted: false)]
        let evaluation = try await llmManager.evaluateGoals(goals, with: "Test transcript")

        XCTAssertFalse(evaluation.suggestions.isEmpty)
    }

    func testFallbackCoachingMessage() async throws {
        // Test fallback behavior when API is unavailable
        guard !OpenAIConfig.shared.isConfigured else {
            return
        }

        let goals = [
            Goal(text: "Goal 1", isCompleted: true),
            Goal(text: "Goal 2", isCompleted: true)
        ]

        try await llmManager.generateCoachingResponse(for: "Test", goals: goals)

        // Should get a fallback message about API key
        XCTAssertFalse(llmManager.coachingResponse.isEmpty)
    }
}

class PromptTemplatesTests: XCTestCase {
    var templates: PromptTemplates!

    override func setUp() {
        super.setUp()
        templates = PromptTemplates()
    }

    func testCustomPromptTemplate() {
        let template = "Hello {{name}}, your score is {{score}}."
        let variables = ["name": "Alice", "score": "95"]

        let result = templates.customPrompt(template: template, variables: variables)
        XCTAssertEqual(result, "Hello Alice, your score is 95.")
    }

    func testRealtimeCoachingPrompt() {
        let goal = Goal(text: "Reduce filler words", isCompleted: false)
        let prompt = templates.realtimeCoachingPrompt(
            partialTranscription: "Um, so, like, I think...",
            currentGoal: goal
        )

        XCTAssertTrue(prompt.contains("Reduce filler words"))
        XCTAssertTrue(prompt.contains("Um, so, like"))
    }
}

class ModelCacheTests: XCTestCase {
    func testModelFileNames() {
        XCTAssertEqual(LLMModel.tinyLlama.fileName, "tinyllama-1.1b-q4_k_m.gguf")
        XCTAssertEqual(LLMModel.phi2.fileName, "phi-2-q4_k_m.gguf")
        XCTAssertEqual(LLMModel.mistral.fileName, "mistral-7b-q4_k_m.gguf")
    }

    func testModelSizes() {
        let models = LLMModel.allCases
        for model in models {
            XCTAssertFalse(model.size.isEmpty)
            XCTAssertTrue(model.size.contains("B") || model.size.contains("MB"))
        }
    }
}

class OpenAIChatServiceTests: XCTestCase {
    func testServiceSingleton() {
        let service1 = OpenAIChatService.shared
        let service2 = OpenAIChatService.shared
        XCTAssertTrue(service1 === service2)
    }

    func testChatCompletionRequiresAPIKey() async {
        guard !OpenAIConfig.shared.isConfigured else {
            // Skip if API key is configured
            return
        }

        do {
            _ = try await OpenAIChatService.shared.complete(prompt: "Test")
            XCTFail("Should throw error without API key")
        } catch {
            // Expected error
            XCTAssertTrue(error is OpenAIError)
        }
    }
}
