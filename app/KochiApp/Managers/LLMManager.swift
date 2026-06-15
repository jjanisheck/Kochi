import Foundation
import Combine

// MARK: - LLM Manager (Apple Foundation Models)
@available(macOS 27, iOS 27, *)
@MainActor
class LLMManager: ObservableObject {
    // Published state read by views
    @Published var isProcessing = false
    @Published var coachingResponse = ""
    @Published var streamingText = ""
    @Published var runningSummary = ""
    @Published var isAvailable = false

    private let fm = FoundationModelsService.shared

    init() {
        Task { @MainActor [weak self] in self?.updateAvailability() }
    }

    private func updateAvailability() {
        isAvailable = fm.isAvailable
    }

    /// Clears per-meeting analysis state at the start of a recording session.
    func resetSession() {
        runningSummary = ""
        coachingResponse = ""
        streamingText = ""
    }

    // MARK: - Goal evaluation

    func evaluateChunk(_ chunk: String, goals: [Goal]) async throws -> GoalEvaluation {
        isProcessing = true
        defer { isProcessing = false }
        updateAvailability()
        guard !chunk.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return GoalEvaluation(evaluations: [:], feedback: [:], overallScore: 0, suggestions: [])
        }
        runningSummary = chunk          // retained published state; not currently read by the live UI
        do {
            return try await fm.evaluateGoals(goals, transcript: chunk)
        } catch {
            print("❌ LLMManager.evaluateChunk: \(error)")
            return fallbackEvaluateGoals(goals, transcription: chunk)
        }
    }

    func evaluateFullTranscript(_ transcript: String, goals: [Goal]) async throws -> GoalEvaluation {
        isProcessing = true
        defer { isProcessing = false }
        updateAvailability()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return GoalEvaluation(evaluations: [:], feedback: [:], overallScore: 0, suggestions: [])
        }
        do {
            return try await fm.evaluateGoals(goals, transcript: transcript)
        } catch {
            print("❌ LLMManager.evaluateFullTranscript: \(error)")
            return fallbackEvaluateGoals(goals, transcription: transcript)
        }
    }

    /// Legacy signature retained for existing callers.
    func evaluateGoals(_ goals: [Goal], with transcription: String) async throws -> GoalEvaluation {
        try await evaluateFullTranscript(transcription, goals: goals)
    }

    // MARK: - Coaching

    func generateCoachingResponse(for transcription: String, goals: [Goal]) async throws {
        isProcessing = true
        defer { isProcessing = false }
        do {
            let response = try await fm.generateCoachingResponse(transcript: transcription, goals: goals)
            self.coachingResponse = response
            self.streamingText = response
        } catch {
            print("❌ LLMManager.generateCoachingResponse: \(error)")
            let fallback = generateFallbackCoachingMessage(goals: goals)
            self.coachingResponse = fallback
            self.streamingText = fallback
        }
    }

    // MARK: - Session notes

    func generateSessionNotes(transcription: String, goals: [Goal]) async throws -> String {
        isProcessing = true
        defer { isProcessing = false }
        do {
            return try await fm.generateSessionNotes(transcript: transcription, goals: goals)
        } catch {
            print("❌ LLMManager.generateSessionNotes: \(error)")
            return generateFallbackNotes(transcription: transcription, goals: goals)
        }
    }

    // MARK: - Keyword fallbacks (used only if a model call throws)

    private func fallbackEvaluateGoals(_ goals: [Goal], transcription: String) -> GoalEvaluation {
        var evaluations: [UUID: Bool] = [:]
        var feedback: [UUID: String] = [:]
        let lower = transcription.lowercased()
        for goal in goals {
            let keywords = goal.text.lowercased().split(separator: " ").map(String.init)
            let directMatch = lower.contains(goal.text.lowercased())
            let matches = keywords.filter { $0.count > 3 && lower.contains($0) }
            let pct = Double(matches.count) / Double(max(keywords.count, 1))
            let achieved = directMatch || pct > 0.5
            evaluations[goal.id] = achieved
            feedback[goal.id] = achieved ? "Keywords detected in transcript" : "Not yet discussed"
        }
        let achieved = evaluations.values.filter { $0 }.count
        let score = Double(achieved) / Double(max(goals.count, 1))
        return GoalEvaluation(
            evaluations: evaluations, feedback: feedback, overallScore: score,
            suggestions: goals.filter { evaluations[$0.id] == false }.prefix(2).map { "Focus on: \($0.text)" }
        )
    }

    private func generateFallbackCoachingMessage(goals: [Goal]) -> String {
        let completed = goals.filter { $0.isCompleted }.count
        let total = goals.count
        if completed == total && total > 0 { return "All objectives achieved. Mission complete!" }
        if completed > total / 2 { return "Solid progress! \(completed)/\(total) goals achieved. Stay focused!" }
        return "Stay sharp! Review your goals and drive toward completion."
    }

    private func generateFallbackNotes(transcription: String, goals: [Goal]) -> String {
        let completed = goals.filter { $0.isCompleted }.map { "- \($0.text)" }
        let pending = goals.filter { !$0.isCompleted }.map { "- \($0.text)" }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        return """
        Session Notes - \(df.string(from: Date()))

        Goals Completed:
        \(completed.isEmpty ? "None" : completed.joined(separator: "\n"))

        Goals Pending:
        \(pending.isEmpty ? "None" : pending.joined(separator: "\n"))

        Transcript:
        \(transcription)
        """
    }
}

// MARK: - Supporting error type
enum LLMError: LocalizedError {
    case modelUnavailable
    case inferenceFailed
    var errorDescription: String? {
        switch self {
        case .modelUnavailable: return "On-device model unavailable. Requires macOS 27 / iOS 27."
        case .inferenceFailed:  return "Analysis failed. Please try again."
        }
    }
}
