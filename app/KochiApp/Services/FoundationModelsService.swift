import Foundation
import FoundationModels

/// On-device analysis via Apple Foundation Models (`SystemLanguageModel`). Fully local —
/// no Private Cloud Compute, no network, no entitlement required.
@available(macOS 27, iOS 27, *)
final class FoundationModelsService {
    static let shared = FoundationModelsService()
    private init() {}

    private let onDevice = SystemLanguageModel.default

    /// True when the on-device model is ready to serve requests.
    var isAvailable: Bool {
        if case .available = onDevice.availability { return true }
        return false
    }

    // MARK: - Goal evaluation (on-device, structured)

    func evaluateGoals(_ goals: [Goal], transcript: String) async throws -> GoalEvaluation {
        guard !goals.isEmpty else {
            return GoalEvaluation(evaluations: [:], feedback: [:], overallScore: 0, suggestions: [])
        }
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return GoalEvaluation(evaluations: [:], feedback: [:], overallScore: 0,
                                  suggestions: ["No transcript to evaluate"])
        }

        var goalsText = ""
        for (i, goal) in goals.enumerated() { goalsText += "\(i + 1). \(goal.text)\n" }

        let session = LanguageModelSession(model: onDevice, instructions: Self.goalInstructions)
        let prompt = """
        Goals:
        \(goalsText)
        Transcript:
        "\(String(transcript.suffix(8_000)))"

        Return one result per goal, using its 1-based number. Mark a goal achieved ONLY
        when the transcript contains clear, specific evidence that the goal was actually
        met. If a goal says to mention or discuss something, that thing must actually
        appear in the transcript — a related or adjacent topic does NOT count. If the
        goal is only loosely related, implied, partially addressed, or absent, mark it
        NOT achieved. When you are not sure, mark it NOT achieved. In each reason, quote
        the exact transcript phrase that proves the goal was met, or state what is missing.
        """
        let output = try await session.respond(to: prompt, generating: GoalEvalOutput.self).content
        return output.toGoalEvaluation(goals: goals)
    }

    // MARK: - Coaching (on-device, plain text, prewarmed)

    func generateCoachingResponse(transcript: String, goals: [Goal]) async throws -> String {
        try await generateCoachReaction(transcript: transcript, goals: goals, recentReactions: []).caption
    }

    func generateCoachReaction(transcript: String, goals: [Goal], recentReactions: [String]) async throws -> CoachReaction {
        let completed = goals.filter { $0.isCompleted }.map { $0.text }
        let pending = goals.filter { !$0.isCompleted }.map { $0.text }
        let session = LanguageModelSession(model: onDevice, instructions: Self.coachInstructions)
        session.prewarm()
        let prompt = """
        Recent transcript (speaker labels identify who spoke): "\(String(transcript.suffix(8_000)))"
        Completed goals: \(completed.isEmpty ? "None" : completed.joined(separator: ", "))
        Pending goals: \(pending.isEmpty ? "None" : pending.joined(separator: ", "))
        Recent reactions (avoid repeating advice): \(recentReactions.suffix(3).joined(separator: " | "))

        Choose a useful coaching intent, expression, and restrained gesture. If no
        intervention is warranted, listen attentively. Ground advice in what was actually
        said. Don't infer emotions, interruptions, silence duration, or speaking balance
        from text alone. Never choose goal or salute: verified achievements come from
        the app's goal events. Caption: ONE sentence, max 15 words, no emojis.
        Match the gesture to YOUR coaching response: acknowledge or agree for useful
        contributions; talk for a suggestion; disagree for an explicit correction;
        shrug for uncertainty; sigh for relief after resolution. Most routine updates
        should use none. Use a firm expression for a clear redirect, never anger,
        sarcasm, or ridicule. Positive wording alone is not a completed goal.
        """
        let directive = try await session.respond(to: prompt, generating: CoachingDirective.self).content
        return CoachReaction(directive: directive)
    }

    // MARK: - Session notes (on-device, structured -> markdown)

    func generateSessionNotes(transcript: String, goals: [Goal]) async throws -> String {
        do {
            let notes = try await notesCall(transcript: transcript)
            return notes.renderedMarkdown(goals: goals)
        } catch LanguageModelError.contextSizeExceeded {
            // Verified API: context overflow is LanguageModelError.contextSizeExceeded
            // (top-level enum, macOS 27). Shrink the transcript and retry once.
            print("⚠️ FM notes context exceeded, retrying smaller")
            let half = String(transcript.suffix(transcript.count / 2))
            let notes = try await notesCall(transcript: half)
            return notes.renderedMarkdown(goals: goals)
        }
        // Other LanguageModelError cases / SystemLanguageModel.Error propagate to
        // LLMManager, which falls back to keyword notes — never interrupting transcription.
    }

    private func notesCall(transcript: String) async throws -> SessionNotes {
        // Fully on-device. (Private Cloud Compute would need the gated
        // com.apple.developer.private-cloud-compute entitlement; Kōchi runs local-only.)
        let session = LanguageModelSession(model: onDevice, instructions: Self.notesInstructions)
        let prompt = """
        Generate concise meeting notes from this transcript.
        Transcript:
        "\(transcript)"
        """
        return try await session.respond(to: prompt, generating: SessionNotes.self).content
    }

    // MARK: - Spoken goals -> short goals (on-device, structured)

    /// Parses a freely-spoken phrase into up to three short, actionable goals.
    func parseGoals(from spokenText: String) async throws -> [String] {
        let session = LanguageModelSession(model: onDevice, instructions: Self.parseGoalsInstructions)
        let prompt = """
        The user spoke the following to set their goals for an upcoming meeting:
        "\(spokenText)"

        Extract 1 to 3 short, actionable goals from what they said. Each goal is a
        concise phrase (about 2-8 words), no numbering, no trailing punctuation.
        Keep the user's wording and order where you can. Return only the goals.
        """
        let output = try await session.respond(to: prompt, generating: ParsedGoals.self).content
        return output.goals
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Instructions

    private static let goalInstructions = """
    You are a strict, objective evaluator deciding whether each goal was actually met in
    a meeting transcript. Judge ONLY on explicit, specific evidence present in the
    transcript. Do not assume, infer unstated intent, or give the benefit of the doubt.
    A goal that is merely related to the conversation, implied, or partially touched on
    is NOT met. If the evidence is not clear and specific, mark the goal not achieved.
    """
    private static let coachInstructions = """
    You are a direct, no-nonsense meeting coach giving brief, actionable feedback.
    """
    private static let notesInstructions = """
    You write concise, well-structured meeting notes: a short summary, key points, and action items.
    """
    private static let parseGoalsInstructions = """
    You convert a short spoken phrase into 1-3 concise, actionable meeting goals.
    Each goal is a brief phrase (about 2-8 words), no numbering, no trailing
    punctuation. Preserve the speaker's intent and order; do not invent goals
    they did not mention.
    """
}
