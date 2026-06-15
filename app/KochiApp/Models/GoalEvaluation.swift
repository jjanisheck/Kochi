import Foundation

// MARK: - Goal Evaluation Model
struct GoalEvaluation {
    let evaluations: [UUID: Bool]
    let feedback: [UUID: String]
    let overallScore: Double
    let suggestions: [String]
    
    // Convenience initializer for compatibility
    init(evaluations: [UUID: Bool], suggestions: [String]) {
        self.evaluations = evaluations
        self.feedback = [:]
        self.overallScore = 0.0
        self.suggestions = suggestions
    }
    
    // Full initializer
    init(evaluations: [UUID: Bool], feedback: [UUID: String], overallScore: Double, suggestions: [String]) {
        self.evaluations = evaluations
        self.feedback = feedback
        self.overallScore = overallScore
        self.suggestions = suggestions
    }
}