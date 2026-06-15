import XCTest
@testable import KochiApp

// MARK: - Unit Tests for Faster Iteration
// Run these with Cmd+U in Xcode - NO simulator needed!

final class LLMManagerTests: XCTestCase {
    var llmManager: LLMManager!
    var goalManager: GoalManager!

    override func setUp() {
        super.setUp()
        llmManager = LLMManager()
        goalManager = GoalManager()
        goalManager.goals = [
            Goal(text: "discuss budget", isCompleted: false),
            Goal(text: "ask about timeline", isCompleted: false),
            Goal(text: "get licensing info", isCompleted: false)
        ]
    }

    override func tearDown() {
        llmManager = nil
        goalManager = nil
        super.tearDown()
    }

    func testCoachingResponseGeneration() async throws {
        // Test that coaching response is generated
        let transcription = "We discussed the budget and they have $50,000 allocated for this project."

        try await llmManager.generateCoachingResponse(
            for: transcription,
            goals: goalManager.goals
        )

        XCTAssertFalse(llmManager.coachingResponse.isEmpty, "Coaching response should not be empty")
    }

    func testGoalEvaluation() async throws {
        // Test that goals are correctly evaluated
        let transcription = "We discussed the budget and they have $50,000 allocated."

        let evaluation = try await llmManager.evaluateGoals(
            goalManager.goals,
            with: transcription
        )

        XCTAssertGreaterThan(evaluation.overallScore, 0.0, "Overall score should be greater than 0")
        XCTAssertEqual(evaluation.evaluations.count, 3, "Should evaluate all 3 goals")
    }

    func testGoalEvaluationWithDirectMatch() async throws {
        // Test that direct keyword matches are detected
        let transcription = "Let's discuss the budget for this project and timeline."

        let evaluation = try await llmManager.evaluateGoals(
            goalManager.goals,
            with: transcription
        )

        // Should match "discuss budget" goal
        let budgetGoal = goalManager.goals.first { $0.text.contains("budget") }!
        XCTAssertTrue(evaluation.evaluations[budgetGoal.id] == true, "Budget goal should be achieved")
    }

    func testGoalEvaluationWithSemanticMatch() async throws {
        // Test semantic similarity (even without exact keywords)
        let transcription = "They have financial resources available and can afford the investment."

        let evaluation = try await llmManager.evaluateGoals(
            goalManager.goals,
            with: transcription
        )

        // Should have some semantic relevance to budget
        XCTAssertGreaterThan(evaluation.overallScore, 0.0, "Should detect semantic relevance")
    }

    func testSessionNotesGeneration() async throws {
        // Test session notes generation
        goalManager.goals[0].isCompleted = true // Mark first goal as complete

        let notes = try await llmManager.generateSessionNotes(
            transcription: "We had a great discussion about the budget.",
            goals: goalManager.goals
        )

        XCTAssertTrue(notes.contains("Session Notes"), "Notes should contain header")
        XCTAssertTrue(notes.contains("discuss budget"), "Notes should contain completed goal")
    }
}

final class TranscriptionManagerTests: XCTestCase {
    var transcriptionManager: TranscriptionManager!

    override func setUp() {
        super.setUp()
        transcriptionManager = TranscriptionManager()
    }

    override func tearDown() {
        transcriptionManager = nil
        super.tearDown()
    }

    func testInitialState() {
        XCTAssertFalse(transcriptionManager.isTranscribing, "Should not be transcribing initially")
        XCTAssertTrue(transcriptionManager.transcriptionText.isEmpty, "Transcription should be empty initially")
    }

    func testLanguageSelection() {
        transcriptionManager.selectedLanguage = .spanish
        XCTAssertEqual(transcriptionManager.selectedLanguage, .spanish)
        XCTAssertEqual(transcriptionManager.selectedLanguage.rawValue, "es-ES")
    }

    func testLanguageDisplayNames() {
        XCTAssertEqual(TranscriptionLanguage.english.displayName, "English")
        XCTAssertEqual(TranscriptionLanguage.spanish.displayName, "Spanish")
        XCTAssertEqual(TranscriptionLanguage.french.displayName, "French")
    }
}

final class GoalManagerTests: XCTestCase {
    var goalManager: GoalManager!

    override func setUp() {
        super.setUp()
        goalManager = GoalManager()
    }

    override func tearDown() {
        goalManager = nil
        super.tearDown()
    }

    func testAddGoal() {
        let initialCount = goalManager.goals.count
        goalManager.addGoal(text: "New test goal")

        XCTAssertEqual(goalManager.goals.count, initialCount + 1, "Should add one goal")
        XCTAssertEqual(goalManager.goals.last?.text, "New test goal")
        XCTAssertFalse(goalManager.goals.last?.isCompleted ?? true, "New goal should not be completed")
    }

    func testToggleGoalCompletion() {
        goalManager.addGoal(text: "Test goal")
        let goal = goalManager.goals.last!

        // Toggle to completed
        goalManager.toggleGoalCompletion(goal)
        XCTAssertTrue(goalManager.goals.last?.isCompleted ?? false, "Goal should be completed")

        // Toggle back to incomplete
        goalManager.toggleGoalCompletion(goal)
        XCTAssertFalse(goalManager.goals.last?.isCompleted ?? true, "Goal should be incomplete")
    }

    func testRemoveGoal() {
        goalManager.addGoal(text: "Goal to remove")
        let goal = goalManager.goals.last!
        let countBeforeRemoval = goalManager.goals.count

        goalManager.removeGoal(goal)

        XCTAssertEqual(goalManager.goals.count, countBeforeRemoval - 1, "Should remove one goal")
        XCTAssertFalse(goalManager.goals.contains { $0.id == goal.id }, "Should not contain removed goal")
    }
}

// MARK: - Performance Tests
final class PerformanceTests: XCTestCase {
    func testGoalEvaluationPerformance() throws {
        let llmManager = LLMManager()
        let goals = [
            Goal(text: "discuss budget", isCompleted: false),
            Goal(text: "ask about timeline", isCompleted: false),
            Goal(text: "get licensing info", isCompleted: false)
        ]
        let transcription = "We discussed the budget and they have $50,000 allocated for this project. The timeline is 6 months and we need to get licensing sorted out."

        measure {
            // Test performance of goal evaluation
            let expectation = XCTestExpectation(description: "Goal evaluation")

            Task {
                _ = try? await llmManager.evaluateGoals(goals, with: transcription)
                expectation.fulfill()
            }

            wait(for: [expectation], timeout: 10.0)  // Increased timeout for API calls
        }
    }
}
