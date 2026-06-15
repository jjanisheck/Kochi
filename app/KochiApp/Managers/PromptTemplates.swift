import Foundation

// MARK: - Prompt Templates
class PromptTemplates {
    
    // MARK: - Coaching Prompt
    func coachingPrompt(transcription: String, goals: [Goal]) -> String {
        let goalsText = goals.map { "- \($0.text)" }.joined(separator: "\n")
        
        return """
        You are a helpful communication coach analyzing a conversation. Based on the following transcription and goals, provide brief, encouraging feedback.
        
        Goals:
        \(goalsText)
        
        Transcription:
        \(transcription)
        
        Provide specific, actionable feedback in 2-3 sentences that helps the speaker improve. Be positive and constructive.
        """
    }
    
    // MARK: - Goal Evaluation Prompt
    func goalEvaluationPrompt(goals: [Goal], transcription: String) -> String {
        let goalsText = goals.enumerated().map { index, goal in
            "\(index + 1). \(goal.text)"
        }.joined(separator: "\n")
        
        return """
        Evaluate the speaker's performance against these communication goals based on the transcription.
        
        Goals:
        \(goalsText)
        
        Transcription:
        \(transcription)
        
        For each goal, indicate if it was achieved and provide brief feedback. Format your response clearly.
        """
    }
    
    // MARK: - Session Notes Prompt
    func sessionNotesPrompt(transcription: String, goals: [Goal]) -> String {
        let goalsText = goals.map { "- \($0.text)" }.joined(separator: "\n")
        
        return """
        Create a brief summary of this communication session.
        
        Goals for this session:
        \(goalsText)
        
        Transcription:
        \(transcription)
        
        Write a concise summary (3-5 sentences) highlighting:
        1. Key points discussed
        2. Progress on goals
        3. Areas for improvement
        4. Positive achievements
        
        Keep the tone encouraging and constructive.
        """
    }
    
    // MARK: - Real-time Coaching Prompt
    func realtimeCoachingPrompt(partialTranscription: String, currentGoal: Goal) -> String {
        return """
        Based on this ongoing conversation, provide a very brief (1 sentence) coaching tip related to the goal: "\(currentGoal.text)"
        
        Current speech: \(partialTranscription)
        
        Tip:
        """
    }
    
    // MARK: - Custom Prompt
    func customPrompt(template: String, variables: [String: String]) -> String {
        var prompt = template
        for (key, value) in variables {
            prompt = prompt.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return prompt
    }
}