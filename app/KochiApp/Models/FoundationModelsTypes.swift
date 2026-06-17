import Foundation
import FoundationModels

// MARK: - Goal evaluation (structured generation)

@available(macOS 27, iOS 27, *)
@Generable
struct GoalEvalResult {
    @Guide(description: "The 1-based number of the goal, matching the numbered list in the prompt")
    var goalNumber: Int
    @Guide(description: "True ONLY when the transcript contains clear, explicit, specific evidence that this exact goal was met. False if the goal is merely related, implied, partially addressed, or absent. When uncertain, false.")
    var achieved: Bool
    @Guide(description: "If achieved, quote the exact transcript phrase that proves it. If not achieved, state what is missing.")
    var reason: String
}

@available(macOS 27, iOS 27, *)
@Generable
struct GoalEvalOutput {
    @Guide(description: "Exactly one result per goal, in the same order as the prompt")
    var results: [GoalEvalResult]
}

// MARK: - Session notes (structured generation)

@available(macOS 27, iOS 27, *)
@Generable
struct SessionNotes {
    @Guide(description: "A 2-3 sentence summary of the meeting")
    var summary: String
    @Guide(description: "3-5 key discussion points")
    var keyPoints: [String]
    @Guide(description: "Action items mentioned, including an owner if one was stated")
    var actionItems: [String]
}

// MARK: - Spoken goals (structured generation)

@available(macOS 27, iOS 27, *)
@Generable
struct ParsedGoals {
    @Guide(description: "1 to 3 short, actionable meeting goals extracted from the spoken text. Each goal is a concise phrase of about 2-8 words, with no numbering or punctuation. Preserve the speaker's intent and ordering.")
    var goals: [String]
}

// MARK: - Conversion to the app's existing GoalEvaluation shape

@available(macOS 27, iOS 27, *)
extension GoalEvalOutput {
    /// Maps index-keyed model output onto the app's UUID-keyed GoalEvaluation.
    func toGoalEvaluation(goals: [Goal]) -> GoalEvaluation {
        // 1-based index -> Goal
        var indexMap: [Int: Goal] = [:]
        for (i, goal) in goals.enumerated() { indexMap[i + 1] = goal }

        var evaluations: [UUID: Bool] = [:]
        var feedback: [UUID: String] = [:]
        for r in results {
            guard let goal = indexMap[r.goalNumber] else { continue }
            evaluations[goal.id] = r.achieved
            feedback[goal.id] = r.achieved ? "Achieved: \(r.reason)" : "Pending: \(r.reason)"
        }
        // Backfill goals the model omitted.
        for goal in goals where evaluations[goal.id] == nil {
            evaluations[goal.id] = false
            feedback[goal.id] = "Not evaluated"
        }
        let achieved = evaluations.values.filter { $0 }.count
        let score = Double(achieved) / Double(max(goals.count, 1))
        let suggestions = goals
            .filter { evaluations[$0.id] == false }
            .prefix(2)
            .map { "Focus on: \($0.text)" }
        return GoalEvaluation(evaluations: evaluations, feedback: feedback,
                              overallScore: score, suggestions: Array(suggestions))
    }
}

// MARK: - Session notes rendering

@available(macOS 27, iOS 27, *)
extension SessionNotes {
    /// Renders structured notes to the markdown string the existing UI consumes.
    func renderedMarkdown(goals: [Goal]) -> String {
        let completed = goals.filter { $0.isCompleted }.map { "- \($0.text)" }
        let pending = goals.filter { !$0.isCompleted }.map { "- \($0.text)" }
        let points = keyPoints.map { "- \($0)" }.joined(separator: "\n")
        let actions = actionItems.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(summary)

        Key Points:
        \(points.isEmpty ? "- (none)" : points)

        Action Items:
        \(actions.isEmpty ? "- (none)" : actions)

        Goals Completed:
        \(completed.isEmpty ? "- None" : completed.joined(separator: "\n"))

        Goals Pending:
        \(pending.isEmpty ? "- None" : pending.joined(separator: "\n"))
        """
    }
}
